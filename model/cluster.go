package model

const (
	CLUSTER_CALL_SERVICE_NAME = "freeswitch"
)

type ClusterInfo struct {
	Id        int64  `json:"id" db:"id"`
	NodeName  string `json:"node_name" db:"node_name"`
	StartedAt int64  `json:"started_at" db:"started_at"`
	UpdatedAt int64  `json:"updated_at" db:"updated_at"`
	Master    bool   `json:"master" db:"master"`
}
