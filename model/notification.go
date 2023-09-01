package model

import "encoding/json"

const (
	NotificationHideMember  = "hide_member"
	NotificationHideAttempt = "hide_attempt"
	NotificationWaitingList = "waiting_list"
)

type Notification struct {
	Id        int64      `json:"id" db:"id"`
	DomainId  int64      `json:"-" db:"domain_id"`
	Action    string     `json:"action" db:"action"`
	Timeout   *int64     `json:"timeout,omitempty" db:"timeout"`
	CreatedAt int64      `json:"created_at" db:"created_at"`
	CreatedBy *int64     `json:"created_by,omitempty" db:"created_by"`
	ForUsers  Int64Array `json:"for_users" db:"for_users"`

	Description string      `json:"description,omitempty" db:"description"`
	Body        interface{} `json:"body,omitempty"`
}

func (n *Notification) ToJson() []byte {
	data, _ := json.Marshal(n)
	return data
}
