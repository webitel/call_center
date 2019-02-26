package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
)

type Resource struct {
	id        int
	updatedAt int64
	rps       int
}

func NewResource(config *model.OutboundResource) *Resource {
	return &Resource{
		id:        config.Id,
		updatedAt: config.UpdatedAt,
		rps:       config.Rps,
	}
}

func (r *Resource) Name() string {
	return fmt.Sprintf("%v", r.id)
}

func (r *Resource) IsExpire(updatedAt int64) bool {
	return r.updatedAt != updatedAt
}
