package sqlstore

import (
	"database/sql"
	"fmt"
	"github.com/lib/pq"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"net/http"
)

type SqlCalendarStore struct {
	SqlStore
}

func NewSqlCalendarStore(sqlStore SqlStore) store.CalendarStore {
	us := &SqlCalendarStore{sqlStore}
	return us
}

func (s *SqlCalendarStore) CreateTableIfNotExists() {
}

func (s SqlCalendarStore) Create(calendar *model.Calendar) (*model.Calendar, *model.AppError) {
	if err := s.GetMaster().Insert(calendar); err != nil {
		return nil, model.NewAppError("SqlCalendarStore.Save", "store.sql_calendar.save.app_error", nil,
			fmt.Sprintf("id=%v, %v", calendar.Id, err.Error()), http.StatusInternalServerError)
	} else {
		return calendar, nil
	}
}

func (s SqlCalendarStore) GetAllPageByPermission() {

}

func (s SqlCalendarStore) GetAllPage(domainId int64, offset, limit int) ([]*model.Calendar, *model.AppError) {
	var calendars []*model.Calendar

	if _, err := s.GetReplica().Select(&calendars,
		`select c.id,
       c.name,
       c.start,
       c.finish,
       c.description,
       json_build_object('id', ct.id, 'name', ct.name)::jsonb as timezone
from calendar c
       left join calendar_timezones ct on c.timezone_id = ct.id
where c.domain_id = :DomainId
order by id
limit :Limit
offset :Offset`, map[string]interface{}{"DomainId": domainId, "Limit": limit, "Offset": offset}); err != nil {
		return nil, model.NewAppError("SqlCalendarStore.GetAllPage", "store.sql_calendar.get_all.app_error", nil, err.Error(), http.StatusInternalServerError)
	} else {
		return calendars, nil
	}
}

func (s SqlCalendarStore) GetAllPageByGroups(domainId int64, groups []int, offset, limit int) ([]*model.Calendar, *model.AppError) {
	var calendars []*model.Calendar

	if _, err := s.GetReplica().Select(&calendars,
		`select c.id,
       c.name,
       c.start,
       c.finish,
       c.description,
       json_build_object('id', ct.id, 'name', ct.name)::jsonb as timezone
from calendar c
       left join calendar_timezones ct on c.timezone_id = ct.id
where c.domain_id = :DomainId
  and (
    exists(select 1
      from calendar_acl a
      where a.dc = c.domain_id and a.object = c.id and a.subject = any(:Groups::int[]) and a.access&:Access = :Access)
  )
order by id
limit :Limit
offset :Offset`, map[string]interface{}{"DomainId": domainId, "Limit": limit, "Offset": offset, "Groups": pq.Array(groups), "Access": model.PERMISSION_ACCESS_READ.Value()}); err != nil {
		return nil, model.NewAppError("SqlCalendarStore.GetAllPage", "store.sql_calendar.get_all.app_error", nil, err.Error(), http.StatusInternalServerError)
	} else {
		return calendars, nil
	}
}

func (s SqlCalendarStore) Get(domainId int64, id int) (*model.Calendar, *model.AppError) {
	var calendar *model.Calendar
	if err := s.GetReplica().SelectOne(&calendar, `
			select c.id,
			   c.name,
			   c.start,
			   c.finish,
			   c.description,
			   json_build_object('id', ct.id, 'name', ct.name)::jsonb as timezone
		from calendar c
			   left join calendar_timezones ct on c.timezone_id = ct.id
		where c.domain_id = :DomainId and c.id = :Id 	
		`, map[string]interface{}{"Id": id, "DomainId": domainId}); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlCalendarStore.Get", "store.sql_calendar.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlCalendarStore.Get", "store.sql_calendar.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	} else {
		return calendar, nil
	}
}

func (s SqlCalendarStore) GetByGroups(domainId int64, id int, groups []int) (*model.Calendar, *model.AppError) {
	var calendar *model.Calendar
	if err := s.GetReplica().SelectOne(&calendar, `
			select c.id,
			   c.name,
			   c.start,
			   c.finish,
			   c.description,
			   json_build_object('id', ct.id, 'name', ct.name)::jsonb as timezone
		from calendar c
			   left join calendar_timezones ct on c.timezone_id = ct.id
		where c.domain_id = :DomainId and c.id = :Id and (
			exists(select 1
			  from calendar_acl a
			  where a.dc = c.domain_id and a.object = c.id and a.subject = any(:Groups::int[]) and a.access&:Access = :Access)
		  )	
		`, map[string]interface{}{"Id": id, "DomainId": domainId, "Groups": pq.Array(groups), "Access": model.PERMISSION_ACCESS_READ.Value()}); err != nil {
		if err == sql.ErrNoRows {
			return nil, model.NewAppError("SqlCalendarStore.Get", "store.sql_calendar.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
		} else {
			return nil, model.NewAppError("SqlCalendarStore.Get", "store.sql_calendar.get.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	} else {
		return calendar, nil
	}
}

func (s SqlCalendarStore) Delete(id int) *model.AppError {
	if _, err := s.GetMaster().Exec(`delete from calendar where id=:Id`, map[string]interface{}{"Id": id}); err != nil {
		return model.NewAppError("SqlCalendarStore.Delete", "store.sql_calendar.delete.app_error", nil,
			fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
	}
	return nil
}
