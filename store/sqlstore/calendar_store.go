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
	for _, db := range sqlStore.GetAllConns() {
		table := db.AddTableWithName(model.Calendar{}, "calendar").SetKeys(true, "Id")
		table.ColMap("Id").SetUnique(true)
		table.ColMap("Name").SetMaxSize(30)
		table.ColMap("Timezone").SetMaxSize(15)
		table.ColMap("Start")
		table.ColMap("Finish")
	}
	return us
}

func (s SqlCalendarStore) Save(calendar *model.Calendar) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if err := s.GetMaster().Insert(calendar); err != nil {
			result.Err = model.NewAppError("SqlCalendarStore.Save", "store.sql_calendar.save.app_error", nil,
				fmt.Sprintf("id=%v, %v", calendar.Id, err.Error()), http.StatusInternalServerError)
		} else {
			result.Data = calendar
		}
	})
}

func (s SqlCalendarStore) GetAllPage(filter string, offset, limit int, sortField string, desc bool) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
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
			FROM get_calendars(:OrderByField, :OrderType, :Limit, :Offset)
			WHERE (:Filter = '' OR name like :Filter)
			`, q); err != nil {
			result.Err = model.NewAppError("SqlCalendarStore.GetAllPage", "store.sql_calendar.get_all.app_error", nil, err.Error(), http.StatusInternalServerError)
		} else {
			result.Data = calendars
		}
	})
}

func (s SqlCalendarStore) Get(id int) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		var calendar *model.Calendar
		if err := s.GetReplica().SelectOne(&calendar, `
			select * from calendar where id = :Id		
		`, map[string]interface{}{"Id": id}); err != nil {
			if err == sql.ErrNoRows {
				result.Err = model.NewAppError("SqlCalendarStore.Get", "store.sql_calendar.get.app_error", nil,
					fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusNotFound)
			} else {
				result.Err = model.NewAppError("SqlCalendarStore.Get", "store.sql_calendar.get.app_error", nil,
					fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
			}
		} else {
			result.Data = calendar
		}
	})
}

func (s SqlCalendarStore) Delete(id int) store.StoreChannel {
	return store.Do(func(result *store.StoreResult) {
		if _, err := s.GetMaster().Exec(`delete from calendar where id=:Id`, map[string]interface{}{"Id": id}); err != nil {
			result.Err = model.NewAppError("SqlCalendarStore.Delete", "store.sql_calendar.delete.app_error", nil,
				fmt.Sprintf("Id=%v, %s", id, err.Error()), http.StatusInternalServerError)
		}
	})
}
