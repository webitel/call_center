package model

import (
	"encoding/json"
	"fmt"
	"io"
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
	DialString            string                 `json:"dial_string" db:"dial_string"`
	Number                string                 `json:"number,omitempty" db:"number"`
	SuccessivelyErrors    uint16                 `json:"successively_errors" db:"successively_errors"`
	MaxSuccessivelyErrors uint16                 `json:"max_successively_errors" db:"max_successively_errors"`
	ErrorIds              StringArray            `json:"error_ids" db:"error_ids"`
	GatewayId             int64                  `json:"gateway_id" db:"gateway_id"`
}

type SipGateway struct {
	Id        int64   `json:"id" db:"id"`
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

func (resource *OutboundResource) IsValid() *AppError {
	if len(resource.Name) <= 3 {
		return NewAppError("OutboundResource.IsValid", "model.outbound_resource.is_valid.name.app_error", nil, "name="+resource.Name, http.StatusBadRequest)
	}
	return nil
}

func OutboundResourcesToJson(resources []*OutboundResource) string {
	b, _ := json.Marshal(resources)
	return string(b)
}

func (r *OutboundResource) ToJson() string {
	b, _ := json.Marshal(r)
	return string(b)
}

func OutboundResourceFromJson(data io.Reader) *OutboundResource {
	var resource OutboundResource
	if err := json.NewDecoder(data).Decode(&resource); err != nil {
		return nil
	} else {
		return &resource
	}
}
