package agent_manager

func (agentManager *AgentManagerImpl) ReservedAgentForAttempt() <-chan AgentsInAttemptObject {
	return agentManager.agentsInAttempt
}
