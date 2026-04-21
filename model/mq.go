package model

const (
	EngineExchange      = "engine"
	CallCenterExchange  = "callcenter"
	CallExchange        = "call"
	ChatExchange        = "chat"
	CallRoutingTemplate = "events.*.%s.*.*"

	IMQueueNamePrefix = "im-delivery.cc-processor.v1"
	IMExchange        = "im_delivery.broadcast"
)
