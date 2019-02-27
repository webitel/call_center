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
	attemptCount int64
	stop         chan struct{}
	stopped      chan struct{}
	input        chan *model.MemberAttempt
	queuesCache  utils.ObjectCache
	store        store.Store
}

func NewQueueManager(s store.Store) *QueueManager {
	return &QueueManager{
		store:       s,
		input:       make(chan *model.MemberAttempt),
		stop:        make(chan struct{}),
		stopped:     make(chan struct{}),
		queuesCache: utils.NewLruWithParams(MAX_QUEUES_CACHE, "QueueManager", MAX_QUEUES_EXPIRE_CACHE, ""),
	}
}

func (o *QueueManager) Start() {
	mlog.Debug("QueueManager started")
	rand.Seed(time.Now().Unix())

	defer func() {
		mlog.Debug("Stopped QueueManager")
		close(o.stopped)
	}()

	for {
		select {
		case <-o.stop:
			mlog.Debug("QueueManager received stop signal")
			close(o.input)
			return
		case m := <-o.input:
			o.attemptCount++
			o.wg.Add(1)
			mlog.Debug(fmt.Sprintf("Make attempt call [%d] to %v", o.attemptCount, m.Id))
			go func(m *model.MemberAttempt) {
				time.Sleep(time.Duration(rand.Int31n(100)) * time.Millisecond)
				res := <-o.store.Member().SetEndMemberAttempt(m.Id, model.MEMBER_STATE_END, model.GetMillis(), "OK")
				if res.Err != nil {
					panic(res.Err)
				}
				mlog.Debug(fmt.Sprintf("End call to %v", m.Id))
				o.wg.Done()
			}(m)
		}
	}

}

func (o *QueueManager) Stop() {
	mlog.Debug("QueueManager Stopping")
	mlog.Debug("Wait for close attempts")
	o.wg.Wait()
	close(o.stop)
	<-o.stopped
}

func (o *QueueManager) AddMember(attempt *model.MemberAttempt) {
	o.input <- attempt
}
