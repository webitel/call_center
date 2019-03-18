package apis

import (
	"github.com/webitel/call_center/model"
	"net/http"
)

func (api *API) InitOutboundResources() {
	api.Routes.OutboundResources.Handle("", api.ApiHandler(listOutboundResources)).Methods("GET")
	api.Routes.OutboundResources.Handle("", api.ApiHandler(createOutboundResource)).Methods("POST")
	api.Routes.OutboundResources.Handle("/{id:[0-9]+}", api.ApiHandler(getOutboundResources)).Methods("GET")
	api.Routes.OutboundResources.Handle("/{id:[0-9]+}", api.ApiHandler(deleteOutboundResources)).Methods("DELETE")
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

func createOutboundResource(c *Context, w http.ResponseWriter, r *http.Request) {
	resource := model.OutboundResourceFromJson(r.Body)
	if resource == nil {
		c.SetInvalidParam("resource")
		return
	}

	if err := resource.IsValid(); err != nil {
		c.Err = err
		return
	}

	resource, err := c.App.CreateOutboundResource(resource)
	if err != nil {
		c.Err = err
		return
	}

	w.WriteHeader(http.StatusCreated)
	w.Write([]byte(resource.ToJson()))
}

func deleteOutboundResources(c *Context, w http.ResponseWriter, r *http.Request) {
	c.RequireId()
	if c.Err != nil {
		return
	}

	c.Err = c.App.DeleteOutboundResource(int64(c.Params.Id))
	if c.Err != nil {
		return
	}

	ReturnStatusOK(w)
}
