package queue

import (
	workflow "buf.build/gen/go/webitel/workflow/protocolbuffers/go"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
	"time"
)

const (
	ExpiredPollingInterval = 1 * 1000 * 30
	ExpiredWorkers         = 4
	ExpiredQueue           = 10
	ExpiredLimit           = 500
)

type ExpiredManager struct {
	app       App
	store     store.Store
	watcher   *utils.Watcher
	startOnce sync.Once
	pool      *utils.Pool
}

type ExpiredJob struct {
	app App
	model.ExpiredMember
}

func NewExpiredManager(app App, store store.Store) *ExpiredManager {
	var manager ExpiredManager
	manager.app = app
	manager.store = store
	manager.pool = utils.NewPool(ExpiredWorkers, ExpiredQueue)
	return &manager
}

func (s *ExpiredManager) Start() {
	wlog.Debug("starting expired service")
	s.watcher = utils.MakeWatcher("Expired", ExpiredPollingInterval, s.job)
	s.startOnce.Do(func() {
		go s.watcher.Start()
	})
}

func (s *ExpiredManager) Stop() {
	s.watcher.Stop()
}

func (s *ExpiredManager) job() {
	st := time.Now()
	if hooks, err := s.store.Member().SetExpired(ExpiredLimit); err != nil {
		wlog.Error(err.Error())
	} else {
		wlog.Debug(fmt.Sprintf("set expired members time: %s, hook count %d", time.Now().Sub(st), len(hooks)))

		for _, v := range hooks {
			s.pool.Exec(&ExpiredJob{
				app:           s.app,
				ExpiredMember: *v,
			})
		}

		if len(hooks) >= ExpiredLimit {
			s.job()
		}
	}
}

func (v *ExpiredJob) Execute() {
	st := time.Now()
	req := &workflow.StartFlowRequest{
		SchemaId:  v.SchemaId,
		DomainId:  v.DomainId,
		Variables: v.Variables,
	}

	if id, err := v.app.FlowManager().Queue().StartFlow(req); err != nil {
		wlog.Error(fmt.Sprintf("hook \"leaving\" expired (time %s) member_id=%d, error: %s", time.Now().Sub(st), v.MemberId, err.Error()))
	} else {
		wlog.Debug(fmt.Sprintf("hook \"leaving\" expired (time %s) member_id=%d, job_id: %s", time.Now().Sub(st), v.MemberId, id))
	}
}
