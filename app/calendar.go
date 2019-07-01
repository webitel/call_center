package app

import "github.com/webitel/call_center/model"

func (a *App) GetCalendarsPage(filter string, page, perPage int, sortField string, desc bool) ([]*model.Calendar, *model.AppError) {
	return a.GetCalendars(filter, page*perPage, perPage, sortField, desc)
}

func (a *App) GetCalendars(filter string, offset, limit int, sortField string, desc bool) ([]*model.Calendar, *model.AppError) {
	return a.Srv.Store.Calendar().GetAllPage(filter, offset, limit, sortField, desc)
}

func (a *App) GetCalendar(id int) (*model.Calendar, *model.AppError) {
	return a.Srv.Store.Calendar().Get(id)
}

func (a *App) DeleteCalendar(id int) *model.AppError {

	if _, err := a.GetCalendar(id); err != nil {
		return err
	}

	return a.Srv.Store.Calendar().Delete(id)
}

func (a *App) CreateCalendar(calendar *model.Calendar) (*model.Calendar, *model.AppError) {
	err := calendar.IsValid()
	if err != nil {
		return nil, err
	}

	if c, err := a.Store.Calendar().Create(calendar); err != nil {
		return nil, err
	} else {
		return c, nil
	}
}
