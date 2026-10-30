package model

import (
	"strconv"
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

// EmailWakeUpResult is the kept result of the event; AttemptId is nil for not_active, and FallbackQueueId
// is the queue of the last finished attempt for not_active.
type EmailWakeUpResult struct {
	Result          string  `db:"wakeup_result"`
	AttemptId       *int64  `db:"wakeup_attempt_id"`
	AttemptState    *string `db:"wakeup_attempt_state"`
	AttemptVersion  *int64  `db:"wakeup_attempt_version"`
	Replayed        bool    `db:"wakeup_replayed"`
	FallbackQueueId *int32  `db:"wakeup_fallback_queue_id"`
}

// Contract and topology of the Email attempt snapshots for email-service,
// described in docs/events.md of webitel-emails. Every object is durable.
const (
	EmailSnapshotEventType   = "cc.email.attempt.snapshot"
	EmailSnapshotSchema      = 1
	EmailSnapshotExchange    = "cc.email.events"
	EmailSnapshotRoutingKey  = "cc.email.attempt.snapshot.v1"
	EmailSnapshotContentType = "application/json"

	// Declared by email-service, the consumer; both queues are quorum.
	EmailSnapshotQueue                = "email.thread.projection"
	EmailSnapshotDeadLetterExchange   = "cc.email.events.dlx"
	EmailSnapshotDeadLetterQueue      = "email.thread.projection.dlq"
	EmailSnapshotDefaultDeliveryLimit = 20

	EmailSnapshotHeaderEventId       = "x-event-id"
	EmailSnapshotHeaderEventType     = "x-event-type"
	EmailSnapshotHeaderSchemaVersion = "x-schema-version"

	// Marker of a new email in a Thread without an active attempt; it has no attempt.
	EmailTransitionInboundReopened = "inbound_reopened"
)

// emailSnapshotNamespace makes the event id of an outbox row stable across republishing.
var emailSnapshotNamespace = uuid.Parse("9ea89e50-dddc-4e4e-b517-6be31cb9dfdc")

// EmailSnapshotEvent is one cc_email_attempt_outbox row on the wire. Nulls are
// sent explicitly; attempt fields are null only in the inbound_reopened marker.
type EmailSnapshotEvent struct {
	EventId       string    `json:"event_id"`
	EventType     string    `json:"event_type"`
	SchemaVersion int       `json:"schema_version"`
	OccurredAt    time.Time `json:"occurred_at"`

	DomainId          int64   `json:"domain_id"`
	ThreadId          int64   `json:"thread_id"`
	ProjectionVersion int64   `json:"projection_version"`
	Transition        string  `json:"transition"`
	Source            string  `json:"source"`
	CausationId       *string `json:"causation_id"`

	AttemptId      *int64     `json:"attempt_id"`
	AttemptVersion *int64     `json:"attempt_version"`
	AttemptState   *string    `json:"attempt_state"`
	Result         *string    `json:"result"`
	QueueId        *int32     `json:"queue_id"`
	AgentId        *int32     `json:"agent_id"`
	AgentUserId    *int64     `json:"agent_user_id"`
	PostponedUntil *time.Time `json:"postponed_until"`
}

// EmailSnapshotEventId is the UUIDv5 of the event type and the outbox sequence.
func EmailSnapshotEventId(sequence int64) string {
	return uuid.NewSHA1(emailSnapshotNamespace, []byte(EmailSnapshotEventType+":"+strconv.FormatInt(sequence, 10))).String()
}

// EmailOutboxRow is a cc_email_attempt_outbox row claimed by the snapshot publisher.
type EmailOutboxRow struct {
	Sequence       int64      `db:"sequence"`
	DomainId       int64      `db:"domain_id"`
	ThreadId       int64      `db:"thread_id"`
	AttemptId      *int64     `db:"attempt_id"`
	AttemptVersion *int64     `db:"attempt_version"`
	AttemptState   *string    `db:"attempt_state"`
	Result         *string    `db:"result"`
	QueueId        *int32     `db:"queue_id"`
	AgentId        *int32     `db:"agent_id"`
	AgentUserId    *int64     `db:"agent_user_id"`
	PostponedUntil *time.Time `db:"postponed_until"`
	Transition     string     `db:"transition"`
	Source         string     `db:"source"`
	CausationId    *string    `db:"causation_id"`
	OccurredAt     time.Time  `db:"occurred_at"`
}

// Event renders the row as its cc.email.attempt.snapshot event.
func (r *EmailOutboxRow) Event() EmailSnapshotEvent {
	return EmailSnapshotEvent{
		EventId:           EmailSnapshotEventId(r.Sequence),
		EventType:         EmailSnapshotEventType,
		SchemaVersion:     EmailSnapshotSchema,
		OccurredAt:        r.OccurredAt.UTC(),
		DomainId:          r.DomainId,
		ThreadId:          r.ThreadId,
		ProjectionVersion: r.Sequence,
		Transition:        r.Transition,
		Source:            r.Source,
		CausationId:       r.CausationId,
		AttemptId:         r.AttemptId,
		AttemptVersion:    r.AttemptVersion,
		AttemptState:      r.AttemptState,
		Result:            r.Result,
		QueueId:           r.QueueId,
		AgentId:           r.AgentId,
		AgentUserId:       r.AgentUserId,
		PostponedUntil:    r.PostponedUntil,
	}
}

// EmailOutboxBacklog is what the snapshot publisher has not sent yet.
type EmailOutboxBacklog struct {
	Pending  int64      `db:"pending"`
	OldestAt *time.Time `db:"oldest_at"`
}
