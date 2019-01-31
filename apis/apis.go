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

	Profile *mux.Router // 'api/v2/profiles'
}

type API struct {
	App          *app.App
	PublicRoutes *RoutesPublic
}

func Init(a *app.App, root *mux.Router) *API {
	api := &API{
		App:          a,
		PublicRoutes: &RoutesPublic{},
	}
	api.PublicRoutes.Root = root
	api.PublicRoutes.ApiRoot = root.PathPrefix(model.API_URL_SUFFIX).Subrouter()
	api.PublicRoutes.Profile = api.PublicRoutes.ApiRoot.PathPrefix("/profiles").Subrouter()

	api.InitProfile()
	return api
}

func (api *API) Handle404(w http.ResponseWriter, r *http.Request) {
	web.Handle404(api.App, w, r)
}
