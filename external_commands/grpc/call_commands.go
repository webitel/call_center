package grpc

import (
	"fmt"
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"google.golang.org/grpc"

	"google.golang.org/grpc/connectivity"
	"os"
	"sync"
	"time"
)

type connectionIterator struct {
	index  int
	length int
}

func (c *connectionIterator) Next() int {
	c.index = (c.index + 1) % c.length
	return c.index
}

type CallCommandsImpl struct {
	connections []*CallConnection
	iterator    *connectionIterator
	sync.Mutex
}

func NewCallCommands(settings model.ExternalCommandsSettings) model.Commands {
	var opts []grpc.DialOption

	if len(settings.Urls) == 0 {
		mlog.Critical(fmt.Sprintf("failed to open grpc connection %v", settings.Urls))
		time.Sleep(time.Second)
		os.Exit(1)
	}

	opts = append(opts,
		grpc.WithInsecure(),
		grpc.WithBlock(),
		grpc.WithTimeout(10*time.Second),
	)

	r := &CallCommandsImpl{
		connections: make([]*CallConnection, 0, len(settings.Urls)),
	}

	for _, h := range settings.Urls {
		c, err := newConnection(h, opts)
		if err != nil {
			mlog.Critical(fmt.Sprintf("failed to open grpc connection %v error: %s", h, err.Error()))
			time.Sleep(time.Second)
			os.Exit(1)
		}

		if v, err := c.GetServerVersion(); err == nil {
			mlog.Info(fmt.Sprintf("[%s] %v", h, v))
		} else {
			mlog.Critical(err.Error())
		}

		r.Lock()
		r.connections = append(r.connections, c)
		r.Unlock()
	}

	r.iterator = &connectionIterator{
		index:  0,
		length: len(r.connections),
	}

	mlog.Debug(fmt.Sprintf("success to open grpc connection %v", settings.Urls))
	return r
}

func (c *CallCommandsImpl) GetCallConnection() model.CallCommands {
	c.Lock()
	defer c.Unlock()

	i := c.iterator.index

	for j := c.iterator.Next(); ; j = c.iterator.Next() {
		switch c.connections[j].client.GetState() {
		case connectivity.Idle, connectivity.Ready:
			return c.connections[j]
		}

		if i == j {
			break
		}
	}

	mlog.Error(fmt.Sprintf("no active connections to call server"))
	con := c.connections[c.iterator.Next()]

	return con
}

func (c *CallCommandsImpl) Close() {
	mlog.Debug(fmt.Sprintf("receive close grpc connection"))
	for _, c := range c.connections {
		c.close()
	}
}
