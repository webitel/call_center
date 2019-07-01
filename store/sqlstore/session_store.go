package sqlstore

import (
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlSessionStore struct {
	SqlStore
}

func NewSqlSessionStore(sqlStore SqlStore) store.SessionStore {
	us := &SqlSessionStore{sqlStore}
	for _, db := range sqlStore.GetAllConns() {
		table := db.AddTableWithName(model.Session{}, "session").SetKeys(true, "Id")
		table.ColMap("Id").SetMaxSize(26)
		table.ColMap("Token").SetMaxSize(500)
		table.ColMap("UserId").SetMaxSize(26)
	}
	return us
}

func (self *SqlSessionStore) CreateIndexesIfNotExists() {

}

func (self *SqlSessionStore) Get(sessionIdOrToken string) (*model.Session, *model.AppError) {
	var sessions []*model.Session

	if _, err := self.GetReplica().Select(&sessions, "SELECT id as id, 'my-token' as token, '100@10.10.10.144' as userid  FROM tokens LIMIT 1", map[string]interface{}{}); err != nil {
		return nil, model.NewAppError("SqlSessionStore.Get", "store.sql_session.get.app_error", nil, "sessionIdOrToken="+sessionIdOrToken+", "+err.Error(), http.StatusInternalServerError)
	} else if len(sessions) == 0 {
		return nil, model.NewAppError("SqlSessionStore.Get", "store.sql_session.get.app_error", nil, "sessionIdOrToken="+sessionIdOrToken, http.StatusNotFound)
	} else {
		return sessions[0], nil
	}
}
