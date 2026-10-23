-- After email_routing_update.sql and email_routing_validate.sql.
-- Run with psql -v ON_ERROR_STOP=1 -f, outside a transaction (no --single-transaction).
\set ON_ERROR_STOP on

-- IF NOT EXISTS would skip an invalid index left by an interrupted build.
-- Emit separate top-level commands: CONCURRENTLY is not allowed inside DO.
SELECT format('DROP INDEX CONCURRENTLY %I.%I', 'call_center', c.relname)
FROM pg_index i
         JOIN pg_class c ON c.oid = i.indexrelid
         JOIN (VALUES
             ('cc_member_attempt_email_number_idx', 'call_center.cc_member_attempt'::regclass),
             ('cc_member_attempt_history_email_number_idx', 'call_center.cc_member_attempt_history'::regclass)
         ) expected(index_name, table_id) ON c.relname = expected.index_name AND i.indrelid = expected.table_id
WHERE c.relnamespace = 'call_center'::regnamespace AND NOT i.indisvalid
ORDER BY c.relname
\gexec

-- Finished Email attempts not yet moved to history.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_number_idx
    ON call_center.cc_member_attempt (domain_id, (destination ->> 'number'), leaving_at DESC)
    WHERE channel = 'email' AND state = 'leaving';

CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_history_email_number_idx
    ON call_center.cc_member_attempt_history (domain_id, (destination ->> 'number'), leaving_at DESC)
    WHERE channel = 'email';
