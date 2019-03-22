package app

import "github.com/webitel/call_center/model"

func (a *App) GetQueueById(id int64) (*model.Queue, *model.AppError) {
	if result := <-a.Srv.Store.Queue().GetById(id); result.Err != nil {
		return nil, result.Err
	} else {
		return result.Data.(*model.Queue), nil
	}
}
