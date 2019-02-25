package web

import (
	"github.com/gorilla/mux"
	"github.com/webitel/call_center/model"
	"net/http"
	"strconv"
)

const (
	PAGE_DEFAULT     = 0
	PER_PAGE_DEFAULT = 60
	PER_PAGE_MAXIMUM = 200
)

type Params struct {
	Id            int
	Page          int
	PerPage       int
	SortFieldName string
	SortDesc      bool
	Filter        string
}

func ParamsFromRequest(r *http.Request) *Params {
	params := &Params{}
	query := r.URL.Query()
	props := mux.Vars(r)

	if val := query.Get(model.API_URL_FILTER_NAME); val != "" {
		params.Filter = val
	}

	if val := query.Get(model.API_URL_SORT_FIELD_NAME); val != "" {
		params.SortFieldName = val
	}

	if val := query.Get(model.API_URL_SORT_DESC); val == "1" {
		params.SortDesc = true
	}

	if val, err := strconv.Atoi(query.Get("page")); err != nil || val < 0 {
		params.Page = PAGE_DEFAULT
	} else {
		params.Page = val
	}

	if val, err := strconv.Atoi(query.Get("per_page")); err != nil || val < 0 {
		params.PerPage = PER_PAGE_DEFAULT
	} else if val > PER_PAGE_MAXIMUM {
		params.PerPage = PER_PAGE_MAXIMUM
	} else {
		params.PerPage = val
	}

	if val, ok := props["id"]; ok {
		if id, err := strconv.Atoi(val); err == nil {
			params.Id = id
		}
	}

	return params
}
