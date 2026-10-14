package sqlstore

import (
	"context"
	"errors"
	"strconv"
	"time"

	"github.com/go-gorp/gorp"
	"github.com/lib/pq"

	"github.com/webitel/call_center/model"
)

// EmailDistribute runs cc_email_distribute in a short transaction; maxDuration lets the cycle
// commit its work before the timeouts, which only guard against a stuck cycle.
func (s *SqlMemberStore) EmailDistribute(ctx context.Context, queueBatch int, maxDuration, lockTimeout, statementTimeout time.Duration) ([]*model.EmailDistributeResult, *model.AppError) {
	var res []*model.EmailDistributeResult
	err := s.inEmailCycleTx(ctx, lockTimeout, statementTimeout, func(ex gorp.SqlExecutor) error {
		_, err := ex.Select(&res, `select result, queue_id, attempt_id, agent_id
from call_center.cc_email_distribute(:QueueBatch::int4, make_interval(secs => :MaxSec::float8))`,
			map[string]any{"QueueBatch": queueBatch, "MaxSec": maxDuration.Seconds()})
		return err
	})
	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.EmailDistribute", model.EmailDistributeErrorId(emailCycleOutcome(ctx, err)), nil,
			err.Error(), extractCodeFromErr(err))
	}

	return res, nil
}

// EmailLifecycleWatch runs cc_email_lifecycle_watch like a distribution cycle; maxDuration lets it commit in time.
func (s *SqlMemberStore) EmailLifecycleWatch(ctx context.Context, batch int, maxDuration, lockTimeout, statementTimeout time.Duration) (*model.EmailLifecycleResult, *model.AppError) {
	var res model.EmailLifecycleResult
	err := s.inEmailCycleTx(ctx, lockTimeout, statementTimeout, func(ex gorp.SqlExecutor) error {
		return ex.SelectOne(&res, `select released, processing_timeouts, postponed_woken, postponed_queued, offline_returned, lock_skipped, time_limited
from call_center.cc_email_lifecycle_watch(:Batch::int4, make_interval(secs => :MaxSec::float8))`,
			map[string]any{"Batch": batch, "MaxSec": maxDuration.Seconds()})
	})
	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.EmailLifecycleWatch", model.EmailLifecycleErrorId(emailCycleOutcome(ctx, err)), nil,
			err.Error(), extractCodeFromErr(err))
	}

	return &res, nil
}

// inEmailCycleTx runs fn in a short transaction with transaction-local lock and statement timeouts.
func (s *SqlMemberStore) inEmailCycleTx(ctx context.Context, lockTimeout, statementTimeout time.Duration, fn func(ex gorp.SqlExecutor) error) error {
	// Begin waits for a pooled connection only until ctx expires.
	tx, err := s.GetMaster().WithContext(ctx).(*gorp.DbMap).Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	ex := tx.WithContext(ctx)
	if _, err = ex.Exec(`select set_config('lock_timeout', $1, true), set_config('statement_timeout', $2, true)`,
		strconv.FormatInt(lockTimeout.Milliseconds(), 10), strconv.FormatInt(statementTimeout.Milliseconds(), 10)); err != nil {
		return err
	}
	if err = fn(ex); err != nil {
		return err
	}

	return tx.Commit()
}

// emailCycleOutcome is the failure kind kept in the error id, so the caller can back off on timeouts.
func emailCycleOutcome(ctx context.Context, err error) string {
	var pqErr *pq.Error
	switch {
	// A cancelled context also cancels the statement, so it is checked first.
	case errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded):
		return model.EmailDistributeContextTimeout
	case errors.As(err, &pqErr) && pqErr.Code == "55P03":
		return model.EmailDistributeLockTimeout
	case errors.As(err, &pqErr) && pqErr.Code == "57014":
		return model.EmailDistributeStatementTimeout
	}
	return model.EmailDistributeError
}
