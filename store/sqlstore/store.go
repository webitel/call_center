package sqlstore

import (
	_ "github.com/lib/pq"

	"github.com/go-gorp/gorp"
	"github.com/webitel/call_center/store"
)

type SqlStore interface {
	GetMaster() *gorp.DbMap
	GetReplica() *gorp.DbMap
	GetAllConns() []*gorp.DbMap

	Session() store.SessionStore
	Calendar() store.CalendarStore
	Queue() store.QueueStore
	Agent() store.AgentStore
}
