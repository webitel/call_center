package mq

import (
	"github.com/webitel/call_center/model"
)

type E interface {
	ToJSON() string
}

type MQ interface {
	SendJSON(name string, data []byte) *model.AppError
	Close()

	ConsumeCallEvent() <-chan model.CallActionData
	ConsumeChatEvent() <-chan model.ChatEvent

	AgentChangeStatus(domainId int64, userId int64, e E) *model.AppError
	AgentChannelEvent(channel string, domainId int64, queueId int, userId int64, e E) *model.AppError

	SendNotification(domainId int64, event *model.Notification) *model.AppError

	QueueEvent() QueueEvent
}

type QueueEvent interface {
}
