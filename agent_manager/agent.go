package agent_manager

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"strconv"
	"sync"
)

type Agent struct {
	info    *model.Agent
	manager AgentManager
	sync.RWMutex
}

func NewAgent(info *model.Agent, am AgentManager) AgentObject {
	return &Agent{
		info:    info,
		manager: am,
	}
}

func (agent *Agent) DomainId() int64 {
	return agent.info.DomainId
}

func (agent *Agent) UserId() int64 {
	//FIXME
	if agent.info.UserId != nil {
		return *agent.info.UserId
	}
	return 0
}

func (agent *Agent) Name() string {
	return agent.info.Name
}

func (agent *Agent) Id() int {
	return agent.info.Id
}

func (agent *Agent) UpdatedAt() int64 {
	return agent.info.UpdatedAt
}

func (agent *Agent) IsExpire(updatedAt int64) bool {
	return agent.info.UpdatedAt != updatedAt
}

func (agent *Agent) StoreStatus(s model.AgentStatus) {
	agent.Lock()
	agent.info.Status = s.Status
	agent.info.StatusPayload = s.StatusPayload
	agent.Unlock()
}

// TODO
func (agent *Agent) GetCallEndpoints() []string {
	if agent.info.Destination == nil {
		return nil
	}
	return []string{*agent.info.Destination}
}

// TODO
func (agent *Agent) CallNumber() string {
	if agent.info.Extension == nil {
		return ""
	}
	return *agent.info.Extension
}

func (agent *Agent) TeamId() int {
	return agent.info.TeamId
}

func (agent *Agent) TeamUpdatedAt() int64 {
	return agent.info.TeamUpdatedAt
}

func (agent *Agent) SetTeamUpdatedAt(at int64) {
	agent.info.TeamUpdatedAt = at
}

func (agent *Agent) SetBreakOut() *model.AppError {
	return agent.manager.SetBreakOut(agent)
}

func (agent *Agent) IsOnDemand() bool {
	return agent.info.OnDemand
}

func (agent *Agent) GreetingMedia() *model.RingtoneFile {
	return agent.info.GreetingMedia
}

func (agent *Agent) SetOnDemand(v bool) {
	//todo mutex
	agent.info.OnDemand = v
}

func (agent *Agent) Variables() map[string]string {
	return agent.info.Variables
}

func (agent *Agent) HasPush() bool {
	return agent.info.HasPush
}

func (agent *Agent) HookData() map[string]string {
	agent.RLock()
	defer agent.RUnlock()

	data := map[string]string{
		"agent_id":   strconv.Itoa(agent.Id()),
		"user_id":    fmt.Sprintf("%d", agent.UserId()),
		"team_id":    fmt.Sprintf("%d", agent.TeamId()),
		"agent_name": agent.Name(),
		"status":     agent.info.Status,
	}

	if agent.info.StatusPayload != nil {
		data["status_payload"] = *agent.info.StatusPayload
	}
	if agent.info.Extension != nil {
		data["extension"] = *agent.info.Extension
	}

	return data
}
