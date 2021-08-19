package sqlstore

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlStatisticStore struct {
	SqlStore
}

func NewSqlStatisticStore(sqlStore SqlStore) store.StatisticStore {
	as := &SqlStatisticStore{sqlStore}
	return as
}

func (s SqlStatisticStore) RefreshInbound1H() *model.AppError {
	_, err := s.GetMaster().Exec(`refresh materialized view cc_inbound_stats`)

	if err != nil {
		return model.NewAppError("SqlAgentStore.RefreshInbound1H", "store.sql_agent.refresh_inbound_stats.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}
