package sqlstore

import (
	_ "github.com/lib/pq"
	"github.com/webitel/call_center/store"

	"github.com/go-gorp/gorp"
)

type SqlStore interface {
	GetMaster() *gorp.DbMap
	GetReplica() *gorp.DbMap
	GetAllConns() []*gorp.DbMap

	Cluster() store.ClusterStore
	Queue() store.QueueStore
	Member() store.MemberStore
	OutboundResource() store.OutboundResourceStore
	Agent() store.AgentStore
	Team() store.TeamStore
	Gateway() store.GatewayStore
	Call() store.CallStore
}
