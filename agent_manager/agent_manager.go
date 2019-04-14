package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"sync"
	"time"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 500

const (
	MAX_AGENTS_CACHE        = 10000
	MAX_AGENTS_EXPIRE_CACHE = 60 * 60 * 24 //day
)

type AgentManagerImpl struct {
	store              store.Store
	watcher            *utils.Watcher
	nodeId             string
	startOnce          sync.Once
	agentsCache        utils.ObjectCache
	agentsInAttempt    chan AgentInAttemptObject
	agentStatusManager AgentStatusManager
	sync.Mutex
}

func NewAgentManager(nodeId string, s store.Store) AgentManager {
	var agentManager AgentManagerImpl
	agentManager.store = s
	agentManager.nodeId = nodeId
	agentManager.agentsCache = utils.NewLruWithParams(MAX_AGENTS_CACHE, "Agents", MAX_AGENTS_EXPIRE_CACHE, "")
	agentManager.agentsInAttempt = make(chan AgentInAttemptObject)
	agentManager.agentStatusManager = NewAgentStatusManager(s) //
	return &agentManager
}

func (agentManager *AgentManagerImpl) Start() {
	mlog.Debug("Starting agent service")
	agentManager.watcher = utils.MakeWatcher("AgentManager", DEFAULT_WATCHER_POLLING_INTERVAL, agentManager.PollAndNotify)
	agentManager.startOnce.Do(func() {
		agentManager.agentStatusManager.Start()
		go agentManager.watcher.Start()
	})
}

func (agentManager *AgentManagerImpl) Stop() {
	agentManager.watcher.Stop()

	agentManager.agentStatusManager.Stop()
}

func (agentManager *AgentManagerImpl) PollAndNotify() {
	result := <-agentManager.store.Agent().ReservedForAttemptByNode(agentManager.nodeId)

	if result.Err != nil {
		mlog.Error(result.Err.Error())
		time.Sleep(time.Second * 5)
		return
	}

	for _, v := range result.Data.([]*model.AgentsForAttempt) {
		if agent, err := agentManager.GetAgent(v.AgentId, v.AgentUpdatedAt); err != nil {
			mlog.Error(fmt.Sprintf("Get agent Id=%d for AttemptId=%d error: %s", v.AgentId, v.AttemptId, err.Error()))
			if result := <-agentManager.store.Member().SetAttemptAgentId(v.AttemptId, nil); result.Err != nil {
				mlog.Error(result.Err.Error())
			}
			continue
		} else {
			agentManager.agentsInAttempt <- NewAgentInAttempt(agent, v.AttemptId)
		}
	}
}

func (agentManager *AgentManagerImpl) GetAgent(id int64, updatedAt int64) (AgentObject, *model.AppError) {
	agentManager.Lock()
	defer agentManager.Unlock()

	var agent AgentObject
	item, ok := agentManager.agentsCache.Get(id)
	if ok {
		agent, ok = item.(AgentObject)
		if ok && !agent.IsExpire(updatedAt) {
			return agent, nil
		}
	}

	if result := <-agentManager.store.Agent().Get(id); result.Err != nil {
		return nil, result.Err
	} else {
		agent = NewAgent(result.Data.(*model.Agent), agentManager)
	}
	agentManager.agentsCache.AddWithDefaultExpires(id, agent)
	mlog.Debug(fmt.Sprintf("Add agent to cache %v", agent.Name()))
	return agent, nil
}

func (agentManager *AgentManagerImpl) SetAgentState(agent AgentObject, state string, timeoutSeconds int) *model.AppError {

	if err := agentManager.agentStatusManager.SetAgentState(agent, state, timeoutSeconds); err != nil {
		mlog.Error(fmt.Sprintf("Agent %s[%d] has been changed state to \"%s\" error: %s", agent.Name(), agent.Id(), state, err.Error()))
		return err
	}

	agentManager.notifyChangeAgentState(agent, state)
	mlog.Debug(fmt.Sprintf("Agent %s[%d] has been changed state to \"%s\"", agent.Name(), agent.Id(), state))
	return nil
}
