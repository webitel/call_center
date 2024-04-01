package model

type TaskToAgent struct {
	AttemptId      int64             `json:"attempt_id" db:"attempt_id"`
	Destination    []byte            `json:"destination" db:"destination"`
	Variables      map[string]string `json:"variables" db:"variables"`
	Name           string            `json:"name" db:"name"`
	TeamId         int               `json:"team_id" db:"team_id"`
	TeamUpdatedAt  int64             `json:"team_updated_at" db:"team_updated_at"`
	AgentUpdatedAt int64             `json:"agent_updated_at" db:"agent_updated_at"`
}
