package agent_manager

import (
	"github.com/webitel/call_center/model"
)

type Agent struct {
	info    *model.Agent
	manager AgentManager
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

func (agent *Agent) SuccessivelyNoAnswers() uint16 {
	return uint16(agent.info.SuccessivelyNoAnswers)
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

func (agent *Agent) GetCallEndpoints() []string {
	return []string{agent.info.Destination}
}

func (agent *Agent) CallNumber() string {
	return agent.info.Extension
}

func (agent *Agent) Online(channels []string, onDemand bool) (*model.AgentOnlineData, *model.AppError) {
	return agent.manager.SetOnline(agent, channels, onDemand)
}

func (agent *Agent) Offline() *model.AppError {
	return agent.manager.SetOffline(agent)
}

func (agent *Agent) SetOnBreak() *model.AppError {
	return agent.manager.SetPause(agent, nil, nil)
}

func (agent *Agent) IsOnDemand() bool {
	return agent.info.OnDemand
}
