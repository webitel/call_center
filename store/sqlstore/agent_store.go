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
	if _, err := s.GetMaster().Select(&agentsInAttempt, `update cc_member_attempt a
set state = 4
from (
    select a.id as attempt_id, a.agent_id, ca.updated_at as agent_updated_at
    from cc_member_attempt a
        inner join cc_agent ca on a.agent_id = ca.id
    where a.state = 3 and a.agent_id notnull and a.node_id = :Node
    for update skip locked
) t
where a.id = t.attempt_id
returning t.*`, map[string]interface{}{
		"Node": nodeId,
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
	if err := s.GetReplica().SelectOne(&agent, `
			select a.id, a.user_id, a.domain_id, a.updated_at, coalesce( (u.name)::varchar, u.username) as name, 'sofia/sip/' || u.extension || '@' || d.name as destination, 
			u.extension, a.status, a.status_payload, a.successively_no_answers
from cc_agent a
    inner join directory.wbt_user u on u.id = a.user_id
    inner join directory.wbt_domain d on d.dc = a.domain_id
where a.id = :Id and u.extension notnull		
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

//TODO deprecated
func (s SqlAgentStore) ChangeDeadlineState() ([]*model.AgentChangedState, *model.AppError) {
	var times []*model.AgentChangedState
	if _, err := s.GetMaster().Select(&times, `select *
	from cc_agent_state_timeout()
    as (cur_time  int8, agent_id int, agent_updated_at int8, state varchar)`, map[string]interface{}{}); err != nil {
		return nil, model.NewAppError("SqlAgentStore.ChangeDeadlineState", "store.sql_agent.set_deadline_state.app_error", nil,
			fmt.Sprintf("%s", err.Error()), http.StatusInternalServerError)
	} else {
		return times, nil
	}
}

func (s SqlAgentStore) SaveActivityCallStatistic(agentId int, offeringAt, answerAt, bridgeStartAt, bridgeStopAt int64, nowAnswer bool) (int, *model.AppError) {
	cnt, err := s.GetMaster().SelectInt(`with ag as (
  select a.id as agent_id, a.max_no_answer, caa.successively_no_answers, (a.max_no_answer > 0 and a.max_no_answer > caa.successively_no_answers + 1) next_call
  from cc_agent a
    inner join cc_agent_activity caa on a.id = caa.agent_id
  where a.id = :AgentId
)
update cc_agent_activity a
set last_offering_call_at = :OfferingAt,
    last_answer_at = case when :AnswerAt = 0::bigint then last_answer_at else :AnswerAt end,
    last_bridge_start_at = case when :BridgedStartAt = 0::bigint then last_bridge_start_at else :BridgedStartAt end,
    last_bridge_end_at = case when :BridgedStopAt = 0::bigint then last_bridge_end_at else :BridgedStopAt end,
    calls_abandoned = case when :AnswerAt = 0::bigint then calls_abandoned + 1 else calls_abandoned end,
    calls_answered = case when :AnswerAt != 0::bigint then calls_answered + 1 else calls_answered end,
    successively_no_answers = case when :NoAnswer and ag.next_call is true then a.successively_no_answers + 1 else 0 end
from ag
where a.agent_id = ag.agent_id
returning case when :NoAnswer and ag.max_no_answer > 0 and ag.next_call is false then 1 else 0 end stopped`, map[string]interface{}{"AgentId": agentId, "OfferingAt": offeringAt, "AnswerAt": answerAt, "BridgedStartAt": bridgeStartAt, "BridgedStopAt": bridgeStopAt, "NoAnswer": nowAnswer})
	if err != nil {
		return 0, model.NewAppError("SqlAgentStore.SaveActivityCallStatistic", "store.sql_agent.save_call_activity.app_error", nil,
			fmt.Sprintf("AgentId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
	} else {
		return int(cnt), nil
	}
}

func (s SqlAgentStore) ConfirmAttempt(agentId int, attemptId int64) (int, *model.AppError) {
	cnt, err := s.GetMaster().SelectInt(`select cnt from cc_confirm_agent_attempt(:AgentId, :AttemptId) cnt`,
		map[string]interface{}{"AgentId": agentId, "AttemptId": attemptId})

	if err != nil {
		return 0, model.NewAppError("SqlAgentStore.ConfirmAttempt", "store.sql_agent.confirm_attempt.app_error", nil,
			fmt.Sprintf("AgenetId=%v, AttemptId=%v, %s", agentId, attemptId, err.Error()), http.StatusInternalServerError)
	}

	return int(cnt), nil
}

func (s SqlAgentStore) MissedAttempt(agentId int, attemptId int64, cause string) *model.AppError {
	_, err := s.GetMaster().Exec(`insert into cc_agent_missed_attempt (attempt_id, agent_id, cause) 
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
	_, err := s.GetMaster().Exec(`refresh materialized view cc_agent_end_state_day_5min`)
	if err != nil {
		return model.NewAppError("SqlAgentStore.RefreshEndStateDay5Min", "store.sql_queue.refresh_state_5min.app_error",
			nil, err.Error(), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetWaiting(agentId int, bridged bool) *model.AppError {
	_, err := s.GetMaster().Exec(`update cc_agent
set state = :State,
    last_state_change = now(),
    last_bridge_end_at = case when :Bridged is true then now() else last_bridge_end_at end,
	state_timeout = null,
	active_queue_id = null,
	attempt_id = null
where id = :Id`, map[string]interface{}{
		"State":   model.AGENT_STATE_WAITING,
		"Id":      agentId,
		"Bridged": bridged,
	})
	if err != nil {
		return model.NewAppError("SqlAgentStore.SetOffering", "store.sql_agent.set_waiting.app_error", nil,
			fmt.Sprintf("AgenetId=%v, State=%v, %s", agentId, model.AGENT_STATE_WAITING, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetOffering(agentId, queueId int, attemptId int64) (int, *model.AppError) {
	successivelyNoAnswers, err := s.GetMaster().SelectInt(`update cc_agent
			set state = :State,
				last_offering_at = now(),
				last_state_change = now(),
				active_queue_id = :QueueId,
				attempt_id = :AttemptId
			where id = :Id
			returning successively_no_answers`, map[string]interface{}{
		"State":     model.AGENT_STATE_OFFERING,
		"AttemptId": attemptId,
		"Id":        agentId,
		"QueueId":   queueId,
	})
	if err != nil {
		return 0, model.NewAppError("SqlAgentStore.SetOffering", "store.sql_agent.set_offering.app_error", nil,
			fmt.Sprintf("AgenetId=%v, State=%v, %s", agentId, model.AGENT_STATE_OFFERING, err.Error()), http.StatusInternalServerError)
	}
	return int(successivelyNoAnswers), nil
}

func (s SqlAgentStore) SetTalking(agentId int) *model.AppError {
	_, err := s.GetMaster().Exec(`update cc_agent
		set state = :State,
			last_state_change = now(),
			last_bridge_start_at = now(),
		    state_timeout = null
		where id = :Id`, map[string]interface{}{
		"State": model.AGENT_STATE_TALK,
		"Id":    agentId,
	})
	if err != nil {
		return model.NewAppError("SqlAgentStore.SetTalking", "store.sql_agent.set_talking.app_error", nil,
			fmt.Sprintf("AgenetId=%v, State=%v, %s", agentId, model.AGENT_STATE_TALK, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetReporting(agentId int, timeout int) *model.AppError {
	_, err := s.GetMaster().Exec(`update cc_agent
set state = :State,
    last_state_change = now(),
	successively_no_answers = 0,
    state_timeout = case when :Timeout > 0 then now() + (:Timeout || ' sec')::interval else null end
where id = :Id`, map[string]interface{}{
		"State":   model.AGENT_STATE_REPORTING,
		"Timeout": timeout,
		"Id":      agentId,
	})
	if err != nil {
		return model.NewAppError("SqlAgentStore.SetReporting", "store.sql_agent.set_reporting.app_error", nil,
			fmt.Sprintf("AgenetId=%v, State=%v, %s", agentId, model.AGENT_STATE_REPORTING, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetFine(agentId int, timeout int, noAnswer bool) *model.AppError {
	_, err := s.GetMaster().Exec(`update cc_agent
set state = :State,
    last_state_change = now(),
	successively_no_answers = case when :NoAnswer is true then successively_no_answers + 1 else 0 end,
    state_timeout = case when :Timeout > 0 then now() + (:Timeout || ' sec')::interval else null end  
where id = :Id`, map[string]interface{}{
		"State":    model.AGENT_STATE_FINE,
		"Timeout":  timeout,
		"NoAnswer": noAnswer,
		"Id":       agentId,
	})
	if err != nil {
		return model.NewAppError("SqlAgentStore.SetFine", "store.sql_agent.set_fine.app_error", nil,
			fmt.Sprintf("AgenetId=%v, State=%v, %s", agentId, model.AGENT_STATE_FINE, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetOnline(agentId int, channels []string, onDemand bool) (*model.AgentOnlineData, *model.AppError) {
	var data *model.AgentOnlineData

	err := s.GetMaster().SelectOne(&data, `select timestamp, channels
		from cc_agent_set_login(:AgentId, :Channels::varchar[], :OnDemand) channels  (channels jsonb, timestamp int8)`,
		map[string]interface{}{
			"AgentId":  agentId,
			"Channels": pq.Array(channels),
			"OnDemand": onDemand,
		})

	if err != nil {
		return nil, model.NewAppError("SqlAgentStore.SetOnline", "store.sql_agent.set_online.app_error", nil,
			fmt.Sprintf("AgenetId=%v, Status=%v, %s", agentId, model.AgentStatusOnline, err.Error()), http.StatusInternalServerError)
	}

	return data, nil
}

func (s SqlAgentStore) SetStatus(agentId int, status string, payload *string) *model.AppError {
	if _, err := s.GetMaster().Exec(`update cc_agent
			set status = :Status,
  			status_payload = :Payload,
			last_state_change = now(),
			successively_no_answers = 0
		where id = :AgentId`, map[string]interface{}{
		"AgentId": agentId,
		"Status":  status,
		"Payload": payload,
	}); err != nil {
		return model.NewAppError("SqlAgentStore.SetStatus", "store.sql_agent.set_status.app_error", nil,
			fmt.Sprintf("AgenetId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) WaitingChannel(agentId int, channel string) (int64, *model.AppError) {
	timestamp, err := s.GetMaster().SelectInt(`update cc_agent_channel c
set state = :State,
    joined_at = now(),
    timeout = null
where (c.agent_id, c.channel) = (:AgentId::int, :Channel::varchar) and c.state in ('wrap_time', 'missed')
returning cc_view_timestamp(c.joined_at) as timestamp`, map[string]interface{}{
		"State":   model.ChannelStateWaiting,
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
	_, err := s.GetMaster().Exec(`update cc_agent
set status = :Status,
	last_status_change = now(),
    successively_no_answers = 0
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
	_, err := s.GetMaster().Exec(`insert into cc_agent_missed_attempt (attempt_id, agent_id, cause, missed_at)
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
	_, err := s.GetMaster().Select(&channels, `update cc_agent_channel
	set state = 'waiting',
		timeout = null,
		joined_at = now()
	where timeout < now()
	returning agent_id, channel, cc_view_timestamp(joined_at) as timestamp`)

	if err != nil {
		return nil, model.NewAppError("SqlAgentStore.GetChannelTimeout", "store.sql_agent.channel_timeout.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return channels, nil
}
