package cluster

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"net/http"
	"sync"
)

var (
	ErrNotFoundConnection  = model.NewAppError("Cluster", "cluster.pool.connection_not_found", nil, "", http.StatusInternalServerError)
	ErrNotOpenedConnection = model.NewAppError("Cluster", "cluster.pool.connection_not_opened", nil, "", http.StatusInternalServerError)
)

type Strategy string

const (
	StrategyRoundRobin Strategy = "round-robin"
)

type Connection interface {
	Name() string
	Ready() bool
	Close() *model.AppError
}

type Pool interface {
	Append(connection Connection)
	Remove(id string)
	GetById(id string) (Connection, *model.AppError)
	Get(strategy Strategy) (Connection, *model.AppError)
	All() []Connection
	CloseAllConnections()
	RecheckConnections()
}

func NewPoolConnections() Pool {
	return &connectionsPool{
		connections: make([]Connection, 0, 1),
		iterator:    &connectionIterator{},
	}
}

type connectionIterator struct {
	index  int
	length int
}

func (c *connectionIterator) Next() int {
	c.index = (c.index + 1) % c.length
	return c.index
}

type connectionsPool struct {
	connections []Connection
	iterator    *connectionIterator
	index       int
	sync.RWMutex
}

func (c *connectionsPool) Append(conn Connection) {
	c.Lock()
	c.connections = append(c.connections, conn)
	c.iterator.length = len(c.connections)
	c.Unlock()
}

func (c *connectionsPool) Remove(id string) {
	c.Lock()
	defer c.Unlock()

	for i, v := range c.connections {
		if v.Name() == id {
			c.iterator.length = len(c.connections) - 1
			c.connections[i] = c.connections[c.iterator.length]
			if err := c.connections[c.iterator.length].Close(); err != nil {
				wlog.Error(err.Error())
			}
			c.connections[c.iterator.length] = nil
			c.connections = c.connections[:len(c.connections)-1]
			wlog.Debug(fmt.Sprintf("remove connection %s", v.Name()))
			return
		}
	}
}

func (c *connectionsPool) GetById(id string) (Connection, *model.AppError) {
	c.RLock()
	defer c.RUnlock()

	for _, v := range c.connections {
		if v.Name() == id {
			return v, nil
		}
	}

	return nil, ErrNotFoundConnection
}

func (c *connectionsPool) Get(strategy Strategy) (Connection, *model.AppError) {
	c.RLock()
	defer c.RUnlock()

	if c.iterator.length == 0 {
		return nil, ErrNotOpenedConnection
	}

	i := c.iterator.index

	for j := c.iterator.Next(); ; j = c.iterator.Next() {
		if c.connections[j].Ready() {
			return c.connections[j], nil
		}

		if i == j {
			break
		}
	}

	return nil, ErrNotOpenedConnection
}

func (c *connectionsPool) CloseAllConnections() {
	c.Lock()
	defer c.Unlock()

	for _, v := range c.connections {
		if err := v.Close(); err != nil {
			wlog.Error(fmt.Sprintf("close connection %s, error: %s", v.Name(), err.Error()))
		}
		wlog.Debug(fmt.Sprintf("close connection %s", v.Name()))
	}
}

func (c *connectionsPool) All() []Connection {
	return c.connections
}

func (c *connectionsPool) RecheckConnections() {
	for _, conn := range c.connections {
		if conn != nil && !conn.Ready() {
			c.Remove(conn.Name())
		}
	}
}
