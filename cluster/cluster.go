package cluster

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/engine/discovery"
	"github.com/webitel/wlog"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 10 * 1000 //30s

type cluster struct {
	store           store.ClusterStore
	nodeId          string
	startOnce       sync.Once
	pollingInterval int
	info            *discovery.ClusterData
	watcher         *utils.Watcher
	discovery       discovery.ServiceDiscovery
}

type Cluster interface {
	Setup() error
	Start(pubHost string, pubPort int) error
	Stop()
	Master() bool

	ServiceDiscovery() discovery.ServiceDiscovery
}

func NewServiceDiscovery(id, addr string, check func() (bool, error)) (discovery.ServiceDiscovery, error) {
	return discovery.NewConsul(id, addr, check)
}

func NewCluster(nodeId, addr string, st store.ClusterStore) (Cluster, error) {

	cons, err := NewServiceDiscovery(nodeId, addr, func() (bool, error) {
		return true, nil //TODO
	})

	if err != nil {
		return nil, err
	}

	return &cluster{
		discovery:       cons,
		nodeId:          nodeId,
		store:           st,
		pollingInterval: DEFAULT_WATCHER_POLLING_INTERVAL,
	}, nil
}

func (c *cluster) Start(pubHost string, pubPort int) error {
	wlog.Info(fmt.Sprintf("starting cluster [%s] service", c.nodeId))
	err := c.discovery.RegisterService(model.ServiceName, pubHost, pubPort, model.APP_SERVICE_TTL, model.APP_DEREGESTER_CRITICAL_TTL)
	if err != nil {
		return err
	}
	c.watcher = utils.MakeWatcher("Cluster", c.pollingInterval, c.Heartbeat)
	c.startOnce.Do(func() {
		go c.watcher.Start()
	})
	return nil
}

func (c *cluster) Stop() {
	if c.watcher != nil {
		c.watcher.Stop()
	}

	if c.discovery != nil {
		c.discovery.Shutdown()
	}
}

func (c *cluster) Setup() error {
	if info, err := c.store.CreateOrUpdate(c.nodeId); err != nil {
		return err
	} else {
		c.info = info
	}

	if info, err := c.store.UpdateClusterInfo(c.nodeId, true); err != nil {
		return err
	} else {
		c.info = info
		wlog.Debug(fmt.Sprintf("cluster [%s] master = %v", c.nodeId, info.Master))
	}

	return nil
}

func (c *cluster) ServiceDiscovery() discovery.ServiceDiscovery {
	return c.discovery
}

func (c *cluster) Master() bool {
	if c.info == nil {
		return false
	}
	return c.info.Master
}
