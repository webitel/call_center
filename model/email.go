package model

import (
	"fmt"
	"net/http"
	"strings"
	"time"

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
	EventId         string
	DomainId        int64
	ThreadId        int64
	QueueId         int32
	Priority        int32
	StickyAgentId   int32
	ExtraEmailCount bool
	FromAddress     string
}

// IsValid checks the call before it reaches the store. New fields get an error id per field;
// priority and sticky agent keep the ids they had before IsValid.
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
	case j.Priority < 0:
		return NewAppError("EmailJoin.IsValid", EmailJoinInvalidPriority, nil,
			fmt.Sprintf("priority=%d", j.Priority), http.StatusBadRequest)
	case j.StickyAgentId < 0:
		return NewAppError("EmailJoin.IsValid", EmailJoinInvalidArguments, nil,
			fmt.Sprintf("sticky_agent_id=%d", j.StickyAgentId), http.StatusBadRequest)
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

// Ids of priority and sticky agent errors, shared by IsValid and cc_email_join_to_queue.
const (
	EmailJoinInvalidPriority  = "store.sql_member.email_join.invalid_priority"
	EmailJoinInvalidArguments = "store.sql_member.email_join.invalid"
)

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

// Rows of one Email distribution cycle; queue, attempt and agent depend on Result.
const (
	EmailDistributeAssigned        = "assigned"
	EmailDistributeBusy            = "busy"
	EmailDistributeNoAgent         = "no_agent"
	EmailDistributeNoSkills        = "no_skills"
	EmailDistributeCalendarClosed  = "calendar_closed"
	EmailDistributeCalendarInvalid = "calendar_invalid"
	EmailDistributeTimeLimit       = "time_limit"
	// The Queue is served with auto-release off: payload.email_auto_release_sec is not an integer 0…2147483647.
	EmailDistributePayloadInvalid = "payload_invalid"
)

type EmailDistributeResult struct {
	Result    string `db:"result"`
	QueueId   *int32 `db:"queue_id"`
	AttemptId *int64 `db:"attempt_id"`
	AgentId   *int32 `db:"agent_id"`
}

// Failure kinds of an Email distribution cycle, kept at the end of the AppError id.
const (
	EmailDistributeLockTimeout      = "lock_timeout"
	EmailDistributeStatementTimeout = "statement_timeout"
	EmailDistributeContextTimeout   = "context_timeout"
	EmailDistributeError            = "error"

	emailDistributeErrorId = "store.sql_member.email_distribute."
	emailLifecycleErrorId  = "store.sql_member.email_lifecycle."
)

func EmailDistributeErrorId(outcome string) string {
	return emailDistributeErrorId + outcome
}

// EmailDistributeOutcome tells the failure kind of an EmailDistribute error.
func EmailDistributeOutcome(err *AppError) string {
	return emailCycleOutcome(err, emailDistributeErrorId)
}

func EmailLifecycleErrorId(outcome string) string {
	return emailLifecycleErrorId + outcome
}

// EmailLifecycleOutcome tells the failure kind of an EmailLifecycleWatch error; the kinds are those of distribution.
func EmailLifecycleOutcome(err *AppError) string {
	return emailCycleOutcome(err, emailLifecycleErrorId)
}

func emailCycleOutcome(err *AppError, prefix string) string {
	if err == nil || !strings.HasPrefix(err.Id, prefix) {
		return EmailDistributeError
	}
	return strings.TrimPrefix(err.Id, prefix)
}

// EmailLifecycleResult counts the transitions of one lifecycle watcher cycle.
type EmailLifecycleResult struct {
	Released           int  `db:"released"`
	ProcessingTimeouts int  `db:"processing_timeouts"`
	PostponedWoken     int  `db:"postponed_woken"`
	PostponedQueued    int  `db:"postponed_queued"`
	OfflineReturned    int  `db:"offline_returned"`
	LockSkipped        int  `db:"lock_skipped"`
	TimeLimited        bool `db:"time_limited"`
}

// Operations and callers of an Email attempt command; system transitions are not commands.
const (
	EmailAttemptTake     = "take"
	EmailAttemptPostpone = "postpone"
	EmailAttemptResume   = "resume"
	EmailAttemptReturn   = "return"
	EmailAttemptComplete = "complete"
	EmailAttemptRenew    = "renew"

	EmailSourceEngine = "engine"
	EmailSourceFlow   = "flow"
)

// EmailAttemptCommand changes an Email attempt. Engine sets the attempt, agent and expected
// version; a Flow sets only the Thread and the event that woke it.
type EmailAttemptCommand struct {
	Op              string
	Source          string
	CommandId       string
	DomainId        int64
	ThreadId        int64
	AttemptId       *int64
	AgentId         *int32
	ExpectedVersion *int64
	EmailEventId    *string
	PostponedUntil  *time.Time
	PostponeForSec  *int32
	RenewalSec      *int32
}

// EmailAttemptResult is the attempt after the command, or after its first execution when Replayed.
type EmailAttemptResult struct {
	Replayed          bool       `db:"replayed"`
	AttemptId         int64      `db:"attempt_id"`
	ThreadId          int64      `db:"thread_id"`
	State             string     `db:"attempt_state"`
	AttemptVersion    int64      `db:"attempt_version"`
	ProjectionVersion int64      `db:"projection_version"`
	Result            *string    `db:"result"`
	QueueId           int32      `db:"queue_id"`
	AgentId           *int32     `db:"agent_id"`
	PostponedUntil    *time.Time `db:"postponed_until"`
}

// Stable ids of Email attempt command errors.
const (
	EmailAttemptErrInvalidArgument       = "cc.email_attempt.invalid_argument"
	EmailAttemptErrNotFound              = "cc.email_attempt.not_found"
	EmailAttemptErrWakeupRequired        = "cc.email_attempt.wakeup_required"
	EmailAttemptErrOwnerMismatch         = "cc.email_attempt.owner_mismatch"
	EmailAttemptErrVersionConflict       = "cc.email_attempt.version_conflict"
	EmailAttemptErrInvalidState          = "cc.email_attempt.invalid_state"
	EmailAttemptErrAgentOffline          = "cc.email_attempt.agent_offline"
	EmailAttemptErrAgentIneligible       = "cc.email_attempt.agent_ineligible"
	EmailAttemptErrSlotExhausted         = "cc.email_attempt.slot_exhausted"
	EmailAttemptErrPostponedLimit        = "cc.email_attempt.postponed_limit_exhausted"
	EmailAttemptErrProlongationLimit     = "cc.email_attempt.prolongation_exhausted"
	EmailAttemptErrCommandConflict       = "cc.email_attempt.command_id_conflict"
	EmailAttemptErrSerializationConflict = "cc.email_attempt.serialization_conflict"
	EmailAttemptErrDeadlock              = "cc.email_attempt.deadlock"
	EmailAttemptErrLockTimeout           = "cc.email_attempt.lock_timeout"
	EmailAttemptErrUnavailable           = "cc.email_attempt.unavailable"
	EmailAttemptErrInternal              = "cc.email_attempt.app_error"
)

// Results of waking the active attempt of a Thread by an inbound Email event.
const (
	EmailWakeupWoken     = "woken"
	EmailWakeupQueued    = "queued"
	EmailWakeupReopened  = "reopened"
	EmailWakeupNoop      = "noop"
	EmailWakeupNotActive = "not_active"

	EmailWakeupErrEventConflict = "cc.email_wakeup.event_conflict"
)

// EmailWakeUp asks to wake the active attempt of a Thread once per inbound Email event.
type EmailWakeUp struct {
	EventId  string
	DomainId int64
	ThreadId int64
}

// EmailWakeUpResult is the kept result of the event; AttemptId is nil for not_active.
type EmailWakeUpResult struct {
	Result         string  `db:"wakeup_result"`
	AttemptId      *int64  `db:"wakeup_attempt_id"`
	AttemptState   *string `db:"wakeup_attempt_state"`
	AttemptVersion *int64  `db:"wakeup_attempt_version"`
	Replayed       bool    `db:"wakeup_replayed"`
}
