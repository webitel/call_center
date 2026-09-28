package chat

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/webitel/call_center/model"
	"github.com/webitel/engine/pkg/wbt/chat_manager"
	"github.com/webitel/wlog"
)

// STATE_BUFFER_SIZE is the whole tolerance for a busy reader. Every chat event is
// delivered once per participant, so a single leave in a conversation with nine agents
// arrives nine times - the old buffer of 5 could not hold even one such burst. Once
// even this is full the queue goroutine is gone for good, not merely late.
const STATE_BUFFER_SIZE = 50

// STATE_SEND_TIMEOUT gives a merely slow reader a chance to catch up before a state is
// dropped. It is paid at most ONCE per conversation: the send runs on the goroutine that
// drains every chat event, which is what keeps the AMQP reader moving, so a wait repeated
// per event would fill the reader queue and stall calls.
const STATE_SEND_TIMEOUT = time.Millisecond * 800

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
	stateStalled  atomic.Bool
	cause         string
	log           *wlog.Logger
	sync.RWMutex
}

func newConversation(cli chat_manager.Chat, domainId int64, id, inviterId, inviterUserId string, variables map[string]string,
	log *wlog.Logger) *Conversation {

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
		state:         make(chan ChatState, STATE_BUFFER_SIZE),
		cli:           cli,
		lastMessageAt: model.GetMillis(),
		log: log.With(
			wlog.String("conversation_id", id),
			wlog.Int64("domain_id", domainId),
		),
	}
}

func (cm *ChatManager) NewConversation(domainId int64, id, inviterId, inviterUserId string, variables map[string]string) (*Conversation, *model.AppError) {
	cli, err := cm.api.Client()
	if err != nil {
		return nil, model.NewAppError("Chat.Inbound", "chat.inbound.app_err", nil, err.Error(), http.StatusInternalServerError)
	}

	conv := newConversation(cli, domainId, id, inviterId, inviterUserId, variables, cm.log)
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

	invId, err := c.cli.InviteToConversation(
		ctx,
		c.DomainId,
		userId,
		c.id,
		c.inviterId,
		c.inviterUserId,
		title,
		int(timeout),
		model.UnionStringMaps(c.variables, vars),
	)

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

	c.pushState(ChatStateInvite)
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
		err := c.cli.Leave(sess.UserId, sess.ChannelId, sess.ConversationId, chat_manager.AgentLeave)
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

func (c *Conversation) Cause() string {
	c.RLock()
	cause := c.cause
	c.RUnlock()
	return cause
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

// pushState hands a state transition to the queue goroutine driving this conversation.
// A full buffer means the reader is either slow or gone, and the two are told apart once:
// the first overflow waits, and if that wait expires the reader is treated as gone and
// every later state is dropped immediately. That caps the total delay this conversation
// can ever impose on the shared chat consumer at one STATE_SEND_TIMEOUT.
func (c *Conversation) pushState(state ChatState) {
	select {
	case c.state <- state:
		return
	default:
	}

	if c.stateStalled.Load() {
		c.log.Error(fmt.Sprintf("conversation %s dropped state %v: queue stopped reading", c.id, state),
			wlog.String("conversation_id", c.id),
		)
		return
	}

	timer := time.NewTimer(STATE_SEND_TIMEOUT)
	defer timer.Stop()

	select {
	case c.state <- state:
	case <-timer.C:
		c.stateStalled.Store(true)
		c.log.Error(fmt.Sprintf("conversation %s dropped state %v: queue did not read it in %s", c.id, state, STATE_SEND_TIMEOUT),
			wlog.String("conversation_id", c.id),
		)
	}
}

func (c *Conversation) setInvite(inviteId string, timestamp int64) {
	sess := c.getSessionByInviteId(inviteId)
	if sess != nil {
		sess.SetActivity()
		sess.InviteId = inviteId
		sess.InviteAt = timestamp
		c.pushState(ChatStateInvite)
	} else {
		c.log.Warn(fmt.Sprintf("Conversation invite %s not found inviteId %s", c.id, inviteId))
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
		c.pushState(ChatStateBridge)
	} else {
		c.log.Warn(fmt.Sprintf("Conversation %s not found chanel_id %s", c.id, channelId))
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

func (c *Conversation) setClose(timestamp int64, cause string) {
	c.Lock()
	c.closeAt = timestamp // TODO created from register in queue
	c.cause = cause
	c.Unlock()

	s := c.MemberSession()
	if s != nil {
		s.cause = cause
	}

	c.pushState(ChatStateClose)
}

func (c *Conversation) setDeclined(inviteId string, timestamp int64) {
	sess := c.getSessionByInviteId(inviteId)
	if sess != nil {
		//c.Lock()
		sess.Lock()
		sess.stopAt = timestamp
		sess.Unlock()
		c.pushState(ChatStateDeclined)
	} else {
		c.log.Warn(fmt.Sprintf("Conversation decline %s not found inviteId %s", c.id, inviteId))
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
