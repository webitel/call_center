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
	Bot bool
}

type Session struct {
	threadId      string
	from          string
	cli           *Client
	hdrs          metadata.MD
	lastMessageAt int64
	ActivityAt    int64
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
	s.cli.closeSession(s.threadId)
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
	s.Unlock()
}

func (s *Session) SilentSec() int64 {
	s.RLock()
	t := s.lastMessageAt
	s.RUnlock()

	return (model.GetMillis() - t) / 1000
}

func (s *Session) MemberIdleMessage() int64 {
	return 0
}

func (s *Session) OperatorIdleMessage() int64 {
	return 0
}

func (s *Session) AddMemberUser(ctx context.Context, userId int64) error {
	_, err := s.cli.Api.AddMember(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.AddMemberRequest{
			ThreadId: s.threadId,
			Member: &thread.PeerIdentity{
				Sub: strconv.Itoa(int(userId)),
				Iss: "webitel",
			},
			Role: thread.ThreadRole_ROLE_MEMBER,
		})

	return err
}

func (s *Session) RemoveMemberUser(ctx context.Context, userId int64, reason string) error {
	_, err := s.cli.Api.RemoveMember(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.RemoveMemberRequest{
			ThreadId: s.threadId,
			Member: &thread.PeerIdentity{
				Sub: strconv.Itoa(int(userId)),
				Iss: "webitel",
			},
			Reason: &reason,
		})

	return err
}
