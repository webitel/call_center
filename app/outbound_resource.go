package app

import "github.com/webitel/call_center/model"

func (a *App) GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError) {
	return a.Store.OutboundResource().GetById(id)
}

func (a *App) GetOutboundResourcesPage(filter string, page, perPage int, sortField string, desc bool) ([]*model.OutboundResource, *model.AppError) {
	return a.GetOutboundResources(filter, page*perPage, perPage, sortField, desc)
}

func (a *App) GetOutboundResources(filter string, offset, limit int, sortField string, desc bool) ([]*model.OutboundResource, *model.AppError) {
	return a.Store.OutboundResource().GetAllPage(filter, offset, limit, sortField, desc)
}

func (a *App) CreateOutboundResource(resource *model.OutboundResource) (*model.OutboundResource, *model.AppError) {
	return a.Store.OutboundResource().Create(resource)
}

func (a *App) DeleteOutboundResource(id int64) *model.AppError {
	_, err := a.GetOutboundResourceById(id)
	if err != nil {
		return err
	}

	return a.Store.OutboundResource().Delete(id)
}

func (a *App) GetGateway(id int64) (*model.SipGateway, *model.AppError) {
	return a.Store.Gateway().Get(id)
}
