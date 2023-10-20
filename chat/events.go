package chat

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"net/http"
	"strings"
)

const (
	ChatEventInvite  = "user_invite"
	ChatEventJoined  = "join_conversation"
	ChatEventDecline = "decline_invite"
	ChatEventLeave   = "leave_conversation"
	ChatEventClose   = "close_conversation"
	ChatEventMessage = "message"
)

var (
	ErrNotFound = model.NewAppError("Chat", "chat.not_found", nil, "not found conversation", http.StatusNotFound)
	ErrBadId    = model.NewAppError("Chat", "chat.valid.id", nil, "bad conversation_id", http.StatusBadRequest)
)

func (m *ChatManager) handleEvent(e *model.ChatEvent) {
	chat, err := m.GetConversation(e.ConversationId())
	if err != nil {
		wlog.Warn(fmt.Sprintf("chat %s [%s]: %s", e.ConversationId(), e.Name, err.Error()))
		return
	}

	if chat == nil {
		wlog.Debug(fmt.Sprintf("skip chat %s", e.ConversationId()))
		return
	}

	wlog.Debug(fmt.Sprintf("chat receive [%s] domaind_id=%d user_id=%d vdata=%v", e.Name, e.DomainId, e.UserId, e.Data))

	switch e.Name {
	case ChatEventInvite:
		//chat.setInvite(e.InviteId(), e.Timestamp())
	case ChatEventDecline:
		chat.setDeclined(e.InviteId(), e.Timestamp())
	case ChatEventJoined:
		chat.setJoined(e.ChannelId(), e.Timestamp())

	case ChatEventMessage:
		chat.setNewMessage(e.MessageChannelId())
	case ChatEventLeave, ChatEventClose:
		chat.setClose(e.Timestamp(), strings.ToLower(e.Cause()))
		//m.RemoveConversation(chat)
	default:
		wlog.Warn(fmt.Sprintf("skip [%s] domaind_id=%d user_id=%d vdata=%v", e.Name, e.DomainId, e.UserId, e.Data))
	}
}
