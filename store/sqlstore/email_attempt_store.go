package sqlstore

import (
	"context"
	"database/sql/driver"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"time"

	"github.com/go-gorp/gorp"
	"github.com/lib/pq"

	"github.com/webitel/call_center/model"
)

// EmailAttemptCommand runs cc_email_attempt_command in a short transaction; lockTimeout bounds the
// wait for the locks of the agent, its Email channel and the attempt.
func (s *SqlMemberStore) EmailAttemptCommand(ctx context.Context, cmd model.EmailAttemptCommand, lockTimeout time.Duration) (*model.EmailAttemptResult, *model.AppError) {
	var res model.EmailAttemptResult
	err := s.inEmailTx(ctx, lockTimeout, func(ex gorp.SqlExecutor) error {
		return ex.SelectOne(&res, `select x.replayed, x.attempt_id, x.thread_id, x.attempt_state, x.attempt_version,
       x.projection_version, x.result, x.queue_id, x.agent_id, x.postponed_until
from call_center.cc_email_attempt_command(:Op::text, :Source::text, :CommandId::text, :DomainId::int8, :ThreadId::int8,
     :AttemptId::int8, :AgentId::int4, :ExpectedVersion::int8, :EmailEventId::uuid, :PostponedUntil::timestamptz,
     :PostponeForSec::int4, :RenewalSec::int4) x`, map[string]any{
			"Op":              cmd.Op,
			"Source":          cmd.Source,
			"CommandId":       cmd.CommandId,
			"DomainId":        cmd.DomainId,
			"ThreadId":        cmd.ThreadId,
			"AttemptId":       cmd.AttemptId,
			"AgentId":         cmd.AgentId,
			"ExpectedVersion": cmd.ExpectedVersion,
			"EmailEventId":    cmd.EmailEventId,
			"PostponedUntil":  cmd.PostponedUntil,
			"PostponeForSec":  cmd.PostponeForSec,
			"RenewalSec":      cmd.RenewalSec,
		})
	})
	if err != nil {
		return nil, emailLifecycleError("SqlMemberStore.EmailAttemptCommand", fmt.Sprintf("Op=%s, Source=%s, CommandId=%s, DomainId=%d, ThreadId=%d",
			cmd.Op, cmd.Source, cmd.CommandId, cmd.DomainId, cmd.ThreadId), err)
	}

	return &res, nil
}

// EmailWakeUp runs cc_email_wakeup_thread in a short transaction under lockTimeout.
func (s *SqlMemberStore) EmailWakeUp(ctx context.Context, in model.EmailWakeUp, lockTimeout time.Duration) (*model.EmailWakeUpResult, *model.AppError) {
	var res model.EmailWakeUpResult
	err := s.inEmailTx(ctx, lockTimeout, func(ex gorp.SqlExecutor) error {
		return ex.SelectOne(&res, `select x.wakeup_result, x.wakeup_attempt_id, x.wakeup_attempt_state, x.wakeup_attempt_version, x.wakeup_replayed,
       x.wakeup_fallback_queue_id
from call_center.cc_email_wakeup_thread(:EventId::uuid, :DomainId::int8, :ThreadId::int8) x`,
			map[string]any{"EventId": in.EventId, "DomainId": in.DomainId, "ThreadId": in.ThreadId})
	})
	if err != nil {
		return nil, emailLifecycleError("SqlMemberStore.EmailWakeUp", fmt.Sprintf("EventId=%s, DomainId=%d, ThreadId=%d",
			in.EventId, in.DomainId, in.ThreadId), err)
	}

	return &res, nil
}

// inEmailTx runs fn in a short transaction whose lock waits are bounded by lockTimeout.
func (s *SqlMemberStore) inEmailTx(ctx context.Context, lockTimeout time.Duration, fn func(ex gorp.SqlExecutor) error) error {
	tx, err := s.GetMaster().WithContext(ctx).(*gorp.DbMap).Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	ex := tx.WithContext(ctx)
	if _, err = ex.Exec(`select set_config('lock_timeout', $1, true)`, strconv.FormatInt(lockTimeout.Milliseconds(), 10)); err != nil {
		return err
	}
	if err = fn(ex); err != nil {
		return err
	}

	return tx.Commit()
}

// emailLifecycleError gives a stable error id; grpc_api maps the id to a gRPC code.
func emailLifecycleError(where, details string, err error) *model.AppError {
	id, code := model.EmailAttemptErrInternal, http.StatusInternalServerError

	var pqErr *pq.Error
	var netErr net.Error
	switch {
	case errors.As(err, &pqErr):
		switch pqErr.Code {
		case "EMAAR", "22023", "22P02":
			id, code = model.EmailAttemptErrInvalidArgument, http.StatusBadRequest
		case "EMANF":
			id, code = model.EmailAttemptErrNotFound, http.StatusNotFound
		case "EMAWK":
			id, code = model.EmailAttemptErrWakeupRequired, http.StatusPreconditionFailed
		case "EMAOW":
			id, code = model.EmailAttemptErrOwnerMismatch, http.StatusPreconditionFailed
		case "EMAST":
			id, code = model.EmailAttemptErrInvalidState, http.StatusPreconditionFailed
		case "EMAOF":
			id, code = model.EmailAttemptErrAgentOffline, http.StatusPreconditionFailed
		case "EMAEL":
			id, code = model.EmailAttemptErrAgentIneligible, http.StatusPreconditionFailed
		case "EMASL":
			id, code = model.EmailAttemptErrSlotExhausted, http.StatusTooManyRequests
		case "EMAVR":
			id, code = model.EmailAttemptErrVersionConflict, http.StatusConflict
		case "EMACF":
			id, code = model.EmailAttemptErrCommandConflict, http.StatusConflict
		case "EMWKY":
			id, code = model.EmailWakeupErrEventConflict, http.StatusConflict
		case "EMAPL":
			id, code = model.EmailAttemptErrPostponedLimit, http.StatusTooManyRequests
		case "EMAPX":
			id, code = model.EmailAttemptErrProlongationLimit, http.StatusTooManyRequests
		case "40001":
			id, code = model.EmailAttemptErrSerializationConflict, http.StatusConflict
		case "40P01":
			id, code = model.EmailAttemptErrDeadlock, http.StatusConflict
		case "55P03":
			id, code = model.EmailAttemptErrLockTimeout, http.StatusServiceUnavailable
		case "53300", "57P01", "57P02", "57P03":
			id, code = model.EmailAttemptErrUnavailable, http.StatusServiceUnavailable
		default:
			if pqErr.Code.Class() == "08" {
				id, code = model.EmailAttemptErrUnavailable, http.StatusServiceUnavailable
			}
		}
	case errors.Is(err, driver.ErrBadConn) || errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) ||
		errors.As(err, &netErr) || errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled):
		id, code = model.EmailAttemptErrUnavailable, http.StatusServiceUnavailable
	}

	return model.NewAppError(where, id, nil, details+": "+err.Error(), code)
}

// IsEmailAttempt tells whether an active attempt of the domain is an Email one, which the attempt
// cache never holds.
func (s *SqlMemberStore) IsEmailAttempt(ctx context.Context, domainId, attemptId int64) (bool, *model.AppError) {
	n, err := s.GetMaster().WithContext(ctx).SelectInt(`select count(*)
from call_center.cc_member_attempt a
where a.id = :Id and a.domain_id = :DomainId and a.channel = 'email' and a.leaving_at is null`,
		map[string]any{"Id": attemptId, "DomainId": domainId})
	if err != nil {
		return false, model.NewAppError("SqlMemberStore.IsEmailAttempt", "store.sql_member.is_email_attempt.app_error", nil,
			err.Error(), extractCodeFromErr(err))
	}

	return n > 0, nil
}
