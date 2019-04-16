package agent_manager

import "github.com/webitel/call_center/model"

type AgentManager interface {
	Start()
	Stop()
	GetAgent(id int64, updatedAt int64) (AgentObject, *model.AppError)

	SetAgentStatus(agent AgentObject, status *model.AgentStatus) *model.AppError
	SetAgentState(agent AgentObject, state string, timeoutSeconds int) *model.AppError
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
	GetEndpoints() []string
	IsExpire(updatedAt int64) bool

	MaxNoAnswer() int
	NoAnswerDelayTime() int
}
