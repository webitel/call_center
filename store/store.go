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
	Statistic() StatisticStore
	Trigger() TriggerStore
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
	UserIds(queueId int, skipAgentId int) (model.Int64Array, *model.AppError)
}

type MemberStore interface {
	ReserveMembersByNode(nodeId string) (int64, *model.AppError)
	UnReserveMembersByNode(nodeId, cause string) (int64, *model.AppError)

	GetActiveMembersAttempt(nodeId string) ([]*model.MemberAttempt, *model.AppError)

	DistributeChatToQueue(node string, queueId int64, convId string, vars map[string]string, bucketId *int32, priority int, stickyAgentId *int) (*model.InboundChatQueue, *model.AppError)
	DistributeDirect(node string, memberId int64, communicationId, agentId int) (*model.MemberAttempt, *model.AppError)
	DistributeCallToQueue(node string, queueId int64, callId string, vars map[string]string, bucketId *int32, priority int, stickyAgentId *int) (*model.InboundCallQueue, *model.AppError)
	DistributeCallToQueueCancel(id int64) *model.AppError
	DistributeCallToAgent(node string, callId string, vars map[string]string, agentId int32, force bool) (*model.InboundCallAgent, *model.AppError)

	/*
		Flow control
	*/
	SetBarred(id int64) *model.AppError
	CancelAgentAttempt(id int64, agentHoldTime int) (*model.MissedAgent, *model.AppError)
	SetDistributeCancel(id int64, description string, nextDistributeSec uint32, stop bool, vars map[string]string) *model.AppError

	SetAttemptFindAgent(id int64) *model.AppError
	AnswerPredictAndFindAgent(id int64) *model.AppError

	SetAttemptOffering(attemptId int64, agentId *int, agentCallId, memberCallId *string, destination, display *string) (int64, *model.AppError)
	SetAttemptBridged(attemptId int64) (int64, *model.AppError)
	SetAttemptReporting(attemptId int64, deadlineSec uint32) (int64, *model.AppError)
	SchemaResult(attemptId int64, callback *model.AttemptCallback, maxAttempts uint, waitBetween uint64, perNum bool) (*model.AttemptLeaving, *model.AppError)
	//SetAttemptAbandoned(attemptId int64) (*model.AttemptLeaving, *model.AppError)
	SetAttemptAbandonedWithParams(attemptId int64, maxAttempts uint, sleep uint64, vars map[string]string, perNum bool,
		excludeNum bool, redial bool, desc *string, stickyAgentId *int32) (*model.AttemptLeaving, *model.AppError)

	SetAttemptMissedAgent(attemptId int64, agentHoldSec int) (*model.MissedAgent, *model.AppError)
	SetAttemptMissed(id int64, agentHoldTime int, maxAttempts uint, waitBetween uint64, perNum bool) (*model.MissedAgent, *model.AppError)
	SetAttemptResult(id int64, result string, channelState string, agentHoldTime int, vars map[string]string,
		maxAttempts uint, waitBetween uint64, perNum bool, desc *string, stickyAgentId *int32) (*model.MissedAgent, *model.AppError)
	CallbackReporting(attemptId int64, callback *model.AttemptCallback, maxAttempts uint, waitBetween uint64, byNum bool) (*model.AttemptReportingResult, *model.AppError)

	SaveToHistory() ([]*model.HistoryAttempt, *model.AppError)
	GetTimeouts(nodeId string) ([]*model.AttemptReportingTimeout, *model.AppError)
	RenewalProcessing(domainId, attId int64, renewalSec uint32) (*model.RenewalProcessing, *model.AppError)

	// CHAT TODO
	CreateConversationChannel(parentChannelId, name string, attemptId int64) (string, *model.AppError)

	RefreshQueueStatsLast2H() *model.AppError

	TransferredTo(id, toId int64) *model.AppError
	TransferredFrom(id, toId int64, toAgentId int, toAgentSessId string) *model.AppError
	CancelAgentDistribute(agentId int32) ([]int64, *model.AppError)
	SetExpired() ([]int64, *model.AppError)

	StoreForm(attemptId int64, form []byte, fields map[string]string) *model.AppError

	CleanAttempts(nodeId string) *model.AppError
	FlipResource(attemptId int64, skippResources []int) (*model.AttemptFlipResource, *model.AppError)
}

type AgentStore interface {
	Get(id int) (*model.Agent, *model.AppError)
	GetChannelTimeout() ([]*model.ChannelTimeout, *model.AppError)

	SetOnline(agentId int, onDemand bool) (*model.AgentOnlineData, *model.AppError)
	WaitingChannel(agentId int, channel string) (int64, *model.AppError)

	SetOnBreak(agentId int) *model.AppError

	SetStatus(agentId int, status string, payload *string) *model.AppError

	CreateMissed(missed *model.MissedAgentAttempt) *model.AppError

	ReservedForAttemptByNode(nodeId string) ([]*model.AgentsForAttempt, *model.AppError)

	MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError
	ConfirmAttempt(agentId int, attemptId int64) ([]string, *model.AppError)

	RefreshAgentPauseCauses() *model.AppError
	RefreshAgentStatistics() *model.AppError

	GetNoAnswerChannels(agentId int) ([]*model.CallNoAnswer, *model.AppError)

	OnlineWithOutActive(sec int) ([]model.AgentHashKey, *model.AppError)
	LosePredictAttempt(id int) *model.AppError
}

type TeamStore interface {
	Get(id int) (*model.Team, *model.AppError)
}

type GatewayStore interface {
	Get(id int64) (*model.SipGateway, *model.AppError)
}

type StatisticStore interface {
	RefreshInbound1H() *model.AppError
}

type TriggerStore interface {
	ScheduleNewJobs() *model.AppError
	FetchIdleJobs(node string, limit int) ([]model.TriggerJob, *model.AppError)
	SetError(job *model.TriggerJob, jobErr error) *model.AppError
	SetResult(job *model.TriggerJob) *model.AppError
	CleanActive(nodeId string) *model.AppError
}
