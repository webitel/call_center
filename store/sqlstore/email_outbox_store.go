package sqlstore

import (
	"context"
	"sort"
	"time"

	"github.com/lib/pq"

	"github.com/webitel/call_center/model"
)

const emailOutboxErrorId = "store.sql_member.email_outbox.app_error"

// EmailOutboxClaim leases up to batch ready rows of cc_email_attempt_outbox to owner; rows of another
// publisher are skipped, and an expired lease is claimed again.
func (s *SqlMemberStore) EmailOutboxClaim(ctx context.Context, owner string, batch int, lease time.Duration) ([]*model.EmailOutboxRow, *model.AppError) {
	var rows []*model.EmailOutboxRow
	_, err := s.GetMaster().WithContext(ctx).Select(&rows, `with ready as (
    select o.sequence
    from call_center.cc_email_attempt_outbox o
    where o.published_at is null
      and o.next_attempt_at <= now()
      and (o.locked_until is null or o.locked_until < now())
    order by o.next_attempt_at, o.sequence
    limit :Batch
    for update skip locked
)
update call_center.cc_email_attempt_outbox o
set locked_by = :Owner, locked_until = now() + :LeaseMs * interval '1 millisecond'
from ready
where o.sequence = ready.sequence
returning o.sequence, o.domain_id, o.thread_id, o.attempt_id, o.attempt_version, o.attempt_state, o.result, o.queue_id,
          o.agent_id, o.agent_user_id, o.postponed_until, o.transition, o.source, o.causation_id, o.occurred_at`,
		map[string]any{"Batch": batch, "Owner": owner, "LeaseMs": lease.Milliseconds()})
	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.EmailOutboxClaim", emailOutboxErrorId, nil, err.Error(), extractCodeFromErr(err))
	}

	sort.Slice(rows, func(i, j int) bool { return rows[i].Sequence < rows[j].Sequence })
	return rows, nil
}

// EmailOutboxPublished marks rows of owner published after the broker confirmed them; a row whose
// lease another publisher took meanwhile is not counted.
func (s *SqlMemberStore) EmailOutboxPublished(ctx context.Context, owner string, sequences []int64) (int64, *model.AppError) {
	res, err := s.GetMaster().WithContext(ctx).Exec(`update call_center.cc_email_attempt_outbox
set published_at = now(), locked_by = null, locked_until = null, last_error = null
where sequence = any(:Sequences) and locked_by = :Owner and published_at is null`,
		map[string]any{"Sequences": pq.Array(sequences), "Owner": owner})
	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.EmailOutboxPublished", emailOutboxErrorId, nil, err.Error(), extractCodeFromErr(err))
	}

	n, _ := res.RowsAffected()
	return n, nil
}

// EmailOutboxRelease gives rows of owner back for a retry at next; failed counts an attempt only for
// rows whose own publish failed, never for a broker outage.
func (s *SqlMemberStore) EmailOutboxRelease(ctx context.Context, owner string, sequences []int64, next time.Time, reason string, failed bool) *model.AppError {
	_, err := s.GetMaster().WithContext(ctx).Exec(`update call_center.cc_email_attempt_outbox
set locked_by = null, locked_until = null, next_attempt_at = :Next, last_error = left(:Reason, 1024),
    attempts = attempts + case when :Failed then 1 else 0 end
where sequence = any(:Sequences) and locked_by = :Owner and published_at is null`,
		map[string]any{"Sequences": pq.Array(sequences), "Owner": owner, "Next": next, "Reason": reason, "Failed": failed})
	if err != nil {
		return model.NewAppError("SqlMemberStore.EmailOutboxRelease", emailOutboxErrorId, nil, err.Error(), extractCodeFromErr(err))
	}

	return nil
}

// EmailOutboxCleanup deletes up to limit published rows without a command older than before; command
// rows keep the response of a repeated command.
func (s *SqlMemberStore) EmailOutboxCleanup(ctx context.Context, before time.Time, limit int) (int64, *model.AppError) {
	res, err := s.GetMaster().WithContext(ctx).Exec(`delete from call_center.cc_email_attempt_outbox
where sequence in (
    select o.sequence
    from call_center.cc_email_attempt_outbox o
    where o.published_at is not null and o.published_at < :Before and o.command_id is null
    order by o.published_at
    limit :Limit
    for update skip locked
)`, map[string]any{"Before": before, "Limit": limit})
	if err != nil {
		return 0, model.NewAppError("SqlMemberStore.EmailOutboxCleanup", emailOutboxErrorId, nil, err.Error(), extractCodeFromErr(err))
	}

	n, _ := res.RowsAffected()
	return n, nil
}

// EmailOutboxBacklog counts unpublished rows and finds the oldest of them.
func (s *SqlMemberStore) EmailOutboxBacklog(ctx context.Context) (*model.EmailOutboxBacklog, *model.AppError) {
	var res model.EmailOutboxBacklog
	err := s.GetMaster().WithContext(ctx).SelectOne(&res, `select count(*) as pending, min(o.occurred_at) as oldest_at
from call_center.cc_email_attempt_outbox o
where o.published_at is null`)
	if err != nil {
		return nil, model.NewAppError("SqlMemberStore.EmailOutboxBacklog", emailOutboxErrorId, nil, err.Error(), extractCodeFromErr(err))
	}

	return &res, nil
}
