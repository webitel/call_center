package apis

import "net/http"

func (api *API) InitProfile() {
	api.PublicRoutes.Profile.Handle("", api.ApiSessionRequired(listProfiles)).Methods("GET")
}

func listProfiles(c *Context, w http.ResponseWriter, r *http.Request) {
	w.Write([]byte("TODO"))
}
