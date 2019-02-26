package model

type ClusterInfo struct {
	Id        int64  `json:"id" db:"id"`
	NodeName  string `json:"node_name" db:"node_name"`
	UpdatedAt int64  `json:"updated_at" db:"updated_at"`
	Master    bool   `json:"master" db:"master"`
}
