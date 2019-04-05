package model

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
}

type AgentsForAttempt struct {
	AttemptId      int64 `json:"attempt_id" db:"attempt_id"`
	AgentId        int64 `json:"agent_id" db:"agent_id"`
	AgentUpdatedAt int64 `json:"agent_updated_at" db:"agent_updated_at"`
}

type AgentStats struct {
	AgentId int64 `json:"agent_id"`
	QueueId int64 `json:"queue_id"`
}
