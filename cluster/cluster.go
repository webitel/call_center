package cluster

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 30 * 1000 //30s

type cluster struct {
	store           store.Store
	nodeId          string
	startOnce       sync.Once
	pollingInterval int
	info            *model.ClusterInfo
	watcher         *utils.Watcher
	consul          *consul
}

func NewCluster(nodeId string, store store.Store) (Cluster, *model.AppError) {

	cons, err := NewConsul(func() (bool, *model.AppError) {
		return true, nil //TODO
	})

	if err != nil {
		return nil, err
	}

	err = cons.RegisterService()
	if err != nil {
		return nil, err
	}

	return &cluster{
		consul:          cons,
		nodeId:          nodeId,
		store:           store,
		pollingInterval: DEFAULT_WATCHER_POLLING_INTERVAL,
	}, nil
}

func (c *cluster) Start() {
	wlog.Info("Starting cluster service")
	c.watcher = utils.MakeWatcher("Cluster", c.pollingInterval, c.Heartbeat)
	c.startOnce.Do(func() {
		go c.watcher.Start()
	})
}
func (c *cluster) Stop() {
	if c.watcher != nil {
		c.watcher.Stop()
	}
}

func (c *cluster) Setup() *model.AppError {
	if info, err := c.store.Cluster().CreateOrUpdate(c.nodeId); err != nil {
		return err
	} else {
		c.info = info
	}
	return nil
}
