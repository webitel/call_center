package sqlstore

import (
	"context"

	_ "github.com/lib/pq"
	"github.com/webitel/call_center/store"

	"github.com/go-gorp/gorp"
)

type SqlStore interface {
	GetMaster() *gorp.DbMap
	GetReplica() *gorp.DbMap
	GetAllConns() []*gorp.DbMap
	// WithTransaction runs fn in a master transaction bound to ctx.
	WithTransaction(ctx context.Context, fn func(ex gorp.SqlExecutor) error) error

	Cluster() store.ClusterStore
	Queue() store.QueueStore
	Member() store.MemberStore
	OutboundResource() store.OutboundResourceStore
	Agent() store.AgentStore
	Team() store.TeamStore
	Gateway() store.GatewayStore
	Call() store.CallStore
	Statistic() store.StatisticStore
}
