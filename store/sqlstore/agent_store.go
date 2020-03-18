package sqlstore

import (
	"database/sql"
	"fmt"
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
			select a.id, a.user_id, a.domain_id, a.updated_at, u.name, u.extension as destination, a.status, a.status_payload, a.successively_no_answers
from cc_agent a
    inner join directory.wbt_user u on u.id = a.user_id
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

func (s SqlAgentStore) SetStatus(agentId int, status string, payload []byte) *model.AppError {
	if _, err := s.GetMaster().Exec(`update cc_agent
			set status = :Status
  			,status_payload = :Payload
			,last_state_change = :Now
			,successively_no_answers = 0
			where id = :AgentId`, map[string]interface{}{
		"AgentId": agentId,
		"Status":  status,
		"Payload": nil,
		"Now":     model.GetMillis(),
	}); err != nil {
		return model.NewAppError("SqlAgentStore.SetStatus", "store.sql_agent.set_status.app_error", nil,
			fmt.Sprintf("AgenetId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetState(agentId int, state string, timeoutSeconds int) (*model.AgentState, *model.AppError) {
	var agentState *model.AgentState
	if err := s.GetMaster().SelectOne(&agentState, `update cc_agent
set state = :State
  ,state_timeout = case when :Timeout > 0 then now() + (:Timeout || ' sec')::INTERVAL else null end
where id = :AgentId
returning id agent_id, state, state_timeout`, map[string]interface{}{"AgentId": agentId, "State": state, "Timeout": timeoutSeconds}); err != nil {
		return nil, model.NewAppError("SqlAgentStore.SetState", "store.sql_agent.set_state.app_error", nil,
			fmt.Sprintf("AgenetId=%v, State=%v, %s", agentId, state, err.Error()), http.StatusInternalServerError)
	} else {
		return agentState, nil
	}
}

func (s SqlAgentStore) ChangeDeadlineState(newState string) ([]*model.AgentChangedState, *model.AppError) {
	var times []*model.AgentChangedState //TODO
	if _, err := s.GetMaster().Select(&times, `update cc_agent
set state = :State,
    state_timeout = null,
	active_queue_id = null
where state_timeout < now()
returning id, state`, map[string]interface{}{"State": newState}); err != nil {
		return nil, model.NewAppError("SqlAgentStore.ChangeDeadlineState", "store.sql_agent.set_deadline_state.app_error", nil,
			fmt.Sprintf("State=%v, %s", newState, err.Error()), http.StatusInternalServerError)
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
    last_state_change = :Time,
    last_bridge_end_at = case when :Bridged is true then :Time else last_bridge_end_at end,
	state_timeout = null,
	active_queue_id = null
where id = :Id`, map[string]interface{}{
		"State":   model.AGENT_STATE_WAITING,
		"Time":    model.GetMillis(),
		"Id":      agentId,
		"Bridged": bridged,
	})
	if err != nil {
		return model.NewAppError("SqlAgentStore.SetOffering", "store.sql_agent.set_waiting.app_error", nil,
			fmt.Sprintf("AgenetId=%v, State=%v, %s", agentId, model.AGENT_STATE_WAITING, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetOffering(agentId, queueId int) (int, *model.AppError) {
	successivelyNoAnswers, err := s.GetMaster().SelectInt(`update cc_agent
			set state = :State,
				last_offering_at = :Time,
				last_state_change = :Time,
				active_queue_id = :QueueId
			where id = :Id
			returning successively_no_answers`, map[string]interface{}{
		"State":   model.AGENT_STATE_OFFERING,
		"Time":    model.GetMillis(),
		"Id":      agentId,
		"QueueId": queueId,
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
			last_state_change = :Time,
			last_bridge_start_at = :Time,
		    state_timeout = null
		where id = :Id`, map[string]interface{}{
		"State": model.AGENT_STATE_TALK,
		"Time":  model.GetMillis(),
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
    last_state_change = :Time,
    last_bridge_end_at = :Time,
	successively_no_answers = 0,
    state_timeout = case when :Timeout > 0 then now() + (:Timeout || ' sec')::interval else null end
where id = :Id`, map[string]interface{}{
		"State":   model.AGENT_STATE_REPORTING,
		"Time":    model.GetMillis(),
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
    last_state_change = :Time,
	successively_no_answers = case when :NoAnswer is true then successively_no_answers + 1 else 0 end,
    state_timeout = case when :Timeout > 0 then now() + (:Timeout || ' sec')::interval else null end  
where id = :Id`, map[string]interface{}{
		"State":    model.AGENT_STATE_FINE,
		"Time":     model.GetMillis(),
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

func (s SqlAgentStore) SetOnBreak(agentId int) *model.AppError {
	_, err := s.GetMaster().Exec(`update cc_agent
set state = :State,
    status = :Status,
    successively_no_answers = 0,
	active_queue_id = null
where id = :Id`, map[string]interface{}{
		"Id":     agentId,
		"State":  model.AGENT_STATE_WAITING,
		"Status": model.AGENT_STATUS_PAUSE,
	})
	if err != nil {
		return model.NewAppError("SqlAgentStore.SetOnBreak", "store.sql_agent.set_break.app_error", nil,
			fmt.Sprintf("AgenetId=%v, Status=%v State=%v, %s", agentId, model.AGENT_STATUS_PAUSE, model.AGENT_STATE_WAITING,
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
