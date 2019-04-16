package app

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

func (a *App) NewCall(params *model.CallRequest) (uuid, cause string, err *model.AppError) {
	uuid, cause, err = a.callCommands.NewCall(params)
	return
}

func (a *App) SetCallVariables(id string, variables map[string]string) *model.AppError {
	return a.callCommands.SetCallVariables(id, variables)
}

func (a *App) ConsumeCallEvent() <-chan mq.Event {
	return a.MQ.ConsumeCallEvent()
}
