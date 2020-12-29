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
	ChatEventMessage = "message"
)

var (
	ErrNotFound = errors.New("not found")
	ErrBadId    = errors.New("bad conversation_id")
)

func (m *ChatManager) handleEvent(e *model.ChatEvent) {
	chat, err := m.GetConversation(e.ConversationId())
	if err != nil {
		wlog.Warn(fmt.Sprintf("chat %s: %s", e.ConversationId(), err.Error()))
		return
	}

	if chat == nil {
		wlog.Debug(fmt.Sprintf("skip chat %d", e.ConversationId()))
		return
	}

	switch e.Name {
	case ChatEventInvite:
		chat.setInvite(e.InviteId(), e.Timestamp())
		fmt.Println("NEW INVITE")
	case ChatEventDecline:
		chat.setDeclined(e.InviteId(), e.Timestamp())
		fmt.Println("NEW DECLINED")
	case ChatEventJoined:
		chat.setJoined(e.ChannelId(), e.Timestamp())
		fmt.Println("NEW JOINED")

	case ChatEventMessage:
		fmt.Println("NEW MESSAGE")
	case ChatEventLeave, ChatEventClose:
		chat.setClose(e.Timestamp())
		fmt.Println("CLOSE")
	default:
		wlog.Warn(fmt.Sprintf("skip [%s] domaind_id=%d user_id=%d vdata=%v", e.Name, e.DomainId, e.UserId, e.Data))
	}
}
