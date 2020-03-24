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
	AGENT_STATUS_OFFLINE = "offline"
	AGENT_STATUS_WAITING = "waiting"
	AGENT_STATUS_PAUSE   = "pause"
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
	Id                    int    `json:"id" db:"id"`
	DomainId              int64  `json:"domain_id" db:"domain_id"`
	UserId                *int64 `json:"user_id" db:"user_id"`
	Name                  string `json:"name" db:"name"`
	UpdatedAt             int64  `json:"updated_at" db:"updated_at"`
	Destination           string `json:"destination" db:"destination"`
	Extension             string `json:"extension" db:"extension"`
	SuccessivelyNoAnswers int    `json:"successively_no_answers" db:"successively_no_answers"`
	AgentStatus
}

type AgentEvent struct {
	Event     string `json:"event"`
	AgentId   int    `json:"agent_id"`
	UserId    int64  `json:"user_id"`
	DomainId  int64  `json:"domain_id"`
	Timestamp int64  `json:"timestamp"`
}

type AgentEventStatus struct {
	AgentEvent
	AgentStatus
	Timeout *int `json:"timeout"`
}

func (e *AgentEventStatus) ToJSON() string {
	data, _ := json.Marshal(e)
	return string(data)
}

type AgentStatus struct {
	Status        string  `json:"status" db:"status"`
	StatusPayload *string `json:"status_payload" db:"status_payload"`
	Timeout       *int    `json:"timeout"`
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
}

type AgentState struct {
	//Id        int64      `json:"id" db:"id"`
	AgentId   int64      `json:"agent_id" db:"agent_id"`
	JoinedAt  time.Time  `json:"joined_at" db:"joined_at"`
	TimeoutAt *time.Time `json:"timeout_at" db:"state_timeout"`
	State     string     `json:"state" db:"state" `
}

type AgentChangedState struct {
	Id    int64  `json:"id" db:"id"`
	State string `json:"state" db:"state"`
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
