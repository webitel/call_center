package queue

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/protos/cc"
	"github.com/webitel/wlog"
	"net/http"
	"sync"
	"time"
)

const (
	MAX_QUEUES_CACHE        = 10000
	MAX_MEMBERS_CACHE       = 30000
	MAX_QUEUES_EXPIRE_CACHE = 60 * 60 * 24 //day
)

type QueueManager struct {
	wg              sync.WaitGroup
	app             App
	attemptCount    int64
	mq              mq.MQ
	stop            chan struct{}
	stopped         chan struct{}
	input           chan *Attempt
	queuesCache     utils.ObjectCache
	membersCache    utils.ObjectCache
	store           store.Store
	resourceManager *ResourceManager
	agentManager    agent_manager.AgentManager
	callManager     call_manager.CallManager
	teamManager     *teamManager
	sync.Mutex
}

func NewQueueManager(app App, s store.Store, m mq.MQ, callManager call_manager.CallManager, resourceManager *ResourceManager, agentManager agent_manager.AgentManager) *QueueManager {
	return &QueueManager{
		store:           s,
		app:             app,
		callManager:     callManager,
		resourceManager: resourceManager,
		agentManager:    agentManager,
		mq:              m,
		teamManager:     NewTeamManager(s, m),
		input:           make(chan *Attempt),
		stop:            make(chan struct{}),
		stopped:         make(chan struct{}),
		queuesCache:     utils.NewLruWithParams(MAX_QUEUES_CACHE, "QueueManager", MAX_QUEUES_EXPIRE_CACHE, ""),
		membersCache:    utils.NewLruWithParams(MAX_MEMBERS_CACHE, "Members", MAX_QUEUES_EXPIRE_CACHE, ""),
	}
}

func (queueManager *QueueManager) Start() {
	wlog.Debug("queueManager started")

	defer func() {
		wlog.Debug("stopped QueueManager")
		close(queueManager.stopped)
	}()

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

func (queueManager *QueueManager) Stop() {
	wlog.Debug("queueManager Stopping")
	wlog.Debug(fmt.Sprintf("wait for close attempts %d", queueManager.membersCache.Len()))
	queueManager.wg.Wait()
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
	queueManager.Lock()
	defer queueManager.Unlock()
	var queue QueueObject

	item, ok := queueManager.queuesCache.Get(id)
	if ok {
		queue, ok = item.(QueueObject)
		if ok && !queue.IsExpire(updatedAt) {
			return queue, nil
		}
	}

	if config, err := queueManager.app.GetQueueById(int64(id)); err != nil {
		return nil, err
	} else {
		queue, err = NewQueue(queueManager, queueManager.resourceManager, config)
		if err != nil {
			return nil, err
		}
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
		panic(err.Error())
		return nil, err
	}

	attempt.domainId = queue.DomainId()
	attempt.channel = queue.Channel()

	if attempt.IsBarred() {
		err = queueManager.Barred(attempt)
		if err != nil {
			wlog.Error(err.Error())
		} else {
			attempt.Log("this destination is barred")
		}
		return nil, nil
	}

	if attempt.IsTimeout() {
		//panic("CHANGE TO SET MEMBER FUNCTION")
		return nil, nil
	}

	attempt.resource = queueManager.GetAttemptResource(attempt)

	if err = queue.DistributeAttempt(attempt); err != nil {
		wlog.Error(err.Error())
		queueManager.Abandoned(attempt)
		queueManager.LeavingMember(attempt, queue)

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

	if in.BucketId != 0 {
		bucketId = &in.BucketId
	}

	// FIXME add domain
	res, err := queueManager.store.Member().DistributeCallToQueue(
		queueManager.app.GetInstanceId(),
		int64(in.GetQueue().GetId()),
		in.GetMemberCallId(),
		in.GetVariables(),
		bucketId,
		int(in.GetPriority()),
	)

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

	_, err = queueManager.callManager.InboundCall(callInfo, ringtone)
	if err != nil {
		printfIfErr(queueManager.store.Member().DistributeCallToQueueCancel(res.AttemptId))
		wlog.Error(fmt.Sprintf("[%s] call %s (%d) distribute error: %s", callInfo.AppId, callInfo.Id, res.AttemptId, err.Error()))
		return nil, err
	}

	attempt, _ := queueManager.CreateAttemptIfNotExists(ctx, &model.MemberAttempt{
		Id:                  res.AttemptId,
		QueueId:             res.QueueId,
		QueueUpdatedAt:      res.QueueUpdatedAt,
		QueueCount:          0, // TODO
		QueueActiveCount:    0,
		QueueWaitingCount:   0,
		CreatedAt:           time.Time{},
		HangupAt:            0,
		BridgedAt:           0,
		Destination:         res.Destination,
		ListCommunicationId: nil,
		TeamUpdatedAt:       model.NewInt64(res.TeamUpdatedAt),
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

func (queueManager *QueueManager) DistributeChatToQueue(ctx context.Context, in *cc.ChatJoinToQueueRequest) (*Attempt, *model.AppError) {
	//var member *model.MemberAttempt
	var bucketId *int32

	if in.BucketId != 0 {
		bucketId = &in.BucketId
	}

	// FIXME add domain
	res, err := queueManager.store.Member().DistributeChatToQueue(
		queueManager.app.GetInstanceId(),
		int64(in.GetQueue().GetId()),
		in.GetConversationId(),
		in.GetVariables(),
		bucketId,
		int(in.GetPriority()),
	)

	if err != nil {
		wlog.Error(err.Error())
		return nil, err
	}

	attempt, _ := queueManager.CreateAttemptIfNotExists(ctx, &model.MemberAttempt{
		Id:                  res.AttemptId,
		QueueId:             res.QueueId,
		QueueUpdatedAt:      res.QueueUpdatedAt,
		QueueCount:          0,
		QueueActiveCount:    0,
		QueueWaitingCount:   0,
		CreatedAt:           time.Time{},
		HangupAt:            0,
		BridgedAt:           0,
		Destination:         res.Destination,
		ListCommunicationId: nil,
		TeamUpdatedAt:       model.NewInt64(res.TeamUpdatedAt),
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
	queueManager.DistributeAttempt(attempt)
	return attempt, nil
}

func (queueManager *QueueManager) LeavingMember(attempt *Attempt, queue QueueObject) {
	queueManager.membersCache.Remove(attempt.Id())
	queueManager.wg.Done()

	wlog.Info(fmt.Sprintf("[%s] leaving member %s[%v] AttemptId=%d  from queue \"%s\" [%d]", queue.TypeName(), attempt.Name(),
		attempt.MemberId(), attempt.Id(), queue.Name(), queueManager.membersCache.Len()))
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

func (queueManager *QueueManager) Abandoned(attempt *Attempt) {
	attempt.SetResult(AttemptResultAbandoned)
	_, err := queueManager.store.Member().SetAttemptAbandoned(attempt.Id())
	if err != nil {
		wlog.Error(err.Error())

		return
	}
}

func (queueManager *QueueManager) Barred(attempt *Attempt) *model.AppError {
	//todo hook
	return queueManager.teamManager.store.Member().SetBarred(attempt.Id())
}

func (queueManager *QueueManager) SetAttemptAbandonedWithParams(attempt *Attempt, maxAttempts uint, sleep uint64) {
	attempt.SetResult(AttemptResultAbandoned)
	_, err := queueManager.store.Member().SetAttemptAbandonedWithParams(attempt.Id(), maxAttempts, sleep)
	if err != nil {
		wlog.Error(err.Error())

		return
	}
}

func (queueManager *QueueManager) GetChat(id string) (*chat.Conversation, *model.AppError) {
	return queueManager.app.GetChat(id)
}

func (queueManager *QueueManager) closeBeforeReporting(attemptId int64, res *model.AttemptReportingResult) (err *model.AppError) {

	if res.Channel == nil || res.AgentCallId == nil {
		return
	}

	switch *res.Channel {
	case model.QueueChannelCall:
		if call, ok := queueManager.callManager.GetCall(*res.AgentCallId); ok {
			err = call.Hangup("", true)
		}
		break
	case model.QueueChannelChat:
		var conv *chat.Conversation
		if conv, err = queueManager.GetChat(*res.AgentCallId); err == nil {
			err = conv.Reporting()
		}
	case model.QueueChannelTask:
		var task *TaskChannel
		if task, err = queueManager.getAgentTaskFromAttemptId(attemptId); err == nil {
			err = task.Reporting()
		}
	}

	return
}

func (queueManager *QueueManager) ReportingAttempt(attemptId int64, result model.AttemptResult2) *model.AppError {

	// TODO
	if !result.Success && result.Status == "" {
		result.Status = "abandoned"
	}

	wlog.Debug(fmt.Sprintf("attempt[%d] callback: %v", attemptId, result))

	res, err := queueManager.store.Member().CallbackReporting(attemptId, result.Status, result.Description, result.ExpireAt, result.NextCall)
	if err != nil {
		return err
	}

	err = queueManager.closeBeforeReporting(attemptId, res)

	if res.UserId != nil && res.DomainId != nil {
		e := WaitingChannelEvent{
			ChannelEvent: ChannelEvent{
				Timestamp: res.Timestamp,
				AttemptId: model.NewInt64(attemptId),
				Status:    model.ChannelStateWaiting,
			},
		}

		ev := model.NewEvent("channel", *res.UserId, e)
		err = queueManager.mq.AgentChannelEvent("", *res.DomainId, res.QueueId, *res.UserId, ev)
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
