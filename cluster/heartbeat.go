package cluster

import "github.com/webitel/call_center/mlog"

func (cluster *ClusterImpl) Heartbeat() {
	if err := cluster.store.Cluster().UpdateUpdatedTime(cluster.nodeId); err != nil {
		mlog.Error(err.Error())
	}
}
