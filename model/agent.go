package model

import "time"

/*
Most Idle Agent(MIA) - найбільш вільний
Least Occupied Agent(LOA) - найменш занятий оператор

*/

const (
	AGENT_STRATEGY_LONGEST_IDLE_TIME = "longest-idle-time" // +
	AGENT_STRATYGY_ROUND_ROBIN       = "round-robin"       // +
	AGENT_STRATYGY_TOP_DOWN          = "top-down"          // ?
	AGENT_STRATYGY_LEAST_TALK_TIME   = "least-talk-time"   // +
	AGENT_STRATYGY_FEWEST_CALLS      = "fewest-calls"      // +
	AGENT_STRATYGY_RANDOM            = "random"            // +
)

const (
	AGENT_STATE_LOGOUT    = "logged_out"
	AGENT_STATE_WAITING   = "waiting"
	AGENT_STATE_OFFERING  = "offering"
	AGENT_STATE_TALK      = "talking"
	AGENT_STATE_REPORTING = "reporting"
	AGENT_STATE_BREAK     = "break"
)

const (
	AGENT_CALL_RINGING = iota
	AGENT_CALL_BRIDGE
	AGENT_CALL_HANGUP
)

type Agent struct {
	Id                int64  `json:"id" db:"id"`
	Name              string `json:"name" db:"name"`
	Logged            bool   `json:"logged" db:"logged"`
	MaxNoAnswer       int    `json:"max_no_answer" db:"max_no_answer"`
	WrapUpTime        int    `json:"wrap_up_time" db:"wrap_up_time"`
	RejectDelayTime   int    `json:"reject_delay_time" db:"reject_delay_time"`
	BusyDelayTime     int    `json:"busy_delay_time" db:"busy_delay_time"`
	NoAnswerDelayTime int    `json:"no_answer_delay_time" db:"no_answer_delay_time"`
	UserId            *int64 `json:"user_id" db:"user_id"`
	UpdatedAt         int64  `json:"updated_at" db:"updated_at"`
	Destination       string `json:"destination" db:"destination"`
}

type AgentsForAttempt struct {
	AttemptId      int64 `json:"attempt_id" db:"attempt_id"`
	AgentId        int64 `json:"agent_id" db:"agent_id"`
	AgentUpdatedAt int64 `json:"agent_updated_at" db:"agent_updated_at"`
}

type AgentState struct {
	Id        int64      `json:"id" db:"id"`
	AgentId   int64      `json:"agent_id" db:"agent_id"`
	JoinedAt  time.Time  `json:"joined_at" db:"joined_at"`
	TimeoutAt *time.Time `json:"timeout_at" db:"timeout_at"`
	State     string     `json:"state" db:"state" `
}

type AgentStats struct {
	AgentId int64 `json:"agent_id"`
	QueueId int64 `json:"queue_id"`
}
