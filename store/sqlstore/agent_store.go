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

func (s SqlAgentStore) ReservedForAttemptByNode(nodeId string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {

		var agentsInAttempt []*model.AgentsForAttempt
		if _, err := s.GetMaster().Select(&agentsInAttempt, `select a.attempt_id, a.agent_id, a.agent_updated_at
			from cc_reserved_agent_for_attempt($1) a`, nodeId); err != nil {
			result.Err = model.NewAppError("SqlAgentStore.ReservedForAttemptByNode", "store.sql_agent.reserved_for_attempt.app_error",
				map[string]interface{}{"Error": err.Error()},
				err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = agentsInAttempt
		}
	})
}

func (s SqlAgentStore) Get(id int64) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var agent *model.Agent
		if err := s.GetReplica().SelectOne(&agent, `
			select id, name, max_no_answer, wrap_up_time, reject_delay_time, busy_delay_time, no_answer_delay_time, call_timeout, user_id, updated_at, destination,
				status, status_payload
			from cc_agent where id = :Id		
		`, map[string]interface{}{"Id": id}); err != nil {
			if err == sql.ErrNoRows {
				result.Err = model.NewAppError("SqlAgentStore.Get", "store.sql_agent.get.app_error", nil,
					fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
			} else {
				result.Err = model.NewAppError("SqlAgentStore.Get", "store.sql_agent.get.app_error", nil,
					fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
			}
		} else {
			result.Data = agent
		}
	})
}

func (s SqlAgentStore) SetStatus(agentId int64, status string, payload interface{}) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`update cc_agent
			set status = :Status
  			,status_payload = :Payload
			where id = :AgentId`, map[string]interface{}{"AgentId": agentId, "Status": status, "Payload": payload}); err != nil {
			result.Err = model.NewAppError("SqlAgentStore.SetStatus", "store.sql_agent.set_status.app_error", nil,
				fmt.Sprintf("AgenetId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
		}
	})
}

func (s SqlAgentStore) SetState(agentId int64, state string, timeoutSeconds int) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var agentState *model.AgentState
		if err := s.GetMaster().SelectOne(&agentState, `
			insert into cc_agent_state_history (agent_id, state, timeout_at) 
			values (:AgentId, :State, case when :Timeout > 0 then now() + (:Timeout || ' sec')::INTERVAL else null end)   
			returning id, agent_id, state, timeout_at, timeout_at`, map[string]interface{}{"AgentId": agentId, "State": state, "Timeout": timeoutSeconds}); err != nil {
			result.Err = model.NewAppError("SqlAgentStore.SetState", "store.sql_agent.set_state.app_error", nil,
				fmt.Sprintf("AgenetId=%v, State=%v, %s", agentId, state, err.Error()), http.StatusInternalServerError)
		} else {
			result.Data = agentState
		}
	})
}

func (s SqlAgentStore) ChangeDeadlineState(newState string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var times []*model.AgentStateHistoryTime //TODO
		if _, err := s.GetMaster().Select(&times, `insert into cc_agent_state_history (agent_id, joined_at, state, payload)
  select a.id, h.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload
from cc_agent a
  ,lateral (
    select h.timeout_at
    from cc_agent_state_history h
    where h.agent_id = a.id
    order by h.joined_at desc
    limit 1
  ) h
where  a.status in  ('online', 'pause') and h.timeout_at < now()
			returning id, agent_id, joined_at, state, payload`, map[string]interface{}{"State": newState}); err != nil {
			result.Err = model.NewAppError("SqlAgentStore.ChangeDeadlineState", "store.sql_agent.set_deadline_state.app_error", nil,
				fmt.Sprintf("State=%v, %s", newState, err.Error()), http.StatusInternalServerError)
		} else {
			result.Data = times
		}
	})
}

/*
func (s SqlAgentStore) ChangeDeadlineState(newState string) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var times []*model.AgentStateHistoryTime //TODO
		if _, err := s.GetMaster().Select(&times, `insert into cc_agent_state_history (agent_id, joined_at, state, payload)
			select h.agent_id, h.timeout_at, case when ca.status = 'online' then 'waiting' else ca.status end, ca.status_payload
			from cc_agent_state_history h
  				inner join cc_agent ca on h.agent_id = ca.id
			where h.timeout_at <= now()
  				and not exists(
    				select *
    				from cc_agent_state_history h2
    				 where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
  				)
			returning id, agent_id, joined_at, state, payload`, map[string]interface{}{"State": newState}); err != nil {
			result.Err = model.NewAppError("SqlAgentStore.ChangeDeadlineState", "store.sql_agent.set_deadline_state.app_error", nil,
				fmt.Sprintf("State=%v, %s", newState, err.Error()), http.StatusInternalServerError)
		} else {
			result.Data = times
		}
	})
}
*/

func (s SqlAgentStore) SaveActivityCallStatistic(agentId, offeringAt, answerAt, bridgeStartAt, bridgeStopAt int64, nowAnswer bool) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
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
			result.Err = model.NewAppError("SqlAgentStore.SaveActivityCallStatistic", "store.sql_agent.save_call_activity.app_error", nil,
				fmt.Sprintf("AgentId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
		} else {
			result.Data = cnt
		}
	})
}
