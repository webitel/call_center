package apis

import (
	"github.com/webitel/call_center/model"
	"net/http"
)

func (api *API) InitCalendar() {
	api.Routes.Calendar.Handle("", api.ApiHandler(listCalendars)).Methods("GET")
}

func listCalendars(c *Context, w http.ResponseWriter, r *http.Request) {

	calendars, err := c.App.GetCalendarsPage(c.Params.Filter, c.Params.Page, c.Params.PerPage, c.Params.SortFieldName, c.Params.SortDesc)
	if err != nil {
		c.Err = err
		return
	}

	w.Write([]byte(model.CalendarsToJson(calendars)))
}
