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
	store           store.Store
	watcher         *utils.Watcher
	nodeId          string
	startOnce       sync.Once
	agentsCache     utils.ObjectCache
	agentsInAttempt chan AgentsInAttemptObject
	sync.Mutex
}

func NewAgentManager(nodeId string, s store.Store) AgentManager {
	var agentManager AgentManagerImpl
	agentManager.store = s
	agentManager.nodeId = nodeId
	agentManager.agentsCache = utils.NewLruWithParams(MAX_AGENTS_CACHE, "Agents", MAX_AGENTS_EXPIRE_CACHE, "")
	agentManager.agentsInAttempt = make(chan AgentsInAttemptObject)
	return &agentManager
}

func (agentManager *AgentManagerImpl) Start() {
	mlog.Debug("Starting agent service")
	agentManager.watcher = utils.MakeWatcher("AgentManager", DEFAULT_WATCHER_POLLING_INTERVAL, agentManager.PollAndNotify)
	agentManager.startOnce.Do(func() {
		go agentManager.watcher.Start()
	})
}

func (agentManager *AgentManagerImpl) Stop() {
	agentManager.watcher.Stop()
}

func (agentManager *AgentManagerImpl) PollAndNotify() {

	result := <-agentManager.store.Agent().ReservedForAttemptByNode(agentManager.nodeId)
	if result.Err != nil {
		mlog.Error(result.Err.Error())
		time.Sleep(time.Second * 5)
		return
	}

	for _, v := range result.Data.([]*model.AgentsForAttempt) {
		agentManager.GetAgents(v.AgentIds)
		//agentManager.agentsInAttempt <- NewAgentsInAttempt(v)
	}
}

func (agentManager *AgentManagerImpl) GetAgent(id int64) (AgentObject, *model.AppError) {
	agentManager.Lock()
	defer agentManager.Unlock()

	var agent AgentObject
	item, ok := agentManager.agentsCache.Get(id)
	if ok {
		agent, ok = item.(AgentObject)
		return agent, nil
	}

	if result := <-agentManager.store.Agent().Get(id); result.Err != nil {
		return nil, result.Err
	} else {
		agent = result.Data.(AgentObject)
	}
	agentManager.agentsCache.AddWithDefaultExpires(id, agent)
	mlog.Debug(fmt.Sprintf("Add agent to cache %v", agent))
	return agent, nil
}

func (agentManager *AgentManagerImpl) GetAgents(ids []int64) ([]AgentObject, *model.AppError) {
	var agent AgentObject
	var err *model.AppError
	agents := make([]AgentObject, len(ids), len(ids))

	for _, id := range ids {
		if agent, err = agentManager.GetAgent(id); err != nil {
			return nil, err
		} else {
			agents = append(agents, agent)
		}

	}
	return agents, nil
}
