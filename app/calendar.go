package app

import "github.com/webitel/call_center/model"

func (a *App) GetCalendarsPage(domainId int64, page, perPage int) ([]*model.Calendar, *model.AppError) {
	return a.Srv.Store.Calendar().GetAllPage(domainId, page*perPage, perPage)
}

func (a *App) GetCalendarsPageByGroups(domainId int64, groups []int, page, perPage int) ([]*model.Calendar, *model.AppError) {
	return a.Srv.Store.Calendar().GetAllPageByGroups(domainId, groups, page*perPage, perPage)
}

func (a *App) GetCalendar(domainId int64, id int) (*model.Calendar, *model.AppError) {
	return a.Srv.Store.Calendar().Get(domainId, id)
}

func (a *App) GetCalendarByGroup(domainId int64, id int, groups []int) (*model.Calendar, *model.AppError) {
	return a.Srv.Store.Calendar().GetByGroups(domainId, id, groups)
}

func (a *App) DeleteCalendar(domainId int64, id int) *model.AppError {

	if _, err := a.GetCalendar(domainId, id); err != nil {
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
