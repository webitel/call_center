package model

type OutboundResource struct {
	Id                    int                    `json:"id" db:"id"`
	Enabled               bool                   `json:"enabled" db:"enabled"`
	UpdatedAt             int64                  `json:"updated_at" db:"updated_at"`
	Limit                 int                    `json:"limit" db:"limit"`
	Priority              int                    `json:"priority" db:"priority"`
	Rps                   int                    `json:"rps" db:"rps"`
	Reserve               bool                   `json:"reserve" db:"reserve"`
	Variables             map[string]interface{} `json:"variables" db:"variables"`
	Number                string                 `json:"number" dbs:"number"`
	MaxSuccessivelyErrors int                    `json:"max_successively_errors" db:"max_successively_errors"`
}

func (resource *OutboundResource) IsValid() *AppError {
	return nil
}
