package model

const (
	QUEUE_TYPE_INBOUND = iota
	QUEUE_TYPE_VOICE_BROADCAST
)

const (
	QUEUE_SIDE_MEMBER = "member"
	QUEUE_SIDE_AGENT  = "agent"
)

const (
	QUEUE_SIDE_FILD        = "cc_side"
	QUEUE_ID_FILD          = "cc_queue_id"
	QUEUE_NAME_FILD        = "cc_queue_name"
	QUEUE_MEMBER_ID_FILD   = "cc_member_id"
	QUEUE_ATTEMPT_ID_FILD  = "cc_attempt_id"
	QUEUE_RESOURCE_ID_FILD = "cc_resource_id"
	QUEUE_NODE_ID_FILD     = "cc_node_id"
)

type Queue struct {
	Id        int                     `json:"id" db:"id"`
	Type      int                     `json:"type" db:"type"`
	Name      string                  `json:"name" db:"name"`
	Strategy  string                  `json:"strategy" db:"strategy"`
	Payload   *map[string]interface{} `json:"payload" db:"payload"`
	UpdatedAt int64                   `json:"updated_at" db:"updated_at"`
	MaxCalls  int                     `json:"max_calls" db:"max_calls"`
}
