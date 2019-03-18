package model

const (
	AGENT_STRATEGY_LONGEST_IDLE_TIME = "longest-idle-time" // +
	AGENT_STRATYGY_RING_ALL          = "ring-all"          // +
	AGENT_STRATYGY_ROUND_ROBIN       = "round-robin"       // ?
	AGENT_STRATYGY_TOP_DOWN          = "top-down"          // ?
	AGENT_STRATYGY_LEAST_TALK_TIME   = "least-talk-time"   // +
	AGENT_STRATYGY_FEWEST_CALLS      = "fewest-calls"      // +
	AGENT_STRATYGY_RANDOM            = "random"            // +
)

type Agent struct {
	Id int64 `json:"id"`
}

type AgentStats struct {
	AgentId int64 `json:"agent_id"`
	QueueId int64 `json:"queue_id"`
}
