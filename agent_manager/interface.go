package agent_manager

import "github.com/webitel/call_center/model"

type AgentManager interface {
	Start()
	Stop()
	GetAgent(id int, updatedAt int64) (AgentObject, *model.AppError)

	SetOnline(agent AgentObject, onDemand bool) (*model.AgentOnlineData, *model.AppError)
	SetOffline(agent AgentObject) *model.AppError
	SetPause(agent AgentObject, payload *string, timeout *int) *model.AppError
	SetBreakOut(agent AgentObject) *model.AppError

	//internal
	SetAgentOnBreak(agentId int) *model.AppError
	MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError
}

type AgentObject interface {
	Id() int
	DomainId() int64
	UserId() int64
	Name() string
	GetCallEndpoints() []string
	CallNumber() string
	UpdatedAt() int64
	TeamId() int
	TeamUpdatedAt() int64
	SetTeamUpdatedAt(at int64)

	IsExpire(updatedAt int64) bool

	Online(onDemand bool) (*model.AgentOnlineData, *model.AppError)
	Offline() *model.AppError
	SetOnBreak() *model.AppError
	SetBreakOut() *model.AppError
	SetOnDemand(v bool)
	IsOnDemand() bool
	GreetingMedia() *model.RingtoneFile
	Variables() map[string]string
	HasPush() bool
}
