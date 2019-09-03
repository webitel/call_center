package model

import (
	"encoding/json"
	"io"
	"net/http"
)

type CalendarAcceptOfDay struct {
	Id             int   `json:"id"`
	CalendarId     int   `json:"calendar_id"`
	Week           int8  `json:"week"`
	StartTimeOfDay int16 `json:"start_time_of_day"`
	EndTimeOfDay   int16 `json:"end_time_of_day"`
}

type CalendarExceptDate struct {
	Id         int  `json:"id"`
	CalendarId int  `json:"calendar_id"`
	Repeat     int8 `json:"repeat"`
	Date       int  `json:"date"`
}

// Description of the Calendar
// swagger:model Calendar
type Calendar struct {
	Id          int     `json:"id" db:"id"`
	Name        string  `json:"name" db:"name"`
	DomainId    int64   `json:"domain_id"`
	Start       *int    `json:"start" db:"start"`
	Finish      *int    `json:"finish" db:"finish"`
	Timezone    Lookup  `json:"timezone"`
	Description *string `json:"description,omitempty"`
}

func (c *Calendar) IsValid() *AppError {
	if len(c.Name) <= 3 {
		return NewAppError("Calendar.IsValid", "model.calendar.is_valid.name.app_error", nil, "name="+c.Name, http.StatusBadRequest)
	}

	if c.DomainId == 0 {
		return NewAppError("Calendar.IsValid", "model.calendar.is_valid.domain_id.app_error", nil, "name="+c.Name, http.StatusBadRequest)
	}
	return nil
}

func CalendarFromJson(data io.Reader) *Calendar {
	var calendar Calendar
	if err := json.NewDecoder(data).Decode(&calendar); err != nil {
		return nil
	} else {
		return &calendar
	}
}

func CalendarsToJson(calendars []*Calendar) string {
	b, _ := json.Marshal(calendars)
	return string(b)
}

func (c *Calendar) ToJson() string {
	b, _ := json.Marshal(c)
	return string(b)
}
