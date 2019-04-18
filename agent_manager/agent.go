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

func (agent *Agent) Name() string {
	return agent.info.Name
}

func (agent *Agent) Id() int64 {
	return agent.info.Id
}

func (agent *Agent) UpdatedAt() int64 {
	return agent.info.UpdatedAt
}

func (agent *Agent) IsExpire(updatedAt int64) bool {
	return agent.info.UpdatedAt != updatedAt
}

func (agent *Agent) CallDestination() string {
	return "user/9999@10.10.10.144"
}

func (agent *Agent) GetEndpoints() []string {
	return []string{"sofia/external/111@10.10.10.25:15060"}
}

func (agent *Agent) MaxNoAnswer() int {
	return agent.info.MaxNoAnswer
}

func (agent *Agent) WrapUpTime() int {
	return agent.info.WrapUpTime
}

func (agent *Agent) RejectDelayTime() int {
	return agent.info.RejectDelayTime
}

func (agent *Agent) BusyDelayTime() int {
	return agent.info.BusyDelayTime
}

func (agent *Agent) NoAnswerDelayTime() int {
	return agent.info.NoAnswerDelayTime
}

func (agent *Agent) CallTimeout() uint16 {
	return uint16(agent.info.CallTimeout)
}

func (agent *Agent) Online() *model.AppError {
	return agent.manager.SetOnline(agent)
}

func (agent *Agent) Offline() *model.AppError {
	return agent.manager.SetOffline(agent)
}
