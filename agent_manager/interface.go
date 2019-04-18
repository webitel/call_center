package agent_manager

import "github.com/webitel/call_center/model"

type AgentManager interface {
	Start()
	Stop()
	GetAgent(id int64, updatedAt int64) (AgentObject, *model.AppError)

	SetOnline(agent AgentObject) *model.AppError
	SetOffline(agent AgentObject) *model.AppError
	SetPause(agent AgentObject, payload []byte, timeout int) *model.AppError

	SetAgentStatus(agent AgentObject, status *model.AgentStatus) *model.AppError
	SetAgentState(agent AgentObject, state string, timeoutSeconds int) *model.AppError
}

type AgentObject interface {
	Id() int64
	Name() string
	CallDestination() string
	GetEndpoints() []string
	UpdatedAt() int64

	IsExpire(updatedAt int64) bool

	Online() *model.AppError
	Offline() *model.AppError

	MaxNoAnswer() int
	WrapUpTime() int
	RejectDelayTime() int
	BusyDelayTime() int
	NoAnswerDelayTime() int
	CallTimeout() uint16
}
