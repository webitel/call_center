package agent_manager

import "github.com/webitel/call_center/model"

type Agent struct {
	info *model.Agent
}

type AgentInAttempt struct {
	agent     AgentObject
	attemptId int64
}

func NewAgent(info *model.Agent) AgentObject {
	return &Agent{
		info: info,
	}
}

func NewAgentInAttempt(agent AgentObject, attemptId int64) AgentInAttemptObject {
	a := &AgentInAttempt{
		attemptId: attemptId,
		agent:     agent,
	}
	return a
}

func (agent *Agent) Name() string {
	return agent.info.Name
}

func (agent *Agent) Id() int64 {
	return agent.info.Id
}

func (agent *Agent) IsExpire(updatedAt int64) bool {
	return agent.info.UpdatedAt != updatedAt
}

func (agent *Agent) CallDestination() string {
	return "user/9999@10.10.10.144"
}

func (aia *AgentInAttempt) Agent() AgentObject {
	return aia.agent
}

func (aia *AgentInAttempt) AgentName() string {
	return aia.agent.Name()
}

func (aia *AgentInAttempt) AttemptId() int64 {
	return aia.attemptId
}
