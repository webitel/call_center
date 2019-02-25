package model

const (
	API_URL_SUFFIX_V2       = "/api/v2"
	API_URL_SUFFIX          = API_URL_SUFFIX_V2
	API_URL_FILTER_NAME     = "filter"
	API_URL_SORT_FIELD_NAME = "sort"
	API_URL_SORT_DESC       = "desc"

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
