package app

import "github.com/webitel/call_center/model"

func (a *App) GetOutboundResourceById(id int64) (*model.OutboundResource, *model.AppError) {
	if result := <-a.Srv.Store.OutboundResource().GetById(id); result.Err != nil {
		return nil, result.Err
	} else {
		return result.Data.(*model.OutboundResource), nil
	}
}
