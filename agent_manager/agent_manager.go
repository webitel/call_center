package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 1000

const (
	MAX_AGENTS_CACHE        = 10000
	MAX_AGENTS_EXPIRE_CACHE = 60 * 60 * 24 //day
)

type AgentManagerImpl struct {
	store       store.Store
	watcher     *utils.Watcher
	nodeId      string
	startOnce   sync.Once
	agentsCache utils.ObjectCache
	sync.Mutex
}

func NewAgentManager(nodeId string, s store.Store) AgentManager {
	var agentManager AgentManagerImpl
	agentManager.store = s
	agentManager.nodeId = nodeId
	agentManager.agentsCache = utils.NewLruWithParams(MAX_AGENTS_CACHE, "Agents", MAX_AGENTS_EXPIRE_CACHE, "")
	return &agentManager
}

func (agentManager *AgentManagerImpl) Start() {
	wlog.Debug("starting agent service")
	agentManager.watcher = utils.MakeWatcher("AgentManager", DEFAULT_WATCHER_POLLING_INTERVAL, agentManager.changeDeadlineState)
	agentManager.startOnce.Do(func() {
		go agentManager.watcher.Start()
	})
}

func (agentManager *AgentManagerImpl) Stop() {
	agentManager.watcher.Stop()
}

func (agentManager *AgentManagerImpl) GetAgent(id int, updatedAt int64) (AgentObject, *model.AppError) {
	agentManager.Lock()
	defer agentManager.Unlock()

	/*

	 */

	var agent AgentObject
	item, ok := agentManager.agentsCache.Get(id)
	if ok {
		agent, ok = item.(AgentObject)
		if ok && !agent.IsExpire(updatedAt) {
			return agent, nil
		}
	}

	if a, err := agentManager.store.Agent().Get(id); err != nil {
		return nil, err
	} else {
		agent = NewAgent(a, agentManager)
	}

	agentManager.agentsCache.AddWithDefaultExpires(id, agent)
	wlog.Debug(fmt.Sprintf("add agent to cache %v", agent.Name()))
	return agent, nil
}

func (agentManager *AgentManagerImpl) SetAgentStatus(agent AgentObject, status *model.AgentStatus) *model.AppError {
	if err := agentManager.store.Agent().SetStatus(agent.Id(), status.Status, status.StatusPayload); err != nil {
		wlog.Error(fmt.Sprintf("agent %s[%d] has been changed state to \"%s\" error: %s", agent.Name(), agent.Id(), status.Status, err.Error()))
		return err
	}

	wlog.Debug(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\"", agent.Name(), agent.Id(), status.Status))

	return nil
}

func (agentManager *AgentManagerImpl) SetAgentState(agent AgentObject, state string, timeoutSeconds int) *model.AppError {

	if _, err := agentManager.store.Agent().SetState(agent.Id(), state, timeoutSeconds); err != nil {
		wlog.Error(fmt.Sprintf("agent %s[%d] has been changed state to \"%s\" error: %s", agent.Name(), agent.Id(), state, err.Error()))
		return err
	}

	agentManager.notifyChangeAgentState(agent, state)
	wlog.Debug(fmt.Sprintf("agent %s[%d] has been changed state to \"%s\" (%d)", agent.Name(), agent.Id(), state, timeoutSeconds))
	return nil
}

func (agentManager *AgentManagerImpl) SetOnline(agent AgentObject) *model.AppError {
	return agentManager.SetAgentStatus(agent, &model.AgentStatus{
		Status: model.AGENT_STATUS_ONLINE,
	})
}

func (agentManager *AgentManagerImpl) SetOffline(agent AgentObject) *model.AppError {
	return agentManager.SetAgentStatus(agent, &model.AgentStatus{
		Status: model.AGENT_STATUS_OFFLINE,
	})
}

//todo add timeout
func (agentManager *AgentManagerImpl) SetPause(agent AgentObject, payload []byte, timeout int) *model.AppError {
	return agentManager.SetAgentStatus(agent, &model.AgentStatus{
		Status:        model.AGENT_STATUS_PAUSE,
		StatusPayload: payload,
	})
}

func (agentManager *AgentManagerImpl) changeDeadlineState() {
	if s, err := agentManager.store.Agent().ChangeDeadlineState(model.AGENT_STATE_WAITING); err != nil {
		wlog.Error(err.Error())
	} else {
		for _, v := range s {
			//todo event
			wlog.Debug(fmt.Sprintf("agent %d has been changed state to \"%s\" - timeout", v.Id, v.State))
		}
	}
}

func (agentManager *AgentManagerImpl) MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError {
	return agentManager.store.Agent().MissedAttempt(agentId, attemptId, cause)
}
