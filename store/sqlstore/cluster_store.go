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

func (s SqlClusterStore) CreateOrUpdate(nodeId string) (*discovery.ClusterData, error) {
	var info *discovery.ClusterData
	if err := s.GetMaster().SelectOne(&info, `
           insert into cc_cluster (node_name, updated_at, master)
           values (:NodeId, :Time, false)
            on conflict (node_name)
              do update
               set updated_at = :Time,
                started_at = :Time,
                master = coalesce((select true
                 where not exists(select 1
                                  from cc_cluster c1
                                  where c1.master and to_timestamp((c1.updated_at::bigint/1000)::bigint) <= to_timestamp(:Time::bigint/1000) - '30s'::interval)), false)
            returning *`, map[string]interface{}{"NodeId": nodeId, "Time": model.GetMillis()}); err != nil {
		return nil, model.NewAppError("SqlClusterStore.CreateOrUpdate", "store.sql_cluster.create_or_update.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return info, nil
	}
}

func (s SqlClusterStore) UpdateClusterInfo(nodeId string, started bool) (*discovery.ClusterData, error) {
	var info *discovery.ClusterData
	if err := s.GetMaster().SelectOne(&info, `with u as (
    update cc_cluster c
         set updated_at = case when :NodeId = c.node_name then :Time else c.updated_at end,
             master = case when t.ms isnull then  t.rn = 1 else c.master end,
             started_at = case when :IsStarted then :Time else c.started_at end
    from (
        select c2.id,
               row_number() over (order by c2.updated_at desc) rn,
               c2.updated_at,
               (select 1 where exists(
                    select 1 from cc_cluster c3 where c3.master and to_timestamp(c3.updated_at/1000) > now() - '40 sec'::interval
               )) as ms
        from cc_cluster c2
    ) t
    where t.id = c.id
    returning c.*
)
select u.id, u.node_name, u.master, u.started_at, updated_at
from u
where u.node_name = :NodeId
`, map[string]interface{}{"NodeId": nodeId, "Time": model.GetMillis(), "IsStarted": started}); err != nil {
		return nil, model.NewAppError("SqlClusterStore.UpdateUpdatedTime", "store.sql_cluster.update_updated_at.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	}
	return info, nil
}
