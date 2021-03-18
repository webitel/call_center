package model

const (
	ChannelStateWaiting = "waiting"

	ChannelStateDistribute = "distribute"
	ChannelStateOffering   = "offering"
	ChannelStateAnswered   = "answered"
	ChannelStateBridged    = "bridged"
	ChannelStateHold       = "hold" //TODO
	ChannelStateProcessing = "processing"
	ChannelStateMissed     = "missed"
	ChannelStateWrapTime   = "wrap_time"
)

type ChannelTimeout struct {
	UserId    int64   `json:"user_id" db:"user_id"`
	Channel   *string `json:"channel" db:"channel"`
	Timestamp int64   `json:"timestamp" db:"timestamp"`
	DomainId  int64   `json:"domain_id" db:"domain_id"`
}
