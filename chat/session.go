package chat

import (
	"github.com/webitel/engine/chat_manager"
	"sync"
)

type ChatState uint8

const (
	ChatStateInit ChatState = iota
	ChatStateInvite
	ChatStateActive
	ChatStateStopped
)

type ChatDirection string

const (
	ChatDirectionInbound  ChatDirection = "inbound"
	ChatDirectionOutbound ChatDirection = "outbound"
)

type ChatSession struct {
	DomainId       int64
	UserId         int64
	Direction      ChatDirection
	ConversationId string
	ChannelId      string
	InviteId       string
	InviteAt       int64
	CreatedAt      int64
	AnsweredAt     int64
	StopAt         int64
	state          chan ChatState
	api            chat_manager.Chat

	sync.RWMutex
}

func OutboundChat(domainId, userId int64) *ChatSession {
	return &ChatSession{}
}

func (c *ChatSession) setInvite(inviteId string, timestamp int64) {
	c.Lock()
	c.InviteId = inviteId
	c.InviteAt = timestamp
	c.Unlock()

	c.state <- ChatStateInvite
}
