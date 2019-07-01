package cluster

import (
	"github.com/webitel/call_center/mlog"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/call_center/utils"
	"sync"
)

var DEFAULT_WATCHER_POLLING_INTERVAL = 30 * 1000 //30s

type ClusterImpl struct {
	store           store.Store
	nodeId          string
	startOnce       sync.Once
	pollingInterval int
	info            *model.ClusterInfo
	watcher         *utils.Watcher
}

func NewCluster(nodeId string, store store.Store) Cluster {
	return &ClusterImpl{
		nodeId:          nodeId,
		store:           store,
		pollingInterval: DEFAULT_WATCHER_POLLING_INTERVAL,
	}
}

func (cluster *ClusterImpl) Start() {
	mlog.Info("Starting cluster service")
	cluster.watcher = utils.MakeWatcher("Cluster", cluster.pollingInterval, cluster.Heartbeat)
	cluster.startOnce.Do(func() {
		go cluster.watcher.Start()
	})
}
func (cluster *ClusterImpl) Stop() {
	if cluster.watcher != nil {
		cluster.watcher.Stop()
	}
}

func (cluster *ClusterImpl) Setup() *model.AppError {
	if info, err := cluster.store.Cluster().CreateOrUpdate(cluster.nodeId); err != nil {
		return err
	} else {
		cluster.info = info
	}
	return nil
}
