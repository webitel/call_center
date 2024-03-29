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
	_, err := s.GetMaster().Exec(`refresh materialized view CONCURRENTLY call_center.cc_inbound_stats`)

	if err != nil {
		return model.NewAppError("SqlAgentStore.RefreshInbound1H", "store.sql_agent.refresh_inbound_stats.app_error", nil,
			err.Error(), http.StatusInternalServerError)
	}

	return nil
}

func (s *SqlStatisticStore) LibVersion() (string, *model.AppError) {
	var str string
	err := s.GetMaster().SelectOne(&str, `select x from call_center.cc_version() x`)
	if err != nil {
		return "", model.NewAppError("SqlMemberStore.LibVersion", "store.sql_member.lib_version.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return str, nil
}
