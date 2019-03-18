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
	Id() int
	Take()
}

type Resource struct {
	id          int
	updatedAt   int64
	name        string
	rps         int
	rateLimiter ratelimit.Limiter
	variables   map[string]string
	dialString  string
	number      []string
}

func NewResource(config *model.OutboundResource) (ResourceObject, *model.AppError) {
	r := &Resource{
		id:          config.Id,
		updatedAt:   config.UpdatedAt,
		name:        config.Name,
		rps:         config.Rps,
		dialString:  config.DialString,
		rateLimiter: ratelimit.New(config.Rps), // check rps zero
		variables:   model.MapStringInterfaceToString(config.Variables),
		number:      []string{config.Number},
	}

	return r, nil
}

func (r *Resource) Name() string {
	return fmt.Sprintf("%v", r.name)
}

func (r *Resource) IsExpire(updatedAt int64) bool {
	return r.updatedAt != updatedAt
}

func (r *Resource) Id() int {
	return r.id
}

func (r *Resource) Take() {
	if r.rps > 0 {
		r.rateLimiter.Take()
	}
}

func (r *Resource) GetDialString() (dialString string) {

	//dialString = r.regDialString.ReplaceAllString("sofia/external/$1@10.10.10.200:5080", number)
	dialString = "sofia/external/" + r.dialString + "@10.10.10.25:5080"
	return
	//return "user/1003@10.10.10.25"
	//return "sofia/gateway/testLinphone/123"
}
