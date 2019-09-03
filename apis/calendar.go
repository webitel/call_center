package apis

import (
	"github.com/webitel/call_center/model"
	"net/http"
)

func (api *API) InitCalendar() {
	// swagger:operation GET /calendars calendars
	//
	// ---
	// produces:
	// - application/json
	// responses:
	//   '200':
	//     description: successful operation
	//     schema:
	//       $ref: '#/definitions/Calendar'
	api.Routes.Calendar.Handle("", api.ApiSessionRequired(listCalendars)).Methods("GET")
	api.Routes.Calendar.Handle("", api.ApiSessionRequired(createCalendar)).Methods("POST")
	api.Routes.Calendar.Handle("/{id:[0-9]+}", api.ApiSessionRequired(getCalendar)).Methods("GET")
	api.Routes.Calendar.Handle("/{id:[0-9]+}", api.ApiSessionRequired(deleteCalendar)).Methods("DELETE")
}

func listCalendars(c *Context, w http.ResponseWriter, r *http.Request) {
	var calendars []*model.Calendar

	c.RequireDomainId()
	if c.Err != nil {
		return
	}

	permission := c.Session.GetPermission(model.PERMISSION_SCOPE_CALENDAR)
	if !permission.CanRead() {
		c.SetPermissionError(permission, model.PERMISSION_ACCESS_READ)
	}

	if c.Err != nil {
		return
	}

	if permission.Rbac {
		calendars, c.Err = c.App.GetCalendarsPageByGroups(c.DomainId(), c.Session.RoleIds, c.Params.Page, c.Params.PerPage)
	} else {
		calendars, c.Err = c.App.GetCalendarsPage(c.DomainId(), c.Params.Page, c.Params.PerPage)
	}

	if c.Err != nil {
		return
	}

	w.Write([]byte(model.NewListJson(calendars)))
}

func getCalendar(c *Context, w http.ResponseWriter, r *http.Request) {
	var calendar *model.Calendar
	c.RequireId()
	if c.Err != nil {
		return
	}

	c.RequireDomainId()
	if c.Err != nil {
		return
	}

	permission := c.Session.GetPermission(model.PERMISSION_SCOPE_CALENDAR)
	if !permission.CanRead() {
		c.SetPermissionError(permission, model.PERMISSION_ACCESS_READ)
	}

	if c.Err != nil {
		return
	}

	if permission.Rbac {
		calendar, c.Err = c.App.GetCalendarByGroup(c.DomainId(), c.Params.Id, c.Session.RoleIds)
	} else {
		calendar, c.Err = c.App.GetCalendar(c.DomainId(), c.Params.Id)
	}

	if c.Err != nil {
		return
	}

	calendar, err := c.App.GetCalendar(c.DomainId(), c.Params.Id)
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

	c.RequireDomainId()
	if c.Err != nil {
		return
	}

	c.Err = c.App.DeleteCalendar(c.DomainId(), c.Params.Id)
	if c.Err != nil {
		return
	}

	ReturnStatusOK(w)
}

func createCalendar(c *Context, w http.ResponseWriter, r *http.Request) {
	calendar := model.CalendarFromJson(r.Body)
	if calendar == nil {
		c.SetInvalidParam("calendar")
		return
	}

	calendar, err := c.App.CreateCalendar(calendar)
	if err != nil {
		c.Err = err
		return
	}

	w.WriteHeader(http.StatusCreated)
	w.Write([]byte(calendar.ToJson()))
}
