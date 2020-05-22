package queue

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/grpc_api/cc"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
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

	e := NewWaitingChannelEvent(channel, nil, timestamp)
	return 0, queueManager.mq.ChannelEvent(channel, agent.DomainId(), agent.Id(), e)
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
		//TODO fixme
		panic("AAAA")
		//queueManager.attemptBarred(attempt, queue)
		return nil, nil
	}

	if attempt.IsTimeout() {
		panic("CHANGE TO SET MEMBER FUNCTION")
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
	var member *model.MemberAttempt

	req, err := queueManager.app.GetCall(in.MemberCallId)
	if err != nil {
		wlog.Error(fmt.Sprintf("distribute error: %s", err.Error()))
		return nil, err
	}

	ringtone := ""
	if in.WaitingMusic != nil {
		if in.WaitingMusic.Id != 0 && in.WaitingMusic.Type != "" {
			ringtone = model.RingtoneUri(in.DomainId, int(in.WaitingMusic.Id), fmt.Sprintf("audio/%s", in.WaitingMusic.Type))
		}
	}
	call, err := queueManager.callManager.InboundCall(req, ringtone)
	if err != nil {
		wlog.Error(fmt.Sprintf("[%s] call %s distribute error: %s", req.AppId, req.Id, err.Error()))
		return nil, err
	}

	member, err = queueManager.store.Member().DistributeCallToQueue(queueManager.app.GetInstanceId(), int64(in.GetQueue().GetId()),
		call.Id(), call.FromNumber(), call.FromName(), in.Variables, int(in.Priority))

	if err != nil {
		wlog.Error(fmt.Sprintf("[%s] call %s distribute error: %s", call.NodeName(), call.Id(), err.Error()))
		return nil, err
	}

	attempt, _ := queueManager.CreateAttemptIfNotExists(ctx, member)

	queueManager.DistributeAttempt(attempt)
	return attempt, nil
}

func (queueManager *QueueManager) DistributeChatToQueue(queueId int, channelId string, number, name string, priority int) (QueueObject, *model.AppError) {
	member, err := queueManager.store.Member().DistributeChatToQueue(queueManager.app.GetInstanceId(), int64(queueId),
		channelId, number, name, priority)

	if err != nil {
		wlog.Error(fmt.Sprintf("chat %s distribute error: %s", channelId, err.Error()))
		return nil, err
	}

	attempt, err := queueManager.CreateAttemptIfNotExists(context.Background(), member)
	if err != nil {
		return nil, err
	}

	return queueManager.DistributeAttempt(attempt)
}

func (queueManager *QueueManager) DistributeDirectMember(memberId int64, communicationId, agentId int) (*Attempt, *model.AppError) {
	member, err := queueManager.store.Member().DistributeDirect(queueManager.app.GetInstanceId(), memberId, communicationId, agentId)

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
	_, err := queueManager.store.Member().SetAttemptAbandoned(attempt.Id())
	if err != nil {
		wlog.Error(err.Error())

		return
	}
}

func (queueManager *QueueManager) ReportingAttempt(attemptId int64, result model.AttemptResult2) *model.AppError {
	res, err := queueManager.store.Member().Reporting(attemptId, result.Status)
	if err != nil {
		return err
	}

	if res.AgentCallId != nil && res.Channel != nil {
		if call, ok := queueManager.callManager.GetCall(*res.AgentCallId); ok {
			err = call.Hangup("", true)
		}
	} else {
		// FIXME

	}

	e := WrapTimeEvent{
		WrapTime: WrapTime{
			Timeout: *res.AgentTimeout,
		},
		ChannelEvent: ChannelEvent{
			Timestamp: res.Timestamp,
			Channel:   *res.Channel,
			AttemptId: model.NewInt64(attemptId),
			Status:    model.ChannelStateWrapTime,
		},
	}

	ev := model.NewEvent("channel", e)
	err = queueManager.mq.AttemptEvent(*res.Channel, 1, 2134, res.AgentId, ev)

	return err
}
