package model

import (
	"encoding/json"
	"io"
	"net/http"
)

type OutboundResource struct {
	Id                    int                    `json:"id" db:"id"`
	Name                  string                 `json:"name" db:"name"`
	Enabled               bool                   `json:"enabled" db:"enabled"`
	Limit                 uint16                 `json:"limit" db:"limit"`
	Rps                   uint16                 `json:"rps" db:"rps"`
	Reserve               bool                   `json:"reserve" db:"reserve"`
	UpdatedAt             int64                  `json:"updated_at,omitempty" db:"updated_at"`
	Variables             map[string]interface{} `json:"variables,omitempty" db:"variables"`
	DialString            string                 `json:"dial_string" db:"dial_string"`
	Number                string                 `json:"number,omitempty" db:"number"`
	MaxSuccessivelyErrors uint16                 `json:"max_successively_errors" db:"max_successively_errors"`
}

func (resource *OutboundResource) IsValid() *AppError {
	if len(resource.Name) <= 3 {
		return NewAppError("OutboundResource.IsValid", "model.outbound_resource.is_valid.name.app_error", nil, "name="+resource.Name, http.StatusBadRequest)
	}
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

func OutboundResourceFromJson(data io.Reader) *OutboundResource {
	var resource OutboundResource
	if err := json.NewDecoder(data).Decode(&resource); err != nil {
		return nil
	} else {
		return &resource
	}
}
