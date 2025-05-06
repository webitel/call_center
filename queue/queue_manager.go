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
	maxQueueCache  = 10000
	maxMemberCache = 50000
	maxExpireCache = 0 //60 * 60 * 24 //day

	timeoutWaitBeforeStop = time.Second * 10
)

type Manager struct {
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
	log              *wlog.Logger
	sync.Mutex
}

var (
	errNotFoundConnection = model.NewAppError("QM", "qm.connection.not_found", nil, "Not found", http.StatusNotFound)
)

var (
	queueGroup singleflight.Group
)

func NewQueueManager(app App, s store.Store, m mq.MQ, callManager call_manager.CallManager, resourceManager *ResourceManager,
	agentManager agent_manager.AgentManager, bridgeSleep time.Duration) *Manager {
	return &Manager{
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
		queuesCache:      utils.NewLruWithParams(maxQueueCache, "QueueManager", maxExpireCache, ""),
		membersCache:     utils.NewLruWithParams(maxMemberCache, "Members", maxExpireCache, ""),
		log: wlog.GlobalLogger().With(
			wlog.Namespace("context"),
			wlog.String("name", "queue_manager"),
		),
	}
}

func (qm *Manager) Start() {
	qm.log.Debug("queueManager started")

	defer func() {
		qm.log.Debug("stopped QueueManager")
		close(qm.stopped)
	}()

	qm.listenWaitingList()

	for {
		select {
		case <-qm.stop:
			qm.log.Debug("queueManager received stop signal")
			close(qm.input)
			return
		case attempt := <-qm.input:
			qm.DistributeAttempt(attempt)
			//case call := <-queueManager.callManager.InboundCall():
			//	go queueManager.DistributeCall(call)
		}
	}
}

func (qm *Manager) closeAttempts() {
	var err *model.AppError
	var id int64
	var ok bool

	for _, v := range qm.membersCache.Keys() {
		fmt.Println(v)
		if id, ok = v.(int64); !ok {
			continue
		}

		err = qm.ReportingAttempt(id, model.AttemptCallback{
			Status: "shutdown", // TODO
		}, false)
		if err != nil {
			qm.log.Error(err.Error(),
				wlog.Err(err),
			)
		}
	}
}

func (qm *Manager) Stop() {
	qm.log.Debug("queueManager Stopping")
	qm.stopWaitingList()
	qm.log.Debug(fmt.Sprintf("wait %v for close attempts %d", timeoutWaitBeforeStop, qm.membersCache.Len()))

	if waitTimeout(&qm.wg, timeoutWaitBeforeStop) {
		qm.closeAttempts()
	}

	close(qm.stop)
	<-qm.stopped
}

func (qm *Manager) GetNodeId() string {
	return qm.app.GetInstanceId()
}

func (qm *Manager) CreateAttemptIfNotExists(ctx context.Context, attempt *model.MemberAttempt) (*Attempt, *model.AppError) {
	var a *Attempt
	var ok bool

	if a, ok = qm.GetAttempt(attempt.Id); ok {
		panic("ERROR")
		//if attempt.Result == nil {
		//	wlog.Error(fmt.Sprintf("attempt %v in queue", a.Id()))
		//} else {
		//	a.SetMember(attempt)
		//}
	} else {
		a = qm.createAttempt(ctx, attempt)
		if attempt.AgentId != nil && attempt.AgentUpdatedAt != nil {
			if agent, err := qm.agentManager.GetAgent(*attempt.AgentId, *attempt.AgentUpdatedAt); err != nil {
				panic(err.Error())
			} else {
				a.SetAgent(agent)
			}
		}
	}

	return a, nil
}

func (qm *Manager) createAttempt(ctx context.Context, conf *model.MemberAttempt) *Attempt {
	attempt := NewAttempt(ctx, conf, qm.log)
	qm.membersCache.AddWithDefaultExpires(attempt.Id(), attempt)
	qm.wg.Add(1)
	qm.attemptCount++
	return attempt
}

func (qm *Manager) GetQueue(id int, updatedAt int64) (QueueObject, *model.AppError) {
	var v interface{}
	var ok bool
	var doErr error
	var err *model.AppError

	var queue QueueObject

	item, ok := qm.queuesCache.Get(id)
	if ok {
		queue, ok = item.(QueueObject)
		if ok && !queue.IsExpire(updatedAt) {
			return queue, nil
		}
	}

	v, doErr, _ = queueGroup.Do(fmt.Sprintf("queue-%d-%d", id, updatedAt), func() (interface{}, error) {
		res, appErr := qm.app.GetQueueById(int64(id))
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

	queue, err = NewQueue(qm, qm.resourceManager, queueParams)
	if err != nil {
		return nil, err
	}

	qm.queuesCache.AddWithDefaultExpires(id, queue)
	queue.Log().Debug(fmt.Sprintf("add queue %s to cache", queue.Name()))
	return queue, nil
}

func (qm *Manager) GetResource(id, updatedAt int64) (ResourceObject, *model.AppError) {
	return qm.resourceManager.Get(id, updatedAt)
}

func (qm *Manager) SetResourceError(resource ResourceObject, errorId string) {
	if resource.CheckCodeError(errorId) {
		resource.Log().Warn(fmt.Sprintf("resource %s Id=%d error: %s", resource.Name(), resource.Id(), errorId),
			wlog.String("error_id", errorId),
		)

		if responseError, err := qm.store.OutboundResource().
			SetError(int64(resource.Id()), int64(1), errorId, model.OUTBOUND_RESOURCE_STRATEGY_RANDOM); err != nil {

			resource.Log().Error(err.Error(),
				wlog.Err(err),
			)
		} else {
			if responseError.Stopped != nil && *responseError.Stopped {
				resource.Log().Info(fmt.Sprintf("resource %s [%d] stopped, because: %s", resource.Name(), resource.Id(), errorId))
			}

			if responseError.UnReserveResourceId != nil {
				resource.Log().Info(fmt.Sprintf("new resource ResourceId=%d from reserve", *responseError.UnReserveResourceId))
			}
			qm.resourceManager.RemoveFromCacheById(int64(resource.Id()))
		}
	} else {
		qm.SetResourceSuccessful(resource)
	}
}

func (qm *Manager) SetResourceSuccessful(resource ResourceObject) {
	if resource.SuccessivelyErrors() > 0 {
		if err := qm.store.OutboundResource().SetSuccessivelyErrorsById(int64(resource.Id()), 0); err != nil {
			resource.Log().Error(err.Error(),
				wlog.Err(err),
			)
		}
		resource.SetSuccessivelyErrors(0)
	}
}

func (qm *Manager) SetAgentWaitingChannel(agent agent_manager.AgentObject, channel string) (int64, *model.AppError) {
	timestamp, err := qm.store.Agent().WaitingChannel(agent.Id(), channel)
	if err != nil {
		return 0, err
	}

	e := NewWaitingChannelEvent(channel, agent.UserId(), nil, timestamp)
	return 0, qm.mq.AgentChannelEvent(channel, agent.DomainId(), 0, agent.UserId(), e)
}

func (qm *Manager) DistributeAttempt(attempt *Attempt) (QueueObject, *model.AppError) {

	queue, err := qm.GetQueue(attempt.QueueId(), attempt.QueueUpdatedAt())
	if err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
		//TODO added to model "dialing.queue.new_queue.app_error"
		//panic(err.Error())
		return nil, err
	}

	attempt.domainId = queue.DomainId()
	attempt.channel = queue.Channel()
	attempt.queue = queue

	if attempt.IsBarred() {
		err = qm.Barred(attempt)
		if err != nil {
			attempt.log.Error(err.Error(),
				wlog.Err(err),
			)
		} else {
			attempt.Log("this destination is barred")
		}
		queue.Leaving(attempt)
		return nil, nil
	}

	//if attempt.IsTimeout() {
	//	return nil, nil
	//}

	//todo new event instance

	attempt.resource = qm.GetAttemptResource(attempt)

	if err = queue.DistributeAttempt(attempt); err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
		qm.Abandoned(attempt)
		qm.LeavingMember(attempt)

		return nil, err
	} else {
		attempt.log.Info(fmt.Sprintf("[%s] join member %s[%v] AttemptId=%d to queue \"%s\" (size %d, waiting %d, active %d)", queue.TypeName(), attempt.Name(),
			attempt.MemberId(), attempt.Id(), queue.Name(), attempt.member.QueueCount, attempt.member.QueueWaitingCount, attempt.member.QueueActiveCount))
	}

	return queue, nil
}

func (qm *Manager) DistributeCall(_ context.Context, in *cc.CallJoinToQueueRequest) (*Attempt, *model.AppError) {
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
	res, err := qm.store.Member().DistributeCallToQueue(
		qm.app.GetInstanceId(),
		int64(in.GetQueue().GetId()),
		in.GetMemberCallId(),
		in.GetVariables(),
		bucketId,
		int(in.GetPriority()),
		stickyAgentId,
	)

	if err != nil {
		qm.log.Error(fmt.Sprintf("[inbound] join member call_id %s queue %d, %s", in.GetMemberCallId(), in.GetQueue().GetId(), err.Error()),
			wlog.Err(err),
		)
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

	if q, err = qm.GetQueue(res.QueueId, res.QueueUpdatedAt); err != nil {
		qm.log.Error(fmt.Sprintf("[inbound] join member call_id %s queue %d, %s", in.GetMemberCallId(), in.GetQueue().GetId(), err.Error()),
			wlog.Err(err),
			wlog.Int64("attempt_id", res.AttemptId),
			wlog.Int("queue_id", res.QueueId),
		)
		return nil, err
	}

	if ringtone == "" {
		if q != nil {
			ringtone = q.RingtoneUri()
		}
	}

	_, err = qm.callManager.InboundCallQueue(callInfo, ringtone, q.Variables())
	if err != nil {
		printfIfErr(qm.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		qm.log.Error(fmt.Sprintf("[%s] call %s (%d) distribute error: %s", callInfo.AppId, callInfo.Id, res.AttemptId, err.Error()),
			wlog.Err(err),
			wlog.Int64("attempt_id", res.AttemptId),
			wlog.Int("queue_id", res.QueueId),
		)
		return nil, err
	}

	attempt, _ := qm.CreateAttemptIfNotExists(context.Background(), &model.MemberAttempt{
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
		BucketId:            bucketId,
	})

	if _, err = qm.DistributeAttempt(attempt); err != nil {
		printfIfErr(qm.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		return nil, err
	}

	return attempt, nil
}

func (qm *Manager) DistributeCallToAgent(ctx context.Context, in *cc.CallJoinToAgentRequest) (*Attempt, *model.AppError) {
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

	res, err := qm.store.Member().DistributeCallToAgent(
		qm.app.GetInstanceId(),
		in.GetMemberCallId(),
		in.GetVariables(),
		in.GetAgentId(),
		in.CancelDistribute,
		qParams,
	)

	if err != nil {
		qm.log.Error(err.Error(),
			wlog.Err(err),
		)
		return nil, err
	}

	if in.CancelDistribute {
		err = qm.CancelAgentDistribute(in.GetAgentId())
		if err != nil {
			qm.log.Error(err.Error(),
				wlog.Err(err),
			)
		}
	}

	agent, err = qm.agentManager.GetAgent(int(in.GetAgentId()), res.AgentUpdatedAt)
	if err != nil {
		qm.log.Error(err.Error(),
			wlog.Err(err),
		)
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

	_, err = qm.callManager.ConnectCall(callInfo, ringtone)
	if err != nil {
		printfIfErr(qm.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		qm.log.Error(fmt.Sprintf("[%s] call %s (%d) distribute error: %s", callInfo.AppId, callInfo.Id, res.AttemptId, err.Error()),
			wlog.Err(err),
			wlog.Int64("attempt_id", res.AttemptId),
		)
		return nil, err
	}

	attempt, _ := qm.CreateAttemptIfNotExists(ctx, &model.MemberAttempt{
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
			BaseQueue: NewBaseQueue(qm, qm.resourceManager, settings),
		},
	}

	attempt.queue = &queue
	attempt.agent = agent
	attempt.domainId = queue.domainId
	attempt.channel = model.QueueChannelCall

	if err = queue.DistributeAttempt(attempt); err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
		qm.Abandoned(attempt)
		qm.LeavingMember(attempt)

		return nil, err
	} else {
		attempt.log.Info(fmt.Sprintf("[%s] join member %s[%v] AttemptId=%d to queue \"%s\" (size %d, waiting %d, active %d)", queue.TypeName(), attempt.Name(),
			attempt.MemberId(), attempt.Id(), queue.Name(), attempt.member.QueueCount, attempt.member.QueueWaitingCount, attempt.member.QueueActiveCount))
	}

	return attempt, nil
}

func (qm *Manager) DistributeTaskToAgent(ctx context.Context, in *cc.TaskJoinToAgentRequest) (*Attempt, *model.AppError) {
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

	res, err := qm.store.Member().DistributeTaskToAgent(
		qm.app.GetInstanceId(),
		in.DomainId,
		in.GetAgentId(),
		dest,
		in.GetVariables(),
		in.CancelDistribute,
		qParams,
	)

	if err != nil {
		qm.log.Error(err.Error(),
			wlog.Err(err),
		)
		return nil, err
	}

	if in.CancelDistribute {
		err = qm.CancelAgentDistribute(in.GetAgentId())
		if err != nil {
			qm.log.Error(err.Error(),
				wlog.Err(err),
			)
		}
	}

	agent, err = qm.agentManager.GetAgent(int(in.GetAgentId()), res.AgentUpdatedAt)
	if err != nil {
		qm.log.Error(err.Error(),
			wlog.Err(err),
		)
		return nil, err
	}

	attempt, _ := qm.CreateAttemptIfNotExists(ctx, &model.MemberAttempt{
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
		BaseQueue: NewBaseQueue(qm, qm.resourceManager, settings),
	}

	attempt.queue = &queue
	attempt.agent = agent
	attempt.domainId = queue.domainId
	attempt.channel = model.QueueChannelTask

	if err = queue.DistributeAttempt(attempt); err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
		qm.Abandoned(attempt)
		qm.LeavingMember(attempt)

		return nil, err
	} else {
		attempt.log.Info(fmt.Sprintf("[%s] join member %s[%v] AttemptId=%d to queue \"%s\" (size %d, waiting %d, active %d)", queue.TypeName(), attempt.Name(),
			attempt.MemberId(), attempt.Id(), queue.Name(), attempt.member.QueueCount, attempt.member.QueueWaitingCount, attempt.member.QueueActiveCount))
	}

	return attempt, nil
}

func (qm *Manager) DistributeChatToQueue(_ context.Context, in *cc.ChatJoinToQueueRequest) (*Attempt, *model.AppError) {
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
	res, err := qm.store.Member().DistributeChatToQueue(
		qm.app.GetInstanceId(),
		int64(in.GetQueue().GetId()),
		in.GetConversationId(),
		in.GetVariables(),
		bucketId,
		int(in.GetPriority()),
		stickyAgentId,
	)

	if err != nil {
		qm.log.Error(err.Error(),
			wlog.Err(err),
		)
		return nil, err
	}

	attempt, _ := qm.CreateAttemptIfNotExists(context.Background(), &model.MemberAttempt{
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
		ListCommunicationId: res.ListCommunicationId,
		TeamUpdatedAt:       res.TeamUpdatedAt,
		Variables:           res.Variables,
		Name:                res.Name,
		MemberCallId:        &res.ConversationId,
		BucketId:            bucketId,
	})

	if _, err = qm.DistributeAttempt(attempt); err != nil {
		printfIfErr(qm.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		return nil, err
	}
	return attempt, nil
}

func (qm *Manager) DistributeDirectMember(memberId int64, communicationId, agentId int) (*Attempt, *model.AppError) {
	// FIXME -1
	member, err := qm.store.Member().DistributeDirect(qm.app.GetInstanceId(), memberId, communicationId-1, agentId)

	if err != nil {
		qm.log.Error(fmt.Sprintf("member %v to agent %v distribute error: %s", memberId, agentId, err.Error()),
			wlog.Err(err),
			wlog.Int64("member_id", memberId),
			wlog.Int("agent_id", agentId),
		)
		return nil, err
	}

	attempt, _ := qm.CreateAttemptIfNotExists(context.Background(), member)
	if _, err = qm.DistributeAttempt(attempt); err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
	}
	if err = qm.app.NotificationHideMember(attempt.domainId, attempt.QueueId(), attempt.MemberId(), agentId); err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
	}
	return attempt, nil
}

func (qm *Manager) InterceptAttempt(ctx context.Context, domainId int64, attemptId int64, agentId int32) *model.AppError {
	queueId, err := qm.store.Member().Intercept(ctx, domainId, attemptId, agentId)
	if err != nil {
		qm.log.Error(fmt.Sprintf("intercept %v to agent %v error: %s", attemptId, agentId, err.Error()),
			wlog.Err(err),
			wlog.Int64("attempt_id", attemptId),
			wlog.Int64("agent_id", int64(agentId)),
		)
		return err
	}

	if err = qm.app.NotificationInterceptAttempt(domainId, queueId, "", attemptId, agentId); err != nil {
		qm.log.Error(fmt.Sprintf("intercept attempt %d notification, error : %s", attemptId, err.Error()),
			wlog.Err(err),
			wlog.Int64("attempt_id", attemptId),
			wlog.Int64("agent_id", int64(agentId)),
		)
	}

	return nil
}

func (qm *Manager) TimeoutLeavingMember(attempt *Attempt) {
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

		res, err := qm.store.Member().SchemaResult(attempt.Id(), &result, maxAttempts, waitBetween, perNumbers)
		if err != nil {
			attempt.log.Error(err.Error(),
				wlog.Err(err),
			)

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
		qm.LeavingMember(attempt)
	}
}

func (qm *Manager) LeavingMember(attempt *Attempt) {
	if attempt.Result() == "" {
		attempt.SetResult(AttemptResultAbandoned)
	}

	if attempt.manualDistribution && attempt.bridgedAt == 0 {
		if err := qm.app.NotificationInterceptAttempt(attempt.domainId, attempt.QueueId(), attempt.channel, attempt.Id(), 0); err != nil {
			attempt.log.Error(fmt.Sprintf("intercept attempt %d notification, error : %s", attempt.Id(), err.Error()),
				wlog.Err(err),
			)
		}
	}

	// todo fixme: bug if offering && reporting
	if _, ok := qm.membersCache.Get(attempt.Id()); !ok {
		attempt.log.Error(fmt.Sprintf("[%d] not found", attempt.Id()))
		return
	}
	attempt.SetState(HookLeaving)
	attempt.Close()
	qm.membersCache.Remove(attempt.Id())
	qm.wg.Done()

	attempt.log.Info(fmt.Sprintf("[%s] leaving member %s[%v] AttemptId=%d  from queue \"%s\" [%d]", attempt.queue.TypeName(), attempt.Name(),
		attempt.MemberId(), attempt.Id(), attempt.queue.Name(), qm.membersCache.Len()))
}

func (qm *Manager) GetAttemptResource(attempt *Attempt) ResourceObject {
	if attempt.ResourceId() != nil && attempt.ResourceUpdatedAt() != nil {
		resource, err := qm.resourceManager.Get(*attempt.ResourceId(), *attempt.ResourceUpdatedAt())
		if err != nil {
			attempt.log.Error(fmt.Sprintf("attempt resource error: %s", err.Error()),
				wlog.Err(err),
			)
			//FIXME
		} else {
			return resource
		}
	}
	return nil
}

func (qm *Manager) GetAttemptAgent(attempt *Attempt) (agent_manager.AgentObject, bool) {

	if attempt.AgentId() != nil && attempt.AgentUpdatedAt() != nil {
		agent, err := qm.agentManager.GetAgent(*attempt.AgentId(), *attempt.AgentUpdatedAt())
		if err != nil {
			attempt.log.Error(fmt.Sprintf("attempt agent error: %s", err.Error()),
				wlog.Err(err),
			)
			//FIXME
		} else {
			return agent, true
		}
	}

	return nil, false
}

func (qm *Manager) GetAttempt(id int64) (*Attempt, bool) {
	if attempt, ok := qm.membersCache.Get(id); ok {
		return attempt.(*Attempt), true
	}

	return nil, false
}

func (qm *Manager) SetAttemptCancel(id int64, result string) bool {
	att, ok := qm.GetAttempt(id)
	if !ok {
		return false
	}
	att.SetResult(result)
	att.log.Debug("SetAttemptCancel",
		wlog.String("result", result),
	)
	att.SetCancel()

	return true

}

func (qm *Manager) ResumeAttempt(id int64, domainId int64) *model.AppError {
	att, ok := qm.GetAttempt(id)
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

func (qm *Manager) SaveFormFields(ctx context.Context, domainId int64, id int64, fields map[string]string, form []byte) *model.AppError {
	att, ok := qm.GetAttempt(id)
	if !ok || att.domainId != domainId {
		return model.NewAppError("QM", "qm.save_form_fields.valid", nil, "Not found", http.StatusNotFound)
	}

	if att.processingFormStarted {
		att.UpdateProcessingFields(fields)
		att.processingForm.Update(form, fields)
	}

	// store db ?

	return nil
}

func (qm *Manager) Abandoned(attempt *Attempt) {
	res, err := qm.store.Member().SetAttemptAbandonedWithParams(attempt.Id(), 0, 0, nil,
		attempt.perNumbers, attempt.excludeCurrNumber, attempt.redial, attempt.description, attempt.stickyAgentId)
	if err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
	} else if res.MemberStopCause != nil {
		attempt.SetMemberStopCause(res.MemberStopCause)
	}

	if attempt.Result() == "" {
		attempt.SetResult(AttemptResultAbandoned)
	}
	qm.LeavingMember(attempt)
}

func (qm *Manager) Barred(attempt *Attempt) *model.AppError {
	//todo hook
	return qm.teamManager.store.Member().SetBarred(attempt.Id())
}

func (qm *Manager) SetAttemptSuccess(attempt *Attempt, vars map[string]string) {
	res, err := qm.teamManager.store.Member().SetAttemptResult(attempt.Id(), AttemptResultSuccess, "", 0,
		vars, attempt.maxAttempts, attempt.waitBetween, attempt.perNumbers, attempt.description, attempt.stickyAgentId)
	if err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
	} else {
		if res.MemberStopCause != nil {
			attempt.SetMemberStopCause(res.MemberStopCause)
		}
		attempt.SetResult(AttemptResultSuccess)
	}
}

func (qm *Manager) SetAttemptAbandonedWithParams(attempt *Attempt, maxAttempts uint, sleep uint64, vars map[string]string) {
	res, err := qm.store.Member().SetAttemptAbandonedWithParams(attempt.Id(), maxAttempts, sleep, vars, attempt.perNumbers,
		attempt.excludeCurrNumber, attempt.redial, attempt.description, attempt.stickyAgentId)
	if err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
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

func (qm *Manager) GetChat(id string) (*chat.Conversation, *model.AppError) {
	return qm.app.GetChat(id)
}

func (qm *Manager) closeBeforeReporting(attemptId int64, res *model.AttemptReportingResult, ccCause string, a *Attempt) (err *model.AppError) {

	if res.Channel == nil || res.AgentCallId == nil {
		return
	}

	switch *res.Channel {
	case model.QueueChannelCall:
		if call, ok := qm.callManager.GetCall(*res.AgentCallId); ok {
			err = call.Hangup("", true, map[string]string{
				"cc_result": ccCause,
			})
		}
		break
	case model.QueueChannelChat:
		var conv *chat.Conversation
		if a != nil && a.TransferredAt() == 0 {
			if conv, err = qm.GetChat(a.memberChannel.Id()); err == nil {
				err = conv.Reporting(false)
			}
		}
	case model.QueueChannelTask:
		var task *TaskChannel
		if task, err = qm.getAgentTaskFromAttemptId(attemptId); err == nil {
			err = task.Reporting()
		}
	}

	return
}

func (qm *Manager) setChannelReporting(attempt *Attempt, ccCause string, leave bool) (err *model.AppError) {

	if attempt.agentChannel == nil {
		return errNotFoundConnection
	}

	switch attempt.channel {
	case model.QueueChannelCall:
		if call, ok := qm.callManager.GetCall(attempt.agentChannel.Id()); ok {
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
		if conv, err = qm.GetChat(attempt.agentChannel.Id()); err == nil {
			err = conv.Reporting(leave)
		} else {
			return errNotFoundConnection
		}
	case model.QueueChannelTask:
		var task *TaskChannel
		if task, err = qm.getAgentTaskFromAttemptId(attempt.Id()); err == nil {
			err = task.Reporting()
		} else {
			return errNotFoundConnection
		}
	}

	return
}

func (qm *Manager) RenewalAttempt(domainId, attemptId int64, renewal uint32) (err *model.AppError) {
	var data *model.RenewalProcessing

	data, err = qm.store.Member().RenewalProcessing(domainId, attemptId, renewal)
	if err != nil {
		return err
	}

	ev := NewRenewalProcessingEvent(data.AttemptId, data.UserId, data.Channel, data.Timeout, data.Timestamp, data.RenewalSec)
	return qm.mq.AgentChannelEvent(data.Channel, data.DomainId, data.QueueId, data.UserId, ev)
}

func (qm *Manager) ReportingAttempt(attemptId int64, result model.AttemptCallback, system bool) *model.AppError {
	if result.Status == "" {
		result.Status = "abandoned"
	}

	qm.log.Debug(fmt.Sprintf("attempt[%d] callback: %v", attemptId, result),
		wlog.Int64("attempt_id", attemptId),
		wlog.Any("result", result),
	)

	attempt, _ := qm.GetAttempt(attemptId)

	var waitBetween uint64 = 0
	var maxAttempts uint = 0
	var perNumbers = false

	if attempt != nil {
		// TODO [biz]
		if qm.waitChannelClose && !system {
			attempt.SetCallback(&result)
			err := qm.setChannelReporting(attempt, result.Status, true)
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

	res, err := qm.store.Member().CallbackReporting(attemptId, &result, maxAttempts, waitBetween, perNumbers)
	if err != nil {
		return err
	}

	if !system {
		err = qm.closeBeforeReporting(attemptId, res, result.Status, attempt)
	}

	return qm.doLeavingReporting(attemptId, attempt, res, &result)
}

func (qm *Manager) doLeavingReporting(attemptId int64, attempt *Attempt, res *model.AttemptReportingResult, result *model.AttemptCallback) *model.AppError {
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
		err = qm.mq.AgentChannelEvent("", *res.DomainId, q, *res.UserId, ev)
	}

	if attempt != nil {
		attempt.SetMemberStopCause(res.MemberStopCause)
		attempt.SetCallback(result)
		if attempt.channel == "chat" && attempt.state == model.MemberStateWaitAgent && !attempt.canceled {
			attempt.SetCancel()
		}

		// FIXME
		if (attempt.queue.TypeName() == "predictive" || attempt.queue.TypeName() == "inbound") && attempt.memberChannel != nil {
			select {
			case <-attempt.memberChannel.(*call_manager.CallImpl).HangupChan():
				break
			case <-time.After(time.Second):
				break
			}
		}
		qm.LeavingMember(attempt)
	}

	return err
}

func (qm *Manager) getAgentTaskFromAttemptId(id int64) (*TaskChannel, *model.AppError) {
	att, ok := qm.GetAttempt(id)
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

func (qm *Manager) AcceptAgentTask(attemptId int64) *model.AppError {
	task, err := qm.getAgentTaskFromAttemptId(attemptId)
	if err != nil {
		return err
	}

	return task.SetAnswered()
}

func (qm *Manager) CloseAgentTask(attemptId int64) *model.AppError {
	task, err := qm.getAgentTaskFromAttemptId(attemptId)
	if err != nil {
		return err
	}

	return task.SetClosed()
}

func (qm *Manager) TransferTo(attempt *Attempt, toAttemptId int64) {
	// new result
	attempt.Log(fmt.Sprintf("transfer to attempt: %d", toAttemptId))
	attempt.SetResult(AttemptResultAbandoned)
	err := qm.store.Member().TransferredTo(attempt.Id(), toAttemptId)
	if err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
			wlog.Int64("to_attempt_id", toAttemptId),
		)
	}
	//

	qm.LeavingMember(attempt)
}

func (qm *Manager) TransferFrom(team *agentTeam, attempt *Attempt, toAttemptId int64, toAgentId int,
	toAgentSession string, ch Channel) (agent_manager.AgentObject, *model.AppError) {
	a, err := qm.agentManager.GetAgent(toAgentId, 0)
	if err != nil {
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
		return nil, err
	}

	if err = qm.store.Member().TransferredFrom(attempt.Id(), toAttemptId, a.Id(), toAgentSession); err != nil {
		//todo
		attempt.log.Error(err.Error(),
			wlog.Err(err),
		)
	}

	if attempt.agent != nil {
		team.Transfer(attempt, attempt.agent)
	}
	attempt.agent = a

	team.Distribute(attempt.queue, a, NewTransferEvent(attempt, toAttemptId, a.UserId(), attempt.queue, a, attempt.queue.Processing(),
		nil, ch))

	return a, nil
}

func (qm *Manager) LosePredictAgent(id int) {
	if err := qm.store.Agent().LosePredictAttempt(id); err != nil {
		qm.log.Error(err.Error(),
			wlog.Err(err),
			wlog.Int("agent_id", id),
		)
	}
}

func (qm *Manager) CancelAgentDistribute(agentId int32) *model.AppError {
	attempts, err := qm.store.Member().CancelAgentDistribute(agentId)
	if err != nil {
		return err
	}

	for _, v := range attempts {
		att, _ := qm.GetAttempt(v)
		if att != nil && !att.canceled {
			att.log.Debug("CancelAgentDistribute")
			att.SetCancel()
		}
	}

	return nil
}

func (qm *Manager) FlipAttemptResource(attempt *Attempt, skipp []int) (*model.AttemptFlipResource, *model.AppError) {
	res, err := qm.store.Member().FlipResource(attempt.Id(), skipp)
	if err != nil {
		return nil, err
	}

	if res.ResourceId == nil {
		return res, nil
	}

	attempt.FlipResource(res)
	attempt.resource = qm.GetAttemptResource(attempt)
	attempt.communication.Display = model.NewString(attempt.resource.GetDisplay())

	return res, nil
}

func (qm *Manager) AgentTeamHook(event string, agent agent_manager.AgentObject, teamUpdatedAt int64) {
	qm.teamManager.HookAgent(event, agent, teamUpdatedAt)
}

// waitTimeout waits for the wait group for the specified max timeout.
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
