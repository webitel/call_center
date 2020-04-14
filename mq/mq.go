package mq

import (
	"github.com/webitel/call_center/model"
)

type MQ interface {
	SendJSON(name string, data []byte) *model.AppError
	Close()

	ConsumeCallEvent() <-chan model.CallActionData

	AgentChangeStatus(e model.AgentEventStatus) *model.AppError

	AttemptEvent(e model.EventAttempt) *model.AppError

	QueueEvent() QueueEvent
}

type QueueEvent interface {
	SendChangedLength(e *model.QueueEventCount) *model.AppError
}
