package model

import "time"

const APP_SERVICE_NAME = "call_center"

const (
	APP_DEREGESTER_CRITICAL_TTL = time.Minute * 2
	APP_SERVICE_TTL             = time.Second * 30
)
