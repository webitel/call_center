package sqlstore

import (
	"database/sql"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlQueueStore struct {
	SqlStore
}

func NewSqlQueueStore(sqlStore SqlStore) store.QueueStore {
	us := &SqlQueueStore{sqlStore}
	for _, db := range sqlStore.GetAllConns() {
		table := db.AddTableWithName(model.Queue{}, "cc_queue").SetKeys(true, "Id")
		table.ColMap("Id").SetUnique(true)
		table.ColMap("Type")
		table.ColMap("Name")
		table.ColMap("Strategy")
		table.ColMap("Payload")
		table.ColMap("UpdatedAt")
		table.ColMap("MaxCalls")
	}
	return us
}

func (s *SqlQueueStore) CreateIndexesIfNotExists() {

}

func (s SqlQueueStore) GetById(id int) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var queue *model.Queue
		if err := s.GetReplica().SelectOne(&queue, `
			select id, type, name, strategy, payload, updated_at, max_calls from cc_queue where id = :Id		
		`, map[string]interface{}{"Id": id}); err != nil {
			if err == sql.ErrNoRows {
				result.Err = model.NewAppError("SqlQueueStore.Get", "store.sql_queue.get.app_error", nil,
					fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
			} else {
				result.Err = model.NewAppError("SqlQueueStore.Get", "store.sql_queue.get.app_error", nil,
					fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
			}
		} else {
			result.Data = queue
		}
	})
}
