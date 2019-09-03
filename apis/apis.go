// Package API.
//
// the purpose of this application is to provide an application
// that is using plain go code to define an API
//
// This should demonstrate all the possible comment annotations
// that are available to turn go code into a fully compliant swagger 2.0 spec
//
// Terms Of Service:
//
// there are no TOS at this moment, use at your own risk we take no responsibility
//
//     Schemes: http, https
//     Host: 0.0.0.0
//     BasePath: /v2
//     Version: 0.0.1
//     License: MIT http://opensource.org/licenses/MIT
//     Contact: Navrotskyj Igor<navrotskyj@gmail.com>
//
//     Consumes:
//     - application/json
//
//     Produces:
//     - application/json
//
//     Extensions:
//     x-meta-value: value
//     x-meta-array:
//       - value1
//       - value2
//     x-meta-array-obj:
//       - name: obj
//         value: field
//
// swagger:meta
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
	Agents            *mux.Router // /agent
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
	api.Routes.Agents = api.Routes.ApiRoot.PathPrefix("/agents").Subrouter()

	api.InitCalendar()
	api.InitOutboundResources()
	api.InitAgents()
	return api
}

func (api *API) Handle404(w http.ResponseWriter, r *http.Request) {
	web.Handle404(api.App, w, r)
}

var ReturnStatusOK = web.ReturnStatusOK
