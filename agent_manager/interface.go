package agent_manager

type AgentManager interface {
	Start()
	Stop()
	ReservedAgentForAttempt() <-chan AgentInAttemptObject
}

type AgentInAttemptObject interface {
	Agent() AgentObject
	AgentName() string
	AttemptId() int64
}

type AgentObject interface {
	Name() string
	CallDestination() string
	IsExpire(updatedAt int64) bool
}
