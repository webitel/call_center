package queue

import (
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/call_manager"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"sync"
	"time"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 500

type DialingImpl struct {
	app             App
	store           store.Store
	watcher         *utils.Watcher
	queueManager    *QueueManager
	resourceManager *ResourceManager
	agentManager    agent_manager.AgentManager
	startOnce       sync.Once
}

func NewDialing(app App, callManager call_manager.CallManager, agentManager agent_manager.AgentManager, s store.Store) Dialing {
	var dialing DialingImpl
	dialing.app = app
	dialing.store = s
	dialing.agentManager = agentManager
	dialing.resourceManager = NewResourceManager(app)
	dialing.queueManager = NewQueueManager(app, s, callManager, dialing.resourceManager, agentManager)
	return &dialing
}

func (dialing *DialingImpl) Start() {
	mlog.Debug("Starting dialing service")
	dialing.watcher = utils.MakeWatcher("Dialing", DEFAULT_WATCHER_POLLING_INTERVAL, dialing.PollAndNotify)

	dialing.startOnce.Do(func() {
		go dialing.watcher.Start()
		go dialing.queueManager.Start()
	})
}

func (d *DialingImpl) Stop() {
	d.watcher.Stop()
	d.queueManager.Stop()
}

func (d *DialingImpl) PollAndNotify() {
	if !d.app.IsReady() {
		return
	}

	result := <-d.store.Member().GetActiveMembersAttempt(d.app.GetInstanceId())
	if result.Err != nil {
		mlog.Error(result.Err.Error())
		time.Sleep(time.Second)
		return
	}

	for _, v := range result.Data.([]*model.MemberAttempt) {
		d.queueManager.RouteMember(v)
	}
}
