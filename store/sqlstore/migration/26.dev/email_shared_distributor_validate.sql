-- After email_shared_distributor_prepare.sql commits; no enclosing transaction.
SET lock_timeout = '5s';

ALTER TABLE call_center.cc_email_join
    VALIDATE CONSTRAINT cc_email_join_priority_c;

RESET lock_timeout;

-- A failed CONCURRENTLY build leaves an invalid index that IF NOT EXISTS would skip.
SELECT 'DROP INDEX CONCURRENTLY call_center.cc_member_attempt_email_waiting_idx'
FROM pg_index i
WHERE i.indexrelid = to_regclass('call_center.cc_member_attempt_email_waiting_idx') AND NOT i.indisvalid
\gexec

-- Waiting unassigned letters in queue-age order: the shared selection stops at the first assignable one.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_waiting_idx
    ON call_center.cc_member_attempt (queue_id, joined_at, id)
    WHERE channel = 'email' AND state = 'waiting' AND agent_id IS NULL AND leaving_at IS NULL AND email_slot_type IS NULL;
