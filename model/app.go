package model

import "time"

const ServiceName = "iiicall_center"

const (
	APP_DEREGESTER_CRITICAL_TTL = time.Minute * 2
	APP_SERVICE_TTL             = time.Second * 30
)
