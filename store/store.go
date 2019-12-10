package store

import (
	"github.com/webitel/call_center/discovery"
	"github.com/webitel/call_center/model"
)

type Store interface {
	Cluster() ClusterStore
	Queue() QueueStore
	Member() MemberStore
	OutboundResource() OutboundResourceStore
	Agent() AgentStore
	Team() TeamStore
	Gateway() GatewayStore
}

type ClusterStore interface {
	//CreateOrUpdate(nodeId string) (*discovery.ClusterData, error)
	//UpdateUpdatedTime(nodeId string) (*discovery.ClusterData, error)
	UpdateClusterInfo(nodeId string, started bool) (*discovery.ClusterData, error)
}

type OutboundResourceStore interface {
	GetById(id int64) (*model.OutboundResource, *model.AppError)
	GetAllPage(filter string, offset, limit int, sortField string, desc bool) ([]*model.OutboundResource, *model.AppError)
	Create(resource *model.OutboundResource) (*model.OutboundResource, *model.AppError)
	Delete(id int64) *model.AppError
	SetError(id int64, queueId int64, errorId string, strategy model.OutboundResourceUnReserveStrategy) (*model.OutboundResourceErrorResult, *model.AppError)
	SetSuccessivelyErrorsById(id int64, successivelyErrors uint16) *model.AppError
}

type QueueStore interface {
	GetById(id int64) (*model.Queue, *model.AppError)
}

type MemberStore interface {
	ReserveMembersByNode(nodeId string) (int64, *model.AppError)
	UnReserveMembersByNode(nodeId, cause string) (int64, *model.AppError)

	GetActiveMembersAttempt(nodeId string) ([]*model.MemberAttempt, *model.AppError)

	DistributeCallToQueue(queueId int64, callId string, number string, name string, priority int) (int64, *model.AppError)

	SetAttemptState(id int64, state int) *model.AppError
	SetBridged(id, bridgedAt int64, legAId, legBId *string) *model.AppError
	ActiveCount(queue_id int64) (int64, *model.AppError)
	SetAttemptAgentId(attemptId int64, agentId *int64) *model.AppError
	SetAttemptFindAgent(id int64) *model.AppError

	SetAttemptSuccess(attemptId, hangupAt int64, cause string, data []byte) *model.AppError
	SetAttemptStop(attemptId, hangupAt int64, delta int, isErr bool, cause string, data []byte) (bool, *model.AppError)
	SetAttemptBarred(attemptId, hangupAt int64, cause string, data []byte) (bool, *model.AppError)
}

type AgentStore interface {
	Get(id int64) (*model.Agent, *model.AppError)

	SetStatus(agentId int64, status string, payload interface{}) *model.AppError
	SetState(agentId int64, state string, timeoutSeconds int) (*model.AgentState, *model.AppError)

	SaveActivityCallStatistic(agentId, offeringAt, answerAt, bridgeStartAt, bridgeStopAt int64, nowAnswer bool) (int, *model.AppError)

	ReservedForAttemptByNode(nodeId string) ([]*model.AgentsForAttempt, *model.AppError)
	ChangeDeadlineState(newState string) ([]*model.AgentChangedState, *model.AppError)

	ConfirmAttempt(agentId int64, attemptId int64) (int, *model.AppError)
}

type TeamStore interface {
	Get(id int64) (*model.Team, *model.AppError)
}

type GatewayStore interface {
	Get(id int64) (*model.SipGateway, *model.AppError)
}
