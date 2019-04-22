package model

import "encoding/json"

const (
	QUEUE_EVENT_COUNT = "queue_count" // delete

	QUEUE_EVENT_JOIN_MEMBER    = "queue_member_join"
	QUEUE_EVENT_LEAVING_MEMBER = "queue_member_leaving"

	QUEUE_EVENT_OFFERING_MEMBER  = "queue_member_offering"
	QUEUE_EVENT_BRIDGED_MEMBER   = "queue_member_bridged"
	QUEUE_EVENT_UNBRIDGED_MEMBER = "queue_member_unbridged"
)

type QueueEvent struct {
	Name    string `json:"name"`
	Node    string `json:"node"`
	Domain  string `json:"domain"`
	Time    int64  `json:"time"`
	QueueId int64  `json:"queue_id"`
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

func (e *QueueEventCount) ToJSON() string {
	data, _ := json.Marshal(e)
	return string(data)
}
