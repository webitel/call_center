package app

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/mq"
)

func (a *App) NewCall(params *model.CallRequest) (uuid, cause string, err *model.AppError) {
	uuid, cause, err = a.ExternalCommands.NewCall(params)
	if err != nil {
		mlog.Debug(fmt.Sprintf("Call error: %v", err.Error()))
	} else {
		mlog.Debug(fmt.Sprintf("Success create call %s", uuid))
	}
	return
}

func (a *App) SetCallVariables(id string, variables map[string]string) *model.AppError {
	return a.ExternalCommands.SetCallVariables(id, variables)
}

func (a *App) ConsumeCallEvent() <-chan mq.Event {
	return a.MQ.ConsumeCallEvent()
}
