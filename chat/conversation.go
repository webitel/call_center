package chat

import (
	"context"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/chat_manager"
	"github.com/webitel/wlog"
	"net/http"
	"strings"
	"sync"
)

type ChatState uint8

const (
	ChatStateIdle ChatState = iota
	ChatStateInvite
	ChatStateDeclined
	ChatStateBridge
	ChatStateClose
)

var (
	ErrChannelNotFound = model.NewAppError("Chat.InviteInternal", "chat.invite.not_found", nil, "channel not found", http.StatusNotFound)
)

type Conversation struct {
	id            string
	inviterId     string
	inviterUserId string
	DomainId      int64
	variables     map[string]string
	sessions      []*ChatSession
	cli           chat_manager.Chat
	updatedAt     int64
	createdAt     int64
	bridgetAt     int64
	closeAt       int64
	reportingAt   int64
	lastMessageAt int64
	currentState  ChatState
	state         chan ChatState
	sync.RWMutex
}

func newConversation(cli chat_manager.Chat, domainId int64, id, inviterId, inviterUserId string, variables map[string]string) *Conversation {
	// todo
	sess := &ChatSession{
		inviterId:      inviterId,
		inviterUserId:  inviterUserId,
		UserId:         0,
		Direction:      ChatDirectionInbound,
		ConversationId: id,
		ChannelId:      inviterId,
		InviteId:       "",
		InviteAt:       0,
		CreatedAt:      0,
		AnsweredAt:     0,
		ActivityAt:     model.GetMillis(),
		stopAt:         0,
		cli:            cli,
		variables:      variables,
	}

	return &Conversation{
		id:            id,
		inviterId:     inviterId,
		inviterUserId: inviterUserId,
		DomainId:      domainId,
		variables:     variables,
		sessions:      []*ChatSession{sess},
		currentState:  ChatStateIdle,
		state:         make(chan ChatState, 5), //TODO
		cli:           cli,
		lastMessageAt: model.GetMillis(),
	}
}

func (cm *ChatManager) NewConversation(domainId int64, id, inviterId, inviterUserId string, variables map[string]string) (*Conversation, *model.AppError) {
	cli, err := cm.api.Client()
	if err != nil {
		return nil, model.NewAppError("Chat.Inbound", "chat.inbound.app_err", nil, err.Error(), http.StatusInternalServerError)
	}

	conv := newConversation(cli, domainId, id, inviterId, inviterUserId, variables)
	cm.StoreConversation(conv)
	return conv, nil
}

func (c *Conversation) State() <-chan ChatState {
	return c.state
}

func (c *Conversation) BridgedAt() int64 {
	c.RLock()
	defer c.RUnlock()

	return c.bridgetAt
}

func (c *Conversation) InviteInternal(ctx context.Context, userId int64, timeout uint16, title string, vars map[string]string) *model.AppError {
	sess := OutboundChat(c.cli, userId, c.id, c.inviterId, c.inviterUserId)
	c.Lock()
	c.sessions = append(c.sessions, sess)
	c.Unlock()

	invId, err := c.cli.InviteToConversation(ctx, c.DomainId, userId, c.id, c.inviterId, c.inviterUserId, title, int(timeout),
		model.UnionStringMaps(c.variables, vars))

	if err != nil {
		if isChannelClose(err) {
			c.SetStop()
			return ErrChannelNotFound
		}
		return model.NewAppError("Chat.InviteInternal", "chat.invite.internal.app_err", nil, err.Error(), http.StatusInternalServerError)
	}

	//todo
	c.Lock()
	sess.SetActivity()
	sess.InviteId = invId
	sess.InviteAt = model.GetMillis() //todo
	c.Unlock()

	c.state <- ChatStateInvite
	return nil
}

func (c *Conversation) Reporting(noLeave bool) *model.AppError {
	sess := c.LastSession()
	if sess.StopAt() != 0 {
		return model.NewAppError("Chat.Reporting", "chat.reporting.valid.stop_at", nil, "Chat is closed", http.StatusBadRequest)
	}

	c.Lock()
	c.reportingAt = model.GetMillis()
	c.Unlock()

	if !noLeave {
		err := c.cli.Leave(sess.UserId, sess.ChannelId, sess.ConversationId)
		if err != nil {
			return model.NewAppError("Chat.Reporting", "chat.leave.app_err", nil, err.Error(), http.StatusInternalServerError)
		}
	}

	return nil
}

func (c *Conversation) MemberSession() *ChatSession {
	// todo
	c.RLock()
	defer c.RUnlock()

	return c.sessions[0]
}

func (c *Conversation) LastSession() *ChatSession {
	// todo
	c.RLock()
	defer c.RUnlock()

	return c.sessions[len(c.sessions)-1]
}

func (c *Conversation) ReportingAt() int64 {
	c.RLock()
	defer c.RUnlock()

	return c.reportingAt
}

func (c *Conversation) SendText(text string) *model.AppError {

	for _, s := range c.sessions {
		if s != nil && s.StopAt() == 0 {
			err := c.cli.SendText(s.UserId, s.ChannelId, c.id, text)
			if err != nil {
				return model.NewAppError("Chat.SendText", "chat.send.text.app_err", nil, err.Error(), http.StatusInternalServerError)
			}

			return nil
		}
	}

	return nil
}

func (c *Conversation) SilentSec() int64 {
	c.RLock()
	t := c.lastMessageAt
	c.RUnlock()

	return (model.GetMillis() - t) / 1000
}

func (c *Conversation) getSessionByInviteId(invId string) *ChatSession {
	c.Lock()
	defer c.Unlock()
	for _, s := range c.sessions {
		if s != nil && s.InviteId == invId && s.stopAt == 0 {
			return s
		}
	}

	return nil
}

func (c *Conversation) getSessionByChannelId(chanId string) *ChatSession {
	c.Lock()
	defer c.Unlock()
	for _, s := range c.sessions {
		if s.ChannelId == chanId && s.stopAt == 0 {
			return s
		}
	}

	return nil
}

func (c *Conversation) setInvite(inviteId string, timestamp int64) {
	sess := c.getSessionByInviteId(inviteId)
	if sess != nil {
		sess.SetActivity()
		sess.InviteId = inviteId
		sess.InviteAt = timestamp
		c.state <- ChatStateInvite
	} else {
		wlog.Warn(fmt.Sprintf("Conversation invite %s not found inviteId %s", c.id, inviteId))
	}
}

func (c *Conversation) setJoined(channelId string, timestamp int64) {
	var sess *ChatSession
	//todo bug: event joined must be send invite_id
	for _, v := range c.sessions {
		if v != nil && v.InviteId == channelId && v.StopAt() == 0 {
			sess = v
		}
	}

	c.Lock()
	c.lastMessageAt = model.GetMillis()
	c.Unlock()

	if sess != nil {
		sess.ChannelId = channelId
		sess.AnsweredAt = timestamp
		sess.SetActivity()
		c.bridgetAt = timestamp // TODO created from register in queue
		c.state <- ChatStateBridge
	} else {
		wlog.Warn(fmt.Sprintf("Conversation %s not found chanel_id %s", c.id, channelId))
	}
}

func (c *Conversation) setNewMessage(channelId string) {
	c.Lock()
	c.lastMessageAt = model.GetMillis()
	c.Unlock()

	sess := c.getSessionByChannelId(channelId)
	if sess != nil {
		sess.SetActivity()
	}
}

func (c *Conversation) setClose(timestamp int64) {
	c.Lock()
	c.closeAt = timestamp // TODO created from register in queue
	c.Unlock()

	c.state <- ChatStateClose
}

func (c *Conversation) setDeclined(inviteId string, timestamp int64) {
	sess := c.getSessionByInviteId(inviteId)
	if sess != nil {
		//c.Lock()
		sess.Lock()
		sess.stopAt = timestamp
		sess.Unlock()
		c.state <- ChatStateDeclined
	} else {
		wlog.Warn(fmt.Sprintf("Conversation decline %s not found inviteId %s", c.id, inviteId))
	}
}

func (c *Conversation) Active() bool {
	c.RLock()
	defer c.RUnlock()

	return c.closeAt == 0
}

func (c *Conversation) SetStop() {
	c.Lock()
	defer c.Unlock()

	if c.closeAt == 0 {
		c.closeAt = model.GetMillis()
	}

	//todo remove store ?
}

// TODO
func isChannelClose(err error) bool {
	return strings.Index(err.Error(), "channel not found") != -1
}
