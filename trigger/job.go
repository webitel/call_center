package trigger

import (
	"context"
	"github.com/webitel/call_center/model"
	"github.com/webitel/wlog"
)

type Job struct {
	data    model.TriggerJob
	manager *Manager
	ctx     context.Context
	log     *wlog.Logger
}
