package im

import (
	"context"
	"crypto/tls"
	"fmt"
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
	threads map[string]*Session
	sync.RWMutex
}

func NewClient(consulAddr string, events <-chan model.IMMessage, log *wlog.Logger, t *tls.Config) *Client {
	cli := &Client{
		consulAddr: consulAddr,
		log:        log,
		tls:        t,
		events:     events,
		threads:    make(map[string]*Session),
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
				sess.onMessage(Message{
					FromSub: msg.From.Sub,
				})
			}
		}
	}
}

func (cm *Client) NewSession(domainID int64, threadID, subBot, subMember string) *Session {
	sess := &Session{
		cli:           cm,
		threadId:      threadID,
		subBot:        subBot,
		subMember:     subMember,
		lastMessageAt: model.GetMillis(),
		hdrs: metadata.New(map[string]string{
			"x-webitel-type":   "schema",
			"x-webitel-schema": fmt.Sprintf("%d.%s", domainID, subBot),
		}),
	}

	cm.addSession(sess)

	return sess
}

func (cm *Client) GetSession(threadID string) (*Session, bool) {
	cm.RLock()
	sess, ok := cm.threads[threadID]
	cm.RUnlock()

	return sess, ok
}

func (cm *Client) closeSession(threadID string) {
	cm.Lock()
	delete(cm.threads, threadID)
	cm.Unlock()
}

func (cm *Client) addSession(sess *Session) {
	cm.Lock()
	cm.threads[sess.threadId] = sess
	cm.Unlock()
}
