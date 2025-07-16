package model

import (
	"encoding/json"
	"time"
)

/*
Most Idle Agent(MIA) - найбільш вільний
Least Occupied Agent(LOA) - найменш занятий оператор

*/

const (
	AGENT_STRATEGY_LONGEST_IDLE_TIME = "longest-idle-time" // +
	AGENT_STRATYGY_LEAST_TALK_TIME   = "least-talk-time"   // +

	AGENT_STRATYGY_ROUND_ROBIN  = "round-robin"  // +
	AGENT_STRATYGY_TOP_DOWN     = "top-down"     // +
	AGENT_STRATYGY_FEWEST_CALLS = "fewest-calls" // +
	AGENT_STRATYGY_RANDOM       = "random"       // +
)

const (
	AgentChangedStatusEvent = "agent_status"
)

const (
	AgentStatusOnline   = "online"
	AgentStatusOffline  = "offline"
	AgentStatusPause    = "pause"
	AgentStatusBreakOut = "break_out"
)

const (
	AGENT_STATE_LOGOUT    = "offline" // offline
	AGENT_STATE_WAITING   = "waiting"
	AGENT_STATE_OFFERING  = "offering"
	AGENT_STATE_RINGING   = "ringing"
	AGENT_STATE_TALK      = "talking"
	AGENT_STATE_REPORTING = "reporting"
	AGENT_STATE_BREAK     = "break"
	AGENT_STATE_FINE      = "fine"
)

type Agent struct {
	Id            int               `json:"id" db:"id"`
	DomainId      int64             `json:"domain_id" db:"domain_id"`
	UserId        *int64            `json:"user_id" db:"user_id"`
	Name          string            `json:"name" db:"name"`
	UpdatedAt     int64             `json:"updated_at" db:"updated_at"`
	Destination   *string           `json:"destination" db:"destination"`
	Extension     *string           `json:"extension" db:"extension"`
	TeamId        int               `json:"team_id" db:"team_id"`
	TeamUpdatedAt int64             `json:"team_updated_at" db:"team_updated_at"`
	OnDemand      bool              `json:"on_demand" db:"on_demand"`
	GreetingMedia *RingtoneFile     `json:"greeting_media" db:"greeting_media"`
	Variables     map[string]string `json:"variables" db:"variables"`
	HasPush       bool              `json:"has_push" db:"has_push"`
	AgentStatus
}

type AgentHashKey struct {
	Id            int   `json:"id" db:"id" `
	UpdatedAt     int64 `json:"updated_at" db:"updated_at"`
	Sip           bool  `json:"sip" db:"sip"`
	Ws            bool  `json:"ws" db:"ws"`
	ReasonSca     bool  `json:"reason_sca" db:"reason_sca"`
	TeamUpdatedAt int64 `json:"team_updated_at" db:"team_updated_at"`
}

type AgentChannel struct {
	Channel  string `json:"channel"`
	State    string `json:"state"`
	JoinedAt int64  `json:"joined_at"`
	Online   bool   `json:"online"`
}

type MissedAgent struct {
	Timestamp       int64   `json:"timestamp" db:"timestamp"`
	NoAnswers       *uint16 `json:"no_answers" db:"no_answers"`
	MemberStopCause *string `json:"member_stop_cause" db:"member_stop_cause"`
}

type AgentOnlineData struct {
	Timestamp int64          `json:"timestamp" db:"timestamp"`
	Channel   []AgentChannel `json:"channel" db:"channel"`
}

type AgentEvent struct {
	AgentId   int   `json:"agent_id"`
	UserId    int64 `json:"user_id"`
	DomainId  int64 `json:"domain_id"`
	Timestamp int64 `json:"timestamp"`
}

type Event struct {
	Name   string      `json:"event"`
	UserId int64       `json:"user_id"`
	Data   interface{} `json:"data"`
}

func NewEvent(name string, userId int64, data interface{}) Event {
	return Event{
		UserId: userId,
		Name:   name,
		Data:   data,
	}
}

type AgentEventStatus struct {
	AgentEvent
	AgentStatus
}

type AgentEventOnlineStatus struct {
	Channels []AgentChannel `json:"channels"`
	OnDemand bool           `json:"on_demand"`
	AgentEvent
	AgentStatus
}

func (e Event) ToJSON() string {
	data, _ := json.Marshal(e)
	return string(data)
}

func (e AgentEventStatus) ToJSON() string {
	data, _ := json.Marshal(e)
	return string(data)
}

func (e AgentEventOnlineStatus) ToJSON() string {
	data, _ := json.Marshal(e)
	return string(data)
}

type AgentStatus struct {
	Status        string  `json:"status" db:"status"`
	StatusPayload *string `json:"status_payload,omitempty" db:"status_payload"`
}

type MissedAgentAttempt struct {
	AttemptId int64  `json:"attempt_id" db:"attempt_id"`
	AgentId   int    `json:"agent_id" db:"agent_id"`
	Cause     string `json:"cause" db:"cause"`
	MissedAt  int64  `json:"missed_at" db:"missed_at"`
}

type AgentsForAttempt struct {
	AttemptId      int64 `json:"attempt_id" db:"attempt_id"`
	AgentId        int   `json:"agent_id" db:"agent_id"`
	AgentUpdatedAt int64 `json:"agent_updated_at" db:"agent_updated_at"`
	TeamId         int   `json:"team_id" db:"team_id"`
	TeamUpdatedAt  int64 `json:"team_updated_at" db:"team_updated_at"`
}

type AgentState struct {
	//Id        int64      `json:"id" db:"id"`
	AgentId   int64      `json:"agent_id" db:"agent_id"`
	JoinedAt  time.Time  `json:"joined_at" db:"joined_at"`
	TimeoutAt *time.Time `json:"timeout_at" db:"state_timeout"`
	State     string     `json:"state" db:"state" `
}

type AgentChangedState struct {
	Timestamp      int64  `json:"timestamp" db:"cur_time"`
	AgentId        int    `json:"agent_id" db:"agent_id"`
	AgentUpdatedAt int64  `json:"agent_updated_at" db:"agent_updated_at"`
	State          string `json:"state" db:"state"`
}

type AgentInQueueStatistic struct {
	AgentId           int64      `json:"agent_id" db:"agent_id"`
	QueueId           int64      `json:"queue_id" db:"queue_id"`
	LastOfferingAt    *time.Time `json:"last_offering_at" db:"last_offering_at"`
	LastBridgeStartAt *time.Time `json:"last_bridge_start_at" db:"last_bridge_start_at"`
	LastBridgeEndAt   *time.Time `json:"last_bridge_end_at" db:"last_bridge_end_at"`
	CallsAnswered     int        `json:"calls_answered" db:"calls_answered"`
	CallsAbandoned    int        `json:"calls_abandoned" db:"calls_abandoned"`
}

type AgentTriggerJob struct {
	SchemaId  uint32    `json:"schema_id" db:"schema_id"`
	Extension string    `json:"extension" db:"extension"`
	Email     string    `json:"email" db:"email"`
	AgentId   int32     `json:"agent_id" db:"agent_id"`
	Name      string    `json:"name" db:"name"`
	Variables StringMap `json:"variables" db:"variables"`
}

func (agent *Agent) GetUserId() int64 {
	if agent.UserId != nil {
		return *agent.UserId
	}
	return 0
}
