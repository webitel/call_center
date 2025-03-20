package chat

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/chat_manager"
	enginemodel "github.com/webitel/engine/model"
	"net/http"
	"sync"
)

type ChatDirection string

const (
	ChatDirectionInbound  ChatDirection = "inbound"
	ChatDirectionOutbound ChatDirection = "outbound"
)

type ChatSession struct {
	inviterId      string
	inviterUserId  string
	UserId         int64
	Direction      ChatDirection
	ConversationId string
	ChannelId      string
	InviteId       string
	InviteAt       int64
	CreatedAt      int64
	AnsweredAt     int64
	stopAt         int64
	ActivityAt     int64

	cli       chat_manager.Chat
	variables map[string]string
	cause     string

	sync.RWMutex
}

func OutboundChat(cli chat_manager.Chat, userId int64, conversationId, inviterId, invUserId string) *ChatSession {
	return &ChatSession{
		inviterId:      inviterId,
		inviterUserId:  invUserId,
		UserId:         userId,
		Direction:      ChatDirectionOutbound,
		ConversationId: conversationId,
		ChannelId:      "",
		InviteId:       "",
		InviteAt:       0,
		CreatedAt:      model.GetMillis(),
		AnsweredAt:     0,
		stopAt:         0,
		cli:            cli,
	}
}

func (c *ChatSession) Id() string {
	if c.Direction == ChatDirectionOutbound {
		return c.SessionId()
	}
	return c.ConversationId
}

func (c *ChatSession) SessionId() string {
	if c.ChannelId != "" {

		return c.ChannelId
	}

	return c.InviteId
}
func (c *ChatSession) Answered() bool {
	c.RLock()
	a := c.AnsweredAt
	c.RUnlock()

	return a > 0
}

func (c *ChatSession) SetActivity() {
	c.Lock()
	c.ActivityAt = model.GetMillis()
	c.Unlock()
}

func (c *ChatSession) StopAt() int64 {
	c.RLock()
	stopAt := c.stopAt
	c.RUnlock()

	return stopAt
}

func (c *ChatSession) IdleSec() int64 {
	c.RLock()
	t := c.ActivityAt
	c.RUnlock()
	return (model.GetMillis() - t) / 1000
}

func (c *ChatSession) Leave(cause model.LeaveCause) *model.AppError {
	err := c.cli.Leave(c.UserId, c.SessionId(), c.ConversationId, enginemodel.LeaveCause(cause))
	if err != nil {
		return model.NewAppError("ChatSession", "chat_session.leave.app_err", nil, err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (c *ChatSession) Decline() *model.AppError {
	err := c.cli.Decline(c.UserId, c.InviteId, "")
	if err != nil {
		return model.NewAppError("ChatSession", "chat_session.decline.app_err", nil, err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (c *ChatSession) Close(reason model.CloseCause) *model.AppError {
	if c.ChannelId == "" && c.InviteId != "" {
		return c.Decline()
	} else {
		err := c.cli.CloseConversation(c.UserId, c.SessionId(), c.ConversationId, enginemodel.CloseCause(reason))
		if err != nil {
			return model.NewAppError("ChatSession", "chat_session.close.app_err", nil, err.Error(), http.StatusInternalServerError)
		}
		return nil

	}
}

func (c *ChatSession) Stats() map[string]string {
	vars := make(map[string]string)
	if c.cause != "" {
		if c.cause == "transfer" {
			vars["chat_transferred"] = "true"
		} else {
			vars["chat_transferred"] = "false"
		}
	}
	return vars
}
