package model

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
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

type OutboundResourceParameters struct {
	SipCidType       string `json:"cid_type" db:"-"`
	IgnoreEarlyMedia string `json:"ignore_early_media" db:"-"`
}

type OutboundResource struct {
	Id                    int                        `json:"id" db:"id"`
	Name                  string                     `json:"name" db:"name"`
	Enabled               bool                       `json:"enabled" db:"enabled"`
	Limit                 uint16                     `json:"limit" db:"limit"`
	Rps                   uint16                     `json:"rps" db:"rps"`
	Reserve               bool                       `json:"reserve" db:"reserve"`
	UpdatedAt             int64                      `json:"updated_at,omitempty" db:"updated_at"`
	Variables             map[string]interface{}     `json:"variables,omitempty" db:"variables"`
	DisplayNumbers        StringArray                `json:"display_numbers" db:"display_numbers" `
	SuccessivelyErrors    uint16                     `json:"successively_errors" db:"successively_errors"`
	MaxSuccessivelyErrors uint16                     `json:"max_successively_errors" db:"max_successively_errors"`
	ErrorIds              StringArray                `json:"error_ids" db:"error_ids"`
	GatewayId             int64                      `json:"gateway_id" db:"gateway_id"`
	Parameters            OutboundResourceParameters `json:"parameters" db:"parameters"`
}

type SipGateway struct {
	Id                     int64   `json:"id" db:"id"`
	Name                   string  `json:"name" db:"name"`
	UpdatedAt              int64   `json:"updated_at" db:"updated_at"`
	Register               bool    `json:"register" db:"register"`
	Proxy                  string  `json:"proxy" db:"proxy"`
	HostName               *string `json:"host_name" db:"host_name"`
	UserName               *string `json:"username" db:"username"`
	Account                *string `json:"account" db:"account"`
	Password               *string `json:"password" db:"password"`
	DomainId               int64   `json:"domain_id" db:"domain_id"`
	UseBridgeAnswerTimeout bool    `json:"use_bridge_answer_timeout" db:"-"`
	SipCidType             string  `json:"sip_cid_type" db:"-"`
	IgnoreEarlyMedia       string  `json:"ignore_early_media" db:"-"`
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
	} else if g.HostName != nil {
		vars["sip_invite_domain"] = *g.HostName
	}

	if g.SipCidType != "" {
		vars["sip_cid_type"] = g.SipCidType
	}

	if g.IgnoreEarlyMedia != "" {
		vars["ignore_early_media"] = g.IgnoreEarlyMedia
	}

	return vars
}

func (g *SipGateway) Endpoint(destination string) string {
	//TODO space replace ?
	return fmt.Sprintf(SIP_ENDPOINT_TEMPLATE, strings.Replace(destination, " ", "", -1), g.Proxy)
}

type BridgeRequest struct {
	Id          *string
	GranteeId   *int
	ParentId    string
	Name        string
	Destination string
	Display     string
	Timeout     uint16

	Recordings bool
	RecordMono bool
	RecordAll  bool
}

func (g *SipGateway) Bridge(params BridgeRequest) string {
	res := []string{
		fmt.Sprintf("leg_timeout=%d", params.Timeout),
		fmt.Sprintf("wbt_parent_id=%s", params.ParentId),
		fmt.Sprintf("origination_caller_id_number=%s", params.Display),

		fmt.Sprintf("wbt_from_number=%s", params.Display),
		fmt.Sprintf("wbt_from_name=%s", params.Display),
		"wbt_to_type=dest",
		"ignore_display_updates=true",
		fmt.Sprintf("wbt_to_number='%s'", params.Destination),
		fmt.Sprintf("wbt_to_name='%s'", params.Name),

		fmt.Sprintf("effective_callee_id_name='%s'", params.Name),
		//fmt.Sprintf("origination_callee_id_name='%s'", name),
		fmt.Sprintf("%s=%v", CallVariableDomainId, g.DomainId),
		fmt.Sprintf("%s=%v", CallVariableGatewayId, g.Id),
		"sip_route_uri=sip:$${outbound_sip_proxy}",
		"sip_copy_custom_headers=false",
	}

	if params.Id != nil {
		res = append(res, fmt.Sprintf("%s=%s", CALL_ORIGINATION_UUID, *params.Id))
	}

	if params.GranteeId != nil {
		res = append(res, fmt.Sprintf("%s=%d", CallVariableGrantee, *params.GranteeId))
	}

	if g.UseBridgeAnswerTimeout {
		res = append(res, fmt.Sprintf("bridge_answer_timeout=%d", params.Timeout))
	}

	if params.Recordings {
		res = append(res, fmt.Sprintf("hangup_after_bridge=true,recording_follow_transfer=true,RECORD_BRIDGE_REQ=%v,media_bug_answer_req=%v,RECORD_STEREO=%v,execute_on_answer=record_session http_cache://http://$${cdr_url}/sys/recordings?domain=%d&id=%s&name=%s_%s&.%s",
			params.RecordAll, params.RecordAll, !params.RecordMono,
			g.DomainId, params.ParentId, params.ParentId, CallRecordFileTemplate, "mp3"))
	}

	vars := g.Variables()
	for k, v := range vars {
		res = append(res, fmt.Sprintf("%s='%s'", k, v))
	}

	return fmt.Sprintf("[%s]%s", strings.Join(res, ","), g.Endpoint(params.Destination))
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
