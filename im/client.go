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
			if sess, ok := cm.GetSession(msg.ThreadID); ok {
				if msg.System != nil && (msg.System.Type == "member_removed" || msg.System.Type == "transfer") {
					// Only the client leaving ends the conversation. An agent being removed is
					// normal transfer churn: control passes to the next operator and the session
					// must keep running. Cancelling here on the outgoing agent aborted the next
					// transfer's attempt for the same thread, so the invite never reached it. The
					// agent's own attempt is torn down separately via finalizeAttempt/cleanupSession.
					if msg.System.AffectsMember(sess.clientMemberId) || msg.System.AffectsMember(sess.agentMemberId) {
						wlog.Debug("closing session: client left thread", wlog.String("thread_id", msg.ThreadID))
						sess.cancel()
					} else {
						wlog.Debug("member left thread, session kept", wlog.String("thread_id", msg.ThreadID))
					}
				} else {
					sess.onMessage(Message{
						FromSub: msg.From.Sub,
					})
				}
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

	return sess
}

func (cm *Client) GetSession(threadID string) (*Session, bool) {
	cm.RLock()
	defer cm.RUnlock()

	for i := len(cm.threads) - 1; i >= 0; i-- {
		sess := cm.threads[i]
		if sess != nil && sess.threadId == threadID {
			return sess, true
		}
	}

	return nil, false
}

func (cm *Client) closeSession(threadID string, tagID int) {
	cm.Lock()
	cm.threads = slices.DeleteFunc(cm.threads, func(sess *Session) bool {
		return sess != nil && sess.threadId == threadID && sess.tagID == tagID
	})
	cm.Unlock()
}

func (cm *Client) addSession(sess *Session) {
	cm.Lock()
	cm.threads = append(cm.threads, sess)
	cm.Unlock()
}
