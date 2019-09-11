package sqlstore

import (
	"github.com/webitel/call_center/discovery"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlClusterStore struct {
	SqlStore
}

func NewSqlClusterStore(sqlStore SqlStore) store.ClusterStore {
	cs := &SqlClusterStore{sqlStore}
	return cs
}

func (s *SqlClusterStore) CreateTableIfNotExists() {
}

func (s SqlClusterStore) CreateOrUpdate(nodeId string) (discovery.ClusterData, error) {
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
		return nil, model.NewAppError("SqlClusterStore.CreateOrUpdate", "store.sql_cluster.create_or_update.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return info, nil
	}
}

func (s SqlClusterStore) UpdateUpdatedTime(nodeId string) error {
	if _, err := s.GetMaster().Exec(`update cc_cluster
            set updated_at = :Time
            where node_name = :NodeId`, map[string]interface{}{"NodeId": nodeId, "Time": model.GetMillis()}); err != nil {
		return model.NewAppError("SqlClusterStore.UpdateUpdatedTime", "store.sql_cluster.update_updated_at.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	}
	return nil
}
