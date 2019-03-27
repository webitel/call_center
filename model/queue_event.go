package model

const (
	QUEUE_EVENT_COUNT          = "queue_count"
	QUEUE_EVENT_JOIN_MEMBER    = "queue_member_join"
	QUEUE_EVENT_LEAVING_MEMBER = "queue_member_leaving"
)

type QueueEvent struct {
	Name   string `json:"name"`
	Node   string `json:"node"`
	Domain string `json:"domain"`
}

type QueueEventCount struct {
	QueueEvent
	Count int64 `json:"count"`
}

type QueueEventJoinMember struct {
	QueueEvent
}

type QueueEventLeavingMember struct {
	QueueEvent
}
