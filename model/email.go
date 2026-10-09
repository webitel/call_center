package model

import "strings"

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
)

func EmailDistributeErrorId(outcome string) string {
	return emailDistributeErrorId + outcome
}

// EmailDistributeOutcome tells the failure kind of an EmailDistribute error.
func EmailDistributeOutcome(err *AppError) string {
	if err == nil || !strings.HasPrefix(err.Id, emailDistributeErrorId) {
		return EmailDistributeError
	}
	return strings.TrimPrefix(err.Id, emailDistributeErrorId)
}
