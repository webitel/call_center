package model

import (
	"encoding/json"
	"fmt"
	"net/http"
)

const (
	OUTBOUND_RESOURCE_STRATEGY_RANDOM   = "random"
	OUTBOUND_RESOURCE_STRATEGY_TOP_DOWN = "top_down"
	OUTBOUND_RESOURCE_STRATEGY_BY_LIMIT = "by_limit"
)

var (
	SIP_ENDPOINT_TEMPLATE = "sofia/sip/%s@%s"
)

type OutboundResourceUnReserveStrategy string

type OutboundResource struct {
	Id                    int                    `json:"id" db:"id"`
	Name                  string                 `json:"name" db:"name"`
	Enabled               bool                   `json:"enabled" db:"enabled"`
	Limit                 uint16                 `json:"limit" db:"limit"`
	Rps                   uint16                 `json:"rps" db:"rps"`
	Reserve               bool                   `json:"reserve" db:"reserve"`
	UpdatedAt             int64                  `json:"updated_at,omitempty" db:"updated_at"`
	Variables             map[string]interface{} `json:"variables,omitempty" db:"variables"`
	DisplayNumbers        StringArray            `json:"display_numbers" db:"display_numbers" `
	SuccessivelyErrors    uint16                 `json:"successively_errors" db:"successively_errors"`
	MaxSuccessivelyErrors uint16                 `json:"max_successively_errors" db:"max_successively_errors"`
	ErrorIds              *StringArray           `json:"error_ids" db:"error_ids"`
	GatewayId             int64                  `json:"gateway_id" db:"gateway_id"`
}

type SipGateway struct {
	Id        int64   `json:"id" db:"id"`
	Name      string  `json:"name" db:"name"`
	UpdatedAt int64   `json:"updated_at" db:"updated_at"`
	Register  bool    `json:"register" db:"register"`
	Proxy     string  `json:"proxy" db:"proxy"`
	UserName  *string `json:"username" db:"username"`
	Account   *string `json:"account" db:"account"`
	Password  *string `json:"password" db:"password"`
	//SipVariables map[string]interface{} `json:"envar,omitempty" db:"envar"`
}

func (g *SipGateway) Variables() map[string]string {
	vars := make(map[string]string)

	//for k, v := range g.SipVariables {
	//	//TODO ?
	//	vars[k] = fmt.Sprintf("%v", v)
	//}
	vars["sip_h_X-Webitel-Direction"] = "outbound"
	if g.Register && g.UserName != nil && g.Password != nil && g.Account != nil {
		vars["sip_auth_username"] = *g.UserName
		vars["sip_auth_password"] = *g.Password
		vars["sip_from_uri"] = *g.Account
	}

	return vars
}

func (g *SipGateway) Endpoint(destination string) string {
	return fmt.Sprintf(SIP_ENDPOINT_TEMPLATE, destination, g.Proxy)
}

type OutboundResourceGroup struct {
	Name string `json:"name" db:"name"`
}

type OutboundResourceErrorResult struct {
	CountSuccessivelyError *int   `json:"count_successively_error" db:"count_successively_error"`
	Stopped                *bool  `json:"stopped" db:"stopped"`
	UnReserveResourceId    *int64 `json:"un_reserve_resource_id" db:"un_reserve_resource_id"`
}

func (r *OutboundResource) IsValid() *AppError {
	if len(r.Name) <= 3 {
		return NewAppError("OutboundResource.IsValid", "model.outbound_resource.is_valid.name.app_error", nil, "name="+r.Name, http.StatusBadRequest)
	}
	return nil
}

func (r *OutboundResource) ToJson() string {
	b, _ := json.Marshal(r)
	return string(b)
}
