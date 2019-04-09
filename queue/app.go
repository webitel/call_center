package queue

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

type App interface {
	GetInstanceId() string
	IsReady() bool
	GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError)
	GetQueueById(id int64) (*model.Queue, *model.AppError)
	NewCall(params *model.CallRequest) (uuid, cause string, err *model.AppError)
	SetCallVariables(id string, variables map[string]string) *model.AppError

	ConsumeCallEvent() <-chan mq.Event
	SendEventQueueChangedLength(event *model.QueueEventCount) *model.AppError
}

type CallEvent interface {
}
