package sqlstore

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlClusterStore struct {
	SqlStore
}

func NewSqlClusterStore(sqlStore SqlStore) store.ClusterStore {
	cs := &SqlClusterStore{sqlStore}
	for _, db := range sqlStore.GetAllConns() {
		table := db.AddTableWithName(model.ClusterInfo{}, "cc_cluster").SetKeys(true, "Id")
		table.ColMap("Id").SetUnique(true)
		table.ColMap("NodeName").SetNotNull(true).SetMaxSize(20)
		table.ColMap("UpdatedAt").SetNotNull(true)
		table.ColMap("Master").SetNotNull(true)
	}

	return cs
}

func (s SqlClusterStore) CreateOrUpdate(nodeId string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var info *model.ClusterInfo
		if err := s.GetMaster().SelectOne(&info, `
           insert into cc_cluster (node_name, updated_at, master)
           values (:NodeId, :Time, false)
            on conflict (node_name)
              do update
               set updated_at = :Time,
                started_at = :Time,
                master = false
            returning *`, map[string]interface{}{"NodeId": nodeId, "Time": model.GetMillis()}); err != nil {
			result.Err = model.NewAppError("SqlClusterStore.CreateOrUpdate", "store.sql_cluster.create_or_update.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = info
		}
	})
}

func (s SqlClusterStore) UpdateUpdatedTime(nodeId string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`update cc_cluster
            set updated_at = :Time
            where node_name = :NodeId`, map[string]interface{}{"NodeId": nodeId, "Time": model.GetMillis()}); err != nil {
			result.Err = model.NewAppError("SqlClusterStore.UpdateUpdatedTime", "store.sql_cluster.update_updated_at.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		}
	})
}
