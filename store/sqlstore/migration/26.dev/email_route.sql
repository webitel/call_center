-- Route of an email-service event in the flow_manager Inbox: the Flow may choose a queue until the
-- deadline, after it the route watcher joins the fallback queue that call_center found at wake-up.
-- Run with psql -v ON_ERROR_STOP=1 -f after email_service_inbox.sql outside a transaction: the index
-- is built CONCURRENTLY, and psql runs the generated \gexec drop. Every step can be repeated. Rows
-- written before stay with route_state NULL.

ALTER TABLE flow.email_event
    ADD COLUMN IF NOT EXISTS route_state        text,
    -- flow or fallback: who chose route_queue_id.
    ADD COLUMN IF NOT EXISTS route_source       text,
    -- Queue of the intent while joining, the queue call_center answered once routed.
    ADD COLUMN IF NOT EXISTS route_queue_id     integer,
    ADD COLUMN IF NOT EXISTS fallback_queue_id  integer,
    -- The Flow may write its intent only before this time.
    ADD COLUMN IF NOT EXISTS route_due_at       timestamp with time zone,
    -- When the route watcher may take the row; equals route_due_at while pending.
    ADD COLUMN IF NOT EXISTS route_next_at      timestamp with time zone,
    -- Lease of joinQueue or the route watcher; independent of the lease of the Inbox worker.
    ADD COLUMN IF NOT EXISTS route_locked_by    text,
    ADD COLUMN IF NOT EXISTS route_locked_until timestamp with time zone,
    -- Failed joins of the route watcher.
    ADD COLUMN IF NOT EXISTS route_attempts     integer NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS route_last_error   text,
    ADD COLUMN IF NOT EXISTS route_reason       text;

ALTER TABLE flow.email_event
    DROP CONSTRAINT IF EXISTS email_event_route_state_valid,
    ADD CONSTRAINT email_event_route_state_valid
        CHECK (route_state IS NULL OR route_state IN (
            'not_needed', 'pending', 'joining', 'resolving', 'routed', 'unrouted', 'route_failed'
        )),
    DROP CONSTRAINT IF EXISTS email_event_route_source_valid,
    ADD CONSTRAINT email_event_route_source_valid
        CHECK (route_source IS NULL OR route_source IN ('flow', 'fallback')),
    -- An unfinished route has a deadline and a time for the watcher.
    DROP CONSTRAINT IF EXISTS email_event_route_open_valid,
    ADD CONSTRAINT email_event_route_open_valid
        CHECK (coalesce(route_state, '') NOT IN ('pending', 'joining', 'resolving')
            OR (route_due_at IS NOT NULL AND route_next_at IS NOT NULL)),
    -- The intent of the Flow and a finished route keep their queue; waiting and fallback have none yet.
    DROP CONSTRAINT IF EXISTS email_event_route_queue_valid,
    ADD CONSTRAINT email_event_route_queue_valid
        CHECK (
            (coalesce(route_state, '') NOT IN ('joining', 'routed')
                OR (route_queue_id IS NOT NULL AND route_source IS NOT NULL))
            AND (coalesce(route_state, '') <> 'joining' OR route_source = 'flow')
            AND (coalesce(route_state, '') NOT IN ('pending', 'resolving')
                OR (route_queue_id IS NULL AND route_source IS NULL))
        ),
    DROP CONSTRAINT IF EXISTS email_event_route_lease_valid,
    ADD CONSTRAINT email_event_route_lease_valid
        CHECK ((route_locked_by IS NULL) = (route_locked_until IS NULL)
            AND (route_locked_by IS NULL OR coalesce(route_state, '') IN ('joining', 'resolving'))),
    DROP CONSTRAINT IF EXISTS email_event_route_reason_valid,
    ADD CONSTRAINT email_event_route_reason_valid
        CHECK (coalesce(route_state, '') NOT IN ('unrouted', 'route_failed') OR route_reason IS NOT NULL),
    DROP CONSTRAINT IF EXISTS email_event_route_values_valid,
    ADD CONSTRAINT email_event_route_values_valid
        CHECK ((route_queue_id IS NULL OR route_queue_id > 0)
            AND (fallback_queue_id IS NULL OR fallback_queue_id > 0)
            AND route_attempts >= 0
            AND (route_last_error IS NULL OR char_length(route_last_error) <= 1024));

-- A failed CONCURRENTLY build leaves an invalid index that IF NOT EXISTS would skip; it is dropped
-- CONCURRENTLY too, so a repeated run does not lock the Inbox.
SELECT 'DROP INDEX CONCURRENTLY flow.email_event_route_due_idx'
FROM pg_index i
WHERE i.indexrelid = to_regclass('flow.email_event_route_due_idx')
  AND NOT i.indisvalid
\gexec

-- Unfinished routes in the order the route watcher takes them.
CREATE INDEX CONCURRENTLY IF NOT EXISTS email_event_route_due_idx
    ON flow.email_event (route_next_at)
    WHERE route_state IN ('pending', 'joining', 'resolving');
