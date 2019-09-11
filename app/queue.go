package app

import "github.com/webitel/call_center/model"

func (a *App) GetQueueById(id int64) (*model.Queue, *model.AppError) {
	return a.Store.Queue().GetById(id)
}

func (a *App) CreateMemberInQueue(m *model.InboundMember) (int64, *model.AppError) {
	return 0, nil
}
