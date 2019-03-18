package mq

import (
	"github.com/webitel/call_center/model"
)

type CalendarMQ interface {
}

type MQ interface {
	Send(name string, data map[string]interface{}) *model.AppError
	Close()

	ConsumeCallEvent() <-chan Event
}
