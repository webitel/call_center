package sqlstore

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
)

type SqlTriggerStore struct {
	SqlStore
}

func NewSqlTriggerStore(sqlStore SqlStore) store.TriggerStore {
	as := &SqlTriggerStore{sqlStore}
	return as
}

func (s SqlTriggerStore) ScheduleNewJobs() *model.AppError {
	_, err := s.GetMaster().Exec(`call call_center.cc_scheduler_jobs()`)

	if err != nil {
		return model.NewAppError("SqlTriggerStore.ScheduleNewJobs", "store.sql_trigger.schedule.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return nil
}

func (s SqlTriggerStore) FetchIdleJobs(node string, limit int) ([]model.TriggerJob, *model.AppError) {
	var jobs []model.TriggerJob
	_, err := s.GetMaster().Select(&jobs, `update call_center.cc_trigger_job j
set state = :StateActive,
    node_id = :NodeId,
    started_at = now()
from (
    select j.id, t.domain_id, format('%s [%s]%s', t.name, t.type, coalesce(' in ' || tz.name, '')) as name
    from call_center.cc_trigger_job j
		inner join call_center.cc_trigger t on t.id = j.trigger_id
		left join flow.calendar_timezones tz on tz.id = t.timezone_id
    where j.state = :StateIdle
    for update of j skip locked
    limit :Limit
) tj
where j.id = tj.id
returning j.id,
		tj.domain_id,
		tj.name,
        j.trigger_id,
        j.state,
        j.created_at,
        j.started_at,
        j.parameters`, map[string]interface{}{
		"NodeId":      node,
		"Limit":       limit,
		"StateActive": model.TriggerJobStateActive,
		"StateIdle":   model.TriggerJobStateIdle,
	})

	if err != nil {
		return nil, model.NewAppError("SqlTriggerStore.FetchIdleJobs", "store.sql_trigger.fetch_jobs.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return jobs, nil
}

func (s SqlTriggerStore) SetError(job *model.TriggerJob, jobErr error) *model.AppError {
	_, err := s.GetMaster().Exec(`update call_center.cc_trigger_job
set state = :StateError,
    stopped_at = now(),
    error = :Error,
    result = :Result
where id = :Id`, map[string]interface{}{
		"Id":         job.Id,
		"StateError": model.TriggerJobStateError,
		"Error":      jobErr.Error(),
		"Result":     job.ResultJson(),
	})

	if err != nil {
		return model.NewAppError("SqlTriggerStore.SetError", "store.sql_trigger.set_error.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return nil
}

func (s SqlTriggerStore) SetResult(job *model.TriggerJob) *model.AppError {
	_, err := s.GetMaster().Exec(`update call_center.cc_trigger_job
set state = :State,
    stopped_at = now(),
    result = :Result
where id = :Id`, map[string]interface{}{
		"Id":     job.Id,
		"State":  model.TriggerJobStateStop,
		"Result": job.ResultJson(),
	})

	if err != nil {
		return model.NewAppError("SqlTriggerStore.SetResult", "store.sql_trigger.set_result.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return nil
}

func (s SqlTriggerStore) CleanActive(nodeId string) *model.AppError {
	_, err := s.GetMaster().Exec(`update call_center.cc_trigger_job
set stopped_at = now(),
    error = 'stop server'
where node_id = :NodeId`, map[string]interface{}{
		"NodeId": nodeId,
	})

	if err != nil {
		return model.NewAppError("SqlTriggerStore.CleanActive", "store.sql_trigger.clean.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return nil
}
