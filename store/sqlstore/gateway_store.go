package sqlstore

import (
	"database/sql"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlGatewayStore struct {
	SqlStore
}

func NewSqlGatewayStore(sqlStore SqlStore) store.GatewayStore {
	cs := &SqlGatewayStore{sqlStore}
	return cs
}

func (s SqlGatewayStore) Get(id int64) (*model.SipGateway, *model.AppError) {
	var gw *model.SipGateway
	if err := s.GetReplica().SelectOne(&gw, `
			select g.id, 0 updated_at, g.name, g.dc as domain_id, g.register, g.proxy, g.username, g.account, g.password,
				regexp_replace(g.host, '([a-zA-Z+.\-\d]+):?.*', '\1') as host_name
			from directory.sip_gateway g
			where g.id = :Id		
		`, map[string]interface{}{"Id": id}); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlGatewayStore.Get", "store.sql_gateway.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlGatewayStore.Get", "store.sql_gateway.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	} else {
		return gw, nil
	}
}
