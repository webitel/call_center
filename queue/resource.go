package queue

import (
	"github.com/webitel/call_center/model"
	"go.uber.org/ratelimit"
)

const (
	MASK_CHAR = 'X'
)

type ResourceObject interface {
	Name() string
	IsExpire(updatedAt int64) bool
	CheckCodeError(errorId string) bool
	Id() int
	SuccessivelyErrors() uint16
	Variables() map[string]string
	Take()
	Gateway() Gateway
}

type Gateway interface {
	Variables() map[string]string
	Endpoint(destination string) string
}

type Resource struct {
	id                    int
	updatedAt             int64
	name                  string
	rps                   uint16
	rateLimiter           ratelimit.Limiter
	variables             map[string]string
	number                []string
	errorIds              model.StringArray
	successivelyErrors    uint16
	maxSuccessivelyErrors uint16
	gatewayId             *int64
	gateway               Gateway
}

func NewResource(config *model.OutboundResource, gw Gateway) (ResourceObject, *model.AppError) {
	r := &Resource{
		id:                    config.Id,
		updatedAt:             config.UpdatedAt,
		name:                  config.Name,
		rps:                   config.Rps,
		errorIds:              config.ErrorIds,
		successivelyErrors:    config.SuccessivelyErrors,
		maxSuccessivelyErrors: config.MaxSuccessivelyErrors,
		variables:             model.MapStringInterfaceToString(config.Variables),
		number:                []string{config.Number},
		gateway:               gw,
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
	return r.successivelyErrors
}

func (r *Resource) Variables() map[string]string {
	if r.gateway != nil {
		return model.UnionStringMaps(
			r.variables,
			r.gateway.Variables(),
		)
	}
	return r.variables
}

func (r *Resource) Gateway() Gateway {
	return r.gateway
}

func (r *Resource) Take() {
	if r.rateLimiter != nil {
		r.rateLimiter.Take()
	}
}

func (r *Resource) CheckCodeError(errorCode string) bool {
	if r.maxSuccessivelyErrors < 1 {
		return false
	}

	e := []rune(errorCode)
	for _, v := range r.errorIds {
		if checkCodeMask(v, e) {
			return true
		}
	}
	return false
}

func checkCodeMask(maskCode string, code []rune) bool {
	if len(maskCode) != len(code) {
		return false
	}

	for i, v := range maskCode {
		if v == MASK_CHAR {
			continue
		}
		if v != code[i] {
			return true
		}
	}
	return false
}
