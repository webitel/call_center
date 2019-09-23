package cluster

import (
	"fmt"
	"github.com/webitel/wlog"
)

func (c *cluster) Heartbeat() {
	if info, err := c.store.UpdateClusterInfo(c.nodeId, false); err != nil {
		wlog.Error(err.Error())
	} else {
		if c.info != nil && c.info.Master != info.Master {
			wlog.Debug(fmt.Sprintf("cluster [%s] change to master = %v", c.nodeId, c.info.Master))
		}
		c.info = info

	}
}
