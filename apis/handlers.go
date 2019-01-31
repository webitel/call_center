package apis

import (
	"github.com/webitel/call_center/web"
	"net/http"
)

type Context = web.Context

func (api *API) ApiHandler(h func(*Context, http.ResponseWriter, *http.Request)) http.Handler {
	return &web.Handler{
		App:            api.App,
		HandleFunc:     h,
		RequireSession: false,
		TrustRequester: false,
		RequireMfa:     false,
		IsStatic:       false,
	}
}

func (api *API) ApiSessionRequired(h func(*Context, http.ResponseWriter, *http.Request)) http.Handler {
	return &web.Handler{
		App:            api.App,
		HandleFunc:     h,
		RequireSession: true,
		TrustRequester: false,
		RequireMfa:     true,
		IsStatic:       false,
	}
}
