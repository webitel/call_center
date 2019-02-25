package apis

import (
	"github.com/webitel/call_center/model"
	"net/http"
)

func (api *API) InitCalendar() {
	api.Routes.Calendar.Handle("", api.ApiHandler(listCalendars)).Methods("GET")
	api.Routes.Calendar.Handle("/{id:[0-9]+}", api.ApiHandler(getCalendar)).Methods("GET")
	api.Routes.Calendar.Handle("/{id:[0-9]+}", api.ApiHandler(deleteCalendar)).Methods("DELETE")
}

func listCalendars(c *Context, w http.ResponseWriter, r *http.Request) {

	calendars, err := c.App.GetCalendarsPage(c.Params.Filter, c.Params.Page, c.Params.PerPage, c.Params.SortFieldName, c.Params.SortDesc)
	if err != nil {
		c.Err = err
		return
	}

	w.Write([]byte(model.CalendarsToJson(calendars)))
}

func getCalendar(c *Context, w http.ResponseWriter, r *http.Request) {
	c.RequireId()
	if c.Err != nil {
		return
	}

	calendar, err := c.App.GetCalendar(c.Params.Id)
	if err != nil {
		c.Err = err
		return
	}

	w.Write([]byte(calendar.ToJson()))
}

func deleteCalendar(c *Context, w http.ResponseWriter, r *http.Request) {
	c.RequireId()
	if c.Err != nil {
		return
	}

	c.Err = c.App.DeleteCalendar(c.Params.Id)
	if c.Err != nil {
		return
	}

	ReturnStatusOK(w)
}
