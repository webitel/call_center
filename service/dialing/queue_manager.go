package dialing

import (
	"fmt"
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
	wg           sync.WaitGroup
	app          App
	attemptCount int64
	stop         chan struct{}
	stopped      chan struct{}
	input        chan *model.MemberAttempt
	queuesCache  utils.ObjectCache
	store        store.Store
	sync.Mutex
}

func NewQueueManager(app App, s store.Store) *QueueManager {
	return &QueueManager{
		store:       s,
		app:         app,
		input:       make(chan *model.MemberAttempt),
		stop:        make(chan struct{}),
		stopped:     make(chan struct{}),
		queuesCache: utils.NewLruWithParams(MAX_QUEUES_CACHE, "QueueManager", MAX_QUEUES_EXPIRE_CACHE, ""),
	}
}

func (queueManager *QueueManager) Start() {
	mlog.Debug("QueueManager started")
	rand.Seed(time.Now().Unix())

	defer func() {
		mlog.Debug("Stopped QueueManager")
		close(queueManager.stopped)
	}()

	for {
		select {
		case <-queueManager.stop:
			mlog.Debug("QueueManager received stop signal")
			close(queueManager.input)
			return
		case m := <-queueManager.input:
			queueManager.attemptCount++
			queueManager.wg.Add(1)
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

func (queueManager *QueueManager) RouteMember(attempt *model.MemberAttempt) {
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

	if config, err := queueManager.app.GetQueueById(id); err != nil {
		return nil, err
	} else {
		//TODO RESOURCE MANAGER
		queue, err = NewQueue(queueManager, nil, config)

		if err != nil {
			return nil, err
		}
	}

	queueManager.queuesCache.AddWithDefaultExpires(id, queue)
	mlog.Debug(fmt.Sprintf("Add queue %s to cache", queue.Name()))
	return queue, nil
}

func (queueManager *QueueManager) JoinMember(member *model.MemberAttempt) {
	queue, err := queueManager.GetQueue(member.QueueId, member.QueueUpdatedAt)
	if err != nil {
		mlog.Error(err.Error())
		//TODO added to model
		if err.Id == "dialing.queue.new_queue.app_error" {
			queueManager.SetMemberError(member, model.MEMBER_STATE_END, model.MEMBER_CAUSE_QUEUE_NOT_IMPLEMENT)
		} else {
			queueManager.SetMemberError(member, model.MEMBER_STATE_END, model.MEMBER_CAUSE_DATABASE_ERROR)
		}
		return
	}

	memberAttempt := NewAttempt(member)
	queue.AddMemberAttempt(memberAttempt)

	mlog.Debug(fmt.Sprintf("Join member %s to queue %s", memberAttempt.Name(), queue.Name()))
}

func (queueManager *QueueManager) LeavingMember(attempt *Attempt, queue QueueObject) {
	mlog.Debug(fmt.Sprintf("Leaving member %s from queue %s", attempt.Name(), queue.Name()))
	queueManager.wg.Done()
}

func (queueManager *QueueManager) SetMemberError(member *model.MemberAttempt, cause int, result string) {
	res := <-queueManager.store.Member().SetEndMemberAttempt(member.Id, model.MEMBER_STATE_END, model.GetMillis(), result)
	if res.Err != nil {
		panic(res.Err)
	}
}

//TODO remove
func (queueManager *QueueManager) SetAttemptError(attempt *Attempt, cause int, result string) {
	res := <-queueManager.store.Member().SetEndMemberAttempt(attempt.member.Id, model.MEMBER_STATE_END, model.GetMillis(), result)
	if res.Err != nil {
		panic(res.Err)
	}
}
