package chat

import (
	"fmt"
	"github.com/webitel/call_center/model"
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
	v, ok := m.chats.Get(chat.id)
	if !ok {
		m.log.Error(fmt.Sprintf("chat [%s] not exists", chat.id))
		return
	}

	if v == chat {
		m.chats.Remove(chat.id)
		chat.log.Debug(fmt.Sprintf("chat [%s] remove from store domaind_id=%d, chat_user_id=%s", chat.id, chat.DomainId, chat.inviterUserId))
	} else {
		chat.log.Debug(fmt.Sprintf("chat [%s] cache miss store domaind_id=%d, chat_user_id=%s", chat.id, chat.DomainId, chat.inviterUserId))
	}
}
