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
		wlog.Error(fmt.Sprintf("chat [%s] exists", chat.id))
		return
	}

	m.chats.AddWithDefaultExpires(chat.id, chat)
	wlog.Debug(fmt.Sprintf("chat [%s] save to store domaind_Id=%d, chat_user_id=%s len=%d", chat.id, chat.DomainId, chat.inviterUserId, m.chats.Len()))
}

func (m *ChatManager) RemoveConversation(chat *Conversation) {
	if _, ok := m.chats.Get(chat.id); !ok {
		wlog.Error(fmt.Sprintf("chat [%s] not exists", chat.id))
		return
	}

	m.chats.Remove(chat.id)
	wlog.Debug(fmt.Sprintf("chat [%s] remove from store domaind_id=%d, chat_user_id=%s", chat.id, chat.DomainId, chat.inviterUserId))
}
