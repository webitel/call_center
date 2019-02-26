package dialing

import "github.com/webitel/call_center/model"

type App interface {
	GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError)
}
