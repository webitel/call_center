package agent_manager

import "github.com/webitel/call_center/model"

type AgentManager interface {
	Start()
	Stop()
	GetAgent(id int64, updatedAt int64) (AgentObject, *model.AppError)
	SetAgentState(agent AgentObject, state string) *model.AppError
	ReservedAgentForAttempt() <-chan AgentInAttemptObject
}

type AgentInAttemptObject interface {
	Agent() AgentObject
	AgentName() string
	AttemptId() int64
}

type AgentObject interface {
	Id() int64
	Name() string
	CallDestination() string
	IsExpire(updatedAt int64) bool
	CallError(err *model.AppError, cause string)
}
