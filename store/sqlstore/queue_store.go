package sqlstore

import (
	"database/sql"
	"fmt"
	"net/http"

	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
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
	query := `
		select
			q.id,
			q.type,
			q.domain_id,
			q.name as domain_name,
			q.name,
			q.strategy,
			q.payload,
			q.updated_at,
			q.variables,
			q.team_id,
			q.schema_id,
			q.ringtone_id,
			q.do_schema_id,
			q.after_schema_id,
			q.processing,
			q.processing_sec,
			q.processing_renewal_sec,
			q.grantee_id,
			q.form_schema_id,
			q.prolongation_enabled,
			q.prolongation_repeats_number,
			q.prolongation_time_sec,
			q.prolongation_is_timeout_retry,	
			f.mime_type as ringtone_type,
			(
				select
					jsonb_agg(row_to_json(qe))
				from
					call_center.cc_queue_events qe
				inner join
					flow.acr_routing_scheme s on s.id = qe.schema_id and q.domain_id = s.domain_id
				where
					qe.queue_id = q.id and qe.enabled
			) as hooks,
			coalesce(
				(q.payload->'endless')::bool, 
				false
			) as endless,
			case
				when fh.id notnull then jsonb_build_object(
					'id', fh.id, 
					'type', fh.mime_type
				)
			end as hold_music,
			case
				when (payload->'amd'->'playback'->>'id') notnull
				then jsonb_build_object(
					'id', amdpf.id,
					'type', amdpf.mime_type
				)
			end as amd_playback_file
		from
			call_center.cc_queue q
		inner join
			directory.wbt_domain d on q.domain_id = d.dc
		left join
			storage.media_files f on f.id = q.ringtone_id
		left join
			storage.media_files fh on fh.id = (q.payload->'hold'->'id')::int8
		left join
			storage.media_files amdpf on amdpf.id = (payload->'amd'->'playback'->>'id')::int8
		where
			q.id = :Id
	`

	args := map[string]any{
		"Id": id,
	}

	var queue *model.Queue
	if err := s.GetReplica().SelectOne(&queue, query, args); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlQueueStore.Get", "store.sql_queue.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlQueueStore.Get", "store.sql_queue.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	}
	return queue, nil
}

func (s SqlQueueStore) UserIds(queueId int, skipAgentId int) (model.Int64Array, *model.AppError) {
	var res model.Int64Array
	_, err := s.GetReplica().Select(&res, `select distinct a.user_id
from call_center.cc_queue q
    inner join call_center.cc_agent a on a.domain_id = q.domain_id
    inner join call_center.cc_queue_skill qs on qs.queue_id = q.id and qs.enabled
    inner join call_center.cc_skill_in_agent sia on sia.agent_id = a.id and sia.enabled
where q.id = :QueueId
	and a.id != :SkipAgentId
    and (q.team_id isnull or a.team_id = q.team_id)
    and qs.skill_id = sia.skill_id and sia.capacity between qs.min_capacity and qs.max_capacity
    and exists(select 1 from directory.wbt_user_presence p where p.user_id = a.user_id and p.status = 'web' and p.open > 0)`, map[string]interface{}{
		"QueueId":     queueId,
		"SkipAgentId": skipAgentId,
	})

	if err != nil {
		return nil, model.NewAppError("SqlQueueStore.UserIds", "store.sql_queue.users.app_error", nil,
			fmt.Sprintf("queue_id=%v, %s", queueId, err.Error()), http.StatusInternalServerError)
	}

	return model.Int64Array(res), nil
}
