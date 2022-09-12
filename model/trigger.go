package model

import (
	"encoding/json"
	"time"
)

const (
	TriggerJobStateIdle = iota
	TriggerJobStateActive
	TriggerJobStateStop
	TriggerJobStateError
)

type TriggerJobParameter struct {
	SchemaId  uint32                 `json:"schema_id" db:"schema_id"`
	Variables map[string]interface{} `json:"variables" db:"variables"`
	Timeout   uint64                 `json:"timeout" db:"timeout"`
}

type TriggerJob struct {
	Name       string              `json:"name" db:"name"`
	Id         int64               `json:"id" db:"id"`
	DomainId   int64               `json:"domain_id" db:"domain_id"`
	TriggerId  int                 `json:"trigger_id" db:"trigger_id"`
	State      int                 `json:"state" db:"state"`
	CreatedAt  *time.Time          `json:"created_at" db:"created_at"`
	StartedAt  *time.Time          `json:"started_at" db:"started_at"`
	StoppedAt  *time.Time          `json:"stopped_at" db:"stopped_at"`
	Parameters TriggerJobParameter `json:"parameters" db:"parameters"`
	Error      *string             `json:"error" db:"error"`
	Result     interface{}         `json:"result" db:"result"`
}

func (j *TriggerJob) ResultJson() []byte {
	if j.Result == nil {
		return nil
	}
	data, _ := json.Marshal(j.Result)
	return data
}
