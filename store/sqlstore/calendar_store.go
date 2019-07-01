package sqlstore

import (
	"database/sql"
	"fmt"
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

func (s SqlCalendarStore) GetAllPage(filter string, offset, limit int, sortField string, desc bool) ([]*model.Calendar, *model.AppError) {
	var calendars []*model.Calendar

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

	if _, err := s.GetReplica().Select(&calendars,
		`SELECT id, name, timezone, start, finish
			FROM get_calendars(:Filter::text, :OrderByField::text, :OrderType, :Limit, :Offset)
			`, q); err != nil {
		return nil, model.NewAppError("SqlCalendarStore.GetAllPage", "store.sql_calendar.get_all.app_error", nil, err.Error(), http.StatusInternalServerError)
	} else {
		return calendars, nil
	}
}

func (s SqlCalendarStore) Get(id int) (*model.Calendar, *model.AppError) {
	var calendar *model.Calendar
	if err := s.GetReplica().SelectOne(&calendar, `
			select * from calendar where id = :Id		
		`, map[string]interface{}{"Id": id}); err != nil {
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
