package model

import (
	"encoding/json"
	"fmt"
	"time"
)

const (
	MEMBER_CAUSE_SYSTEM_SHUTDOWN     = "SYSTEM_SHUTDOWN"
	MEMBER_CAUSE_ABANDONED           = "abandoned"
	MEMBER_CAUSE_TIMEOUT             = "timeout"
	MEMBER_CAUSE_CANCEL              = "cancel"
	MEMBER_CAUSE_SUCCESSFUL          = "SUCCESSFUL"
	MEMBER_CAUSE_QUEUE_NOT_IMPLEMENT = "QUEUE_NOT_IMPLEMENT"
)

const (
	MemberStateIdle = "idle" // ~Reserved resource

	MemberStateWaiting    = "waiting"
	MemberStateJoined     = "joined"
	MemberStateWaitAgent  = "wait_agent"
	MemberStateActive     = "active"
	MemberStateOffering   = "offering"
	MemberStateBridged    = "bridged"
	MemberStateProcessing = "processing"
	MemberStateLeaving    = "leaving"
	MemberStateCancel     = "cancel"
)

type Communication struct {
	Id   int    `json:"id"`
	Name string `json:"name"` // TODO
}

type MemberCommunication struct {
	Destination string        `json:"destination"`
	Type        Communication `json:"type"`
	Priority    int           `json:"priority"`
	Display     *string       `json:"display"`
}

type AttemptCallback struct {
	Status        string
	NextCallAt    *time.Time
	ExpireAt      *time.Time
	Description   string
	Display       bool
	Variables     map[string]string
	StickyAgentId *int
}

type MemberAttempt struct {
	Id             int64 `json:"id" db:"id"`
	QueueId        int   `json:"queue_id" db:"queue_id"`
	QueueUpdatedAt int64 `json:"queue_updated_at" db:"queue_updated_at"`
	Seq            *int  `json:"seq" db:"seq"`

	QueueCount        int `json:"queue_count" db:"queue_count"`
	QueueActiveCount  int `json:"queue_active_count" db:"queue_active_count"`
	QueueWaitingCount int `json:"queue_waiting_count" db:"queue_waiting_count"`

	State               uint8             `json:"state" db:"state"`
	MemberId            *int64            `json:"member_id" db:"member_id"`
	CreatedAt           time.Time         `json:"created_at" db:"created_at"`
	HangupAt            int64             `json:"hangup_at" db:"hangup_at"`
	BridgedAt           int64             `json:"bridged_at" db:"bridged_at"`
	ResourceId          *int64            `json:"resource_id" db:"resource_id"`
	ResourceUpdatedAt   *int64            `json:"resource_updated_at" db:"resource_updated_at"`
	GatewayUpdatedAt    *int64            `json:"gateway_updated_at" db:"gateway_updated_at"`
	Result              *string           `json:"result" db:"result"`
	Destination         []byte            `json:"destination" db:"destination"`
	ListCommunicationId *int64            `json:"list_communication_id" db:"list_communication_id"`
	AgentId             *int              `json:"agent_id" db:"agent_id"`
	AgentUpdatedAt      *int64            `json:"agent_updated_at" db:"agent_updated_at"`
	TeamUpdatedAt       *int64            `json:"team_updated_at" db:"team_updated_at"`
	Variables           map[string]string `json:"variables" db:"variables"`
	Name                string            `json:"name" db:"name"`
	MemberCallId        *string           `json:"member_call_id" db:"member_call_id"`
}

type AttemptReportingTimeout struct {
	AttemptId      int64  `json:"attempt_id" db:"attempt_id"`
	Timestamp      int64  `json:"timestamp" db:"timestamp"`
	AgentId        int    `json:"agent_id" db:"agent_id"`
	AgentUpdatedAt int64  `json:"agent_updated_at" db:"agent_updated_at"`
	UserId         int64  `json:"user_id" db:"user_id"`
	Channel        string `json:"channel" db:"channel"`
	DomainId       int64  `json:"domain_id" db:"domain_id"`
}

type EventAttempt struct {
	AttemptId int64  `json:"attempt_id"`
	Timestamp int64  `json:"timestamp"`
	Channel   string `json:"channel"`
	Status    string `json:"status"`
	AgentId   *int   `json:"agent_id"`
	UserId    *int64 `json:"user_id"`
	DomainId  int64  `json:"domain_id"`
}

type RenewalProcessing struct {
	AttemptId  int64  `json:"attempt_id" db:"attempt_id"`
	Timeout    int64  `json:"timeout" db:"timeout"`
	Timestamp  int64  `json:"timestamp" db:"timestamp"`
	Channel    string `json:"channel" db:"channel"`
	UserId     int64  `json:"user_id" db:"user_id"`
	QueueId    int    `json:"queue_id" db:"queue_id"` // todo queue null
	DomainId   int64  `json:"domain_id" db:"domain_id"`
	RenewalSec uint32 `json:"renewal_sec" db:"renewal_sec"`
}

type EventAttemptOffering struct {
	MemberId int64 `json:"member_id"`
	EventAttempt
}

func (e *EventAttemptOffering) ToJSON() string {
	data, _ := json.Marshal(e)
	return string(data)
}

func (e *EventAttempt) ToJSON() string {
	data, _ := json.Marshal(e)
	return string(data)
}

type AttemptOfferingAgent struct {
	AgentId        *int  `json:"agent_id" db:"agent_id"`
	AgentNoAnswers *int  `json:"agent_no_answers" db:"agent_no_answers"`
	Timestamp      int64 `json:"timestamp" db:"cur_time"`
}

/*
  success?: boolean
  next_distribute_at?: number
  categories?: Categories

  communication?: MemberCommunication
  new_communication?: MemberCommunication[]
  description?: string

  // integration fields
  display?: boolean
  expire?: number
  variables?: CallVariables
  agent_id?: number
  name?: string
  timezone?: object
*/

type AttemptReportingResult struct {
	Timestamp       int64   `json:"timestamp" db:"timestamp"`
	Channel         *string `json:"channel" db:"channel"`
	AgentCallId     *string `json:"agent_call_id" db:"agent_call_id"`
	AgentId         *int    `json:"agent_id" db:"agent_id"`
	UserId          *int64  `json:"user_id" db:"user_id"`
	DomainId        *int64  `json:"domain_id" db:"domain_id"`
	QueueId         *int    `json:"queue_id" db:"queue_id"`
	AgentTimeout    *int64  `json:"agent_timeout" db:"agent_timeout"`
	MemberStopCause *string `json:"member_stop_cause" db:"member_stop_cause"`
}

type HistoryAttempt struct {
	Id     int64  `json:"id" db:"id"`
	Result string `json:"result" db:"result"`
}

type AttemptResult struct {
	Id         int64   `json:"id" db:"id"`
	State      int8    `json:"state" db:"state"`
	OfferingAt int64   `json:"offering_at" db:"offering_at"`
	AnsweredAt int64   `json:"answered_at" db:"answered_at"`
	BridgedAt  int64   `json:"bridged_at" db:"bridged_at"`
	HangupAt   int64   `json:"hangup_at" db:"hangup_at"`
	AgentId    *int    `json:"agent_id" db:"agent_id"`
	Result     string  `json:"result" db:"result"`
	LegAId     *string `json:"leg_a_id" db:"leg_a_id"`
	LegBId     *string `json:"leg_b_id" db:"leg_b_id"`
}

type InboundMember struct {
	QueueId  int64  `json:"queue_id"`
	CallId   string `json:"call_id"`
	Number   string `json:"number"`
	Name     string `json:"name"`
	Priority int    `json:"priority"`
}

func (ma *MemberAttempt) IsTimeout() bool {
	return ma.Result != nil && *ma.Result == CALL_HANGUP_TIMEOUT
}

func (r AttemptCallback) String() string {
	t := fmt.Sprintf("Status: %v", r.Status)
	if r.ExpireAt != nil {
		t += fmt.Sprintf(", ExpireAt: %v", *r.ExpireAt)
	}
	if r.NextCallAt != nil {
		t += fmt.Sprintf(", NextCall: %v", *r.NextCallAt)
	}
	if r.StickyAgentId != nil {
		t += fmt.Sprintf(", StickyAgentId: %d", *r.StickyAgentId)
	}
	return t
}

func MemberDestinationFromBytes(data []byte) MemberCommunication {
	var dest MemberCommunication
	json.Unmarshal(data, &dest)
	return dest
}
