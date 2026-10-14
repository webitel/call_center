package chat

import (
	"fmt"

	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

func (m *ChatManager) GetConversation(conversationId string) (*Conversation, *model.AppError) {
	if conversationId == "" {
		return nil, ErrBadId
	}

	if item, ok := m.chats.Get(conversationId); ok {
		return item.(*Conversation), nil
	}

	return nil, ErrNotFound
}

func (m *ChatManager) StoreConversation(chat *Conversation) {
	if _, ok := m.chats.Get(chat.id); ok {
		m.log.Error(fmt.Sprintf("chat [%s] exists", chat.id))
		m.chats.AddWithDefaultExpires(chat.id, chat)
		return
	}

	m.chats.AddWithDefaultExpires(chat.id, chat)
	chat.log.Debug(fmt.Sprintf("chat [%s] save to store domaind_Id=%d, chat_user_id=%s len=%d", chat.id, chat.DomainId, chat.inviterUserId, m.chats.Len()))
}

func (m *ChatManager) RemoveConversation(chat *Conversation) {
	log := chat.log.With(wlog.String("chat_user_id", chat.inviterUserId))

	if m.chats.RemoveFunc(chat.id, func(v any) bool { return v == chat }) {
		log.Debug("chat removed from store")
		return
	}

	log.Debug("chat cache miss store")
}
