package app

import "github.com/webitel/call_center/model"

func (a *App) GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError) {
	return a.Store.OutboundResource().GetById(id)
}

func (a *App) GetGateway(id int64) (*model.SipGateway, *model.AppError) {
	return a.Store.Gateway().Get(id)
}
