package cluster

import (
	"fmt"
	"sync"

	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/engine/pkg/discovery"
	"github.com/webitel/wlog"
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
	log             *wlog.Logger
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

func NewCluster(nodeId, addr string, st store.ClusterStore, checkFn func() (bool, error), log *wlog.Logger) (Cluster, error) {
	cons, err := NewServiceDiscovery(nodeId, addr, checkFn)
	if err != nil {
		return nil, err
	}

	return &cluster{
		discovery:       cons,
		nodeId:          nodeId,
		store:           st,
		pollingInterval: DEFAULT_WATCHER_POLLING_INTERVAL,
		log: log.With(
			wlog.Namespace("context"),
			wlog.String("name", "cluster"),
		),
	}, nil
}

func (c *cluster) Start(pubHost string, pubPort int) error {
	c.log.Info("starting cluster")
	err := c.discovery.RegisterService(model.ServiceName, pubHost, pubPort, model.APP_SERVICE_TTL, model.APP_DEREGISTER_CRITICAL_TTL)
	if err != nil {
		return err
	}
	c.startOnce.Do(func() {
		c.watcher = utils.MakeWatcher("Cluster", c.pollingInterval, c.Heartbeat)
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
		c.log.Debug(fmt.Sprintf("master = %v", info.Master),
			wlog.Any("master", info.Master),
		)
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
