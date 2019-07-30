package app

import (
	"github.com/webitel/call_center/model"
)

//func (a *App) NewCall(params *model.CallRequest) (uuid, cause string, err *model.AppError) {
//	uuid, cause, err = a.callCommands.NewCall(params)
//	return
//}

func (a *App) ConsumeCallEvent() <-chan model.Event {
	return a.MQ.ConsumeCallEvent()
}
