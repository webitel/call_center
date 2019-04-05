package cluster

import "github.com/webitel/call_center/mlog"

func (cluster *ClusterImpl) Heartbeat() {
	if result := <-cluster.store.Cluster().UpdateUpdatedTime(cluster.nodeId); result.Err != nil {
		mlog.Error(result.Err.Error())
	}
}
