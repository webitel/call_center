package app

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
)

func (a *App) NewCall(params *model.CallRequest) (string, *model.AppError) {
	s, err := a.ExternalCommands.NewCall(params)
	fmt.Println(s)
	if err != nil {
		mlog.Debug(fmt.Sprintf("Call error: %v", err.Error()))
	} else {
		mlog.Debug(fmt.Sprintf("Success create call %s", s))
	}
	return s, err
}
