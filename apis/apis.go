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

	Profile  *mux.Router // 'api/v2/profiles'
	Calendar *mux.Router // 'api/v2/calendar'
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
	api.Routes.Profile = api.Routes.ApiRoot.PathPrefix("/profiles").Subrouter()
	api.Routes.Calendar = api.Routes.ApiRoot.PathPrefix("/calendars").Subrouter()

	api.InitProfile()
	api.InitCalendar()
	return api
}

func (api *API) Handle404(w http.ResponseWriter, r *http.Request) {
	web.Handle404(api.App, w, r)
}
