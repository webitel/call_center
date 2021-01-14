package app

import (
	"github.com/webitel/call_center/chat"
	"github.com/webitel/call_center/model"
)

func (app *App) ChatManager() *chat.ChatManager {
	return app.chatManager
}

func (app *App) GetChat(conversationId string) (*chat.Conversation, *model.AppError) {
	return app.chatManager.GetConversation(conversationId)
}
