package model

type OutboundResource struct {
	Id           int   `json:"id" db:"id"`
	Enabled      bool  `json:"enabled" db:"enabled"`
	UpdatedAt    int64 `json:"updated_at" db:"updated_at"`
	MaxCallCount int   `json:"max_call_count" db:"max_call_count"`
	Priority     int   `json:"priority" db:"priority"`
	Rps          int   `json:"rps" db:"rps"`
}
