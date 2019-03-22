package queue

import (
	"github.com/webitel/call_center/model"
	"go.uber.org/ratelimit"
)

type ResourceObject interface {
	Name() string
	IsExpire(updatedAt int64) bool
	GetDialString() string
	Id() int
	Variables() map[string]string
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
		id:         config.Id,
		updatedAt:  config.UpdatedAt,
		name:       config.Name,
		rps:        config.Rps,
		dialString: config.DialString,
		variables:  model.MapStringInterfaceToString(config.Variables),
		number:     []string{config.Number},
	}

	if r.rps > 0 {
		r.rateLimiter = ratelimit.New(config.Rps)
	}

	return r, nil
}

func (r *Resource) Name() string {
	return r.name
}

func (r *Resource) IsExpire(updatedAt int64) bool {
	return r.updatedAt != updatedAt
}

func (r *Resource) Id() int {
	return r.id
}

func (r *Resource) Variables() map[string]string {
	return r.variables
}

func (r *Resource) Take() {
	if r.rateLimiter != nil {
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
