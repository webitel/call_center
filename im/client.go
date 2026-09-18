package im

import (
	"context"
	"crypto/tls"
	"fmt"
	"slices"
	"sync"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/metadata"

	"github.com/webitel/engine/pkg/wbt"
	"github.com/webitel/wlog"

	p "github.com/webitel/call_center/gen/im/api/gateway/v1"
	"github.com/webitel/call_center/model"
)

const ServiceName = "im-gateway-service"

type Client struct {
	consulAddr string
	startOnce  sync.Once
	*wbt.Client[p.ThreadManagementClient]
	log     *wlog.Logger
	ctx     context.Context
	cancel  context.CancelFunc
	tls     *tls.Config
	events  <-chan model.IMMessage
	threads []*Session
	sync.RWMutex
}

func NewClient(consulAddr string, events <-chan model.IMMessage, log *wlog.Logger, t *tls.Config) *Client {
	cli := &Client{
		consulAddr: consulAddr,
		log:        log,
		tls:        t,
		events:     events,
		threads:    make([]*Session, 0, 100),
	}

	cli.ctx, cli.cancel = context.WithCancel(context.Background()) // todo

	return cli
}

func (cm *Client) Start() error {
	cm.log.Debug("starting " + ServiceName + " client")

	var err error
	cm.startOnce.Do(func() {
		var opts []wbt.Option
		if cm.tls != nil {
			opts = append(opts, wbt.WithGrpcOptions(
				grpc.WithTransportCredentials(credentials.NewTLS(cm.tls)),
			))
		}

		cm.Client, err = wbt.NewClient(cm.consulAddr, ServiceName, p.NewThreadManagementClient, opts...)
		if err != nil {
			return
		}
		go cm.listenEvents()
	})
	return err
}

func (cm *Client) Stop() {
	cm.log.Debug("stopping " + ServiceName + " client")
	_ = cm.Client.Close()
	cm.cancel()
}

func (cm *Client) listenEvents() {
	for {
		select {
		case <-cm.ctx.Done():
			return
		case msg := <-cm.events:
			sess, ok := cm.GetSession(msg.ThreadID)
			if !ok {
				// DIAG: подія для треду без активної сесії (усі плечі вже закрито/ще не створено).
				if msg.System != nil {
					cm.log.Debug("im event: no session for thread",
						wlog.String("thread_id", msg.ThreadID),
						wlog.String("system_type", msg.System.Type),
						wlog.String("removed_member_id", msg.System.Metadata.RemovedMemberId),
						wlog.String("transferred_member_id", msg.System.Metadata.TransferredMemberId),
					)
				}

				continue
			}

			if msg.System != nil && (msg.System.Type == "member_removed" || msg.System.Type == "transfer") {
				affectsClient := msg.System.AffectsMember(sess.clientMemberId)
				affectsAgent := msg.System.AffectsMember(sess.agentMemberId)

				// DIAG: повний контекст рішення cancel — який саме tagID повернув GetSession,
				// скільки плечей на треді (перекриття A/B при трансфері) і що метчить. Дає
				// змогу зловити на проді, чиє плече (старе A чи нове B) гаситься transfer-подією.
				cm.log.Debug("im system event decision",
					wlog.String("thread_id", msg.ThreadID),
					wlog.String("system_type", msg.System.Type),
					wlog.String("removed_member_id", msg.System.Metadata.RemovedMemberId),
					wlog.String("transferred_member_id", msg.System.Metadata.TransferredMemberId),
					wlog.Int("picked_tag_id", sess.tagID),
					wlog.String("sess_client_member_id", sess.clientMemberId),
					wlog.String("sess_agent_member_id", sess.agentMemberId),
					wlog.Any("affects_client", affectsClient),
					wlog.Any("affects_agent", affectsAgent),
					wlog.Int("thread_sessions", cm.countThreadSessions(msg.ThreadID)),
				)

				// Only the client leaving ends the conversation. An agent being removed is
				// normal transfer churn: control passes to the next operator and the session
				// must keep running. Cancelling here on the outgoing agent aborted the next
				// transfer's attempt for the same thread, so the invite never reached it. The
				// agent's own attempt is torn down separately via finalizeAttempt/cleanupSession.
				if affectsClient || affectsAgent {
					cm.log.Debug("closing session: client left thread",
						wlog.String("thread_id", msg.ThreadID),
						wlog.Int("tag_id", sess.tagID),
						wlog.String("system_type", msg.System.Type),
						wlog.Any("via_client", affectsClient),
						wlog.Any("via_agent", affectsAgent),
					)
					sess.cancel()
				} else {
					cm.log.Debug("member left thread, session kept",
						wlog.String("thread_id", msg.ThreadID),
						wlog.Int("tag_id", sess.tagID),
					)
				}
			} else {
				sess.onMessage(Message{
					FromSub: msg.From.Sub,
				})
			}
		}
	}
}

func (cm *Client) NewSession(ctx context.Context, domainID int64, threadID, subBot, subMember, memberId string, tagID int) *Session {
	sess := &Session{
		cli:            cm,
		tagID:          tagID,
		threadId:       threadID,
		clientMemberId: memberId,
		subBot:         subBot,
		subMember:      subMember,
		lastMessageAt:  model.GetMillis(),
		hdrs: metadata.New(map[string]string{
			"x-webitel-type":   "schema",
			"x-webitel-schema": fmt.Sprintf("%d.%s", domainID, subBot),
		}),
	}

	sess.ctx, sess.cancel = context.WithCancel(ctx)

	cm.addSession(sess)

	// DIAG: created — з лічильником уже наявних плечей на цьому треді (>=1 означає
	// перекриття A/B під час трансфера ще ДО того, як старе плече прибрали).
	cm.log.Debug("im session created",
		wlog.String("thread_id", threadID),
		wlog.Int("tag_id", tagID),
		wlog.String("client_member_id", memberId),
		wlog.String("sub_bot", subBot),
		wlog.String("sub_member", subMember),
		wlog.Int("thread_sessions", cm.countThreadSessions(threadID)),
	)

	return sess
}

// countThreadSessions повертає, скільки живих сесій зараз прив'язано до треду.
// >1 = перекриття плечей (стара A + нова B під час трансфера).
func (cm *Client) countThreadSessions(threadID string) int {
	cm.RLock()
	defer cm.RUnlock()

	var n int
	for _, sess := range cm.threads {
		if sess != nil && sess.threadId == threadID {
			n++
		}
	}

	return n
}

func (cm *Client) GetSession(threadID string) (*Session, bool) {
	cm.RLock()
	defer cm.RUnlock()

	for _, sess := range cm.threads {
		if sess != nil && sess.threadId == threadID {
			return sess, true
		}
	}

	return nil, false
}

func (cm *Client) closeSession(threadID string, tagID int) {
	cm.Lock()
	before := len(cm.threads)
	cm.threads = slices.DeleteFunc(cm.threads, func(sess *Session) bool {
		return sess != nil && sess.threadId == threadID && sess.tagID == tagID
	})
	removed := before - len(cm.threads)
	cm.Unlock()

	// DIAG: закриття конкретного плеча (threadId+tagID). removed=0 означає, що плече
	// вже було прибране (напр. подвійний close) — корисно для гонок при трансфері.
	cm.log.Debug("im session closed",
		wlog.String("thread_id", threadID),
		wlog.Int("tag_id", tagID),
		wlog.Int("removed", removed),
	)
}

func (cm *Client) addSession(sess *Session) {
	cm.Lock()
	cm.threads = append(cm.threads, sess)
	cm.Unlock()
}
