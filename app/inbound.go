package app

import "github.com/webitel/call_center/model"

func (app *App) GetCall(id string) (*model.Call, *model.AppError) {
	return app.Store.Call().Get(id)
}
