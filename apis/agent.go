package apis

import "net/http"

func (api *API) InitAgents() {
	api.Routes.Agents.Handle("/{id:[0-9]+}/login", api.ApiHandler(login_agent)).Methods("PATCH")
	api.Routes.Agents.Handle("/{id:[0-9]+}/logout", api.ApiHandler(logout_agent)).Methods("PATCH")
}

func login_agent(c *Context, w http.ResponseWriter, r *http.Request) {
	c.RequireId()

	if c.Err != nil {
		return
	}

	if c.Err = c.App.SetAgentLogin(int64(c.Params.Id)); c.Err != nil {
		return
	}

	ReturnStatusOK(w)
}

func logout_agent(c *Context, w http.ResponseWriter, r *http.Request) {
	c.RequireId()

	if c.Err != nil {
		return
	}

	if c.Err = c.App.SetAgentLogout(int64(c.Params.Id)); c.Err != nil {
		return
	}

	ReturnStatusOK(w)
}
