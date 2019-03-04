package model

const (
	QUEUE_TYPE_INBOUND = iota
	QUEUE_TYPE_VOICE_BROADCAST
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
