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

func (agent *Agent) SetStateOffering(queueId int, attemptId int64) *model.AppError {
	var err *model.AppError
	if agent.info.SuccessivelyNoAnswers, err = agent.manager.SetAgentOffering(agent, queueId, attemptId); err != nil {
		return err
	}
	return nil
}

func (agent *Agent) SetStateTalking() *model.AppError {
	return agent.manager.SetAgentTalking(agent)
}

func (agent *Agent) SetStateReporting(deadline int) *model.AppError {
	return agent.manager.SetAgentReporting(agent, deadline)
}

func (agent *Agent) SetStateFine(deadline int, noAnswer bool) *model.AppError {
	return agent.manager.SetAgentFine(agent, deadline, noAnswer)
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

func (agent *Agent) Online() *model.AppError {
	return agent.manager.SetOnline(agent)
}

func (agent *Agent) Offline() *model.AppError {
	return agent.manager.SetOffline(agent)
}

func (agent *Agent) SetOnBreak() *model.AppError {
	return agent.manager.SetAgentOnBreak(agent.Id())
}
