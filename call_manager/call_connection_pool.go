package call_manager

import (
	"fmt"
	"github.com/webitel/call_center/cluster"
	"github.com/webitel/call_center/external_commands"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
	"net/http"
	"os"
	"sync"
)

var (
	errNotFoundConnection  = model.NewAppError("CallManager", "call_manager.pool.connection_not_found", nil, "", http.StatusInternalServerError)
	errNotOpenedConnection = model.NewAppError("CallManager", "call_manager.pool.connection_not_opened", nil, "", http.StatusInternalServerError)
)

type connectionIterator struct {
	index  int
	length int
}

func (c *connectionIterator) Next() int {
	c.index = (c.index + 1) % c.length
	return c.index
}

type callConnectionsPool struct {
	connections []model.CallCommands
	iterator    *connectionIterator
	index       int
	sync.RWMutex
	serviceDiscovery cluster.ServiceDiscovery
}

func newCallConnectionsPool(cl cluster.ServiceDiscovery) *callConnectionsPool {
	list, err := cl.GetByName(model.CLUSTER_CALL_SERVICE_NAME)
	if err != nil {
		wlog.Error(err.Error())
		os.Exit(1) //TODO
	}

	c := &callConnectionsPool{
		connections:      make([]model.CallCommands, 0, len(list)),
		iterator:         &connectionIterator{},
		serviceDiscovery: cl,
	}

	for _, v := range list {
		if err := c.registerConnection(v); err != nil {
			wlog.Error(fmt.Sprintf("open connection to %s, error: %s", v.Id, err.Error()))
		}
	}

	return c
}

func (c *callConnectionsPool) registerConnection(config *model.ServiceConnection) *model.AppError {
	client, err := external_commands.NewCallConnection(config.Id, fmt.Sprintf("%s:%d", config.Host, config.Port))
	if err != nil {
		return err
	}

	c.appendConnection(client)
	return nil
}

func (c *callConnectionsPool) appendConnection(client model.CallCommands) {
	version, err := client.GetServerVersion()
	if err != nil {
		wlog.Error(fmt.Sprintf("opened connection %s, error: %s", client.Name(), err.Error()))
		return
	}
	c.Lock()
	c.connections = append(c.connections, client)
	c.iterator.length = len(c.connections)
	c.Unlock()
	wlog.Debug(fmt.Sprintf("opened connection %s [%s]", client.Name(), version))
}

func (c *callConnectionsPool) removeConnectionByName(name string) {
	c.Lock()
	defer c.Unlock()

	for i, v := range c.connections {
		if v.Name() == name {
			c.iterator.length = len(c.connections) - 1
			c.connections[i] = c.connections[c.iterator.length]
			c.connections[c.iterator.length].Close()
			c.connections[c.iterator.length] = nil
			c.connections = c.connections[:len(c.connections)-1]
			wlog.Debug(fmt.Sprintf("remove connection %s", name))
			return
		}
	}
}

func (c *callConnectionsPool) getByName(name string) (model.CallCommands, *model.AppError) {
	c.RLock()
	defer c.RUnlock()

	for _, v := range c.connections {
		if v.Name() == name {
			return v, nil
		}
	}

	return nil, errNotFoundConnection
}

func (c *callConnectionsPool) getByRoundRobin() (model.CallCommands, *model.AppError) {
	c.RLock()
	defer c.RUnlock()

	i := c.iterator.index

	for j := c.iterator.Next(); ; j = c.iterator.Next() {
		if c.connections[j].Ready() {
			return c.connections[j], nil
		}

		if i == j {
			break
		}
	}

	return nil, errNotOpenedConnection
}

func (c *callConnectionsPool) closeAllConnections() {
	c.Lock()
	defer c.Unlock()

	for _, v := range c.connections {
		if err := v.Close(); err != nil {
			wlog.Error(fmt.Sprintf("close connection %s, error: %s", v.Name(), err.Error()))
		}
		wlog.Debug(fmt.Sprintf("close connection %s", v.Name()))
	}
}

func (c *callConnectionsPool) checkConnection() {
	list, err := c.serviceDiscovery.GetByName(model.CLUSTER_CALL_SERVICE_NAME)
	if err != nil {
		wlog.Error(err.Error())
		return
	}

	for _, v := range list {
		if _, err := c.getByName(v.Id); err == errNotFoundConnection {
			if err = c.registerConnection(v); err != nil {
				wlog.Error(fmt.Sprintf("opened connection %s, error: %s", v.Id, err.Error()))
			}
		}
	}

	for _, con := range c.connections {
		if con != nil && !con.Ready() {
			c.removeConnectionByName(con.Name())
		}
	}
}
