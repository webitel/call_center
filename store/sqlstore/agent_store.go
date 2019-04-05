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
			select * from cc_agent where id = :Id		
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
