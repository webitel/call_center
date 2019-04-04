package agent_manager

type AgentManager interface {
	Start()
	Stop()
	ReservedAgentForAttempt() <-chan AgentsInAttemptObject
}
