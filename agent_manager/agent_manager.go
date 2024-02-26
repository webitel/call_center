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

const (
	watcherPollingInterval = 30000

	sizeAgentChane   = 10000
	expireAgentCache = 60 * 5
)

var (
	MaxAgentOnlineWithOutSocSec = 60
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
	am.agentsCache = utils.NewLruWithParams(sizeAgentChane, "Agents", expireAgentCache, "")

	return &am
}

func (am *agentManager) Start() {
	wlog.Debug("starting agent service")
	am.watcher = utils.MakeWatcher("AgentManager", watcherPollingInterval, am.changeDeadlineState)
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

func (am *agentManager) SetOnline(agent AgentObject, onDemand bool) (*model.AgentOnlineData, *model.AppError) {
	data, err := am.store.Agent().SetOnline(agent.Id(), onDemand)
	if err != nil {
		wlog.Error(fmt.Sprintf("agent %s[%d] has been changed status to \"%s\" error: %s", agent.Name(), agent.Id(), model.AgentStatusOnline, err.Error()))
		return nil, err
	}

	agent.SetOnDemand(onDemand)
	agent.StoreStatus(model.AgentStatus{
		Status: model.AgentStatusOnline,
	})
	//FIXME add pool send event
	return data, am.mq.AgentChangeStatus(agent.DomainId(), agent.UserId(), NewAgentEventOnlineStatus(agent, data, onDemand))
}

func (am *agentManager) setAgentStatus(agent AgentObject, status *model.AgentStatus) *model.AppError {
	if err := am.store.Agent().SetStatus(agent.Id(), status.Status, status.StatusPayload); err != nil {
		wlog.Error(fmt.Sprintf("agent %s[%d] has been changed state to \"%s\" error: %s", agent.Name(), agent.Id(), status.Status, err.Error()))
		return err
	}

	return nil
}

func (am *agentManager) SetOffline(agent AgentObject, sys *string) *model.AppError {
	event := model.AgentEventStatus{
		AgentEvent: model.AgentEvent{
			AgentId:   agent.Id(),
			UserId:    agent.UserId(),
			DomainId:  agent.DomainId(),
			Timestamp: model.GetMillis(), //FIXME DB time
		},
		AgentStatus: model.AgentStatus{
			Status: model.AgentStatusOffline,
		},
	}

	if sys != nil {
		event.AgentStatus.StatusPayload = sys
	}

	err := am.setAgentStatus(agent, &event.AgentStatus)

	if err != nil {
		return err
	}
	agent.StoreStatus(event.AgentStatus)
	//add channel queue
	return am.mq.AgentChangeStatus(agent.DomainId(), agent.UserId(), NewAgentEventStatus(agent, event))
}

func (am *agentManager) SetPause(agent AgentObject, payload *string, timeout *int) *model.AppError {
	event := model.AgentEventStatus{
		AgentEvent: model.AgentEvent{
			AgentId:   agent.Id(),
			UserId:    agent.UserId(),
			DomainId:  agent.DomainId(),
			Timestamp: model.GetMillis(), //FIXME DB time
		},
		AgentStatus: model.AgentStatus{
			Status:        model.AgentStatusPause,
			StatusPayload: payload,
		},
	}

	err := am.setAgentStatus(agent, &event.AgentStatus)

	if err != nil {
		return err
	}
	agent.StoreStatus(event.AgentStatus)
	//add channel queue
	return am.mq.AgentChangeStatus(agent.DomainId(), agent.UserId(), NewAgentEventStatus(agent, event))
}

func (am *agentManager) SetBreakOut(agent AgentObject) *model.AppError {
	event := model.AgentEventStatus{
		AgentEvent: model.AgentEvent{
			AgentId:   agent.Id(),
			UserId:    agent.UserId(),
			DomainId:  agent.DomainId(),
			Timestamp: model.GetMillis(), //FIXME DB time
		},
		AgentStatus: model.AgentStatus{
			Status: model.AgentStatusBreakOut,
		},
	}

	err := am.setAgentStatus(agent, &event.AgentStatus)

	if err != nil {
		return err
	}
	//add channel queue
	return am.mq.AgentChangeStatus(agent.DomainId(), agent.UserId(), NewAgentEventStatus(agent, event))
}

// WTEL-1727
// todo new watcher &
func (am *agentManager) changeDeadlineState() {
	if items, err := am.store.Agent().OnlineWithOutActive(MaxAgentOnlineWithOutSocSec); err != nil {
		wlog.Error(err.Error())
	} else {
		for _, v := range items {
			if a, _ := am.GetAgent(v.Id, v.UpdatedAt); a != nil {
				var s *string
				if v.Ws || v.Sip {
					s = model.NewString("system")
					if v.Ws {
						*s = *s + "/ws"
					}
					if v.Sip {
						*s = *s + "/sip"
					}
				}
				err = am.SetOffline(a, s)
				if err != nil {
					wlog.Error(err.Error())
				}
			}
		}
	}

	return
}

func (am *agentManager) MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError {
	return am.store.Agent().MissedAttempt(agentId, attemptId, cause)
}
