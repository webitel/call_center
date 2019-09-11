package discovery

import "time"

func NewServiceDiscovery(id, addr string, check CheckFunction) (ServiceDiscovery, error) {
	return NewConsul(id, addr, check)
}

type ClusterStore interface {
	CreateOrUpdate(nodeId string) (ClusterData, error)
	UpdateUpdatedTime(nodeId string) error
}

type ClusterData interface {
}

type ServiceDiscovery interface {
	RegisterService(name string, pubHost string, pubPort int, ttl, criticalTtl time.Duration) error
	Shutdown()
	GetByName(serviceName string) ([]*ServiceConnection, error)
}
