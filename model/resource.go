package model

type OutboundResource struct {
	Id           int   `json:"id"`
	Enabled      bool  `json:"enabled"`
	UpdatedAt    int64 `db:"updated_at" json:"updated_at"`
	MaxCallCount int   `db:"max_call_count" json:"max_call_count"`
	Priority     int   `json:"priority"`
	Rps          int   `json:"rps"`
}
