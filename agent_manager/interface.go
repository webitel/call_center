package agent_manager

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type AgentManager interface {
	Start()
	Stop()
	GetAgent(id int, updatedAt int64) (AgentObject, *model.AppError)

	SetOnline(agent AgentObject, onDemand bool) (*model.AgentOnlineData, *model.AppError)
	SetOffline(agent AgentObject, sys *string) *model.AppError
	SetPause(agent AgentObject, payload, statusComment *string, timeout *int) *model.AppError
	SetBreakOut(agent AgentObject) *model.AppError

	//internal
	SetAgentOnBreak(agentId int) *model.AppError
	MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError
	SetHookAutoOfflineAgent(hook HookAutoOfflineAgent)
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

	SetOnDemand(v bool)
	IsOnDemand() bool
	GreetingMedia() *model.RingtoneFile
	Variables() map[string]string
	HasPush() bool
	HookData() map[string]string
	StoreStatus(s model.AgentStatus)
	Log() *wlog.Logger
}
