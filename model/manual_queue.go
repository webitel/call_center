package model

import "encoding/json"

type MemberWaiting struct {
	Position      int             `json:"position" db:"position"`
	AttemptId     int64           `json:"attempt_id" db:"attempt_id"`
	Wait          int             `json:"wait" db:"wait"`
	Communication json.RawMessage `json:"communication" db:"communication"`
	Queue         Lookup          `json:"queue" db:"queue"`
	Bucket        *Lookup         `json:"bucket,omitempty" db:"bucket"`
	Deadline      int             `json:"deadline" db:"deadline"`
	Channel       string          `json:"channel" db:"channel"`
}

type MemberWaitingByUsers struct {
	DomainId int64            `json:"-" db:"domain_id"`
	Users    Int64Array       `json:"-" db:"users"`
	Members  []*MemberWaiting `json:"-" db:"members"`
}
