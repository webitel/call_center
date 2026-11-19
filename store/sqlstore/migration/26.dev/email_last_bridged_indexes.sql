-- After email_routing_update.sql and email_routing_validate.sql.
-- Run with psql -v ON_ERROR_STOP=1 -f, outside a transaction (no --single-transaction): the history
-- index is built CONCURRENTLY, as cc_member_attempt_history can be large.
\set ON_ERROR_STOP on

-- Finished Email attempts not yet moved to history.
CREATE INDEX IF NOT EXISTS cc_member_attempt_email_number_idx
    ON call_center.cc_member_attempt (domain_id, (destination ->> 'number'), leaving_at DESC)
    WHERE channel = 'email' AND state = 'leaving';

-- IF NOT EXISTS would skip an invalid index left by an interrupted build.
-- Emit a separate top-level command: CONCURRENTLY is not allowed inside DO.
SELECT 'DROP INDEX CONCURRENTLY call_center.cc_member_attempt_history_email_number_idx'
FROM pg_index i
WHERE i.indexrelid = to_regclass('call_center.cc_member_attempt_history_email_number_idx')
  AND NOT i.indisvalid
\gexec

CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_history_email_number_idx
    ON call_center.cc_member_attempt_history (domain_id, (destination ->> 'number'), leaving_at DESC)
    WHERE channel = 'email';
