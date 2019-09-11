package agent_manager

import (
	"fmt"
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

func (agent *Agent) SetStateOffering(deadline int) *model.AppError {
	return agent.manager.SetAgentState(agent, model.AGENT_STATE_OFFERING, deadline)
}

func (agent *Agent) SetStateTalking(deadline int) *model.AppError {
	return agent.manager.SetAgentState(agent, model.AGENT_STATE_TALK, deadline)
}

func (agent *Agent) SetStateReporting(deadline int) *model.AppError {
	return agent.manager.SetAgentState(agent, model.AGENT_STATE_REPORTING, deadline)
}

func (agent *Agent) SetStateFine(deadline int) *model.AppError {
	return agent.manager.SetAgentState(agent, model.AGENT_STATE_FINE, deadline)
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

func (agent *Agent) GetCallEndpoints() []string {
	return []string{fmt.Sprintf("sofia/sip/400@webitel.lo")}
}

func (agent *Agent) Online() *model.AppError {
	return agent.manager.SetOnline(agent)
}

func (agent *Agent) Offline() *model.AppError {
	return agent.manager.SetOffline(agent)
}
