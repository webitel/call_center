package sqlstore

import (
	"database/sql"
	"fmt"
	"github.com/lib/pq"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlAgentStore struct {
	SqlStore
}

func NewSqlAgentStore(sqlStore SqlStore) store.AgentStore {
	as := &SqlAgentStore{sqlStore}
	return as
}

func (s *SqlAgentStore) CreateTableIfNotExists() {
}

func (s SqlAgentStore) ReservedForAttemptByNode(nodeId string) ([]*model.AgentsForAttempt, *model.AppError) {
	var agentsInAttempt []*model.AgentsForAttempt
	if _, err := s.GetMaster().Select(&agentsInAttempt, `update call_center.cc_member_attempt a
set state = :Active
from (
	select a.id as attempt_id, a.agent_id, (ca.updated_at - extract(epoch from u.updated_at))::int8 as agent_updated_at, a.team_id, team.updated_at as team_updated_at
	from call_center.cc_member_attempt a
		inner join call_center.cc_agent ca on a.agent_id = ca.id
		inner join call_center.cc_team team on team.id = a.team_id
		inner join directory.wbt_user u on u.id = ca.user_id
	where a.state = :WaitAgent and a.agent_id notnull and a.node_id = :Node
	for update skip locked
) t
where a.id = t.attempt_id
returning t.*`, map[string]interface{}{
		"Node":      nodeId,
		"Active":    model.MemberStateActive,
		"WaitAgent": model.MemberStateWaitAgent,
	}); err != nil {
		return nil, model.NewAppError("SqlAgentStore.ReservedForAttemptByNode", "store.sql_agent.reserved_for_attempt.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return agentsInAttempt, nil
	}
}

func (s SqlAgentStore) Get(id int) (*model.Agent, *model.AppError) {
	var agent *model.Agent
	if err := s.GetReplica().SelectOne(&agent, `select a.id,
       a.user_id,
       a.domain_id,
       (a.updated_at - extract(epoch from u.updated_at))::int8 as  updated_at,
       coalesce((u.name)::varchar, u.username)                                                   as name,
       'sofia/sip/' || u.extension || '@' || d.name                                              as destination,
       u.extension,
       a.status,
       a.status_payload,
       a.on_demand,
       case when g.id notnull then json_build_object('id', g.id, 'type', g.mime_type)::jsonb end as greeting_media,
       a.team_id,
       team.updated_at                                                                           as team_updated_at,
       coalesce(push.config, '{}') variables,
       push.config notnull has_push
from call_center.cc_agent a
         inner join directory.wbt_user u on u.id = a.user_id
         inner join directory.wbt_domain d on d.dc = a.domain_id
         inner join call_center.cc_team team on team.id = a.team_id
         left join storage.media_files g on g.id = a.greeting_media_id
left join lateral ( select jsonb_object(array_agg(key), array_agg(val)) as push
			from (SELECT case
							 when s.props ->> 'pn-type'::text = 'fcm' then 'wbt_push_fcm'
							 else 'wbt_push_apn' end                                            as key,
						 array_to_string(array_agg(DISTINCT s.props ->> 'pn-rpid'::text), '::') as val
				  FROM directory.wbt_session s
				  WHERE s.user_id IS NOT NULL
					AND s.access notnull
					AND NULLIF(s.props ->> 'pn-rpid'::text, ''::text) IS NOT NULL
					AND s.user_id = a.user_id
					and s.props ->> 'pn-type'::text in ('fcm', 'apns')
					AND now() at time zone 'UTC' < s.expires
				  group by s.props ->> 'pn-type'::text = 'fcm') t
			where key notnull
			  and val notnull) push(config) ON true
where a.id = :Id	
		`, map[string]interface{}{"Id": id}); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlAgentStore.Get", "store.sql_agent.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlAgentStore.Get", "store.sql_agent.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	} else {
		return agent, nil
	}
}

func (s SqlAgentStore) ConfirmAttempt(agentId int, attemptId int64) ([]string, *model.AppError) {

	var res []string

	_, err := s.GetMaster().Select(&res, `select cnt from call_center.cc_confirm_agent_attempt(:AgentId, :AttemptId) cnt`,
		map[string]interface{}{"AgentId": agentId, "AttemptId": attemptId})

	if err != nil {
		return nil, model.NewAppError("SqlAgentStore.ConfirmAttempt", "store.sql_agent.confirm_attempt.app_error", nil,
			fmt.Sprintf("AgenetId=%v, AttemptId=%v, %s", agentId, attemptId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil
}

func (s SqlAgentStore) MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError {
	_, err := s.GetMaster().Exec(`insert into call_center.cc_agent_missed_attempt (attempt_id, agent_id, cause) 
  values (:AttemptId, :AgentId, :Cause)`, map[string]interface{}{
		"AttemptId": attemptId,
		"AgentId":   agentId,
		"Cause":     cause,
	})

	if err != nil {
		return model.NewAppError("SqlAgentStore.MissedAttempt", "store.sql_agent.missed_attempt.app_error", nil,
			fmt.Sprintf("AgenetId=%v, AttemptId=%v, %s", agentId, attemptId, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) RefreshEndStateDay5Min() *model.AppError {
	_, err := s.GetMaster().Exec(`refresh materialized view call_center.cc_agent_end_state_day_5min`)
	if err != nil {
		return model.NewAppError("SqlAgentStore.RefreshEndStateDay5Min", "store.sql_queue.refresh_state_5min.app_error",
			nil, err.Error(), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetOnline(agentId int, onDemand bool) (*model.AgentOnlineData, *model.AppError) {
	var data *model.AgentOnlineData

	err := s.GetMaster().SelectOne(&data, `select timestamp, channel
		from call_center.cc_agent_set_login(:AgentId, :OnDemand) channels  (channel jsonb, timestamp int8)`,
		map[string]interface{}{
			"AgentId":  agentId,
			"OnDemand": onDemand,
		})

	if err != nil {
		return nil, model.NewAppError("SqlAgentStore.SetOnline", "store.sql_agent.set_online.app_error", nil,
			fmt.Sprintf("AgenetId=%v, Status=%v, %s", agentId, model.AgentStatusOnline, err.Error()), http.StatusInternalServerError)
	}

	return data, nil
}

func (s SqlAgentStore) SetStatus(agentId int, status string, payload *string) *model.AppError {
	if _, err := s.GetMaster().Exec(`with ag as (
	update call_center.cc_agent
			set status = :Status,
  			status_payload = :Payload,
			last_state_change = now()
    where id = :AgentId
		and not exists(select 1 from call_center.cc_member_attempt att where att.agent_id = call_center.cc_agent.id and att.state = 'wait_agent' for update )
    returning id
)
update call_center.cc_agent_channel c
 set online = false
from ag 
where c.agent_id = ag.id`, map[string]interface{}{
		"AgentId": agentId,
		"Status":  status,
		"Payload": payload,
	}); err != nil {
		return model.NewAppError("SqlAgentStore.SetStatus", "store.sql_agent.set_status.app_error", nil,
			fmt.Sprintf("AgenetId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) CheckAllowPause(domainId int64, agentId int) (bool, *model.AppError) {
	var res bool
	err := s.GetMaster().SelectOne(&res, `select exists(SELECT 1
FROM call_center.cc_agent a_1
    JOIN call_center.cc_queue q_1 ON q_1.domain_id = a_1.domain_id
    inner join lateral (
        SELECT array_agg(distinct csia.agent_id) xxx
          FROM call_center.cc_queue_skill qs
            JOIN call_center.cc_skill_in_agent csia ON csia.skill_id = qs.skill_id
            join call_center.cc_agent aa on aa.id = csia.agent_id
          WHERE qs.enabled
            AND csia.enabled
            AND qs.queue_id = q_1.id
            AND csia.capacity >= qs.min_capacity
            AND csia.capacity <= qs.max_capacity
            and (aa.status = 'online' or (aa.id = :AgentId::int and aa.status = 'offline') )
    ) x on true
WHERE (q_1.team_id IS NULL OR a_1.team_id = q_1.team_id)
  and q_1.enabled
  and x.xxx && array [a_1.id]
  and GREATEST(coalesce((q_1.payload->'min_online_agents')::int, 0), 0) > 0
  and array_length(x.xxx, 1) <= GREATEST((q_1.payload->'min_online_agents')::int, 0)
  and a_1.id = :AgentId::int
  and a_1.domain_id = :DomainId::int8)`, map[string]interface{}{
		"AgentId":  agentId,
		"DomainId": domainId,
	})

	if err != nil {
		return false, model.NewAppError("SqlAgentStore.CheckAllowPause", "store.sql_agent.check_status.app_error", nil,
			fmt.Sprintf("AgenetId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
	}

	return !res, nil
}

func (s SqlAgentStore) GetNoAnswerChannels(agentId int, queueTypes []int) ([]*model.CallNoAnswer, *model.AppError) {
	var res []*model.CallNoAnswer
	_, err := s.GetMaster().Select(&res, `select c.id, c.app_id
from call_center.cc_member_attempt at
         left join call_center.cc_queue q on q.id = at.queue_id
         left join call_center.cc_calls c
                   on case when q.type = 4 then c.id::text = at.member_call_id else c.id::text = at.agent_call_id end
where at.agent_id = :AgentId
  and c.answered_at isnull
  and c.id notnull
  and (:QueueTypes::smallint[] isnull or q.type = any(:QueueTypes::smallint[]))`, map[string]interface{}{
		"AgentId":    agentId,
		"QueueTypes": pq.Array(queueTypes),
	})

	if err != nil {
		return nil, model.NewAppError("SqlAgentStore.GetNoAnswerChannels", "store.sql_agent.get_no_answer.app_error", nil,
			fmt.Sprintf("AgenetId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
	}

	return res, nil
}

func (s SqlAgentStore) WaitingChannel(agentId int, channel string) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`select call_center.cc_view_timestamp(joined_at) as timestamp
from call_center.cc_agent_set_channel_waiting(:AgentId, :Channel) as (joined_at timestamptz)`, map[string]interface{}{
		"AgentId": agentId,
		"Channel": channel,
	})

	if err != nil {
		return 0, model.NewAppError("SqlAgentStore.WaitingChannel", "store.sql_agent.waiting_channel.app_error", nil,
			fmt.Sprintf("AgenetId=%v, Channel=%v %s", agentId, channel, err.Error()), http.StatusInternalServerError)
	}

	if timestamp == 0 {
		return 0, model.NewAppError("SqlAgentStore.WaitingChannel", "store.sql_agent.waiting_channel.app_error", nil,
			fmt.Sprintf("AgenetId=%v, Channel=%v not allowed", agentId, channel), http.StatusBadRequest)
	}

	return timestamp, nil
}

func (s SqlAgentStore) SetOnBreak(agentId int) *model.AppError {
	_, err := s.GetMaster().Exec(`update call_center.cc_agent
set status = :Status,
	last_status_change = now()
where id = :Id`, map[string]interface{}{
		"Id":     agentId,
		"Status": model.AgentStatusPause,
	})
	if err != nil {
		return model.NewAppError("SqlAgentStore.SetOnBreak", "store.sql_agent.set_break.app_error", nil,
			fmt.Sprintf("AgenetId=%v, Status=%v State=%v, %s", agentId, model.AgentStatusPause, model.AGENT_STATE_WAITING,
				err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s SqlAgentStore) CreateMissed(missed *model.MissedAgentAttempt) *model.AppError {
	_, err := s.GetMaster().Exec(`insert into call_center.cc_agent_missed_attempt (attempt_id, agent_id, cause, missed_at)
values (:AttemptId, :AgentId, :Cause, :MissedAt)`, map[string]interface{}{
		"AttemptId": missed.AttemptId,
		"AgentId":   missed.AgentId,
		"Cause":     missed.Cause,
		"MissedAt":  missed.MissedAt,
	})

	if err != nil {
		return model.NewAppError("SqlAgentStore.CreateMissed", "store.sql_agent.create_missed.app_error", nil,
			fmt.Sprintf("AttemptId=%v, AgentId=%v %s", missed.AttemptId, missed.AgentId, err.Error()), http.StatusInternalServerError)
	}

	return nil
}

func (s SqlAgentStore) GetChannelTimeout() ([]*model.ChannelTimeout, *model.AppError) {
	var channels []*model.ChannelTimeout
	_, err := s.GetMaster().Select(&channels, `update call_center.cc_agent_channel c
	set state = 'waiting',
		timeout = null,
		joined_at = now()
	from call_center.cc_agent a
	where c.timeout < now() and a.id = c.agent_id
returning a.user_id, channel, call_center.cc_view_timestamp(joined_at) as timestamp, a.domain_id`)

	if err != nil {
		return nil, model.NewAppError("SqlAgentStore.GetChannelTimeout", "store.sql_agent.channel_timeout.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return channels, nil
}

func (s SqlAgentStore) RefreshAgentPauseCauses() *model.AppError {
	_, err := s.GetMaster().Exec(`refresh materialized view CONCURRENTLY call_center.cc_agent_today_pause_cause`)

	if err != nil {
		return model.NewAppError("SqlAgentStore.RefreshAgentPauseCauses", "store.sql_agent.refresh_pause_cause.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (s SqlAgentStore) RefreshAgentStatistics() *model.AppError {
	_, err := s.GetMaster().Exec(`refresh materialized view CONCURRENTLY call_center.cc_agent_today_stats`)

	if err != nil {
		return model.NewAppError("SqlAgentStore.RefreshAgentStatistics", "store.sql_agent.refresh_statistics.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}

// todo need index
func (s SqlAgentStore) OnlineWithOutActive(sec int) ([]model.AgentHashKey, *model.AppError) {
	var res []model.AgentHashKey
	_, err := s.GetMaster().Select(&res, `select a.id, a.updated_at
from call_center.cc_agent a
where a.status in ('online', 'break_out')
    and not exists(SELECT 1
        FROM directory.wbt_session s
        WHERE ((user_id IS NOT NULL) AND (NULLIF((props ->> 'pn-rpid'::text), ''::text) IS NOT NULL))
            and s.user_id = a.user_id::int8
            and s.access notnull
            AND s.expires > now() at time zone 'UTC')

    and not exists(
        select 1
        from directory.wbt_user_presence p
            where p.user_id = a.user_id
                and p.status in ('sip', 'web')
                and (
                    p.open > 0
                    or (p.status = 'web' and p.updated_at >= now() at time zone 'UTC' - (:Sec || ' sec')::interval)
                )
    )
for update skip locked`, map[string]interface{}{
		"Sec": sec,
	})

	if err != nil {
		return nil, model.NewAppError("SqlAgentStore.OnlineWithOutActiveSock", "store.sql_agent.find_active.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return res, nil
}

func (s SqlAgentStore) LosePredictAttempt(id int) *model.AppError {
	_, err := s.GetMaster().Exec(`update call_center.cc_agent_channel
set lose_attempt = lose_attempt + 1
where agent_id = :AgentId and state != 'waiting'`, map[string]interface{}{
		"AgentId": id,
	})

	if err != nil {
		return model.NewAppError("SqlAgentStore.LosePredictAttempt", "store.sql_agent.lose_predict.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}
