package model

import "encoding/json"

type OutboundResource struct {
	Id                    int                    `json:"id" db:"id"`
	Name                  string                 `json:"name" db:"name"`
	Enabled               bool                   `json:"enabled" db:"enabled"`
	Limit                 int                    `json:"limit" db:"limit"`
	Priority              int                    `json:"priority" db:"priority"`
	Rps                   int                    `json:"rps" db:"rps"`
	Reserve               bool                   `json:"reserve" db:"reserve"`
	UpdatedAt             int64                  `json:"updated_at,omitempty" db:"updated_at"`
	Variables             map[string]interface{} `json:"variables,omitempty" db:"variables"`
	Number                string                 `json:"number,omitempty" db:"number"`
	MaxSuccessivelyErrors int                    `json:"max_successively_errors" db:"max_successively_errors"`
}

func (resource *OutboundResource) IsValid() *AppError {
	return nil
}

func OutboundResourcesToJson(resources []*OutboundResource) string {
	b, _ := json.Marshal(resources)
	return string(b)
}

func (r *OutboundResource) ToJson() string {
	b, _ := json.Marshal(r)
	return string(b)
}
