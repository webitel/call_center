package queue

import (
	"github.com/webitel/call_center/agent_manager"
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/pkg/wbt/flow"
)

type App interface {
	GetInstanceId() string
	IsReady() bool
	GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError)
	GetGateway(id int64) (*model.SipGateway, *model.AppError)
	GetQueueById(id int64) (*model.Queue, *model.AppError)
	FlowManager() flow.FlowManager
	ChatManager() *chat.ChatManager
	GetCall(id string) (*model.Call, *model.AppError)
	GetChat(id string) (*chat.Conversation, *model.AppError)
	QueueSettings() model.QueueSettings
	NotificationHideMember(domainId int64, queueId int, memberId *int64, agentId int) *model.AppError
	NotificationInterceptAttempt(domainId int64, queueId int, channel string, attemptId int64, skipAgentId int32) *model.AppError
	NotificationWaitingList(e *model.MemberWaitingByUsers) *model.AppError
	SetAgentBreakOut(agent agent_manager.AgentObject) *model.AppError
}
