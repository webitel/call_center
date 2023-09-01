package queue

import (
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
	"github.com/webitel/flow_manager/client"
)

type App interface {
	GetInstanceId() string
	IsReady() bool
	GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError)
	GetGateway(id int64) (*model.SipGateway, *model.AppError)
	GetQueueById(id int64) (*model.Queue, *model.AppError)
	FlowManager() client.FlowManager
	ChatManager() *chat.ChatManager
	GetCall(id string) (*model.Call, *model.AppError)
	GetChat(id string) (*chat.Conversation, *model.AppError)
	QueueSettings() model.QueueSettings
	NotificationHideMember(domainId int64, queueId int, memberId *int64, agentId int) *model.AppError
	NotificationInterceptAttempt(domainId int64, queueId int, attemptId int64, skipAgentId int32) *model.AppError
	NotificationWaitingList(domainId int64, userIds []int64, list []*model.MemberWaiting) *model.AppError
}
