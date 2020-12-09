package chat

import (
	"errors"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

const (
	ChatEventInvite  = "user_invite"
	ChatEventJoined  = "join_conversation"
	ChatEventDecline = "decline_invite"
	ChatEventLeave   = "leave_conversation"
	ChatEventClose   = "close_conversation"
)

var (
	ErrNotFound = errors.New("not found")
)

func (m *ChatManager) GetChat(conversationId string) (*ChatSession, error) {
	if item, ok := m.chats.Get(conversationId); ok {
		return item.(*ChatSession), nil
	}

	return nil, ErrNotFound
}

func (m *ChatManager) StoreChat(chat *ChatSession) {
	if _, ok := m.chats.Get(chat.ConversationId); ok {
		wlog.Error(fmt.Sprintf("chat [%s] exists", chat.ConversationId))
		return
	}

	m.chats.AddWithDefaultExpires(chat.ConversationId, chat)
	wlog.Debug(fmt.Sprintf("chat [%s] save to store domaind_Id=%d, user_id=%d", chat.ConversationId, chat.DomainId, chat.UserId))
}

func (m *ChatManager) RemoveStore(chat *ChatSession) {
	if _, ok := m.chats.Get(chat.ConversationId); !ok {
		wlog.Error(fmt.Sprintf("chat [%s] not exists", chat.ConversationId))
		return
	}

	m.chats.Remove(chat.ConversationId)
	wlog.Debug(fmt.Sprintf("chat [%s] remove from store domaind_Id=%d, user_id=%d", chat.ConversationId, chat.DomainId, chat.UserId))
}

func NewChat(conversationId string, domainId, userId int64) *ChatSession {
	return &ChatSession{
		ConversationId: conversationId,
		DomainId:       domainId,
		UserId:         userId,
	}
}

func (m *ChatManager) handleEvent(e *model.ChatEvent) {
	switch e.Name {
	case ChatEventInvite:
		chat, err := m.GetChat(e.ConversationId())
		if chat == nil {
			return
		}
		// todo crash
		if err != nil && chat.Direction == ChatDirectionOutbound {
			// success make outbound chat invite
			// parse invite type
			//chat.setInvite()
		} else {
			// inbound chat ?
			m.StoreChat(NewChat(e.ConversationId(), e.DomainId, e.UserId))
		}

	case ChatEventJoined:
	case ChatEventDecline, ChatEventLeave, ChatEventClose:
		if chat, err := m.GetChat(e.ConversationId()); err != nil {
			wlog.Error(err.Error())
		} else {
			m.RemoveStore(chat)
		}
	default:
		wlog.Warn(fmt.Sprintf("skip [%s] domaind_id=%d user_id=%d vdata=%v", e.Name, e.DomainId, e.UserId, e.Data))
	}
	fmt.Println(e.Name)
}
