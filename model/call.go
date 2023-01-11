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
	CALL_PROXY_URI_VARIABLE          = "sip_route_uri"
	CALL_ORIGINATION_UUID            = "origination_uuid"
	CALL_TIMEOUT_VARIABLE            = "call_timeout"
	CALL_PROGRESS_TIMEOUT_VARIABLE   = "progress_timeout"
	CALL_IGNORE_EARLY_MEDIA_VARIABLE = "ignore_early_media"
	CALL_DIRECTION_VARIABLE          = "webitel_direction"

	CALL_ANSWER_APPLICATION   = "answer"
	CALL_SLEEP_APPLICATION    = "sleep"
	CALL_PLAYBACK_APPLICATION = "playback"
	CALL_HANGUP_APPLICATION   = "hangup"

	CallVariableGrantee = "wbt_grantee_id"
)

const (
	CallVariableDomainId   = "sip_h_X-Webitel-Domain-Id"
	CallVariableUserId     = "sip_h_X-Webitel-User-Id"
	CallVariableDirection  = "sip_h_X-Webitel-Direction"
	CallVariableGatewayId  = "sip_h_X-Webitel-Gateway-Id"
	CallVariableDomainName = "domain_name"
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
	CallActionAmdName     = "amd"
)

var (
	CallRecordFileTemplate = "${url_encode ${wbt_from_number}}_${url_encode ${wbt_destination}}.mp3"
)

type inboundCallData struct {
	CallId          string  `json:"call_id" db:"call_id"`
	CallState       string  `json:"call_state" db:"call_state"`
	CallDirection   string  `json:"call_direction" db:"call_direction"`
	CallDestination string  `json:"call_destination" db:"call_destination"`
	CallTimestamp   int64   `json:"call_timestamp" db:"call_timestamp"`
	CallAppId       string  `json:"call_app_id" db:"call_app_id"`
	CallFromNumber  *string `json:"call_from_number" db:"call_from_number"`
	CallFromName    *string `json:"call_from_name" db:"call_from_name"`
	CallAnsweredAt  int64   `json:"call_answered_at" db:"call_answered_at"`
	CallBridgedAt   int64   `json:"call_bridged_at" db:"call_bridged_at"`
	CallCreatedAt   int64   `json:"call_created_at" db:"call_created_at"`
}

type InboundCallQueue struct {
	AttemptId      int64             `json:"attempt_id" db:"attempt_id"`
	QueueId        int               `json:"queue_id" db:"queue_id"`
	QueueUpdatedAt int64             `json:"queue_updated_at" db:"queue_updated_at"`
	Destination    []byte            `json:"destination" db:"destination"`
	Variables      map[string]string `json:"variables" db:"variables"`
	Name           string            `json:"name" db:"name"`
	TeamUpdatedAt  *int64            `json:"team_updated_at" db:"team_updated_at"`
	//ListCommunicationId *int64 `json:"list_communication_id" db:"list_communication_id"`

	inboundCallData
}

type InboundCallAgent struct {
	AttemptId      int64             `json:"attempt_id" db:"attempt_id"`
	Destination    []byte            `json:"destination" db:"destination"`
	Variables      map[string]string `json:"variables" db:"variables"`
	Name           string            `json:"name" db:"name"`
	TeamId         int               `json:"team_id" db:"team_id"`
	TeamUpdatedAt  int64             `json:"team_updated_at" db:"team_updated_at"`
	AgentUpdatedAt int64             `json:"agent_updated_at" db:"agent_updated_at"`

	inboundCallData
}

///id, direction, destination, parent_id, timestamp, app_id, from_number, domain_id, answered_at, bridged_at, created_at
type Call struct {
	Id          string  `json:"id" db:"id"`
	State       string  `json:"state" db:"state"`
	DomainId    int64   `json:"domain_id" db:"domain_id"`
	Direction   string  `json:"direction" db:"direction"`
	Destination string  `json:"destination" db:"destination"`
	ParentId    *string `json:"parent_id" db:"parent_id"`
	Timestamp   int64   `json:"timestamp" db:"timestamp"`
	AppId       string  `json:"app_id" db:"app_id"`
	FromNumber  string  `json:"from_number" db:"from_number"`
	FromName    string  `json:"from_name" db:"from_name"`
	AnsweredAt  int64   `json:"answered_at" db:"answered_at"`
	BridgedAt   int64   `json:"bridged_at" db:"bridged_at"`
	CreatedAt   int64   `json:"created_at" db:"created_at"`
}

type CallAction struct {
	Id        string `json:"id"`
	AppId     string `json:"app_id"`
	DomainId  int64  `json:"domain_id,string"`
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
	GatewayId   *int           `json:"gateway_id"` // FIXME
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
	Cause               string                 `json:"cause"`
	SipCode             *int                   `json:"sip"`
	OriginSuccess       *bool                  `json:"originate_success"`
	ReportingAt         *int64                 `json:"reporting_at,string"`
	TransferTo          *string                `json:"transfer_to"`
	TransferFrom        *string                `json:"transfer_from"`
	TransferToAgent     *int                   `json:"transfer_to_agent,string"`
	TransferFromAttempt *int64                 `json:"transfer_from_attempt,string"`
	TransferToAttempt   *int64                 `json:"transfer_to_attempt,string"`
	Variables           map[string]interface{} `json:"payload"`
}

type CallNoAnswer struct {
	Id    string `json:"id" db:"id"`
	AppId string `json:"app_id" db:"app_id"`
}

type CallActionAMD struct {
	CallAction
	AiResult string `json:"ai_result"`
	AiError  string `json:"ai_error"`
	Result   string `json:"result"`
	Cause    string `json:"cause"`
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

	case CallActionAmdName:
		c.parsed = &CallActionAMD{
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
	Id           *string
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

func (cr *CallRequest) SetPush() {
	cr.Variables["execute_on_originate"] = "wbt_send_hook"
}
