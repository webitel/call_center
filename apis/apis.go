package apis

import (
	"github.com/gorilla/mux"
	"github.com/webitel/call_center/app"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/web"
	"net/http"
)

type RoutesPublic struct {
	Root    *mux.Router // ''
	ApiRoot *mux.Router // 'api/v2'

	Calendar          *mux.Router // 'api/v2/calendars'
	OutboundResources *mux.Router // 'api/v2/resources'
}

type API struct {
	App    *app.App
	Routes *RoutesPublic
}

func Init(a *app.App, root *mux.Router) *API {
	api := &API{
		App:    a,
		Routes: &RoutesPublic{},
	}
	api.Routes.Root = root
	api.Routes.ApiRoot = root.PathPrefix(model.API_URL_SUFFIX).Subrouter()

	api.Routes.Calendar = api.Routes.ApiRoot.PathPrefix("/calendars").Subrouter()
	api.Routes.OutboundResources = api.Routes.ApiRoot.PathPrefix("/resources").Subrouter()

	api.InitCalendar()
	api.InitOutboundResources()
	return api
}

func (api *API) Handle404(w http.ResponseWriter, r *http.Request) {
	web.Handle404(api.App, w, r)
}

var ReturnStatusOK = web.ReturnStatusOK
