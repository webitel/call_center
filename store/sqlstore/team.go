package sqlstore

import (
	"database/sql"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlTeamStore struct {
	SqlStore
}

func NewSqlTeamStore(sqlStore SqlStore) store.TeamStore {
	as := &SqlTeamStore{sqlStore}
	return as
}

func (s SqlTeamStore) Get(id int) (*model.Team, *model.AppError) {
	var team *model.Team
	if err := s.GetReplica().SelectOne(&team, `
			select id,
			   domain_id,
			   name,
			   description,
			   strategy,
			   max_no_answer,
			   wrap_up_time,
			   no_answer_delay_time,
			   call_timeout,
			   invite_chat_timeout,
			   task_accept_timeout,
			   updated_at,
			   (
				select jsonb_agg(row_to_json(qe))
				from call_center.cc_team_events qe
					inner join flow.acr_routing_scheme s on s.id = qe.schema_id and t.domain_id = s.domain_id
				where qe.team_id = t.id and qe.enabled
			   ) hooks
		from call_center.cc_team t
		where id = :Id
		`, map[string]interface{}{"Id": id}); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlTeamStore.Get", "store.sql_team.get.not_found", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlTeamStore.Get", "store.sql_team.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	} else {
		return team, nil
	}
}
