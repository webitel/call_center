package model

type Queue struct {
	Id        int                     `json:"id" db:"id"`
	Type      int                     `json:"type" db:"type"`
	Strategy  string                  `json:"strategy" db:"strategy"`
	Payload   *map[string]interface{} `json:"payload" db:"payload"`
	UpdatedAt int64                   `json:"updated_at" db:"updated_at"`
	MaxCalls  int                     `json:"max_calls" db:"max_calls"`
}
