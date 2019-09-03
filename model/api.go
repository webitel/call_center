package model

import "encoding/json"

const (
	API_URL_SUFFIX_V2       = "/api/v2"
	API_URL_SUFFIX          = API_URL_SUFFIX_V2
	API_URL_FILTER_NAME     = "filter"
	API_URL_FIELDS_NAME     = "fields"
	API_URL_SORT_FIELD_NAME = "sort"
	API_URL_SORT_DESC       = "desc"
	API_URL_DOMAIN_ID       = "domain_id"

	STATUS      = "status"
	STATUS_OK   = "OK"
	STATUS_FAIL = "FAIL"

	HEADER_REQUEST_ID = "X-Request-ID"
	HEADER_TOKEN      = "X-Access-Token"
	HEADER_BEARER     = "BEARER"
	HEADER_AUTH       = "Authorization"
	HEADER_FORWARDED  = "X-Forwarded-For"
	HEADER_REAL_IP    = "X-Real-IP"
)

type ListResponse struct {
	Items interface{} `json:"items"`
}

func NewListJson(src interface{}) string {
	r := ListResponse{
		Items: src,
	}
	data, _ := json.Marshal(r)
	return string(data)
}
