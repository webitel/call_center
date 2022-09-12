package trigger

import (
	"context"
	"github.com/webitel/call_center/model"
)

type Job struct {
	data    model.TriggerJob
	manager *Manager
	ctx     context.Context
}
