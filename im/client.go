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
)

const ServiceName = "im-gateway-service"

type Client struct {
	consulAddr string
	startOnce  sync.Once
	*wbt.Client[p.ThreadManagementClient]
	log *wlog.Logger
	ctx context.Context
	tls *tls.Config
}

func NewClient(consulAddr string, log *wlog.Logger, t *tls.Config) *Client {
	cli := &Client{
		consulAddr: consulAddr,
		log:        log,
		tls:        t,
	}

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
	})
	return err
}

func (cm *Client) Stop() {
	cm.log.Debug("stopping " + ServiceName + " client")
	_ = cm.Client.Close()
}

func (cm *Client) NewSession(domainID int64, threadId, from string) *Session {
	return &Session{
		cli:      cm,
		threadId: threadId,
		from:     from,
		hdrs: metadata.New(map[string]string{
			"x-webitel-type":   "schema",
			"x-webitel-schema": fmt.Sprintf("%d.%s", domainID, from),
		}),
	}
}
