package model

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/wlog"
)

const (
	CALL_STRATEGY_DEFAULT = iota
	CALL_STRATEGY_FAILOVER
	CALL_STRATEGY_MULTIPLE
)

const (
	CALL_DIRECTION_INBOUND  = "inbound"
	CALL_DIRECTION_OUTBOUND = "outbound"
	CALL_DIRECTION_DIALER   = "dialer"
)

const (
	CALL_EVENT_CREATE   = "CHANNEL_CREATE"
	CALL_EVENT_ANSWER   = "CHANNEL_ANSWER"
	CALL_EVENT_PARK     = "CHANNEL_PARK"
	CALL_EVENT_HANGUP   = "CHANNEL_HANGUP_COMPLETE"
	CALL_EVENT_BRIDGE   = "CHANNEL_BRIDGE"
	CALL_EVENT_UNBRIDGE = "CHANNEL_UNBRIDGE"

	CALL_EVENT_CUSTOM = "CUSTOM"

	CALL_ATTRIBUTE_EVENT_NAME        = "Event-Name"
	CALL_ATTRIBUTE_DURATION_NAME     = "variable_duration"
	CALL_ATTRIBUTE_HANGUP_CAUSE_NAME = "variable_hangup_cause"

	CALL_ATTRIBUTE_FROM_NUMBER = "Caller-Caller-ID-Number"
	CALL_ATTRIBUTE_FROM_NAME   = "Caller-Caller-ID-Name"
	CALL_ATTRIBUTE_HANGUP_CODE = "variable_hangup_cause_q850"
)

const (
	CALL_PROXY_URI_VARIABLE              = "sip_route_uri"
	CALL_ORIGINATION_UUID                = "origination_uuid"
	CALL_TIMEOUT_VARIABLE                = "call_timeout"
	CALL_PROGRESS_TIMEOUT_VARIABLE       = "progress_timeout"
	CALL_DOMAIN_VARIABLE                 = "domain_name"
	CALL_IGNORE_EARLY_MEDIA_VARIABLE     = "ignore_early_media"
	CALL_DIRECTION_VARIABLE              = "webitel_direction"
	CALL_RECORD_MIN_SEC_VARIABLE         = "RECORD_MIN_SEC"
	CALL_RECORD_STEREO_VARIABLE          = "RECORD_STEREO"
	CALL_RECORD_BRIDGE_REQ_VARIABLE      = "RECORD_BRIDGE_REQ"
	CALL_RECORD_FLLOW_TRANSFER_VARIABLE  = "recording_follow_transfer"
	CALL_RECORD_SESSION_TEMPLATE         = `http_cache://$${cdr_url}/sys/formLoadFile?domain=${domain_name}&id=${uuid}&type=mp3&email=none&name=recordSession&.mp3`
	CALL_RECORD_SESSION_APPLICATION_NAME = "record_session"

	CALL_ANSWER_APPLICATION   = "answer"
	CALL_SLEEP_APPLICATION    = "sleep"
	CALL_PLAYBACK_APPLICATION = "playback"
	CALL_TRANSFER_APPLICATION = "transfer"
	CALL_HANGUP_APPLICATION   = "hangup"
	CALL_PARK_APPLICATION     = "park"
)

const (
	CALL_HANGUP_REJECTED             = "CALL_REJECTED"
	CALL_HANGUP_NO_ANSWER            = "NO_ANSWER"
	CALL_HANGUP_USER_BUSY            = "USER_BUSY"
	CALL_HANGUP_OUTGOING_CALL_BARRED = "OUTGOING_CALL_BARRED"
	CALL_HANGUP_TIMEOUT              = "TIMEOUT"
	CALL_HANGUP_NORMAL_CLEARING      = "NORMAL_CLEARING"
	CALL_HANGUP_NORMAL_UNSPECIFIED   = "NORMAL_UNSPECIFIED"
	CALL_HANGUP_ORIGINATOR_CANCEL    = "ORIGINATOR_CANCEL"
	CALL_HANGUP_LOSE_RACE            = "LOSE_RACE"
)

const (
	CALL_AMD_APPLICATION_NAME  = "amd"
	CALL_AMD_HUMAN_VARIABLE    = "amd_on_human"
	CALL_AMD_MACHINE_VARIABLE  = "amd_on_machine"
	CALL_AMD_NOT_SURE_VARIABLE = "amd_on_notsure"
)

type CallDirection string

const (
	CallDirectionInbound  CallDirection = "inbound"
	CallDirectionOutbound               = "outbound"
)
const (
	CallActionRingingName = "ringing"
	CallActionActiveName  = "active"
	CallActionBridgeName  = "bridge"
	CallActionHoldName    = "hold"
	CallActionDtmfName    = "dtmf"
	CallActionHangupName  = "hangup"
)

type CallAction struct {
	Id        string `json:"id"`
	AppId     string `json:"app_id"`
	DomainId  int8   `json:"domain_id,string"`
	Timestamp int64  `json:"timestamp,string"`
	Event     string `json:"event"`
}

type CallActionData struct {
	CallAction
	Data   *string     `json:"data,omitempty"`
	parsed interface{} `json:"-"`
}

type CallEndpoint struct {
	Type   string
	Id     string
	Number string
	Name   string
}

func (e *CallEndpoint) GetType() *string {
	if e != nil {
		return &e.Type
	}

	return nil
}

func (e *CallEndpoint) GetId() *string {
	if e != nil {
		return &e.Id
	}

	return nil
}

func (e *CallEndpoint) GetNumber() *string {
	if e != nil {
		return &e.Number
	}

	return nil
}

func (e *CallEndpoint) GetName() *string {
	if e != nil {
		return &e.Name
	}

	return nil
}

type CallActionInfo struct {
	GatewayId   *int           `json:"gateway_id"`
	UserId      *int           `json:"user_id"`
	Direction   string         `json:"direction"`
	Destination string         `json:"destination"`
	From        *CallEndpoint  `json:"from"`
	To          *CallEndpoint  `json:"to"`
	ParentId    *string        `json:"parent_id"`
	Payload     *CallVariables `json:"payload"`
}

type CallActionRinging struct {
	CallAction
	CallActionInfo
}

func (c *CallActionRinging) GetFrom() *CallEndpoint {
	if c != nil {
		return c.From
	}
	return nil
}

func (c *CallActionRinging) GetTo() *CallEndpoint {
	if c != nil {
		return c.To
	}
	return nil
}

type CallActionActive struct {
	CallAction
}

type CallActionHold struct {
	CallAction
}

type CallActionBridge struct {
	CallAction
	BridgedId string `json:"bridged_id"`
}

type CallActionHangup struct {
	CallAction
	Cause         string `json:"cause"`
	SipCode       *int   `json:"sip"`
	OriginSuccess *bool  `json:"originate_success"`
}

type CallVariables map[string]interface{}

func (c *CallActionData) GetEvent() interface{} {
	if c.parsed != nil {
		return c.parsed
	}

	switch c.Event {
	case CallActionRingingName:
		c.parsed = &CallActionRinging{
			CallAction: c.CallAction,
		}
	case CallActionActiveName:
		c.parsed = &CallActionActive{
			CallAction: c.CallAction,
		}

	case CallActionHoldName:
		c.parsed = &CallActionHold{
			CallAction: c.CallAction,
		}

	case CallActionBridgeName:
		c.parsed = &CallActionBridge{
			CallAction: c.CallAction,
		}
	case CallActionHangupName:
		c.parsed = &CallActionHangup{
			CallAction: c.CallAction,
		}
	}

	if c.Data != nil {
		if err := json.Unmarshal([]byte(*c.Data), &c.parsed); err != nil {
			wlog.Error(fmt.Sprintf("parse call %s [%s] error: %s", c.Id, c.Event, err.Error()))
		}
	}
	return c.parsed
}

type CallRequestApplication struct {
	AppName string
	Args    string
}

type CallRequest struct {
	Endpoints    []string
	Strategy     uint8
	Destination  string
	Variables    map[string]string
	Timeout      uint16
	CallerName   string
	CallerNumber string
	Dialplan     string
	Context      string
	Applications []*CallRequestApplication
}
