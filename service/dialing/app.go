package dialing

import "github.com/webitel/call_center/model"

type App interface {
	GetInstanceId() string
	IsReady() bool
	GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError)
	GetQueueById(id int) (*model.Queue, *model.AppError)
}
