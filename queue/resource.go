package queue

import (
	"github.com/webitel/call_center/model"
	"go.uber.org/ratelimit"
)

type ResourceObject interface {
	Name() string
	IsExpire(updatedAt int64) bool
	CheckIfError(errorId string) bool
	GetDialString() string
	Id() int
	SuccessivelyErrors() uint16
	Variables() map[string]string
	Take()
}

type Resource struct {
	id                      int
	updatedAt               int64
	name                    string
	rps                     uint16
	rateLimiter             ratelimit.Limiter
	variables               map[string]string
	dialString              string
	number                  []string
	errorIds                model.StringArray
	successively_errors     uint16
	max_successively_errors uint16
}

func NewResource(config *model.OutboundResource) (ResourceObject, *model.AppError) {
	r := &Resource{
		id:                      config.Id,
		updatedAt:               config.UpdatedAt,
		name:                    config.Name,
		rps:                     config.Rps,
		errorIds:                config.ErrorIds,
		dialString:              config.DialString,
		successively_errors:     config.SuccessivelyErrors,
		max_successively_errors: config.MaxSuccessivelyErrors,
		variables:               model.MapStringInterfaceToString(config.Variables),
		number:                  []string{config.Number},
	}

	if r.rps > 0 {
		r.rateLimiter = ratelimit.New(int(config.Rps))
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

func (r *Resource) SuccessivelyErrors() uint16 {
	return r.successively_errors
}

func (r *Resource) Variables() map[string]string {
	return r.variables
}

func (r *Resource) Take() {
	if r.rateLimiter != nil {
		r.rateLimiter.Take()
	}
}

func (r *Resource) CheckIfError(errorId string) bool {
	if r.max_successively_errors < 1 {
		return false
	}

	for _, v := range r.errorIds {
		if v == errorId {
			return true
		}
	}
	return false
}

func (r *Resource) GetDialString() (dialString string) {

	//dialString = r.regDialString.ReplaceAllString("sofia/external/$1@10.10.10.200:5080", number)
	dialString = "sofia/external/" + r.dialString + "@10.10.10.25:5080"
	return
	//return "user/1003@10.10.10.25"
	//return "sofia/gateway/testLinphone/123"
}
