package store

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/discovery"
)

type Store interface {
	Cluster() ClusterStore
	Queue() QueueStore
	Member() MemberStore
	OutboundResource() OutboundResourceStore
	Agent() AgentStore
	Team() TeamStore
	Gateway() GatewayStore
	Call() CallStore
}

type CallStore interface {
	Get(id string) (*model.Call, *model.AppError)
}

type ClusterStore interface {
	CreateOrUpdate(nodeId string) (*discovery.ClusterData, error)
	//UpdateUpdatedTime(nodeId string) (*discovery.ClusterData, error)
	UpdateClusterInfo(nodeId string, started bool) (*discovery.ClusterData, error)
}

type OutboundResourceStore interface {
	GetById(id int64) (*model.OutboundResource, *model.AppError)
	SetError(id int64, queueId int64, errorId string, strategy model.OutboundResourceUnReserveStrategy) (*model.OutboundResourceErrorResult, *model.AppError)
	SetSuccessivelyErrorsById(id int64, successivelyErrors uint16) *model.AppError
}

type QueueStore interface {
	GetById(id int64) (*model.Queue, *model.AppError)
	RefreshStatisticsDay5Min() *model.AppError
}

type MemberStore interface {
	ReserveMembersByNode(nodeId string) (int64, *model.AppError)
	UnReserveMembersByNode(nodeId, cause string) (int64, *model.AppError)

	GetActiveMembersAttempt(nodeId string) ([]*model.MemberAttempt, *model.AppError)

	DistributeChatToQueue(node string, queueId int64, callId string, number string, name string, priority int) (*model.MemberAttempt, *model.AppError)
	DistributeDirect(node string, memberId int64, communicationId, agentId int) (*model.MemberAttempt, *model.AppError)
	DistributeCallToQueue(node string, queueId int64, callId string, vars map[string]string, bucketId *int32, priority int) (*model.InboundCallQueue, *model.AppError)
	DistributeCallToQueueCancel(id int64) *model.AppError

	/*
		Flow control
	*/
	SetDistributeCancel(id int64, description string, nextDistributeSec uint32, stop bool, vars map[string]string) *model.AppError

	SetAttemptFindAgent(id int64) *model.AppError

	SetAttemptOffering(attemptId int64, agentId *int, agentCallId, memberCallId *string, destination, display *string) (int64, *model.AppError)
	SetAttemptBridged(attemptId int64) (int64, *model.AppError)
	SetAttemptReporting(attemptId int64, deadlineSec uint16) (int64, *model.AppError)
	SetAttemptAbandoned(attemptId int64) (int64, *model.AppError)
	SetAttemptAbandonedWithParams(attemptId int64, maxAttempts uint, sleep uint64) (int64, *model.AppError)

	SetAttemptMissedAgent(attemptId int64, agentHoldSec int) (*model.MissedAgent, *model.AppError)
	SetAttemptMissed(id int64, holdSec, agentHoldTime int) (int64, *model.AppError)
	SetAttemptResult(id int64, result string, holdSec int, channelState string, agentHoldTime int) (int64, *model.AppError)
	CallbackReporting(attemptId int64, status, description string, expireAt, nextDistributeAt *int64) (*model.AttemptReportingResult, *model.AppError)

	SaveToHistory() ([]*model.HistoryAttempt, *model.AppError)
	GetTimeouts(nodeId string) ([]*model.AttemptReportingTimeout, *model.AppError)

	// CHAT TODO
	CreateConversationChannel(parentChannelId, name string, attemptId int64) (string, *model.AppError)
}

type AgentStore interface {
	Get(id int) (*model.Agent, *model.AppError)
	GetChannelTimeout() ([]*model.ChannelTimeout, *model.AppError)

	SetOnline(agentId int, channels []string, onDemand bool) (*model.AgentOnlineData, *model.AppError)
	WaitingChannel(agentId int, channel string) (int64, *model.AppError)

	SetOnBreak(agentId int) *model.AppError

	SetStatus(agentId int, status string, payload *string) *model.AppError

	CreateMissed(missed *model.MissedAgentAttempt) *model.AppError

	ReservedForAttemptByNode(nodeId string) ([]*model.AgentsForAttempt, *model.AppError)

	MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError
	ConfirmAttempt(agentId int, attemptId int64) ([]string, *model.AppError)

	RefreshEndStateDay5Min() *model.AppError
}

type TeamStore interface {
	Get(id int) (*model.Team, *model.AppError)
}

type GatewayStore interface {
	Get(id int64) (*model.SipGateway, *model.AppError)
}
