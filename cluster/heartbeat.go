package cluster

import "github.com/webitel/wlog"

func (c *cluster) Heartbeat() {
	if err := c.store.Cluster().UpdateUpdatedTime(c.nodeId); err != nil {
		wlog.Error(err.Error())
	}
}
