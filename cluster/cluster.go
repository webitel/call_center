package cluster

import (
	"fmt"
	"github.com/webitel/call_center/discovery"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 10 * 1000 //30s

type cluster struct {
	store           discovery.ClusterStore
	nodeId          string
	startOnce       sync.Once
	pollingInterval int
	info            *discovery.ClusterData
	watcher         *utils.Watcher
	discovery       discovery.ServiceDiscovery
}

type Cluster interface {
	Setup() error
	Start()
	Stop()
	Master() bool

	ServiceDiscovery() discovery.ServiceDiscovery
}

func NewServiceDiscovery(id, addr string, check func() (bool, error)) (discovery.ServiceDiscovery, error) {
	return discovery.NewConsul(id, addr, check)
}

func NewCluster(nodeId, addr string, store discovery.ClusterStore) (Cluster, error) {

	cons, err := NewServiceDiscovery(nodeId, addr, func() (bool, error) {
		return true, nil //TODO
	})

	if err != nil {
		return nil, err
	}

	err = cons.RegisterService(model.APP_SERVICE_NAME, "", 0, model.APP_SERVICE_TTL, model.APP_DEREGESTER_CRITICAL_TTL)
	if err != nil {
		return nil, err
	}

	return &cluster{
		discovery:       cons,
		nodeId:          nodeId,
		store:           store,
		pollingInterval: DEFAULT_WATCHER_POLLING_INTERVAL,
	}, nil
}

func (c *cluster) Start() {
	wlog.Info(fmt.Sprintf("starting cluster [%s] service", c.nodeId))
	c.watcher = utils.MakeWatcher("Cluster", c.pollingInterval, c.Heartbeat)
	c.startOnce.Do(func() {
		go c.watcher.Start()
	})
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
	if info, err := c.store.UpdateClusterInfo(c.nodeId, true); err != nil {
		return err
	} else {
		c.info = info
		wlog.Debug(fmt.Sprintf("cluster [%s] %v", c.nodeId, info))
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
