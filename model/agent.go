package model

import "time"

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
	AGENT_STATUS_ONLINE  = "online"
	AGENT_STATUS_PAUSE   = "pause"
)

const (
	AGENT_STATE_LOGOUT    = "logged_out"
	AGENT_STATE_WAITING   = "waiting"
	AGENT_STATE_OFFERING  = "offering"
	AGENT_STATE_RINGING   = "ringing"
	AGENT_STATE_TALK      = "talking"
	AGENT_STATE_REPORTING = "reporting"
	AGENT_STATE_BREAK     = "break"
	AGENT_STATE_FINE      = "fine"
)

const (
	AGENT_CALL_RINGING = iota
	AGENT_CALL_BRIDGE
	AGENT_CALL_HANGUP
)

type Agent struct {
	Id   int64  `json:"id" db:"id"`
	Name string `json:"name" db:"name"`

	UserId      *int64 `json:"user_id" db:"user_id"`
	UpdatedAt   int64  `json:"updated_at" db:"updated_at"`
	Destination string `json:"destination" db:"destination"`
	AgentStatus
}

type AgentStatus struct {
	Status        string      `json:"status" db:"status"`
	StatusPayload interface{} `json:"status_payload" db:"status_payload"`
}

type AgentsForAttempt struct {
	AttemptId      int64 `json:"attempt_id" db:"attempt_id"`
	AgentId        int64 `json:"agent_id" db:"agent_id"`
	AgentUpdatedAt int64 `json:"agent_updated_at" db:"agent_updated_at"`
}

type AgentState struct {
	//Id        int64      `json:"id" db:"id"`
	AgentId   int64      `json:"agent_id" db:"agent_id"`
	JoinedAt  time.Time  `json:"joined_at" db:"joined_at"`
	TimeoutAt *time.Time `json:"timeout_at" db:"state_timeout"`
	State     string     `json:"state" db:"state" `
}

//type AgentStateHistoryTime struct {
//	Id       int64     `json:"id" db:"id"`
//	AgentId  int64     `json:"agent_id" db:"agent_id"`
//	JoinedAt time.Time `json:"joined_at" db:"joined_at"`
//	State    string    `json:"state" db:"state"`
//	Payload  []byte    `json:"payload" db:"payload"`
//}

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
