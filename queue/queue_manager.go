package queue

import (
	"fmt"
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"math/rand"
	"sync"
	"time"
)

const (
	MAX_QUEUES_CACHE        = 10000
	MAX_QUEUES_EXPIRE_CACHE = 60 * 60 * 24 //day
)

type QueueManager struct {
	wg              sync.WaitGroup
	app             App
	attemptCount    int64
	stop            chan struct{}
	stopped         chan struct{}
	input           chan *model.MemberAttempt
	queuesCache     utils.ObjectCache
	membersCache    utils.ObjectCache
	store           store.Store
	resourceManager *ResourceManager
	agentManager    agent_manager.AgentManager
	sync.Mutex
}

func NewQueueManager(app App, s store.Store, resourceManager *ResourceManager, agentManager agent_manager.AgentManager) *QueueManager {
	return &QueueManager{
		store:           s,
		app:             app,
		resourceManager: resourceManager,
		agentManager:    agentManager,
		input:           make(chan *model.MemberAttempt),
		stop:            make(chan struct{}),
		stopped:         make(chan struct{}),
		queuesCache:     utils.NewLruWithParams(MAX_QUEUES_CACHE, "QueueManager", MAX_QUEUES_EXPIRE_CACHE, ""),
		membersCache:    utils.NewLruWithParams(MAX_QUEUES_CACHE, "MembersInQueue", MAX_QUEUES_EXPIRE_CACHE, ""),
	}
}

func (queueManager *QueueManager) Start() {
	mlog.Debug("QueueManager started")
	rand.Seed(time.Now().Unix())

	defer func() {
		mlog.Debug("Stopped QueueManager")
		close(queueManager.stopped)
	}()

	go queueManager.StartListenEvents()

	for {
		select {
		case <-queueManager.stop:
			mlog.Debug("QueueManager received stop signal")
			close(queueManager.input)
			return
		case m := <-queueManager.input:
			queueManager.attemptCount++
			queueManager.JoinMember(m)
		}
	}
}

func (queueManager *QueueManager) Stop() {
	mlog.Debug("QueueManager Stopping")
	mlog.Debug("Wait for close attempts")
	queueManager.wg.Wait()
	close(queueManager.stop)
	<-queueManager.stopped
}

func (queueManager *QueueManager) GetNodeId() string {
	return queueManager.app.GetInstanceId()
}

func (queueManager *QueueManager) RouteMember(attempt *model.MemberAttempt) {
	if _, ok := queueManager.membersCache.Get(attempt.Id); ok {
		mlog.Error(fmt.Sprintf("Attempt %v in queue", attempt.Id))
		return
	}

	queueManager.input <- attempt
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
	mlog.Debug(fmt.Sprintf("Add queue %s to cache", queue.Name()))
	return queue, nil
}

func (queueManager *QueueManager) GetResource(id, updatedAt int64) (ResourceObject, *model.AppError) {
	return queueManager.resourceManager.Get(id, updatedAt)
}

func (queueManager *QueueManager) SetResourceError(resource ResourceObject, routingId int, errorId string) {
	if resource.CheckIfError(errorId) {
		mlog.Warn(fmt.Sprintf("Resource %s Id=%d error: %s", resource.Name(), resource.Id(), errorId))
		if result := <-queueManager.store.OutboundResource().
			SetError(int64(resource.Id()), int64(routingId), errorId, model.OUTBOUND_RESOURCE_STRATEGY_RANDOM); result.Err != nil {

			mlog.Error(result.Err.Error())
		} else {
			responseError := result.Data.(*model.OutboundResourceErrorResult)
			if responseError.Stopped != nil && *responseError.Stopped {
				mlog.Info(fmt.Sprintf("Resource %s [%d] stopped, because: %s", resource.Name(), resource.Id(), errorId))

				queueManager.notifyStoppedResource(resource)
			}

			if responseError.UnReserveResourceId != nil {
				mlog.Info(fmt.Sprintf("New resource ResourceId=%d from reserve", *responseError.UnReserveResourceId))
			}
			queueManager.resourceManager.RemoveFromCacheById(int64(resource.Id()))
		}
	}
}

func (queueManager *QueueManager) SetResourceSuccessful(resource ResourceObject) {
	if resource.SuccessivelyErrors() > 0 {
		if res := <-queueManager.store.OutboundResource().SetSuccessivelyErrorsById(int64(resource.Id()), 0); res.Err != nil {
			mlog.Error(res.Err.Error())
		}
	}
}

func (queueManager *QueueManager) JoinMember(member *model.MemberAttempt) {
	memberAttempt := NewAttempt(member)

	queue, err := queueManager.GetQueue(int(member.QueueId), member.QueueUpdatedAt)
	if err != nil {
		mlog.Error(err.Error())
		//TODO added to model "dialing.queue.new_queue.app_error"
		queueManager.SetAttemptMinus(memberAttempt, model.MEMBER_CAUSE_QUEUE_NOT_IMPLEMENT)
		return
	}

	queueManager.membersCache.AddWithDefaultExpires(memberAttempt.Id(), memberAttempt)
	queueManager.wg.Add(1)
	queue.JoinAttempt(memberAttempt, queueManager.GetAttemptResource(memberAttempt))
	queueManager.notifyChangedQueueLength(queue)
	mlog.Debug(fmt.Sprintf("Join member %s[%d] AttemptId=%d to queue %s", memberAttempt.Name(), memberAttempt.MemberId(), memberAttempt.Id(), queue.Name()))
}

func (queueManager *QueueManager) LeavingMember(attempt *Attempt, queue QueueObject) {
	mlog.Debug(fmt.Sprintf("Leaving member %s[%d] AttemptId=%d from queue %s", attempt.Name(), attempt.MemberId(), attempt.Id(), queue.Name()))

	queueManager.membersCache.Remove(attempt.Id())
	queueManager.wg.Done()
	queueManager.notifyChangedQueueLength(queue)
}

func (queueManager *QueueManager) GetAttemptResource(attempt *Attempt) ResourceObject {
	if attempt.ResourceId() != nil && attempt.ResourceUpdatedAt() != nil {
		resource, err := queueManager.resourceManager.Get(*attempt.ResourceId(), *attempt.ResourceUpdatedAt())
		if err != nil {
			mlog.Error(fmt.Sprintf("Attempt resource error: %s", err.Error()))
		} else {
			return resource
		}
	}
	return nil
}
