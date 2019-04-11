package agent_manager

type AgentInAttempt struct {
	agent     AgentObject
	attemptId int64
}

func NewAgentInAttempt(agent AgentObject, attemptId int64) AgentInAttemptObject {
	a := &AgentInAttempt{
		attemptId: attemptId,
		agent:     agent,
	}
	return a
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
