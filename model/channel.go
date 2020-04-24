package model

const (
	ChannelStateWaiting = "waiting"

	ChannelStateDistribute = "distribute"
	ChannelStateOffering   = "offering"
	ChannelStateAnswered   = "answered"
	ChannelStateBridged    = "active"
	ChannelStateHold       = "hold" //TODO
	ChannelStateReporting  = "reporting"
	ChannelStateMissed     = "missed"
	ChannelStateWrapTime   = "wrap_time"
)

type ChannelTimeout struct {
	AgentId   int    `json:"agent_id" db:"agent_id"`
	Channel   string `json:"channel" db:"channel"`
	Timestamp int64  `json:"timestamp" db:"timestamp"`
}
