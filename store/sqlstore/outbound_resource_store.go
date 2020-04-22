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
	return us
}

func (s SqlOutboundResourceStore) GetAllPage(filter string, offset, limit int, sortField string, desc bool) ([]*model.OutboundResource, *model.AppError) {
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
		`SELECT id, "limit", enabled, rps, reserve, name
			FROM get_outbound_resources(:Filter::text, :OrderByField::text, :OrderType, :Limit, :Offset)
			`, q); err != nil {
		return nil, model.NewAppError("SqlOutboundResourceStore.GetAllPage", "store.sql_outbound_resource.get_all.app_error", nil, err.Error(), http.StatusInternalServerError)
	} else {
		return resources, nil
	}
}

func (s SqlOutboundResourceStore) GetById(id int64) (*model.OutboundResource, *model.AppError) {
	var resource *model.OutboundResource
	if err := s.GetReplica().SelectOne(&resource, `
			select r.id, r.name, r."limit", r.enabled, r.updated_at, r.rps, r.reserve, r.variables, r.max_successively_errors,
    r.successively_errors, r.gateway_id, coalesce(r.error_ids, '{}'::varchar[]) error_ids, array( select d.display
        from cc_outbound_resource_display d where d.resource_id = r.id)::varchar[] display_numbers
from cc_outbound_resource r
    left join directory.sip_gateway g on r.gateway_id = g.id
			where r.id = :Id		
		`, map[string]interface{}{"Id": id}); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlOutboundResourceStore.GetById", "store.sql_outbound_resource.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlOutboundResourceStore.GetById", "store.sql_outbound_resource.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	} else {
		return resource, nil
	}
}

func (s SqlOutboundResourceStore) Create(resource *model.OutboundResource) (*model.OutboundResource, *model.AppError) {
	if err := s.GetMaster().Insert(resource); err != nil {
		return nil, model.NewAppError("SqlOutboundResourceStore.Save", "store.sql_outbound_resource.save.app_error", nil,
			fmt.Sprintf("id=%v, %v", resource.Id, err.Error()), http.StatusInternalServerError)
	} else {
		return resource, nil
	}
}

func (s SqlOutboundResourceStore) Delete(id int64) *model.AppError {
	if _, err := s.GetMaster().Exec(`delete from cc_outbound_resource where id=:Id`, map[string]interface{}{"Id": id}); err != nil {
		return model.NewAppError("SqlOutboundResourceStore.Delete", "store.sql_outbound_resource.delete.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}
	return nil
}

func (s SqlOutboundResourceStore) SetError(id int64, queueId int64, errorId string, strategy model.OutboundResourceUnReserveStrategy) (*model.OutboundResourceErrorResult, *model.AppError) {
	var resErr *model.OutboundResourceErrorResult
	if err := s.GetMaster().SelectOne(&resErr, `
			select count_successively_error, stopped, un_reserve_resource_id from cc_resource_set_error(:Id, :QueueId, :ErrorId, :Strategy)
  				as (count_successively_error smallint, stopped boolean, un_reserve_resource_id bigint)	
		`, map[string]interface{}{"Id": id, "QueueId": queueId, "ErrorId": errorId, "Strategy": strategy}); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlOutboundResourceStore.SetError", "store.sql_outbound_resource.set_error.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlOutboundResourceStore.SetError", "store.sql_outbound_resource.set_error.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	} else {
		return resErr, nil
	}
}

func (s SqlOutboundResourceStore) SetSuccessivelyErrorsById(id int64, successivelyErrors uint16) *model.AppError {
	if _, err := s.GetMaster().Exec(`update cc_outbound_resource
			set successively_errors = :SuccessivelyErrors
			where id = :Id`, map[string]interface{}{"Id": id, "SuccessivelyErrors": successivelyErrors}); err != nil {
		return model.NewAppError("SqlOutboundResourceStore.SetSuccessivelyErrorsById", "store.sql_outbound_resource.set_successively_error.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}
	return nil
}
