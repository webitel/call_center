package cluster

import "github.com/webitel/call_center/mlog"

func (c *cluster) Heartbeat() {
	if err := c.store.Cluster().UpdateUpdatedTime(c.nodeId); err != nil {
		mlog.Error(err.Error())
	}
}
