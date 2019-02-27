package model

const (
	MEMBER_CAUSE_SYSTEM_SHUTDOWN = "SYSTEM_SHUTDOWN"
	MEMBER_CAUSE_ABANDONED       = "ABANDONED"
)

const (
	MEMBER_STATE_END          = -1
	MEMBER_STATE_IDLE         = 0
	MEMBER_STATE_RESERVED     = 1
	MEMBER_STATE_PROGRESS     = 2
	MEMBER_STATE_ACTIVE       = 3
	MEMBER_STATE_POST_PROCESS = 4
)

type MemberAttempt struct {
	Id                int64   `json:"id" db:"id"`
	CommunicationId   int64   `json:"communication_id" db:"communication_id"`
	QueueId           int     `json:"queue_id" db:"queue_id"`
	QueueUpdatedAt    int64   `json:"queue_updated_at" db:"queue_updated_at"`
	State             int     `json:"state" db:"state"`
	MemberId          int64   `json:"member_id" db:"member_id"`
	CreatedAt         int64   `json:"created_at" db:"created_at"`
	HangupAt          int64   `json:"hangup_at" db:"hangup_at"`
	BridgedAt         int64   `json:"bridged_at" db:"bridged_at"`
	ResourceId        *int    `json:"resource_id" db:"resource_id"`
	ResourceUpdatedAt *int64  `json:"resource_updated_at" db:"resource_updated_at"`
	Result            *string `json:"result" db:"result"`
}
