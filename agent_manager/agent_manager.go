package agent_manager

import (
	"fmt"
	"sync"

	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"golang.org/x/sync/singleflight"
)

const (
	watcherPollingInterval = 30000

	sizeAgentChane   = 10000
	expireAgentCache = 60 * 5
)

var (
	MaxAgentOnlineWithOutSocSec = 60
)

type HookAutoOfflineAgent func(agent AgentObject)

type agentManager struct {
	sync.Mutex

	store                store.Store
	mq                   mq.MQ
	watcher              *utils.Watcher
	nodeId               string
	startOnce            sync.Once
	agentsCache          utils.ObjectCache
	hookAutoOfflineAgent HookAutoOfflineAgent
	log                  *wlog.Logger
	requestGroup         singleflight.Group
}

func NewAgentManager(nodeId string, s store.Store, mq_ mq.MQ, log *wlog.Logger) AgentManager {
	am := agentManager{
		store:       s,
		mq:          mq_,
		nodeId:      nodeId,
		agentsCache: utils.NewLruWithParams(sizeAgentChane, "Agents", expireAgentCache, ""),
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("name", "agent_manager"),
		),
	}

	return &am
}

func (am *agentManager) SetHookAutoOfflineAgent(hook HookAutoOfflineAgent) {
	am.hookAutoOfflineAgent = hook
}

func (am *agentManager) Start() {
	am.log.Debug("starting agent service")
	am.watcher = utils.MakeWatcher("AgentManager", watcherPollingInterval, am.changeDeadlineState)
	am.startOnce.Do(func() {
		go am.watcher.Start()
	})
}

func (am *agentManager) Stop() { am.watcher.Stop() }

func (am *agentManager) PutAgentCache(a *model.Agent) AgentObject {
	if item, exists := am.agentsCache.Get(a.Id); exists {
		if currentAgent, ok := item.(AgentObject); ok {
			if currentAgent.UpdatedAt() >= a.UpdatedAt {
				return currentAgent
			}
		}
	}

	agent := NewAgent(a, am, am.log)

	am.agentsCache.AddWithDefaultExpires(a.Id, agent)

	agent.Log().Debug("updated agent in cache", wlog.String("agent_name", agent.Name()), wlog.Int64("updated_at", agent.UpdatedAt()))

	return agent
}

func (am *agentManager) GetAgent(id int, updatedAt int64) (AgentObject, *model.AppError) {
	if item, ok := am.agentsCache.Get(id); ok {
		if agent, ok := item.(AgentObject); ok && !agent.IsExpire(updatedAt) {
			return agent, nil
		}
	}

	key := fmt.Sprintf("agent:%d", id)

	val, err, _ := am.requestGroup.Do(key, func() (any, error) {
		if item, ok := am.agentsCache.Get(id); ok {
			if agent, ok := item.(AgentObject); ok && !agent.IsExpire(updatedAt) {
				return agent, nil
			}
		}

		a, appErr := am.store.Agent().Get(id)
		if appErr != nil {
			return nil, appErr
		}

		agent := NewAgent(a, am, am.log)

		am.agentsCache.AddWithDefaultExpires(id, agent)

		agent.Log().Debug("add agent to cache", wlog.String("agent_name", agent.Name()))

		return agent, nil
	})

	if err != nil {
		if weer, ok := err.(*model.AppError); ok {
			return nil, weer
		}

		return nil, model.NewAppError("GetAgent", "agent_manager.agent_manager.get_agent.update_cache", nil, err.Error(), 500)
	}

	return val.(AgentObject), nil
}

func (am *agentManager) PublishAgentStatusChangeEvent(agent AgentObject, e model.Event) *model.AppError {
	return am.mq.AgentChangeStatus(agent.DomainId(), agent.UserId(), e)
}

func (am *agentManager) SetOnline(agent AgentObject, onDemand bool) (*model.AgentOnlineData, *model.AppError) {
	data, err := am.store.Agent().SetOnline(agent.Id(), onDemand)
	if err != nil {
		agent.Log().Error(
			fmt.Sprintf("agent %s[%d] has been changed status to \"%s\" error: %s", agent.Name(), agent.Id(), model.AgentStatusOnline, err.Error()),
		)
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
	err := am.store.Agent().SetStatus(agent.Id(), status.Status, status.StatusPayload, status.StatusComment)
	if err != nil {
		agent.Log().Error(
			"changing agent status",
			wlog.String("agent_name", agent.Name()),
			wlog.Int("agent_id", agent.Id()),
			wlog.String("new_status", status.Status),
			wlog.Err(err),
		)

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

func (am *agentManager) SetPause(agent AgentObject, payload, statusComment *string, timeout *int) *model.AppError {
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
			StatusComment: statusComment,
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
	agent.StoreStatus(event.AgentStatus)
	//add channel queue
	return am.mq.AgentChangeStatus(agent.DomainId(), agent.UserId(), NewAgentEventStatus(agent, event))
}

// WTEL-1727
// todo new watcher &
func (am *agentManager) changeDeadlineState() {
	if items, err := am.store.Agent().OnlineWithOutActive(MaxAgentOnlineWithOutSocSec); err != nil {
		am.log.Error(err.Error(),
			wlog.Err(err),
		)
	} else {
		for _, v := range items {
			if a, _ := am.GetAgent(v.Id, v.UpdatedAt); a != nil {
				var s *string
				if v.Ws || v.Sip || v.ReasonSca || v.ReasonNoCCLicense {
					s = model.NewString("system")
					if v.ReasonSca {
						*s = *s + "/screen_control"
					} else if v.Ws {
						*s = *s + "/ws"
					}
					if v.Sip {
						*s = *s + "/sip"
					}

					if v.ReasonNoCCLicense {
						*s += "/no_cc_license"
					}
				}
				if a.TeamUpdatedAt() != v.TeamUpdatedAt {
					a.SetTeamUpdatedAt(v.TeamUpdatedAt)
				}
				err = am.SetOffline(a, s)
				if err != nil {
					a.Log().Error(err.Error())
				} else if am.hookAutoOfflineAgent != nil {
					am.hookAutoOfflineAgent(a)
				}
			}
		}
	}
}

func (am *agentManager) MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError {
	return am.store.Agent().MissedAttempt(agentId, attemptId, cause)
}
