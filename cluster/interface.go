package cluster

import "github.com/webitel/call_center/model"

type Cluster interface {
	Setup() *model.AppError
	Start()
	Stop()

	ServiceDiscovery() ServiceDiscovery
}

type ServiceDiscovery interface {
	RegisterService() *model.AppError
	Shutdown()

	GetByName(serviceName string) ([]*model.ServiceConnection, *model.AppError)
}
