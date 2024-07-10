package queue

import (
	cc "buf.build/gen/go/webitel/cc/protocolbuffers/go"
	"context"
	"encoding/json"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"golang.org/x/sync/singleflight"
	"net/http"
	"sync"
	"time"
)

const (
	MAX_QUEUES_CACHE        = 10000
	MAX_MEMBERS_CACHE       = 50000
	MAX_QUEUES_EXPIRE_CACHE = 0 //60 * 60 * 24 //day

	timeoutWaitBeforeStop = time.Second * 10
)

type QueueManager struct {
	wg               sync.WaitGroup
	app              App
	attemptCount     int64
	mq               mq.MQ
	stop             chan struct{}
	stopped          chan struct{}
	input            chan *Attempt
	queuesCache      utils.ObjectCache
	membersCache     utils.ObjectCache
	store            store.Store
	resourceManager  *ResourceManager
	agentManager     agent_manager.AgentManager
	callManager      call_manager.CallManager
	teamManager      *teamManager
	waitChannelClose bool
	bridgeSleep      time.Duration
	sync.Mutex
}

var (
	errNotFoundConnection = model.NewAppError("QM", "qm.connection.not_found", nil, "Not found", http.StatusNotFound)
)

var (
	queueGroup singleflight.Group
)

func NewQueueManager(app App, s store.Store, m mq.MQ, callManager call_manager.CallManager, resourceManager *ResourceManager, agentManager agent_manager.AgentManager, bridgeSleep time.Duration) *QueueManager {
	return &QueueManager{
		store:            s,
		app:              app,
		callManager:      callManager,
		resourceManager:  resourceManager,
		agentManager:     agentManager,
		mq:               m,
		bridgeSleep:      bridgeSleep,
		teamManager:      NewTeamManager(app, s, m),
		input:            make(chan *Attempt),
		stop:             make(chan struct{}),
		stopped:          make(chan struct{}),
		waitChannelClose: app.QueueSettings().WaitChannelClose,
		queuesCache:      utils.NewLruWithParams(MAX_QUEUES_CACHE, "QueueManager", MAX_QUEUES_EXPIRE_CACHE, ""),
		membersCache:     utils.NewLruWithParams(MAX_MEMBERS_CACHE, "Members", MAX_QUEUES_EXPIRE_CACHE, ""),
	}
}

func (queueManager *QueueManager) Start() {
	wlog.Debug("queueManager started")

	defer func() {
		wlog.Debug("stopped QueueManager")
		close(queueManager.stopped)
	}()

	queueManager.listenWaitingList()

	for {
		select {
		case <-queueManager.stop:
			wlog.Debug("queueManager received stop signal")
			close(queueManager.input)
			return
		case attempt := <-queueManager.input:
			queueManager.DistributeAttempt(attempt)
			//case call := <-queueManager.callManager.InboundCall():
			//	go queueManager.DistributeCall(call)
		}
	}
}

func (queueManager *QueueManager) closeAttempts() {
	var err *model.AppError
	var id int64
	var ok bool

	for _, v := range queueManager.membersCache.Keys() {
		fmt.Println(v)
		if id, ok = v.(int64); !ok {
			continue
		}

		err = queueManager.ReportingAttempt(id, model.AttemptCallback{
			Status: "shutdown", // TODO
		}, false)
		if err != nil {
			wlog.Error(err.Error())
		}
	}
}

func (queueManager *QueueManager) Stop() {
	wlog.Debug("queueManager Stopping")
	queueManager.stopWaitingList()
	wlog.Debug(fmt.Sprintf("wait %v for close attempts %d", timeoutWaitBeforeStop, queueManager.membersCache.Len()))

	if waitTimeout(&queueManager.wg, timeoutWaitBeforeStop) {
		queueManager.closeAttempts()
	}

	close(queueManager.stop)
	<-queueManager.stopped
}

func (queueManager *QueueManager) GetNodeId() string {
	return queueManager.app.GetInstanceId()
}

func (queueManager *QueueManager) CreateAttemptIfNotExists(ctx context.Context, attempt *model.MemberAttempt) (*Attempt, *model.AppError) {
	var a *Attempt
	var ok bool

	if a, ok = queueManager.GetAttempt(attempt.Id); ok {
		panic("ERROR")
		//if attempt.Result == nil {
		//	wlog.Error(fmt.Sprintf("attempt %v in queue", a.Id()))
		//} else {
		//	a.SetMember(attempt)
		//}
	} else {
		a = queueManager.createAttempt(ctx, attempt)
		if attempt.AgentId != nil && attempt.AgentUpdatedAt != nil {
			if agent, err := queueManager.agentManager.GetAgent(*attempt.AgentId, *attempt.AgentUpdatedAt); err != nil {
				panic(err.Error())
			} else {
				a.SetAgent(agent)
			}
		}
	}

	return a, nil
}

func (queueManager *QueueManager) createAttempt(ctx context.Context, conf *model.MemberAttempt) *Attempt {
	attempt := NewAttempt(ctx, conf)
	queueManager.membersCache.AddWithDefaultExpires(attempt.Id(), attempt)
	queueManager.wg.Add(1)
	queueManager.attemptCount++
	return attempt
}

func (queueManager *QueueManager) GetQueue(id int, updatedAt int64) (QueueObject, *model.AppError) {
	var v interface{}
	var ok bool
	var doErr error
	var err *model.AppError

	var queue QueueObject

	item, ok := queueManager.queuesCache.Get(id)
	if ok {
		queue, ok = item.(QueueObject)
		if ok && !queue.IsExpire(updatedAt) {
			return queue, nil
		}
	}

	v, doErr, _ = queueGroup.Do(fmt.Sprintf("queue-%d-%d", id, updatedAt), func() (interface{}, error) {
		res, appErr := queueManager.app.GetQueueById(int64(id))
		if appErr != nil {
			return nil, appErr
		}

		return res, nil
	})

	if doErr != nil {
		switch doErr.(type) {
		case *model.AppError:
			err = doErr.(*model.AppError)
		default:
			err = model.NewAppError("Queue.Get", "queue.get.app_err", nil, doErr.Error(), http.StatusInternalServerError)
		}

		return nil, err
	}

	queueParams := v.(*model.Queue)

	queue, err = NewQueue(queueManager, queueManager.resourceManager, queueParams)
	if err != nil {
		return nil, err
	}

	queueManager.queuesCache.AddWithDefaultExpires(id, queue)
	wlog.Debug(fmt.Sprintf("add queue %s to cache", queue.Name()))
	return queue, nil
}

func (queueManager *QueueManager) GetResource(id, updatedAt int64) (ResourceObject, *model.AppError) {
	return queueManager.resourceManager.Get(id, updatedAt)
}

func (queueManager *QueueManager) SetResourceError(resource ResourceObject, errorId string) {
	if resource.CheckCodeError(errorId) {
		wlog.Warn(fmt.Sprintf("resource %s Id=%d error: %s", resource.Name(), resource.Id(), errorId))
		if responseError, err := queueManager.store.OutboundResource().
			SetError(int64(resource.Id()), int64(1), errorId, model.OUTBOUND_RESOURCE_STRATEGY_RANDOM); err != nil {

			wlog.Error(err.Error())
		} else {
			if responseError.Stopped != nil && *responseError.Stopped {
				wlog.Info(fmt.Sprintf("resource %s [%d] stopped, because: %s", resource.Name(), resource.Id(), errorId))

				queueManager.notifyStoppedResource(resource)
			}

			if responseError.UnReserveResourceId != nil {
				wlog.Info(fmt.Sprintf("new resource ResourceId=%d from reserve", *responseError.UnReserveResourceId))
			}
			queueManager.resourceManager.RemoveFromCacheById(int64(resource.Id()))
		}
	}
}

func (queueManager *QueueManager) SetResourceSuccessful(resource ResourceObject) {
	if resource.SuccessivelyErrors() > 0 {
		if err := queueManager.store.OutboundResource().SetSuccessivelyErrorsById(int64(resource.Id()), 0); err != nil {
			wlog.Error(err.Error())
		}
	}
}

func (queueManager *QueueManager) SetAgentWaitingChannel(agent agent_manager.AgentObject, channel string) (int64, *model.AppError) {
	timestamp, err := queueManager.store.Agent().WaitingChannel(agent.Id(), channel)
	if err != nil {
		return 0, err
	}

	e := NewWaitingChannelEvent(channel, agent.UserId(), nil, timestamp)
	return 0, queueManager.mq.AgentChannelEvent(channel, agent.DomainId(), 0, agent.UserId(), e)
}

func (queueManager *QueueManager) DistributeAttempt(attempt *Attempt) (QueueObject, *model.AppError) {

	queue, err := queueManager.GetQueue(attempt.QueueId(), attempt.QueueUpdatedAt())
	if err != nil {
		wlog.Error(err.Error())
		//TODO added to model "dialing.queue.new_queue.app_error"
		//panic(err.Error())
		return nil, err
	}

	attempt.domainId = queue.DomainId()
	attempt.channel = queue.Channel()
	attempt.queue = queue

	if attempt.IsBarred() {
		err = queueManager.Barred(attempt)
		if err != nil {
			wlog.Error(err.Error())
		} else {
			attempt.Log("this destination is barred")
		}
		return nil, nil
	}

	//if attempt.IsTimeout() {
	//	return nil, nil
	//}

	//todo new event instance

	attempt.resource = queueManager.GetAttemptResource(attempt)

	if err = queue.DistributeAttempt(attempt); err != nil {
		wlog.Error(err.Error())
		queueManager.Abandoned(attempt)
		queueManager.LeavingMember(attempt)

		return nil, err
	} else {
		wlog.Info(fmt.Sprintf("[%s] join member %s[%v] AttemptId=%d to queue \"%s\" (size %d, waiting %d, active %d)", queue.TypeName(), attempt.Name(),
			attempt.MemberId(), attempt.Id(), queue.Name(), attempt.member.QueueCount, attempt.member.QueueWaitingCount, attempt.member.QueueActiveCount))
	}

	return queue, nil
}

func (queueManager *QueueManager) DistributeCall(ctx context.Context, in *cc.CallJoinToQueueRequest) (*Attempt, *model.AppError) {
	//var member *model.MemberAttempt
	var bucketId *int32
	var stickyAgentId *int
	var q QueueObject

	if in.BucketId != 0 {
		bucketId = &in.BucketId
	}

	if in.StickyAgentId != 0 {
		stickyAgentId = model.NewInt(int(in.StickyAgentId))
	}

	// FIXME add domain
	res, err := queueManager.store.Member().DistributeCallToQueue(
		queueManager.app.GetInstanceId(),
		int64(in.GetQueue().GetId()),
		in.GetMemberCallId(),
		in.GetVariables(),
		bucketId,
		int(in.GetPriority()),
		stickyAgentId,
	)

	if err != nil {
		wlog.Error(fmt.Sprintf("[inbound] join member call_id %s queue %d, %s", in.GetMemberCallId(), in.GetQueue().GetId(), err.Error()))
		return nil, err
	}

	callInfo := &model.Call{
		Id:          res.CallId,
		State:       res.CallState,
		DomainId:    in.DomainId,
		Direction:   res.CallDirection,
		Destination: res.CallDestination,
		Timestamp:   res.CallTimestamp,
		AppId:       res.CallAppId,
		AnsweredAt:  res.CallAnsweredAt,
		BridgedAt:   res.CallBridgedAt,
		CreatedAt:   res.CallCreatedAt,
	}
	if res.CallFromName != nil {
		callInfo.FromName = *res.CallFromName
	}
	if res.CallFromNumber != nil {
		callInfo.FromNumber = *res.CallFromNumber
	}

	ringtone := ""
	if in.WaitingMusic != nil {
		if in.WaitingMusic.Id != 0 && in.WaitingMusic.Type != "" {
			ringtone = fmt.Sprintf("wbt_queue_playback::%s", model.RingtoneUri(in.DomainId, int(in.WaitingMusic.Id), in.WaitingMusic.Type))
		}
	}

	if q, err = queueManager.GetQueue(res.QueueId, res.QueueUpdatedAt); err != nil {
		wlog.Error(fmt.Sprintf("[inbound] join member call_id %s queue %d, %s", in.GetMemberCallId(), in.GetQueue().GetId(), err.Error()))
		return nil, err
	}

	if ringtone == "" {
		if q != nil {
			ringtone = q.RingtoneUri()
		}
	}

	_, err = queueManager.callManager.InboundCallQueue(callInfo, ringtone, q.Variables())
	if err != nil {
		printfIfErr(queueManager.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		wlog.Error(fmt.Sprintf("[%s] call %s (%d) distribute error: %s", callInfo.AppId, callInfo.Id, res.AttemptId, err.Error()))
		return nil, err
	}

	attempt, _ := queueManager.CreateAttemptIfNotExists(context.Background(), &model.MemberAttempt{
		Id:                  res.AttemptId,
		QueueId:             res.QueueId,
		QueueUpdatedAt:      res.QueueUpdatedAt,
		QueueCount:          0, // TODO
		QueueActiveCount:    0,
		QueueWaitingCount:   0,
		CreatedAt:           time.Now(),
		HangupAt:            0,
		BridgedAt:           0,
		Destination:         res.Destination,
		ListCommunicationId: nil,
		TeamUpdatedAt:       res.TeamUpdatedAt,
		Variables:           res.Variables,
		Name:                res.Name,
		MemberCallId:        &res.CallId,
	})

	if _, err = queueManager.DistributeAttempt(attempt); err != nil {
		printfIfErr(queueManager.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		return nil, err
	}

	return attempt, nil
}

func (queueManager *QueueManager) DistributeCallToAgent(ctx context.Context, in *cc.CallJoinToAgentRequest) (*Attempt, *model.AppError) {
	// FIXME add domain
	var agent agent_manager.AgentObject

	qParams := &model.QueueDumpParams{
		QueueName: in.QueueName,
	}

	if qParams.QueueName == "" {
		qParams.QueueName = "agent"
	}

	if in.Processing != nil && in.Processing.Enabled {
		qParams.HasReporting = model.NewBool(true)
		qParams.ProcessingSec = in.Processing.Sec
		qParams.ProcessingRenewalSec = in.Processing.RenewalSec
		if in.Processing.GetForm().GetId() > 0 {
			qParams.HasForm = model.NewBool(true)
		}
	}

	res, err := queueManager.store.Member().DistributeCallToAgent(
		queueManager.app.GetInstanceId(),
		in.GetMemberCallId(),
		in.GetVariables(),
		in.GetAgentId(),
		in.CancelDistribute,
		qParams,
	)

	if err != nil {
		wlog.Error(err.Error())
		return nil, err
	}

	if in.CancelDistribute {
		err = queueManager.CancelAgentDistribute(in.GetAgentId())
		if err != nil {
			wlog.Error(err.Error())
		}
	}

	agent, err = queueManager.agentManager.GetAgent(int(in.GetAgentId()), res.AgentUpdatedAt)
	if err != nil {
		wlog.Error(err.Error())
		return nil, err
	}

	callInfo := &model.Call{
		Id:          res.CallId,
		State:       res.CallState,
		DomainId:    in.DomainId,
		Direction:   res.CallDirection,
		Destination: res.CallDestination,
		Timestamp:   res.CallTimestamp,
		AppId:       res.CallAppId,
		AnsweredAt:  res.CallAnsweredAt,
		BridgedAt:   res.CallBridgedAt,
		CreatedAt:   res.CallCreatedAt,
	}
	if res.CallFromName != nil {
		callInfo.FromName = *res.CallFromName
	}
	if res.CallFromNumber != nil {
		callInfo.FromNumber = *res.CallFromNumber
	}

	ringtone := ""
	if in.WaitingMusic != nil {
		if in.WaitingMusic.Id != 0 && in.WaitingMusic.Type != "" {
			ringtone = fmt.Sprintf("wbt_queue_playback::%s", model.RingtoneUri(in.DomainId, int(in.WaitingMusic.Id), in.WaitingMusic.Type))
		}
	}

	_, err = queueManager.callManager.ConnectCall(callInfo, ringtone)
	if err != nil {
		printfIfErr(queueManager.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		wlog.Error(fmt.Sprintf("[%s] call %s (%d) distribute error: %s", callInfo.AppId, callInfo.Id, res.AttemptId, err.Error()))
		return nil, err
	}

	attempt, _ := queueManager.CreateAttemptIfNotExists(ctx, &model.MemberAttempt{
		Id:             res.AttemptId,
		CreatedAt:      time.Now(),
		Result:         nil,
		Destination:    res.Destination,
		AgentId:        model.NewInt(int(in.AgentId)),
		AgentUpdatedAt: &res.AgentUpdatedAt,
		TeamUpdatedAt:  model.NewInt64(res.TeamUpdatedAt),
		Variables:      res.Variables,
		Name:           res.Name,
		MemberCallId:   &res.CallId,
	})

	settings := &model.Queue{
		Id:                   0,
		DomainId:             in.DomainId,
		DomainName:           "TODO",
		Type:                 10,
		Name:                 qParams.QueueName,
		Strategy:             "",
		Payload:              nil,
		TeamId:               &res.TeamId,
		Processing:           false,
		ProcessingSec:        30,
		ProcessingRenewalSec: 15,
		Hooks:                nil,
	}
	if qParams.HasReporting != nil && *qParams.HasReporting {
		settings.Processing = true
		settings.ProcessingSec = qParams.ProcessingSec
		settings.ProcessingRenewalSec = qParams.ProcessingRenewalSec
		if in.Processing.GetForm().GetId() > 0 {
			settings.FormSchemaId = model.NewInt(int(in.Processing.GetForm().GetId()))
		}
	}

	var queue = JoinAgentCallQueue{
		CallingQueue: CallingQueue{
			BaseQueue: NewBaseQueue(queueManager, queueManager.resourceManager, settings),
		},
	}

	attempt.queue = &queue
	attempt.agent = agent
	attempt.domainId = queue.domainId
	attempt.channel = model.QueueChannelCall

	if err = queue.DistributeAttempt(attempt); err != nil {
		wlog.Error(err.Error())
		queueManager.Abandoned(attempt)
		queueManager.LeavingMember(attempt)

		return nil, err
	} else {
		wlog.Info(fmt.Sprintf("[%s] join member %s[%v] AttemptId=%d to queue \"%s\" (size %d, waiting %d, active %d)", queue.TypeName(), attempt.Name(),
			attempt.MemberId(), attempt.Id(), queue.Name(), attempt.member.QueueCount, attempt.member.QueueWaitingCount, attempt.member.QueueActiveCount))
	}

	return attempt, nil
}

func (queueManager *QueueManager) DistributeTaskToAgent(ctx context.Context, in *cc.TaskJoinToAgentRequest) (*Attempt, *model.AppError) {
	var agent agent_manager.AgentObject

	qParams := &model.QueueDumpParams{
		QueueName: in.QueueName,
	}
	if qParams.QueueName == "" {
		qParams.QueueName = "agent"
	}

	if in.Processing != nil && in.Processing.Enabled {
		qParams.HasReporting = model.NewBool(true)
		qParams.ProcessingSec = in.Processing.Sec
		qParams.ProcessingRenewalSec = in.Processing.RenewalSec
		if in.Processing.GetForm().GetId() > 0 {
			qParams.HasForm = model.NewBool(true)
		}
	}

	dest, _ := json.Marshal(in.Destination)

	res, err := queueManager.store.Member().DistributeTaskToAgent(
		queueManager.app.GetInstanceId(),
		in.DomainId,
		in.GetAgentId(),
		dest,
		in.GetVariables(),
		in.CancelDistribute,
		qParams,
	)

	if err != nil {
		wlog.Error(err.Error())
		return nil, err
	}

	if in.CancelDistribute {
		err = queueManager.CancelAgentDistribute(in.GetAgentId())
		if err != nil {
			wlog.Error(err.Error())
		}
	}

	agent, err = queueManager.agentManager.GetAgent(int(in.GetAgentId()), res.AgentUpdatedAt)
	if err != nil {
		wlog.Error(err.Error())
		return nil, err
	}

	attempt, _ := queueManager.CreateAttemptIfNotExists(ctx, &model.MemberAttempt{
		Id:             res.AttemptId,
		CreatedAt:      time.Now(),
		Result:         nil,
		Destination:    res.Destination,
		AgentId:        model.NewInt(int(in.AgentId)),
		AgentUpdatedAt: &res.AgentUpdatedAt,
		TeamUpdatedAt:  model.NewInt64(res.TeamUpdatedAt),
		Variables:      res.Variables,
		Name:           res.Name,
	})

	settings := &model.Queue{
		Id:                   0,
		DomainId:             in.DomainId,
		DomainName:           "TODO",
		Type:                 model.QueueTypeAgentTask,
		Name:                 qParams.QueueName,
		Strategy:             "",
		Payload:              nil,
		TeamId:               &res.TeamId,
		Processing:           false,
		ProcessingSec:        30,
		ProcessingRenewalSec: 15,
		Hooks:                nil,
		Variables: map[string]string{
			"wbt_auto_answer": "true",
		},
	}

	if qParams.HasReporting != nil && *qParams.HasReporting {
		settings.Processing = true
		settings.ProcessingSec = qParams.ProcessingSec
		settings.ProcessingRenewalSec = qParams.ProcessingRenewalSec
		if in.Processing.GetForm().GetId() > 0 {
			settings.FormSchemaId = model.NewInt(int(in.Processing.GetForm().GetId()))
		}
	}

	var queue = TaskAgent{
		BaseQueue: NewBaseQueue(queueManager, queueManager.resourceManager, settings),
	}

	attempt.queue = &queue
	attempt.agent = agent
	attempt.domainId = queue.domainId
	attempt.channel = model.QueueChannelTask

	if err = queue.DistributeAttempt(attempt); err != nil {
		wlog.Error(err.Error())
		queueManager.Abandoned(attempt)
		queueManager.LeavingMember(attempt)

		return nil, err
	} else {
		wlog.Info(fmt.Sprintf("[%s] join member %s[%v] AttemptId=%d to queue \"%s\" (size %d, waiting %d, active %d)", queue.TypeName(), attempt.Name(),
			attempt.MemberId(), attempt.Id(), queue.Name(), attempt.member.QueueCount, attempt.member.QueueWaitingCount, attempt.member.QueueActiveCount))
	}

	return attempt, nil
}

func (queueManager *QueueManager) DistributeChatToQueue(ctx context.Context, in *cc.ChatJoinToQueueRequest) (*Attempt, *model.AppError) {
	//var member *model.MemberAttempt
	var bucketId *int32
	var stickyAgentId *int

	if in.BucketId != 0 {
		bucketId = &in.BucketId
	}

	if in.StickyAgentId != 0 {
		stickyAgentId = model.NewInt(int(in.StickyAgentId))
	}

	// FIXME add domain
	res, err := queueManager.store.Member().DistributeChatToQueue(
		queueManager.app.GetInstanceId(),
		int64(in.GetQueue().GetId()),
		in.GetConversationId(),
		in.GetVariables(),
		bucketId,
		int(in.GetPriority()),
		stickyAgentId,
	)

	if err != nil {
		wlog.Error(err.Error())
		return nil, err
	}

	attempt, _ := queueManager.CreateAttemptIfNotExists(context.Background(), &model.MemberAttempt{
		Id:                  res.AttemptId,
		QueueId:             res.QueueId,
		QueueUpdatedAt:      res.QueueUpdatedAt,
		QueueCount:          0,
		QueueActiveCount:    0,
		QueueWaitingCount:   0,
		CreatedAt:           time.Now(),
		HangupAt:            0,
		BridgedAt:           0,
		Destination:         res.Destination,
		ListCommunicationId: nil,
		TeamUpdatedAt:       res.TeamUpdatedAt,
		Variables:           res.Variables,
		Name:                res.Name,
		MemberCallId:        &res.ConversationId,
	})

	if _, err = queueManager.DistributeAttempt(attempt); err != nil {
		printfIfErr(queueManager.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		return nil, err
	}
	return attempt, nil
}

func (queueManager *QueueManager) DistributeDirectMember(memberId int64, communicationId, agentId int) (*Attempt, *model.AppError) {
	// FIXME -1
	member, err := queueManager.store.Member().DistributeDirect(queueManager.app.GetInstanceId(), memberId, communicationId-1, agentId)

	if err != nil {
		wlog.Error(fmt.Sprintf("member %v to agent %v distribute error: %s", memberId, agentId, err.Error()))
		return nil, err
	}

	attempt, _ := queueManager.CreateAttemptIfNotExists(context.Background(), member)
	if _, err = queueManager.DistributeAttempt(attempt); err != nil {
		attempt.Log(err.Error())
	}
	if err = queueManager.app.NotificationHideMember(attempt.domainId, attempt.QueueId(), attempt.MemberId(), agentId); err != nil {
		attempt.Log(err.Error())
	}
	return attempt, nil
}

func (queueManager *QueueManager) InterceptAttempt(ctx context.Context, domainId int64, attemptId int64, agentId int32) *model.AppError {
	queueId, err := queueManager.store.Member().Intercept(ctx, domainId, attemptId, agentId)
	if err != nil {
		wlog.Error(fmt.Sprintf("intercept %v to agent %v error: %s", attemptId, agentId, err.Error()))
		return err
	}

	if err = queueManager.app.NotificationInterceptAttempt(domainId, queueId, "", attemptId, agentId); err != nil {
		wlog.Error(fmt.Sprintf("intercept attempt %d notification, error : %s", attemptId, err.Error()))
	}

	return nil
}

func (queueManager *QueueManager) TimeoutLeavingMember(attempt *Attempt) {
	queue := attempt.queue
	if queue != nil {
		var waitBetween uint64 = 0
		var maxAttempts uint = 0
		var perNumbers = false

		result := model.AttemptCallback{
			Status: "timeout",
		}

		if callback, ok := attempt.AfterDistributeSchema(); ok {
			result = model.AttemptCallback{
				Status:        callback.Status,
				Description:   callback.Description,
				Display:       callback.Display,
				Variables:     callback.Variables,
				StickyAgentId: nil,
				NextCallAt:    nil,
				ExpireAt:      nil,
			}

			waitBetween = attempt.waitBetween
			maxAttempts = attempt.maxAttempts
			perNumbers = attempt.perNumbers

			if callback.AgentId > 0 {
				result.StickyAgentId = model.NewInt(int(callback.AgentId))
			}
		}

		res, err := queueManager.store.Member().SchemaResult(attempt.Id(), &result, maxAttempts, waitBetween, perNumbers)
		if err != nil {
			wlog.Error(err.Error())

			return
		}
		if res.MemberStopCause != nil {
			attempt.SetMemberStopCause(res.MemberStopCause)
		}

		if res.Result != nil {
			attempt.SetResult(*res.Result)
		} else {
			attempt.SetResult(AttemptResultAbandoned)
		}
		queueManager.LeavingMember(attempt)
	}
}

func (queueManager *QueueManager) LeavingMember(attempt *Attempt) {
	if attempt.Result() == "" {
		attempt.SetResult(AttemptResultAbandoned)
	}

	if attempt.manualDistribution && attempt.bridgedAt == 0 {
		if err := queueManager.app.NotificationInterceptAttempt(attempt.domainId, attempt.QueueId(), attempt.channel, attempt.Id(), 0); err != nil {
			wlog.Error(fmt.Sprintf("intercept attempt %d notification, error : %s", attempt.Id(), err.Error()))
		}
	}

	// todo fixme: bug if offering && reporting
	if _, ok := queueManager.membersCache.Get(attempt.Id()); !ok {
		wlog.Error(fmt.Sprintf("[%d] not found", attempt.Id()))
		return
	}
	attempt.SetState(HookLeaving)
	attempt.Close()
	queueManager.membersCache.Remove(attempt.Id())
	queueManager.wg.Done()

	wlog.Info(fmt.Sprintf("[%s] leaving member %s[%v] AttemptId=%d  from queue \"%s\" [%d]", attempt.queue.TypeName(), attempt.Name(),
		attempt.MemberId(), attempt.Id(), attempt.queue.Name(), queueManager.membersCache.Len()))
}

func (queueManager *QueueManager) GetAttemptResource(attempt *Attempt) ResourceObject {
	if attempt.ResourceId() != nil && attempt.ResourceUpdatedAt() != nil {
		resource, err := queueManager.resourceManager.Get(*attempt.ResourceId(), *attempt.ResourceUpdatedAt())
		if err != nil {
			wlog.Error(fmt.Sprintf("attempt resource error: %s", err.Error()))
			//FIXME
		} else {
			return resource
		}
	}
	return nil
}

func (queueManager *QueueManager) GetAttemptAgent(attempt *Attempt) (agent_manager.AgentObject, bool) {

	if attempt.AgentId() != nil && attempt.AgentUpdatedAt() != nil {
		agent, err := queueManager.agentManager.GetAgent(*attempt.AgentId(), *attempt.AgentUpdatedAt())
		if err != nil {
			wlog.Error(fmt.Sprintf("attempt agent error: %s", err.Error()))
			//FIXME
		} else {
			return agent, true
		}
	}

	return nil, false
}

func (queueManager *QueueManager) GetAttempt(id int64) (*Attempt, bool) {
	if attempt, ok := queueManager.membersCache.Get(id); ok {
		return attempt.(*Attempt), true
	}

	return nil, false
}

func (queueManager *QueueManager) SetAttemptCancel(id int64, result string) bool {
	att, ok := queueManager.GetAttempt(id)
	if !ok {
		return false
	}
	att.SetResult(result)

	att.SetCancel()

	return true

}

func (queueManager *QueueManager) ResumeAttempt(id int64, domainId int64) *model.AppError {
	att, ok := queueManager.GetAttempt(id)
	if !ok || att.domainId != domainId {
		return model.NewAppError("QM", "qm.resume_attempt.valid", nil, "Not found", http.StatusNotFound)
	}

	att.agentChannel.Id()
	call, ok := att.agentChannel.(call_manager.Call)
	if ok {
		err := call.BreakPark(nil)
		if err != nil {
			att.Log(err.Error())
			return model.NewAppError("QM", "qm.resume_attempt.call", nil, err.Error(), http.StatusInternalServerError)
		}
	}

	return nil
}

func (queueManager *QueueManager) Abandoned(attempt *Attempt) {
	res, err := queueManager.store.Member().SetAttemptAbandonedWithParams(attempt.Id(), 0, 0, nil,
		attempt.perNumbers, attempt.excludeCurrNumber, attempt.redial, attempt.description, attempt.stickyAgentId)
	if err != nil {
		wlog.Error(err.Error())
	} else if res.MemberStopCause != nil {
		attempt.SetMemberStopCause(res.MemberStopCause)
	}

	if attempt.Result() == "" {
		attempt.SetResult(AttemptResultAbandoned)
	}
	queueManager.LeavingMember(attempt)
}

func (queueManager *QueueManager) Barred(attempt *Attempt) *model.AppError {
	//todo hook
	return queueManager.teamManager.store.Member().SetBarred(attempt.Id())
}

func (queueManager *QueueManager) SetAttemptSuccess(attempt *Attempt, vars map[string]string) {
	res, err := queueManager.teamManager.store.Member().SetAttemptResult(attempt.Id(), AttemptResultSuccess, "", 0,
		vars, attempt.maxAttempts, attempt.waitBetween, attempt.perNumbers, attempt.description, attempt.stickyAgentId)
	if err != nil {
		wlog.Error(err.Error())
	} else {
		if res.MemberStopCause != nil {
			attempt.SetMemberStopCause(res.MemberStopCause)
		}
		attempt.SetResult(AttemptResultSuccess)
	}
}

func (queueManager *QueueManager) SetAttemptAbandonedWithParams(attempt *Attempt, maxAttempts uint, sleep uint64, vars map[string]string) {
	res, err := queueManager.store.Member().SetAttemptAbandonedWithParams(attempt.Id(), maxAttempts, sleep, vars, attempt.perNumbers,
		attempt.excludeCurrNumber, attempt.redial, attempt.description, attempt.stickyAgentId)
	if err != nil {
		wlog.Error(err.Error())

		return
	}
	if res.MemberStopCause != nil {
		attempt.SetMemberStopCause(res.MemberStopCause)
	}

	if res.Result != nil {
		attempt.SetResult(*res.Result)
	} else {
		attempt.SetResult(AttemptResultAbandoned)
	}
}

func (queueManager *QueueManager) GetChat(id string) (*chat.Conversation, *model.AppError) {
	return queueManager.app.GetChat(id)
}

func (queueManager *QueueManager) closeBeforeReporting(attemptId int64, res *model.AttemptReportingResult, ccCause string, a *Attempt) (err *model.AppError) {

	if res.Channel == nil || res.AgentCallId == nil {
		return
	}

	switch *res.Channel {
	case model.QueueChannelCall:
		if call, ok := queueManager.callManager.GetCall(*res.AgentCallId); ok {
			err = call.Hangup("", true, map[string]string{
				"cc_result": ccCause,
			})
		}
		break
	case model.QueueChannelChat:
		var conv *chat.Conversation
		if a != nil && a.TransferredAt() == 0 {
			if conv, err = queueManager.GetChat(a.memberChannel.Id()); err == nil {
				err = conv.Reporting(false)
			}
		}
	case model.QueueChannelTask:
		var task *TaskChannel
		if task, err = queueManager.getAgentTaskFromAttemptId(attemptId); err == nil {
			err = task.Reporting()
		}
	}

	return
}

func (queueManager *QueueManager) setChannelReporting(attempt *Attempt, ccCause string, leave bool) (err *model.AppError) {

	if attempt.agentChannel == nil {
		return errNotFoundConnection
	}

	switch attempt.channel {
	case model.QueueChannelCall:
		if call, ok := queueManager.callManager.GetCall(attempt.agentChannel.Id()); ok {
			errCall := call.SerVariables(map[string]string{
				"cc_result":       ccCause,
				"cc_reporting_at": fmt.Sprintf("%d", model.GetMillis()),
			})

			if errCall != nil {
				attempt.Log(errCall.Error())
			}
		} else {
			return errNotFoundConnection
		}
		break
	case model.QueueChannelChat:
		var conv *chat.Conversation
		if conv, err = queueManager.GetChat(attempt.agentChannel.Id()); err == nil {
			err = conv.Reporting(leave)
		} else {
			return errNotFoundConnection
		}
	case model.QueueChannelTask:
		var task *TaskChannel
		if task, err = queueManager.getAgentTaskFromAttemptId(attempt.Id()); err == nil {
			err = task.Reporting()
		} else {
			return errNotFoundConnection
		}
	}

	return
}

func (queueManager *QueueManager) RenewalAttempt(domainId, attemptId int64, renewal uint32) (err *model.AppError) {
	var data *model.RenewalProcessing

	data, err = queueManager.store.Member().RenewalProcessing(domainId, attemptId, renewal)
	if err != nil {
		return err
	}

	ev := NewRenewalProcessingEvent(data.AttemptId, data.UserId, data.Channel, data.Timeout, data.Timestamp, data.RenewalSec)
	return queueManager.mq.AgentChannelEvent(data.Channel, data.DomainId, data.QueueId, data.UserId, ev)
}

func (queueManager *QueueManager) ReportingAttempt(attemptId int64, result model.AttemptCallback, system bool) *model.AppError {
	if result.Status == "" {
		result.Status = "abandoned"
	}

	wlog.Debug(fmt.Sprintf("attempt[%d] callback: %v", attemptId, result))

	attempt, _ := queueManager.GetAttempt(attemptId)

	var waitBetween uint64 = 0
	var maxAttempts uint = 0
	var perNumbers = false

	if attempt != nil {
		// TODO [biz]
		if queueManager.waitChannelClose && !system {
			attempt.SetCallback(&result)
			err := queueManager.setChannelReporting(attempt, result.Status, true)
			if err != nil {
				attempt.Log(err.Error())
			}
			if err != errNotFoundConnection && attempt.state != model.MemberStateProcessing {
				return err
			}
		}

		attempt.SetCallback(&result)
		if r, ok := attempt.AfterDistributeSchema(); ok {
			if r.Status != "" {
				result.Status = r.Status
			}
			if r.Variables != nil {
				result.Variables = model.UnionStringMaps(result.Variables, r.Variables)
			}
		}
		waitBetween = attempt.waitBetween
		maxAttempts = attempt.maxAttempts
		perNumbers = attempt.perNumbers
	}

	res, err := queueManager.store.Member().CallbackReporting(attemptId, &result, maxAttempts, waitBetween, perNumbers)
	if err != nil {
		return err
	}

	if !system {
		err = queueManager.closeBeforeReporting(attemptId, res, result.Status, attempt)
	}

	return queueManager.doLeavingReporting(attemptId, attempt, res, &result)
}

func (queueManager *QueueManager) doLeavingReporting(attemptId int64, attempt *Attempt, res *model.AttemptReportingResult, result *model.AttemptCallback) *model.AppError {
	var err *model.AppError
	if res.UserId != nil && res.DomainId != nil {
		var ev model.Event
		ch := ""
		if res.Channel != nil {
			ch = *res.Channel
		}

		// if team wrap_time = 0 then waiting
		if res.AgentTimeout != nil && *res.AgentTimeout > 0 {
			ev = NewWrapTimeEventEvent(ch, &attemptId, *res.UserId, res.Timestamp, *res.AgentTimeout)
		} else {
			//ev = NewWaitingChannelEvent(ch, *res.UserId, &attemptId, res.Timestamp)
			ev = NewWrapTimeEventEvent(ch, &attemptId, *res.UserId, res.Timestamp, 0)
		}
		q := 0
		if res.QueueId != nil {
			q = *res.QueueId
		}
		err = queueManager.mq.AgentChannelEvent("", *res.DomainId, q, *res.UserId, ev)
	}

	if attempt != nil {
		attempt.SetMemberStopCause(res.MemberStopCause)
		attempt.SetCallback(result)
		if attempt.channel == "chat" && attempt.state == model.MemberStateWaitAgent && !attempt.canceled {
			attempt.SetCancel()
		}

		// FIXME
		if attempt.queue.TypeName() == "predictive" && attempt.memberChannel != nil {
			select {
			case <-attempt.memberChannel.(*call_manager.CallImpl).HangupChan():
				break
			case <-time.After(time.Second):
				break
			}
		}
		queueManager.LeavingMember(attempt)
	}

	return err
}

func (queueManager *QueueManager) getAgentTaskFromAttemptId(id int64) (*TaskChannel, *model.AppError) {
	att, ok := queueManager.GetAttempt(id)
	if !ok {
		return nil, model.NewAppError("Queue.AcceptAgentTask", "queue.task.accept.not_found", nil,
			fmt.Sprintf("not found attempt_id=%d", id), http.StatusNotFound)
	}

	if att.channelData == nil {
		return nil, model.NewAppError("Queue.AcceptAgentTask", "queue.task.accept.valid.channel", nil,
			fmt.Sprintf("attempt_id=%d not a agent task", id), http.StatusBadRequest)
	}

	task, ok := att.channelData.(*TaskChannel)
	if !ok {
		return nil, model.NewAppError("Queue.AcceptAgentTask", "queue.task.accept.valid.channel", nil,
			fmt.Sprintf("attempt_id=%d not a agent task", id), http.StatusBadRequest)
	}

	return task, nil
}

func (queueManager *QueueManager) AcceptAgentTask(attemptId int64) *model.AppError {
	task, err := queueManager.getAgentTaskFromAttemptId(attemptId)
	if err != nil {
		return err
	}

	return task.SetAnswered()
}

func (queueManager *QueueManager) CloseAgentTask(attemptId int64) *model.AppError {
	task, err := queueManager.getAgentTaskFromAttemptId(attemptId)
	if err != nil {
		return err
	}

	return task.SetClosed()
}

func (queueManager *QueueManager) TransferTo(attempt *Attempt, toAttemptId int64) {
	// new result
	attempt.Log(fmt.Sprintf("transfer to attempt: %d", toAttemptId))
	attempt.SetResult(AttemptResultAbandoned)
	err := queueManager.store.Member().TransferredTo(attempt.Id(), toAttemptId)
	if err != nil {
		wlog.Error(err.Error())
	}
	//

	queueManager.LeavingMember(attempt)
}

func (queueManager *QueueManager) TransferFrom(team *agentTeam, attempt *Attempt, toAttemptId int64, toAgentId int,
	toAgentSession string, ch Channel) (agent_manager.AgentObject, *model.AppError) {
	a, err := queueManager.agentManager.GetAgent(toAgentId, 0)
	if err != nil {
		// fixme
		wlog.Error(err.Error())
	}

	if err = queueManager.store.Member().TransferredFrom(attempt.Id(), toAttemptId, a.Id(), toAgentSession); err != nil {
		//todo
		wlog.Error(err.Error())
	}

	if attempt.agent != nil {
		team.Transfer(attempt, attempt.agent)
	}
	attempt.agent = a

	team.Distribute(attempt.queue, a, NewTransferEvent(attempt, toAttemptId, a.UserId(), attempt.queue, a, attempt.queue.Processing(),
		nil, ch))

	return a, nil
}

func (queueManager *QueueManager) LosePredictAgent(id int) {
	if err := queueManager.store.Agent().LosePredictAttempt(id); err != nil {
		wlog.Error(err.Error())
	}
}

func (queueManager *QueueManager) CancelAgentDistribute(agentId int32) *model.AppError {
	attempts, err := queueManager.store.Member().CancelAgentDistribute(agentId)
	if err != nil {
		return err
	}

	for _, v := range attempts {
		att, _ := queueManager.GetAttempt(v)
		if att != nil && !att.canceled {
			att.SetCancel()
		}
	}

	return nil
}

func (queueManager *QueueManager) FlipAttemptResource(attempt *Attempt, skipp []int) (*model.AttemptFlipResource, *model.AppError) {
	res, err := queueManager.store.Member().FlipResource(attempt.Id(), skipp)
	if err != nil {
		return nil, err
	}

	if res.ResourceId == nil {
		return res, nil
	}

	attempt.FlipResource(res)
	attempt.resource = queueManager.GetAttemptResource(attempt)
	attempt.communication.Display = model.NewString(attempt.resource.GetDisplay())

	return res, nil
}

func (queueManager *QueueManager) AgentTeamHook(event string, agent agent_manager.AgentObject, teamUpdatedAt int64) {
	queueManager.teamManager.HookAgent(event, agent, teamUpdatedAt)
}

// waitTimeout waits for the waitgroup for the specified max timeout.
// Returns true if waiting timed out.
func waitTimeout(wg *sync.WaitGroup, timeout time.Duration) bool {
	c := make(chan struct{})
	go func() {
		defer close(c)
		wg.Wait()
	}()
	select {
	case <-c:
		return false // completed normally
	case <-time.After(timeout):
		return true // timed out
	}
}
