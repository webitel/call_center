package agent_manager

func (agentManager *AgentManagerImpl) ReservedAgentForAttempt() <-chan AgentInAttemptObject {
	return agentManager.agentsInAttempt
}
