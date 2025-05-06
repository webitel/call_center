package queue

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/utils"
	"github.com/webitel/wlog"
	"math/rand"
	"sync"
)

const (
	MASK_CHAR_UPPER = 'X'
	MASK_CHAR_LOWER = 'x'
)

type ResourceObject interface {
	Name() string
	IsExpire(updatedAt int64) bool
	CheckCodeError(errorId string) bool
	GetDisplay() string
	Id() int
	SuccessivelyErrors() uint16
	Variables() map[string]string
	Take()
	Gateway() *model.SipGateway
	Log() *wlog.Logger
	SetSuccessivelyErrors(se uint16)
}

//type Gateway interface {
//	GetId() int64
//	Name() string
//	Variables() map[string]string
//	Endpoint(destination string) string
//}

type Resource struct {
	id                    int
	updatedAt             int64
	name                  string
	rps                   uint16
	rateLimiter           *utils.RateLimiter
	variables             map[string]string
	displayNumbers        []string
	errorIds              model.StringArray
	successivelyErrors    uint16
	maxSuccessivelyErrors uint16
	gatewayId             *int64
	emailProfileId        *int
	gateway               model.SipGateway
	log                   *wlog.Logger
	sync.RWMutex
}

func NewResource(config *model.OutboundResource, gw model.SipGateway, log *wlog.Logger) (ResourceObject, *model.AppError) {
	r := &Resource{
		id:                    config.Id,
		updatedAt:             config.UpdatedAt,
		name:                  config.Name,
		rps:                   config.Rps,
		errorIds:              nil,
		successivelyErrors:    config.SuccessivelyErrors,
		maxSuccessivelyErrors: config.MaxSuccessivelyErrors,
		variables:             model.MapStringInterfaceToString(config.Variables),
		displayNumbers:        config.DisplayNumbers,
		gateway:               gw,
		log: log.With(
			wlog.String("scope", "resource"),
			wlog.Int("resource_id", config.Id),
			wlog.Int64("gateway_id", gw.Id),
		),
	}

	if config.ErrorIds != nil {
		r.errorIds = config.ErrorIds
	}

	r.gateway.IgnoreEarlyMedia = config.Parameters.IgnoreEarlyMedia
	r.gateway.SipCidType = config.Parameters.SipCidType

	if r.rps > 0 {
		r.rateLimiter = utils.NewRateLimiter(config.Rps)
	}

	return r, nil
}

func (r *Resource) Name() string {
	return r.name
}

func (r *Resource) Log() *wlog.Logger {
	return r.log
}

func (r *Resource) GetDisplay() string {
	var l = len(r.displayNumbers)
	if l == 0 {
		return ""
	} else {
		return r.displayNumbers[rand.Intn(l)]
	}
}

func (r *Resource) IsExpire(updatedAt int64) bool {
	return r.updatedAt != updatedAt
}

func (r *Resource) Id() int {
	return r.id
}

func (r *Resource) SuccessivelyErrors() uint16 {
	r.RLock()
	se := r.successivelyErrors
	r.RUnlock()
	return se
}

func (r *Resource) SetSuccessivelyErrors(se uint16) {
	r.Lock()
	r.successivelyErrors = se
	r.Unlock()
}

func (r *Resource) Variables() map[string]string {
	return model.UnionStringMaps(
		r.variables,
		r.gateway.Variables(),
	)
}

func (r *Resource) Gateway() *model.SipGateway {
	return &r.gateway
}

func (r *Resource) Take() {
	if r.rateLimiter != nil {
		r.rateLimiter.Take()
	}
}

func (r *Resource) CheckCodeError(errorCode string) bool {
	if r.maxSuccessivelyErrors < 1 || r.errorIds == nil {
		return false
	}

	e := []rune(errorCode)
	for _, v := range r.errorIds {
		if !checkCodeMask(v, e) {
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
		if v == MASK_CHAR_UPPER || v == MASK_CHAR_LOWER {
			continue
		}
		if v != code[i] {
			return true
		}
	}
	return false
}
