package model

import "encoding/json"

type TaskToAgent struct {
	AttemptId      int64             `json:"attempt_id" db:"attempt_id"`
	Destination    []byte            `json:"destination" db:"destination"`
	Variables      map[string]string `json:"variables" db:"variables"`
	Name           string            `json:"name" db:"name"`
	TeamId         int               `json:"team_id" db:"team_id"`
	TeamUpdatedAt  int64             `json:"team_updated_at" db:"team_updated_at"`
	AgentUpdatedAt int64             `json:"agent_updated_at" db:"agent_updated_at"`
}

type QueueDumpParams struct {
	HasReporting         *bool  `json:"has_reporting,omitempty"`
	HasForm              *bool  `json:"has_form,omitempty"`
	ProcessingSec        uint32 `json:"processing_sec,omitempty"`
	ProcessingRenewalSec uint32 `json:"processing_renewal_sec,omitempty"`
	QueueName            string `json:"queue_name,omitempty"`
}

func (q *QueueDumpParams) ToJson() []byte {
	d, _ := json.Marshal(&q)
	if d == nil {
		return []byte("{}")
	}
	return d
}
