package app

import "github.com/webitel/call_center/model"

func (a *App) GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError) {
	if result := <-a.Srv.Store.OutboundResource().GetById(id); result.Err != nil {
		return nil, result.Err
	} else {
		return result.Data.(*model.OutboundResource), nil
	}
}

func (a *App) GetOutboundResourcesPage(filter string, page, perPage int, sortField string, desc bool) ([]*model.OutboundResource, *model.AppError) {
	return a.GetOutboundResources(filter, page*perPage, perPage, sortField, desc)
}

func (a *App) GetOutboundResources(filter string, offset, limit int, sortField string, desc bool) ([]*model.OutboundResource, *model.AppError) {
	result := <-a.Srv.Store.OutboundResource().GetAllPage(filter, offset, limit, sortField, desc)
	if result.Err != nil {
		return nil, result.Err
	}
	return result.Data.([]*model.OutboundResource), nil
}

func (a *App) CreateOutboundResource(resource *model.OutboundResource) (*model.OutboundResource, *model.AppError) {
	if result := <-a.Srv.Store.OutboundResource().Create(resource); result.Err != nil {
		return nil, result.Err
	} else {
		return result.Data.(*model.OutboundResource), nil
	}
}

func (a *App) DeleteOutboundResource(id int64) *model.AppError {
	_, err := a.GetOutboundResourceById(id)
	if err != nil {
		return err
	}

	if result := <-a.Srv.Store.OutboundResource().Delete(id); result.Err != nil {
		return result.Err
	}
	return nil
}
