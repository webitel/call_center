package dialing

import (
	"fmt"
	"github.com/webitel/call_center/model"
	"go.uber.org/ratelimit"
)

type ResourceObject interface {
	Name() string
	IsExpire(updatedAt int64) bool
	GetDialString() string
}

type Resource struct {
	id          int
	updatedAt   int64
	rps         int
	rateLimiter ratelimit.Limiter
}

func NewResource(config *model.OutboundResource) ResourceObject {
	return &Resource{
		id:          config.Id,
		updatedAt:   config.UpdatedAt,
		rps:         config.Rps,
		rateLimiter: ratelimit.New(config.Rps), // check rps zero
	}
}

func (r *Resource) Name() string {
	return fmt.Sprintf("%v", r.id)
}

func (r *Resource) IsExpire(updatedAt int64) bool {
	return r.updatedAt != updatedAt
}

func (r *Resource) GetDialString() string {
	if r.rps > 0 {
		r.rateLimiter.Take()
	}
	return "sofia/external/todo"
}
