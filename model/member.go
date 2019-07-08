package model

const (
	MEMBER_CAUSE_SYSTEM_SHUTDOWN     = "SYSTEM_SHUTDOWN"
	MEMBER_CAUSE_DATABASE_ERROR      = "DATABASE_ERROR"
	MEMBER_CAUSE_ABANDONED           = "ABANDONED"
	MEMBER_CAUSE_SUCCESSFUL          = "SUCCESSFUL"
	MEMBER_CAUSE_QUEUE_NOT_IMPLEMENT = "QUEUE_NOT_IMPLEMENT"
)

const (
	MEMBER_STATE_END          = -1
	MEMBER_STATE_IDLE         = 0 // ~Reserved resource
	MEMBER_STATE_RESERVED     = 1
	MEMBER_STATE_ORIGINATE    = 2
	MEMBER_STATE_FIND_AGENT   = 3
	MEMBER_STATE_PROGRESS     = 4
	MEMBER_STATE_ACTIVE       = 5
	MEMBER_STATE_POST_PROCESS = 6
)

type MemberAttempt struct {
	Id                int64   `json:"id" db:"id"`
	CommunicationId   int64   `json:"communication_id" db:"communication_id"`
	QueueId           int64   `json:"queue_id" db:"queue_id"`
	QueueUpdatedAt    int64   `json:"queue_updated_at" db:"queue_updated_at"`
	State             uint8   `json:"state" db:"state"`
	MemberId          int64   `json:"member_id" db:"member_id"`
	CreatedAt         int64   `json:"created_at" db:"created_at"`
	HangupAt          int64   `json:"hangup_at" db:"hangup_at"`
	BridgedAt         int64   `json:"bridged_at" db:"bridged_at"`
	ResourceId        *int64  `json:"resource_id" db:"resource_id"`
	ResourceUpdatedAt *int64  `json:"resource_updated_at" db:"resource_updated_at"`
	RoutingId         *int    `json:"routing_id" db:"routing_id"`
	RoutingPattern    *string `json:"routing_pattern" db:"routing_pattern"`
	Result            *string `json:"result" db:"result"`
	Destination       string  `json:"destination" db:"destination"`
	Description       string  `json:"description" db:"description"`
	Variables         []byte  `json:"variables" db:"variables"`
	Name              string  `json:"name" db:"name"`
}

func (ma *MemberAttempt) IsTimeout() bool {
	return ma.Result != nil && *ma.Result == CALL_TIMEOUT
}
