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

func (s SqlAgentStore) SaveActivityStatisticInQueue(stats *model.AgentInQueueStatistic) {

}
