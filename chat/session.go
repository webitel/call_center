package chat

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/chat_manager"
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
	StopAt         int64
	ActivityAt     int64

	cli       chat_manager.Chat
	variables map[string]string

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
		StopAt:         0,
		cli:            cli,
	}
}

func (c *ChatSession) Id() string {
	return c.ConversationId
}

func (c *ChatSession) SessionId() string {
	if c.ChannelId != "" {

		return c.ChannelId
	}

	return c.InviteId
}

func (c *ChatSession) SetActivity() {
	c.Lock()
	c.ActivityAt = model.GetMillis()
	c.Unlock()
}

func (c *ChatSession) IdleSec() int64 {
	return (model.GetMillis() - c.ActivityAt) / 1000
}

func (c *ChatSession) Leave() *model.AppError {
	err := c.cli.Leave(c.UserId, c.ChannelId, c.ConversationId)
	if err != nil {
		return model.NewAppError("ChatSession", "chat_session.leave.app_err", nil, err.Error(), http.StatusInternalServerError)
	}

	return nil
}
