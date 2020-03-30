package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
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

type agentManager struct {
	store       store.Store
	mq          mq.MQ
	watcher     *utils.Watcher
	nodeId      string
	startOnce   sync.Once
	agentsCache utils.ObjectCache
	sync.Mutex
}

func NewAgentManager(nodeId string, s store.Store, mq_ mq.MQ) AgentManager {
	var am agentManager
	am.store = s
	am.mq = mq_
	am.nodeId = nodeId
	am.agentsCache = utils.NewLruWithParams(MAX_AGENTS_CACHE, "Agents", MAX_AGENTS_EXPIRE_CACHE, "")
	return &am
}

func (am *agentManager) Start() {
	wlog.Debug("starting agent service")
	am.watcher = utils.MakeWatcher("AgentManager", DEFAULT_WATCHER_POLLING_INTERVAL, am.changeDeadlineState)
	am.startOnce.Do(func() {
		go am.watcher.Start()
	})
}

func (am *agentManager) Stop() {
	am.watcher.Stop()
}

func (am *agentManager) GetAgent(id int, updatedAt int64) (AgentObject, *model.AppError) {
	am.Lock()
	defer am.Unlock()

	var agent AgentObject
	item, ok := am.agentsCache.Get(id)
	if ok {
		agent, ok = item.(AgentObject)
		if ok && !agent.IsExpire(updatedAt) {
			return agent, nil
		}
	}

	if a, err := am.store.Agent().Get(id); err != nil {
		return nil, err
	} else {
		agent = NewAgent(a, am)
	}

	am.agentsCache.AddWithDefaultExpires(id, agent)
	wlog.Debug(fmt.Sprintf("add agent to cache %v", agent.Name()))
	return agent, nil
}

func (am *agentManager) SetAgentStatus(agent AgentObject, status *model.AgentStatus) *model.AppError {
	if err := am.store.Agent().SetStatus(agent.Id(), status.Status, status.StatusPayload); err != nil {
		wlog.Error(fmt.Sprintf("agent %s[%d] has been changed state to \"%s\" error: %s", agent.Name(), agent.Id(), status.Status, err.Error()))
		return err
	}

	wlog.Debug(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\"", agent.Name(), agent.Id(), status.Status))

	return nil
}

func (am *agentManager) SetAgentState(agent AgentObject, state string, timeoutSeconds int) *model.AppError {
	if _, err := am.store.Agent().SetState(agent.Id(), state, timeoutSeconds); err != nil {
		wlog.Error(fmt.Sprintf("agent %s[%d] has been changed state to \"%s\" error: %s", agent.Name(), agent.Id(), state, err.Error()))
		return err
	}

	am.notifyChangeAgentState(agent, state)
	wlog.Debug(fmt.Sprintf("agent %s[%d] has been changed state to \"%s\" (%d)", agent.Name(), agent.Id(), state, timeoutSeconds))
	return nil
}

func (am *agentManager) SetOnline(agent AgentObject) *model.AppError {
	err := am.SetAgentStatus(agent, &model.AgentStatus{
		Status: model.AGENT_STATUS_WAITING,
	})
	if err != nil {
		return err
	}

	return am.mq.AgentChangeStatus(NewAgentEventStatus(agent, model.AGENT_STATUS_WAITING, nil, nil))
}

func (am *agentManager) SetOffline(agent AgentObject) *model.AppError {
	err := am.SetAgentStatus(agent, &model.AgentStatus{
		Status: model.AGENT_STATUS_OFFLINE,
	})
	if err != nil {
		return err
	}

	return am.mq.AgentChangeStatus(NewAgentEventStatus(agent, model.AGENT_STATUS_OFFLINE, nil, nil))
}

//todo add timeout
func (am *agentManager) SetPause(agent AgentObject, payload *string, timeout *int) *model.AppError {
	err := am.SetAgentStatus(agent, &model.AgentStatus{
		Status:        model.AGENT_STATUS_PAUSE,
		StatusPayload: payload,
	})

	if err != nil {
		return err
	}
	//add channel queue
	return am.mq.AgentChangeStatus(NewAgentEventStatus(agent, model.AGENT_STATUS_PAUSE, payload, timeout))
}

func (am *agentManager) changeDeadlineState() {
	if s, err := am.store.Agent().ChangeDeadlineState(model.AGENT_STATE_WAITING); err != nil {
		wlog.Error(err.Error())
	} else {
		for _, v := range s {
			//todo event

			wlog.Debug(fmt.Sprintf("agent %d has been changed state to \"%s\" - timeout", v.Id, v.State))
		}
	}
}

func (am *agentManager) MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError {
	return am.store.Agent().MissedAttempt(agentId, attemptId, cause)
}
