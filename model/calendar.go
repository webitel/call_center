package model

import "encoding/json"

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

type Calendar struct {
	Id       int    `json:"id"`
	Name     string `json:"name"`
	Timezone string `json:"timezone"`
	Start    *int   `json:"start"`
	Finish   *int   `json:"finish"`
	//Description string `json:"description"`
	//	Accept      []CalendarAcceptOfDay `json:"accept"`
	//	Except      []CalendarExceptDate  `json:"except"`
}

func CalendarsToJson(calendars []*Calendar) string {
	b, _ := json.Marshal(calendars)
	return string(b)
}
