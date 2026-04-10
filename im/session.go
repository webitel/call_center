package im

import (
	"context"
	"strconv"

	"google.golang.org/grpc/metadata"

	thread "github.com/webitel/call_center/gen/im/api/gateway/v1"
)

type Session struct {
	threadId string
	from     string
	cli      *Client
	hdrs     metadata.MD
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
