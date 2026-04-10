package model

type InboundIMQueue struct {
	AttemptId           int64             `json:"attempt_id" db:"attempt_id"`
	QueueId             int               `json:"queue_id" db:"queue_id"`
	QueueUpdatedAt      int64             `json:"queue_updated_at" db:"queue_updated_at"`
	Destination         []byte            `json:"destination" db:"destination"`
	Variables           map[string]string `json:"variables" db:"variables"`
	Name                string            `json:"name" db:"name"`
	TeamUpdatedAt       *int64            `json:"team_updated_at" db:"team_updated_at"`
	ListCommunicationId *int64            `json:"list_communication_id" db:"list_communication_id"`

	ThreadId        string `json:"thread_id" db:"thread_id"`
	ThreadCreatedAt int64  `json:"thread_created_at" db:"thread_created_at"`
}
