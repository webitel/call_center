package app

import "github.com/webitel/call_center/model"

func (a *App) SendEventQueueChangedLength(event *model.QueueEventCount) *model.AppError {
	return a.MQ.QueueEvent().SendChangedLength(event)
}
