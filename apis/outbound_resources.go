package apis

import (
	"github.com/webitel/call_center/model"
	"net/http"
)

func (api *API) InitOutboundResources() {
	api.Routes.OutboundResources.Handle("", api.ApiHandler(listOutboundResources)).Methods("GET")
	api.Routes.OutboundResources.Handle("/{id:[0-9]+}", api.ApiHandler(getOutboundResources)).Methods("GET")
}

func listOutboundResources(c *Context, w http.ResponseWriter, r *http.Request) {
	resources, err := c.App.GetOutboundResourcesPage(c.Params.Filter, c.Params.Page, c.Params.PerPage, c.Params.SortFieldName, c.Params.SortDesc)
	if err != nil {
		c.Err = err
		return
	}

	w.Write([]byte(model.OutboundResourcesToJson(resources)))
}

func getOutboundResources(c *Context, w http.ResponseWriter, r *http.Request) {
	c.RequireId()

	if c.Err != nil {
		return
	}

	resource, err := c.App.GetOutboundResourceById(int64(c.Params.Id))
	if err != nil {
		c.Err = err
		return
	}

	w.Write([]byte(resource.ToJson()))
}
