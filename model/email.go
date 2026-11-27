package model

import (
	"fmt"
	"net/http"

	"github.com/pborman/uuid"
)

// Results of joining an email-service Thread to an Inbound Email Queue.
const (
	EmailJoinCreated       = "created"
	EmailJoinAlreadyActive = "already_active"
	EmailJoinReplayed      = "replayed"
)

// EmailJoin asks to put an email-service Thread into an Inbound Email Queue;
// EventId is the idempotency key of the call.
type EmailJoin struct {
	EventId  string
	DomainId int64
	ThreadId int64
	QueueId  int32
}

// IsValid checks the call before it reaches the store; the error id names the field.
func (j *EmailJoin) IsValid() *AppError {
	switch {
	case j.DomainId <= 0:
		return emailJoinInvalid("domain_id", fmt.Sprintf("domain_id=%d", j.DomainId))
	case j.ThreadId <= 0:
		return emailJoinInvalid("thread_id", fmt.Sprintf("thread_id=%d", j.ThreadId))
	case j.QueueId <= 0:
		return emailJoinInvalid("queue_id", fmt.Sprintf("queue_id=%d", j.QueueId))
	case !IsEmailEventId(j.EventId):
		return emailJoinInvalid("email_event_id", "email_event_id="+j.EventId)
	}

	return nil
}

func emailJoinInvalid(field, details string) *AppError {
	return NewAppError("EmailJoin.IsValid", "model.email_join.is_valid."+field+".app_error", nil,
		details, http.StatusBadRequest)
}

// IsEmailEventId checks the email-service event id, the idempotency key of Email calls.
// flow_manager validates it on receipt; only the 36-character UUID form is accepted,
// while uuid.Parse also takes the urn: one.
func IsEmailEventId(s string) bool {
	return len(s) == 36 && uuid.Parse(s) != nil
}

// EmailJoinResult is the attempt the Thread ended up in. RequestedQueueId is the
// queue of the first call with this event, which a replay may not repeat.
type EmailJoinResult struct {
	Result           string `db:"join_result"`
	AttemptId        int64  `db:"join_attempt_id"`
	QueueId          int32  `db:"join_queue_id"`
	RequestedQueueId int32  `db:"join_requested_queue_id"`
}

// ReplayedWithAnotherQueue reports whether this event was replayed
// with a requested queue different from the first call.
func (r *EmailJoinResult) ReplayedWithAnotherQueue(queueId int32) bool {
	return r.Result == EmailJoinReplayed && r.RequestedQueueId != queueId
}
