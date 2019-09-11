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
set agent_id = r.agent_id
from (
  select r.agent_id, r.attempt_id, a2.updated_at
  from cc_distribute_agent_to_attempt($1) r
  inner join cc_agent a2 on a2.id = r.agent_id
) r
where a.id = r.attempt_id and a.hangup_at = 0
returning a.id as attempt_id, a.agent_id as agent_id, r.updated_at agent_updated_at`, nodeId); err != nil {
		return nil, model.NewAppError("SqlAgentStore.ReservedForAttemptByNode", "store.sql_agent.reserved_for_attempt.app_error",
			map[string]interface{}{"Error": err.Error()},
			err.Error(), http.StatusInternalServerError)
	} else {
		return agentsInAttempt, nil
	}
}

func (s SqlAgentStore) Get(id int64) (*model.Agent, *model.AppError) {
	var agent *model.Agent
	if err := s.GetReplica().SelectOne(&agent, `
			select id, name, user_id, updated_at, destination,
				status, status_payload
			from cc_agent where id = :Id		
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

func (s SqlAgentStore) SetStatus(agentId int64, status string, payload interface{}) *model.AppError {
	if _, err := s.GetMaster().Exec(`update cc_agent
			set status = :Status
  			,status_payload = :Payload
			where id = :AgentId`, map[string]interface{}{"AgentId": agentId, "Status": status, "Payload": payload}); err != nil {
		return model.NewAppError("SqlAgentStore.SetStatus", "store.sql_agent.set_status.app_error", nil,
			fmt.Sprintf("AgenetId=%v, %s", agentId, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlAgentStore) SetState(agentId int64, state string, timeoutSeconds int) (*model.AgentState, *model.AppError) {
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
    state_timeout = null
where state_timeout < now()
returning id, state`, map[string]interface{}{"State": newState}); err != nil {
		return nil, model.NewAppError("SqlAgentStore.ChangeDeadlineState", "store.sql_agent.set_deadline_state.app_error", nil,
			fmt.Sprintf("State=%v, %s", newState, err.Error()), http.StatusInternalServerError)
	} else {
		return times, nil
	}
}

func (s SqlAgentStore) SaveActivityCallStatistic(agentId, offeringAt, answerAt, bridgeStartAt, bridgeStopAt int64, nowAnswer bool) (int, *model.AppError) {
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
