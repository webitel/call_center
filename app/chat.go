package app

import (
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
)

func (app *App) ChatManager() *chat.ChatManager {
	return app.chatManager
}

func (app *App) GetChat(id string) (*chat.ChatSession, *model.AppError) {
	return nil, nil
}
