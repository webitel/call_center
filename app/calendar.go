package app

import "github.com/webitel/call_center/model"

func (a *App) GetCalendarsPage(filter string, page, perPage int, sortField string, desc bool) ([]*model.Calendar, *model.AppError) {
	return a.GetCalendars(filter, page*perPage, perPage, sortField, desc)
}

func (a *App) GetCalendars(filter string, offset, limit int, sortField string, desc bool) ([]*model.Calendar, *model.AppError) {
	result := <-a.Srv.Store.Calendar().GetAllPage(filter, offset, limit, sortField, desc)
	if result.Err != nil {
		return nil, result.Err
	}
	return result.Data.([]*model.Calendar), nil
}

func (a *App) GetCalendar(id int) (*model.Calendar, *model.AppError) {
	if result := <-a.Srv.Store.Calendar().Get(id); result.Err != nil {
		return nil, result.Err
	} else {
		return result.Data.(*model.Calendar), nil
	}
}

func (a *App) DeleteCalendar(id int) *model.AppError {

	if _, err := a.GetCalendar(id); err != nil {
		return err
	}

	if result := <-a.Srv.Store.Calendar().Delete(id); result.Err != nil {
		return result.Err
	}
	return nil
}

func (a *App) CreateCalendar() {

}
