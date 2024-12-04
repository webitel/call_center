package cluster

import (
	"fmt"
	"github.com/webitel/wlog"
)

func (c *cluster) Heartbeat() {
	if info, err := c.store.UpdateClusterInfo(c.nodeId, false); err != nil {
		c.log.Error(err.Error(),
			wlog.Err(err),
		)
	} else {
		if c.info != nil && c.info.Master != info.Master {
			c.log.Debug(fmt.Sprintf("change to master = %v", c.info.Master),
				wlog.Any("master", c.info.Master),
			)
		}
		c.info = info

	}
}
