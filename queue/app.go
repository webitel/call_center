package queue

import (
	"github.com/webitel/call_center/model"
)

type App interface {
	GetInstanceId() string
	IsReady() bool
	GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError)
	GetGateway(id int64) (*model.SipGateway, *model.AppError)
	GetQueueById(id int64) (*model.Queue, *model.AppError)
	SendEventQueueChangedLength(event *model.QueueEventCount) *model.AppError
}
