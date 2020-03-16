package model

import (
	"encoding/json"
	"fmt"
	"github.com/webitel/wlog"
	"strconv"
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

const (
	CALL_ACTION_RINGING       = "ringing"
	CALL_ACTION_ACTIVE        = "active"
	CALL_ACTION_BRIDGE        = "bridge"
	CALL_ACTION_HOLD          = "hold"
	CALL_ACTION_DTMF          = "dtmf"
	CALL_ACTION_UPDATE        = "update"
	CALL_ACTION_HANGUP        = "hangup"
	CALL_ACTION_JOIN_QUEUE    = "join_queue"
	CALL_ACTION_LEAVING_QUEUE = "leaving_queue"
)

type CallAction struct {
	Id            string `json:"id"`
	NodeName      string `json:"node_name"`
	QueueNodeName string `json:"queue_node"`
	ActivityAt    int64  `json:"activity_at,string"`
	Action        string `json:"action"`
}

type CallActionData struct {
	CallAction
	Data   *string     `json:"data,omitempty"`
	parsed interface{} `json:"-"`
}

type CallActionRinging struct {
	CallAction
	CallActionInfo
}

type CallActionJoinQueue struct {
	CallAction
	CallActionInfo
}

type CallActionLeavingQueue struct {
	CallAction
}

type CallActionActive struct {
	CallAction
}

type CallActionHold struct {
	CallAction
}

type CallActionBridge struct {
	CallAction
	CallActionInfo
}

type CallActionHangup struct {
	CallAction
	Cause         string `json:"cause"`
	SipCode       *int   `json:"sip"`
	OriginSuccess *bool  `json:"originate_success"`
}

type CallVariables map[string]interface{}

type CallActionInfo struct {
	ParentId    string `json:"parent_id"`
	OwnerId     string `json:"owner_id"`
	Direction   string `json:"direction"`
	Destination string `json:"destination"`

	FromNumber string `json:"from_number"`
	FromName   string `json:"from_name"`

	ToNumber string `json:"to_number"`
	ToName   string `json:"to_name"`

	Payload   *CallVariables `json:"payload"`
	QueueData *CallVariables `json:"queue"`
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

func (c *CallActionData) GetEvent() interface{} {
	if c.parsed != nil {
		return c.parsed
	}

	switch c.Action {
	case CALL_ACTION_RINGING:
		c.parsed = &CallActionRinging{
			CallAction: c.CallAction,
		}
	case CALL_ACTION_JOIN_QUEUE:
		c.parsed = &CallActionJoinQueue{
			CallAction: c.CallAction,
		}

	case CALL_ACTION_LEAVING_QUEUE:
		c.parsed = &CallActionLeavingQueue{
			CallAction: c.CallAction,
		}

	case CALL_ACTION_ACTIVE:
		c.parsed = &CallActionActive{
			CallAction: c.CallAction,
		}

	case CALL_ACTION_HOLD:
		c.parsed = &CallActionHold{
			CallAction: c.CallAction,
		}

	case CALL_ACTION_BRIDGE:
		c.parsed = &CallActionBridge{
			CallAction: c.CallAction,
		}
	case CALL_ACTION_HANGUP:
		c.parsed = &CallActionHangup{
			CallAction: c.CallAction,
		}
	}

	if c.Data != nil {
		if err := json.Unmarshal([]byte(*c.Data), &c.parsed); err != nil {
			wlog.Error(fmt.Sprintf("parse call %s [%s] error: %s", c.Id, c.Action, err.Error()))
		}
	}
	return c.parsed
}

func (vars CallVariables) GetString(header string) (string, bool) {
	if v, ok := vars[header].(string); ok {
		return v, true
	}
	return "", false
}

func (vars CallVariables) GetInt(header string) *int {
	if v, ok := vars.GetString(header); ok {
		if i, err := strconv.Atoi(v); err == nil {
			return &i
		}
	}
	return nil
}
