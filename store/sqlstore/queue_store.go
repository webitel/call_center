package sqlstore

import (
	"github.com/webitel/call_center/store"
)

type SqlQueueStore struct {
	SqlStore
}

func NewSqlQueueStore(sqlStore SqlStore) store.QueueStore {
	us := &SqlQueueStore{sqlStore}
	return us
}

func (self *SqlQueueStore) CreateIndexesIfNotExists() {

}
