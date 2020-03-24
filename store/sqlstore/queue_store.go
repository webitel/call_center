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
	return us
}

func (s *SqlQueueStore) CreateIndexesIfNotExists() {

}

func (s SqlQueueStore) GetById(id int64) (*model.Queue, *model.AppError) {
	var queue *model.Queue
	if err := s.GetReplica().SelectOne(&queue, `
			select q.id,
       q.type,
       q.domain_id,
       d.name as domain_name,
       q.name,
       q.strategy,
       q.payload,
       q.updated_at,
       q.variables,
       q.timeout,
       q.team_id,
       q.schema_id
from cc_queue q
    inner join directory.wbt_domain d on q.domain_id = d.dc
where q.id = :Id		
		`, map[string]interface{}{"Id": id}); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlQueueStore.Get", "store.sql_queue.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlQueueStore.Get", "store.sql_queue.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	} else {
		return queue, nil
	}
}

func (s SqlQueueStore) RefreshStatisticsDay5Min() *model.AppError {
	_, err := s.GetMaster().Exec(`refresh materialized view cc_member_attempt_log_day_5min`)
	if err != nil {
		return model.NewAppError("SqlQueueStore.RefreshStatisticsDay5Min", "store.sql_queue.refresh_statistics.app_error",
			nil, err.Error(), http.StatusInternalServerError)
	}
	return nil
}
