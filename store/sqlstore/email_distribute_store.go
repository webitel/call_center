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
	// Begin waits for a pooled connection only until ctx expires.
	tx, err := s.GetMaster().WithContext(ctx).(*gorp.DbMap).Begin()
	if err != nil {
		return nil, emailDistributeError(ctx, err)
	}
	defer tx.Rollback()

	ex := tx.WithContext(ctx)
	if _, err = ex.Exec(`select set_config('lock_timeout', $1, true), set_config('statement_timeout', $2, true)`,
		strconv.FormatInt(lockTimeout.Milliseconds(), 10), strconv.FormatInt(statementTimeout.Milliseconds(), 10)); err != nil {
		return nil, emailDistributeError(ctx, err)
	}

	var res []*model.EmailDistributeResult
	if _, err = ex.Select(&res, `select result, queue_id, attempt_id, agent_id
from call_center.cc_email_distribute(:QueueBatch::int4, make_interval(secs => :MaxSec::float8))`,
		map[string]any{"QueueBatch": queueBatch, "MaxSec": maxDuration.Seconds()}); err != nil {
		return nil, emailDistributeError(ctx, err)
	}

	if err = tx.Commit(); err != nil {
		return nil, emailDistributeError(ctx, err)
	}

	return res, nil
}

// emailDistributeError keeps the failure kind in the error id, so the caller can back off on timeouts.
func emailDistributeError(ctx context.Context, err error) *model.AppError {
	outcome := model.EmailDistributeError
	var pqErr *pq.Error
	switch {
	// A cancelled context also cancels the statement, so it is checked first.
	case errors.Is(err, context.DeadlineExceeded) || errors.Is(ctx.Err(), context.DeadlineExceeded):
		outcome = model.EmailDistributeContextTimeout
	case errors.As(err, &pqErr) && pqErr.Code == "55P03":
		outcome = model.EmailDistributeLockTimeout
	case errors.As(err, &pqErr) && pqErr.Code == "57014":
		outcome = model.EmailDistributeStatementTimeout
	}
	return model.NewAppError("SqlMemberStore.EmailDistribute", model.EmailDistributeErrorId(outcome), nil,
		err.Error(), extractCodeFromErr(err))
}
