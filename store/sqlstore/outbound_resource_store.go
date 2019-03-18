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
		table.ColMap("Enabled")
		table.ColMap("UpdatedAt")
		table.ColMap("Limit")
		table.ColMap("Rps")
		table.ColMap("Reserve")
		table.ColMap("Variables")
		table.ColMap("Number")
		table.ColMap("MaxSuccessivelyErrors")
	}
	return us
}

func (s SqlOutboundResourceStore) GetAllPage(filter string, offset, limit int, sortField string, desc bool) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var resources []*model.OutboundResource

		q := map[string]interface{}{
			"Limit":        limit,
			"Offset":       offset,
			"OrderByField": sortField,
			"OrderType":    desc,
			"Filter":       filter,
		}

		if q["OrderByField"] == "" {
			q["OrderByField"] = "id"
		}

		if _, err := s.GetReplica().Select(&resources,
			`SELECT id, "limit", enabled, priority, rps, reserve, name
			FROM get_outbound_resources(:Filter::text, :OrderByField::text, :OrderType, :Limit, :Offset)
			`, q); err != nil {
			result.Err = model.NewAppError("SqlOutboundResourceStore.GetAllPage", "store.sql_outbound_resource.get_all.app_error", nil, err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = resources
		}
	})
}

func (s SqlOutboundResourceStore) GetById(id int64) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var resource *model.OutboundResource
		if err := s.GetReplica().SelectOne(&resource, `
			select id, name, "limit", enabled, updated_at, rps, reserve, variables, number, max_successively_errors, dial_string
			from cc_outbound_resource where id = :Id		
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

func (s SqlOutboundResourceStore) Create(resource *model.OutboundResource) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if err := s.GetMaster().Insert(resource); err != nil {
			result.Err = model.NewAppError("SqlOutboundResourceStore.Save", "store.sql_outbound_resource.save.app_error", nil,
				fmt.Sprintf("id=%v, %v", resource.Id, err.Error()), http.StatusInternalServerError)
		} else {
			result.Data = resource
		}
	})
}

func (s SqlOutboundResourceStore) Delete(id int64) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`delete from cc_outbound_resource where id=:Id`, map[string]interface{}{"Id": id}); err != nil {
			result.Err = model.NewAppError("SqlOutboundResourceStore.Delete", "store.sql_outbound_resource.delete.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	})
}
