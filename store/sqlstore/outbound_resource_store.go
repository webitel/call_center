package sqlstore

import (
	"database/sql"
	"fmt"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlOutboundResourceStore struct {
	SqlStore
}

func NewSqlOutboundResourceStore(sqlStore SqlStore) store.OutboundResourceStore {
	us := &SqlOutboundResourceStore{sqlStore}
	for _, db := range sqlStore.GetAllConns() {
		table := db.AddTableWithName(model.OutboundResource{}, "cc_outbound_resource").SetKeys(true, "Id")
		table.ColMap("Id").SetUnique(true)
		table.ColMap("MaxCallCount")
		table.ColMap("Enabled")
		table.ColMap("UpdatedAt")
		table.ColMap("Rps")
	}
	return us
}

func (s SqlOutboundResourceStore) GetById(id int64) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var resource *model.OutboundResource
		if err := s.GetReplica().SelectOne(&resource, `
			select * from cc_outbound_resource where id = :Id		
		`, map[string]interface{}{"Id": id}); err != nil {
			if err == sql.ErrNoRows {
				result.Err = model.NewAppError("SqlOutboundResourceStore.GetById", "store.sql_outbound_resource.get.app_error", nil,
					fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
			} else {
				result.Err = model.NewAppError("SqlOutboundResourceStore.GetById", "store.sql_outbound_resource.get.app_error", nil,
					fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
			}
		} else {
			result.Data = resource
		}
	})
}
