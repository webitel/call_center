package discovery

import "time"

func NewServiceDiscovery(id, addr string, check CheckFunction) (ServiceDiscovery, error) {
	return NewConsul(id, addr, check)
}

type ClusterStore interface {
	//CreateOrUpdate(nodeId string) (*ClusterData, error)
	//UpdateUpdatedTime(nodeId string) (*ClusterData, error)
	UpdateClusterInfo(nodeId string, started bool) (*ClusterData, error)
}

type ClusterData struct {
	Id        int64  `json:"id" db:"id"`
	NodeName  string `json:"node_name" db:"node_name"`
	Master    bool   `json:"master" db:"master"`
	UpdatedAt int64  `json:"updated_at" db:"updated_at"`
	StartedAt int64  `json:"started_at" db:"started_at"`
}

type ServiceDiscovery interface {
	RegisterService(name string, pubHost string, pubPort int, ttl, criticalTtl time.Duration) error
	Shutdown()
	GetByName(serviceName string) ([]*ServiceConnection, error)
}
