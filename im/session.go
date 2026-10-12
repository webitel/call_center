package im

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"

	thread "github.com/webitel/call_center/gen/im/api/gateway/v1"
	"github.com/webitel/call_center/model"
)

// MaxPreviewDuration is the upper bound accepted by im-gateway GivePreview (duration_ms <= 3600000).
const MaxPreviewDuration = time.Hour

// IsAlreadyMember reports whether err is gRPC AlreadyExists (the contact is already a thread member).
func IsAlreadyMember(err error) bool {
	return status.Code(err) == codes.AlreadyExists
}

func userPeer(userId int64) *thread.PeerIdentity {
	return &thread.PeerIdentity{
		Sub: strconv.FormatInt(userId, 10),
		Iss: "webitel",
	}
}

type Message struct {
	FromSub string
}

type Session struct {
	tagID                   int
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
	previewUserId           string // non-empty while a preview granted by us is not yet upgraded or removed
	botActive               bool
	ctx                     context.Context
	cancel                  context.CancelFunc
	sync.RWMutex
}

func (s *Session) TagID() int {
	return s.tagID
}

func (s *Session) Bridged() bool {
	s.RLock()
	defer s.RUnlock()

	return s.userId != ""
}

func (s *Session) SetBotActive(active bool) {
	s.Lock()
	defer s.Unlock()

	if s.botActive && !active {
		now := model.GetMillis()
		s.lastMessageAt = now
		s.lastMessageAtFromMember = now
		s.lastMessageAtFromAgent = now
	}

	s.botActive = active
}

func (s *Session) BotActive() bool {
	s.RLock()
	defer s.RUnlock()

	return s.botActive
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

func (s *Session) Close(tagID int) {
	s.cli.closeSession(s.threadId, tagID)
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

// GivePreviewUser grants the user a read-only, time-limited preview of the thread.
func (s *Session) GivePreviewUser(ctx context.Context, userId int64, duration time.Duration) error {
	if duration <= 0 || duration > MaxPreviewDuration {
		return fmt.Errorf("preview duration %s out of range (0, %s]", duration, MaxPreviewDuration)
	}

	_, err := s.cli.preview.Api.GivePreview(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.GivePreviewRequest{
			ThreadId:   s.threadId,
			Contact:    userPeer(userId),
			DurationMs: duration.Milliseconds(),
		})
	if err != nil {
		return err
	}

	s.Lock()
	s.previewUserId = strconv.FormatInt(userId, 10)
	s.Unlock()

	return nil
}

// RemovePreviewUser revokes the preview granted by GivePreviewUser. It is a no-op when no preview is active.
func (s *Session) RemovePreviewUser(ctx context.Context) error {
	s.RLock()
	previewUserId := s.previewUserId
	s.RUnlock()

	if previewUserId == "" {
		return nil
	}

	_, err := s.cli.preview.Api.RemoveFromPreview(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.RemoveFromPreviewRequest{
			ThreadId: s.threadId,
			Contact: &thread.PeerIdentity{
				Sub: previewUserId,
				Iss: "webitel",
			},
		})

	// The server preview expires on its own; clear local state so we do not retry on every cleanup.
	s.Lock()
	s.previewUserId = ""
	s.Unlock()

	return err
}

// UpgradePreviewUser atomically turns the active preview into a full ROLE_MEMBER, the same role AddMemberUser uses.
// On error the preview state is kept so RemovePreviewUser can still revoke it.
func (s *Session) UpgradePreviewUser(ctx context.Context, userId int64) error {
	res, err := s.cli.preview.Api.UpgradePreviewToFullMember(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.UpgradePreviewToFullMemberRequest{
			ThreadId: s.threadId,
			Contact:  userPeer(userId),
			Role:     thread.ThreadRole_ROLE_MEMBER,
		})
	if err != nil {
		return err
	}

	if res.GetMember().GetId() != "" {
		s.agentMemberId = res.GetMember().GetId()
	}

	s.Lock()
	s.userId = strconv.Itoa(int(userId))
	s.previewUserId = ""
	s.Unlock()

	return nil
}

// HasPreview reports whether a preview granted by GivePreviewUser is still pending upgrade or removal.
func (s *Session) HasPreview() bool {
	s.RLock()
	defer s.RUnlock()

	return s.previewUserId != ""
}

// MarkUserJoined records userId as the joined operator without calling the gateway,
// for an operator that is already a thread member. The member id is unknown, so
// RemoveMemberUser will not remove this operator from the thread.
func (s *Session) MarkUserJoined(userId int64) {
	s.Lock()
	s.userId = strconv.FormatInt(userId, 10)
	s.Unlock()
}

// IsUserJoined reports whether userId is the operator already joined to the thread.
func (s *Session) IsUserJoined(userId int64) bool {
	s.RLock()
	defer s.RUnlock()

	return s.userId != "" && s.userId == strconv.FormatInt(userId, 10)
}

func (s *Session) AddMemberUser(ctx context.Context, userId int64) error {
	res, err := s.cli.Api.AddMember(
		metadata.NewOutgoingContext(ctx, s.hdrs),
		&thread.AddMemberRequest{
			ThreadId: s.threadId,
			Contact:  userPeer(userId),
			Role:     thread.ThreadRole_ROLE_MEMBER,
		})
	if err != nil {
		return err
	}

	if res.GetMember().GetId() != "" {
		s.agentMemberId = res.GetMember().GetId()
	}

	s.Lock()
	s.userId = strconv.Itoa(int(userId))
	s.Unlock()

	return err
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
