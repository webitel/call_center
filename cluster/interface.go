package cluster

import "github.com/webitel/call_center/model"

type Cluster interface {
	Setup() *model.AppError
	Start()
	Stop()
}
