package agent_manager

import (
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"sync"
)

var DEFAULT_STATUS_WATCHER_POLLING_INTERVAL = 1000

type AgentStatusManager interface {
	Start()
	Stop()
	SetAgentState(agent AgentObject, state string, timeoutSeconds int) *model.AppError
}

type AgentStatusManagerImpl struct {
	store     store.Store
	watcher   *utils.Watcher
	startOnce sync.Once
}

func NewAgentStatusManager(store store.Store) AgentStatusManager {
	return &AgentStatusManagerImpl{
		store: store,
	}
}

func (statusManager *AgentStatusManagerImpl) Start() {
	mlog.Debug("Starting agent-status service")
	statusManager.watcher = utils.MakeWatcher("AgentStatusManager", DEFAULT_STATUS_WATCHER_POLLING_INTERVAL, statusManager.pollAndNotify)
	statusManager.startOnce.Do(func() {
		go statusManager.watcher.Start()
	})
}

func (statusManager *AgentStatusManagerImpl) Stop() {
	statusManager.watcher.Stop()
}

func (statusManager *AgentStatusManagerImpl) pollAndNotify() {
	if result := <-statusManager.store.Agent().ChangeDeadlineState(model.AGENT_STATE_WAITING); result.Err != nil {
		mlog.Error(result.Err.Error())
	}
}

func (statusManager *AgentStatusManagerImpl) SetAgentState(agent AgentObject, state string, timeoutSeconds int) *model.AppError {
	if result := <-statusManager.store.Agent().SetState(agent.Id(), state, timeoutSeconds); result.Err != nil {
		return result.Err
	}
	return nil
}
