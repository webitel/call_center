package trigger

import (
	flow "buf.build/gen/go/webitel/workflow/protocolbuffers/go"
	"context"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/flow_manager/client"
	"github.com/webitel/wlog"
	"sync"
	"time"
)

const (
	WatcherPollingInterval = 1000
	QueueSize              = 1000

	LimitJobs = 100
)

type Manager struct {
	nodeId          string
	store           store.Store
	startOnce       sync.Once
	pollingInterval int
	watcher         *utils.Watcher
	stopped         chan struct{}
	jobs            chan model.TriggerJob
	ctx             context.Context
	cancel          context.CancelFunc
	flow            client.FlowManager
	log             *wlog.Logger
}

func NewManager(nodeId string, s store.Store, fw client.FlowManager, log *wlog.Logger) *Manager {
	m := &Manager{
		nodeId:          nodeId,
		store:           s,
		pollingInterval: WatcherPollingInterval,
		stopped:         make(chan struct{}),
		jobs:            make(chan model.TriggerJob, QueueSize),
		flow:            fw,
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("name", "trigger"),
		),
	}
	m.ctx, m.cancel = context.WithCancel(context.TODO())

	return m
}

func (m *Manager) Start() *model.AppError {
	m.log.Info("starting trigger service")
	m.watcher = utils.MakeWatcher("Trigger", m.pollingInterval, m.schedule)

	m.startOnce.Do(func() {
		m.clean()
		go m.watcher.Start()
		go m.listen()
	})

	return nil
}

func (m *Manager) Stop() *model.AppError {
	if m.watcher != nil {
		m.watcher.Stop()

	}
	m.cancel()
	<-m.stopped

	return nil
}

func (m *Manager) clean() {
	err := m.store.Trigger().CleanActive(m.nodeId)
	if err != nil {
		m.log.Error(err.Error(),
			wlog.Err(err),
		)
		time.Sleep(time.Second * 5)
	}
}

func (m *Manager) schedule() {
	err := m.store.Trigger().ScheduleNewJobs()
	if err != nil {
		m.log.Error(err.Error(),
			wlog.Err(err),
		)
		time.Sleep(time.Second * 5)
	}
	var jobs []model.TriggerJob

	jobs, err = m.store.Trigger().FetchIdleJobs(m.nodeId, LimitJobs)
	if err != nil {
		m.log.Error(err.Error(),
			wlog.Err(err),
		)
		time.Sleep(time.Second * 5)
	}

	for _, j := range jobs {
		m.jobs <- j
	}
}

func (m *Manager) listen() {
	for {
		select {
		case <-m.ctx.Done():
			close(m.stopped)
			return
		case j := <-m.jobs:
			go m.runJob(Job{
				data:    j,
				manager: m,
				ctx:     m.ctx,
				log: m.log.With(
					wlog.Int64("job_id", j.Id),
					wlog.String("trigger", j.Name),
					wlog.Int("trigger_id", j.TriggerId),
				),
			})
		}
	}
}

func (m *Manager) runJob(j Job) {
	j.log.Debug(fmt.Sprintf("[trigger] %s job_id: %d started...", j.data.Name, j.data.Id))
	defer j.log.Debug(fmt.Sprintf("[trigger] %s job_id: %d stopped", j.data.Name, j.data.Id))

	res, err := m.flow.Queue().StartSyncFlow(&flow.StartSyncFlowRequest{
		SchemaId:   j.data.Parameters.SchemaId,
		DomainId:   j.data.DomainId,
		TimeoutSec: j.data.Parameters.Timeout,
		Variables:  mapInterfaceToStringInterface(j.data.Parameters.Variables),
	})
	j.data.Result = map[string]string{
		"job_id": res,
	}
	if err != nil {
		j.log.Error(fmt.Sprintf("job: %d, error: %s", j.data.Id, err.Error()),
			wlog.Err(err),
		)
		if appErr := m.store.Trigger().SetError(&j.data, err); appErr != nil {
			j.log.Error(fmt.Sprintf("job: %d, error: %s", j.data.Id, appErr.Error()),
				wlog.Err(err),
			)
		}
		return
	}

	if appErr := m.store.Trigger().SetResult(&j.data); appErr != nil {
		j.log.Error(fmt.Sprintf("job: %d, error: %s", j.data.Id, appErr.Error()),
			wlog.Err(err),
		)
	}
	return
}

func mapInterfaceToStringInterface(src map[string]interface{}) map[string]string {
	res := make(map[string]string)
	for k, v := range src {
		res[k] = fmt.Sprintf("%v", v)
	}
	return res
}
