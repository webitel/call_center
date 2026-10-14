package im

import (
	"context"
	"strconv"
	"sync"

	"google.golang.org/grpc/metadata"

	thread "github.com/webitel/call_center/gen/im/api/gateway/v1"
	"github.com/webitel/call_center/model"
)

type Message struct {
	FromSub string
}

type Session struct {
	threadId                string
	agentMemberId           string
	clientMemberId          string
	subBot                  string
	subMember               string
	cli                     *Client
	hdrs                    metadata.MD
	lastMessageAt           int64
	lastMessageAtFromMember int64
	lastMessageAtFromAgent  int64
	ActivityAt              int64
	userId                  string
	ctx                     context.Context
	cancel                  context.CancelFunc
	sync.RWMutex
}

func (s *Session) Id() string {
	return s.threadId
}

func (s *Session) Stats() map[string]string {
	return make(map[string]string)
}

func (s *Session) Answered() bool {
	return true
}

func (s *Session) Close() {
	s.cli.closeSession(s)
}

func (s *Session) Done() <-chan struct{} {
	return s.ctx.Done()
}

func (s *Session) SetActivity() {
	s.Lock()
	s.ActivityAt = model.GetMillis()
	s.Unlock()
}

func (s *Session) IdleSec() int64 {
	s.RLock()
	t := s.ActivityAt
	s.RUnlock()

	return (model.GetMillis() - t) / 1000
}

func (s *Session) onMessage(msg Message) {
	s.Lock()
	s.lastMessageAt = model.GetMillis()

	switch msg.FromSub {
	case s.subMember:
		s.lastMessageAtFromMember = model.GetMillis()
	case s.userId:
		s.lastMessageAtFromAgent = model.GetMillis()
	}

	s.Unlock()
}

func (s *Session) SilentSec() int64 {
	s.RLock()
	t := s.lastMessageAt
	s.RUnlock()

	return (model.GetMillis() - t) / 1000
}

func (s *Session) MemberIdleMessage() int64 {
	s.RLock()
	t := s.lastMessageAtFromMember
	s.RUnlock()

	if t == 0 {
		return 0
	}

	return (model.GetMillis() - t) / 1000
}

func (s *Session) OperatorIdleMessage() int64 {
	s.RLock()
	t := s.lastMessageAtFromAgent
	s.RUnlock()

	if t == 0 {
		return 0
	}

	return (model.GetMillis() - t) / 1000
}

func (s *Session) AddMemberUser(ctx context.Context, userId int64) error {
	res, err := s.cli.Api.AddMember(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.AddMemberRequest{
			ThreadId: s.threadId,
			Contact:  webitelPeer(strconv.FormatInt(userId, 10)),
			Role:     thread.ThreadRole_ROLE_MEMBER,
		})
	if err != nil {
		return err
	}

	s.setAgent(res.GetMember().GetId(), userId)

	return nil
}

func (s *Session) TransferMemberUser(ctx context.Context, userId int64, fromUserId string) error {
	res, err := s.cli.Api.Transfer(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.TransferRequest{
			ThreadId:  s.threadId,
			Contact:   webitelPeer(strconv.FormatInt(userId, 10)),
			Initiator: webitelPeer(fromUserId),
			Role:      thread.ThreadRole_ROLE_MEMBER,
		})
	if err != nil {
		return err
	}

	s.setAgent(res.GetMember().GetId(), userId)

	return nil
}

func (s *Session) setAgent(memberId string, userId int64) {
	s.Lock()
	if memberId != "" {
		s.agentMemberId = memberId
	}
	s.userId = strconv.FormatInt(userId, 10)
	s.Unlock()
}

func (s *Session) affectedBy(sys *model.IMSystem) bool {
	s.RLock()
	agentMemberId := s.agentMemberId
	s.RUnlock()

	return (s.clientMemberId != "" && sys.AffectsMember(s.clientMemberId)) ||
		(agentMemberId != "" && sys.AffectsMember(agentMemberId))
}

func webitelPeer(sub string) *thread.PeerIdentity {
	return &thread.PeerIdentity{
		Sub: sub,
		Iss: "webitel",
	}
}

func (s *Session) RemoveMemberUser(ctx context.Context) error {
	if s.agentMemberId == "" {
		return nil
	}

	_, err := s.cli.Api.RemoveMember(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.RemoveMemberRequest{
			ThreadId: s.threadId,
			MemberId: s.agentMemberId,
		})

	return err
}
