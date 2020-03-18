package agent_manager

import "github.com/webitel/call_center/model"

type AgentManager interface {
	Start()
	Stop()
	GetAgent(id int, updatedAt int64) (AgentObject, *model.AppError)

	SetOnline(agent AgentObject) *model.AppError
	SetOffline(agent AgentObject) *model.AppError
	SetPause(agent AgentObject, payload *string, timeout *int) *model.AppError

	//SetAgentStatus(agent AgentObject, status *model.AgentStatus) *model.AppError
	//SetAgentState(agent AgentObject, state string, timeoutSeconds int) *model.AppError

	//internal
	SetAgentOnBreak(agentId int) *model.AppError

	SetAgentWaiting(agentId int, bridged bool) *model.AppError
	SetAgentOffering(agentId, queueId int) (int, *model.AppError)
	SetAgentTalking(agentId int) *model.AppError
	SetAgentReporting(agentId int, timeout int) *model.AppError
	SetAgentFine(agentId int, timeout int, noAnswer bool) *model.AppError

	MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError
}

type AgentObject interface {
	Id() int
	DomainId() int64
	UserId() int64
	Name() string
	GetCallEndpoints() []string
	SuccessivelyNoAnswers() uint16
	UpdatedAt() int64

	IsExpire(updatedAt int64) bool

	Online() *model.AppError
	Offline() *model.AppError
	SetOnBreak() *model.AppError

	SetStateOffering(queueId int) *model.AppError
	SetStateTalking() *model.AppError
	SetStateReporting(deadline int) *model.AppError
	SetStateFine(deadline int, noAnswer bool) *model.AppError
}
