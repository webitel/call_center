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
	output       chan *model.MemberAttempt
	queuesCache  utils.ObjectCache
	store        store.Store
	sync.Mutex
}

func NewQueueManager(app App, s store.Store) *QueueManager {
	return &QueueManager{
		store:       s,
		app:         app,
		input:       make(chan *model.MemberAttempt),
		output:      make(chan *model.MemberAttempt),
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
			return //TODO output channel
		case m := <-queueManager.input:
			queueManager.attemptCount++
			queueManager.wg.Add(1)
			mlog.Debug(fmt.Sprintf("Make attempt call [%d] to %v", queueManager.attemptCount, m.Id))

			q, e := queueManager.GetQueue(m.QueueId, m.QueueUpdatedAt)
			if e != nil {
				panic(e)
			}

			if q != nil {

			}

			go func() {
				time.Sleep(time.Duration(rand.Intn(1000)) * time.Millisecond)
				queueManager.output <- m
			}()

		case m := <-queueManager.output:
			mlog.Debug(fmt.Sprintf("End call to %v", m.Id))
			res := <-queueManager.store.Member().SetEndMemberAttempt(m.Id, model.MEMBER_STATE_END, model.GetMillis(), "OK")
			if res.Err != nil {
				panic(res.Err)
			}
			queueManager.wg.Done()
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

func (queueManager *QueueManager) AddMember(attempt *model.MemberAttempt) {
	queueManager.input <- attempt
}

func (queueManager *QueueManager) GetQueue(id int, updatedAt int64) (*Queue, *model.AppError) {
	queueManager.Lock()
	defer queueManager.Unlock()
	var queue *Queue

	item, ok := queueManager.queuesCache.Get(id)
	if ok {
		queue, ok = item.(*Queue)
		if ok && !queue.IsExpire(updatedAt) {
			return queue, nil
		}
	}

	if config, err := queueManager.app.GetQueueById(id); err != nil {
		return nil, err
	} else {
		queue = NewQueue(config)
	}

	queueManager.queuesCache.AddWithDefaultExpires(id, queue)
	mlog.Debug(fmt.Sprintf("Add queue %s to cache", queue.Name()))
	return queue, nil
}
