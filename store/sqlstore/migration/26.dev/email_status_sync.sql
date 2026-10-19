-- Email status sync: the agent user in snapshots, the inbound_reopened marker of a Thread without an
-- active attempt, the fallback queue of a wake-up, one lock per Thread for wake-up and join, and the
-- lease of the snapshot publisher.
-- Run with psql -v ON_ERROR_STOP=1 -f after email_attempt_lifecycle.sql outside a transaction: the
-- indexes are built CONCURRENTLY, and psql runs the generated \gexec drops. Every step can be repeated.

-- User of the agent, fixed when the snapshot is written.
ALTER TABLE call_center.cc_email_attempt_outbox
    ADD COLUMN IF NOT EXISTS agent_user_id bigint;

-- Writes the full snapshot of an Email attempt after a transition; the sequence is its projection_version.
-- Replaced before the check below, so nodes running during the migration already write the user.
CREATE OR REPLACE FUNCTION call_center.cc_email_attempt_snapshot(_a call_center.cc_member_attempt, _transition text, _source text,
                                                                 _command_id text DEFAULT NULL, _fingerprint text DEFAULT NULL,
                                                                 _causation_id text DEFAULT NULL)
    RETURNS bigint
    LANGUAGE plpgsql
AS $$
DECLARE
    _sequence bigint;
    _result   text := CASE WHEN _a.state = 'leaving' THEN _a.result END;
BEGIN
    INSERT INTO call_center.cc_email_attempt_outbox (domain_id, thread_id, attempt_id, attempt_version, attempt_state, result,
                                                     queue_id, agent_id, agent_user_id, postponed_until, transition, source,
                                                     command_id, fingerprint, response, causation_id)
    VALUES (_a.domain_id, _a.member_call_id::bigint, _a.id, _a.version, _a.state, _result, _a.queue_id, _a.agent_id,
            (SELECT ag.user_id FROM call_center.cc_agent ag WHERE ag.id = _a.agent_id),
            _a.postponed_until, _transition, _source, _command_id, _fingerprint,
            CASE WHEN _command_id IS NOT NULL THEN jsonb_build_object('attempt_id', _a.id, 'state', _a.state,
                'attempt_version', _a.version, 'result', _result, 'agent_id', _a.agent_id, 'postponed_until', _a.postponed_until) END,
            _causation_id)
    RETURNING sequence INTO _sequence;

    RETURN _sequence;
END;
$$;

-- New rows are checked from here; the rows written before are filled and validated below.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_email_attempt_outbox'::regclass
          AND conname = 'cc_email_attempt_outbox_agent_user_valid'
    ) THEN
        ALTER TABLE call_center.cc_email_attempt_outbox
            ADD CONSTRAINT cc_email_attempt_outbox_agent_user_valid
                CHECK ((agent_id IS NULL) = (agent_user_id IS NULL)) NOT VALID;
    END IF;
END
$$;

UPDATE call_center.cc_email_attempt_outbox o
SET agent_user_id = a.user_id
FROM call_center.cc_agent a
WHERE a.id = o.agent_id
  AND o.agent_user_id IS NULL;

-- A snapshot of a deleted agent cannot get its user; report it instead of guessing.
DO $$
DECLARE
    _missing bigint;
BEGIN
    SELECT count(*) INTO _missing
    FROM call_center.cc_email_attempt_outbox o
    WHERE o.agent_id IS NOT NULL AND o.agent_user_id IS NULL;

    IF _missing > 0 THEN
        RAISE EXCEPTION 'cc_email_attempt_outbox: % rows have an agent without a user', _missing;
    END IF;
END
$$;

ALTER TABLE call_center.cc_email_attempt_outbox
    VALIDATE CONSTRAINT cc_email_attempt_outbox_agent_user_valid;

-- The inbound_reopened marker has no attempt.
ALTER TABLE call_center.cc_email_attempt_outbox
    ALTER COLUMN attempt_id DROP NOT NULL,
    ALTER COLUMN attempt_version DROP NOT NULL,
    ALTER COLUMN attempt_state DROP NOT NULL,
    ALTER COLUMN queue_id DROP NOT NULL;

ALTER TABLE call_center.cc_email_attempt_outbox
    DROP CONSTRAINT IF EXISTS cc_email_attempt_outbox_transition_valid,
    ADD CONSTRAINT cc_email_attempt_outbox_transition_valid
        CHECK (transition IN ('created', 'assigned', 'taken', 'postponed', 'resumed', 'woken', 'queued', 'reopened',
                              'deadline_woken', 'deadline_queued', 'returned', 'auto_released', 'logged_out',
                              'processing_started', 'renewed', 'completed', 'processing_timeout',
                              'inbound_reopened')) NOT VALID;

ALTER TABLE call_center.cc_email_attempt_outbox
    VALIDATE CONSTRAINT cc_email_attempt_outbox_transition_valid;

-- A marker carries only the Thread and an optional queue; every other row keeps its attempt.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_email_attempt_outbox'::regclass
          AND conname = 'cc_email_attempt_outbox_marker_valid'
    ) THEN
        ALTER TABLE call_center.cc_email_attempt_outbox
            ADD CONSTRAINT cc_email_attempt_outbox_marker_valid
                CHECK (
                    (transition = 'inbound_reopened'
                        AND attempt_id IS NULL AND attempt_version IS NULL AND attempt_state IS NULL AND result IS NULL
                        AND agent_id IS NULL AND agent_user_id IS NULL AND postponed_until IS NULL
                        AND command_id IS NULL AND source = 'system')
                    OR
                    (transition <> 'inbound_reopened'
                        AND attempt_id IS NOT NULL AND attempt_version IS NOT NULL AND attempt_state IS NOT NULL
                        AND queue_id IS NOT NULL)
                ) NOT VALID;
    END IF;
END
$$;

ALTER TABLE call_center.cc_email_attempt_outbox
    VALIDATE CONSTRAINT cc_email_attempt_outbox_marker_valid;

-- Queue of the last finished attempt, kept with a not_active result so a replay returns it again.
ALTER TABLE call_center.cc_email_wakeup
    ADD COLUMN IF NOT EXISTS fallback_queue_id integer;

ALTER TABLE call_center.cc_email_wakeup
    DROP CONSTRAINT IF EXISTS cc_email_wakeup_state_complete,
    ADD CONSTRAINT cc_email_wakeup_state_complete
        CHECK (
            (state = 'reserved'
                AND result IS NULL AND attempt_id IS NULL AND attempt_state IS NULL AND attempt_version IS NULL
                AND fallback_queue_id IS NULL)
            OR
            (state = 'applied' AND result IS NOT DISTINCT FROM 'not_active'
                AND attempt_id IS NULL AND attempt_state IS NULL AND attempt_version IS NULL
                AND (fallback_queue_id IS NULL OR fallback_queue_id > 0))
            OR
            (state = 'applied' AND result IS NOT NULL AND result IS DISTINCT FROM 'not_active'
                AND attempt_id IS NOT NULL AND attempt_state IS NOT NULL AND attempt_version IS NOT NULL
                AND fallback_queue_id IS NULL)
        ) NOT VALID;

ALTER TABLE call_center.cc_email_wakeup
    VALIDATE CONSTRAINT cc_email_wakeup_state_complete;

-- The result gains the fallback queue, so the function is recreated; the old one is dropped in the same transaction.
BEGIN;

DROP FUNCTION IF EXISTS call_center.cc_email_wakeup_thread(uuid, bigint, bigint);

CREATE FUNCTION call_center.cc_email_wakeup_thread(_event_id uuid, _domain_id bigint, _thread_id bigint)
    RETURNS TABLE (wakeup_result text, wakeup_attempt_id bigint, wakeup_attempt_state text,
                   wakeup_attempt_version bigint, wakeup_replayed boolean, wakeup_fallback_queue_id integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _w        call_center.cc_email_wakeup;
    _id       bigint;
    _owner    integer;
    _state    text;
    _a        call_center.cc_member_attempt;
    _result   text;
    _fallback integer;
BEGIN
    IF _event_id IS NULL OR coalesce(_domain_id, 0) <= 0 OR coalesce(_thread_id, 0) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAAR', MESSAGE = 'email wake-up: invalid arguments';
    END IF;

    -- Thread lock (class 0x454D4154 'EMAT') shared with the join: the marker and a new attempt never interleave.
    PERFORM pg_advisory_xact_lock(1162690900, hashtext(_domain_id::text || ':' || _thread_id::text));

    -- Reserve the event first: a concurrent replay waits for this transaction.
    INSERT INTO call_center.cc_email_wakeup (event_id, domain_id, thread_id)
    VALUES (_event_id, _domain_id, _thread_id)
    ON CONFLICT (event_id) DO NOTHING;

    IF NOT FOUND THEN
        SELECT * INTO STRICT _w FROM call_center.cc_email_wakeup w WHERE w.event_id = _event_id;
        IF _w.domain_id <> _domain_id OR _w.thread_id <> _thread_id THEN
            RAISE EXCEPTION USING ERRCODE = 'EMWKY', MESSAGE = format('email wake-up: event %s belongs to another thread', _event_id);
        END IF;
        RETURN QUERY SELECT _w.result, _w.attempt_id, _w.attempt_state, _w.attempt_version, true, _w.fallback_queue_id;
        RETURN;
    END IF;

    SELECT a.id, a.agent_id, a.state INTO _id, _owner, _state
    FROM call_center.cc_member_attempt a
    WHERE a.domain_id = _domain_id AND a.member_call_id = _thread_id::text AND a.channel = 'email' AND a.leaving_at IS NULL;

    IF FOUND THEN
        -- A postponed attempt may take a slot: agent, then its Email channel, then the attempt.
        IF _state = 'postponed' AND _owner IS NOT NULL THEN
            PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _owner FOR SHARE;
            PERFORM 1 FROM call_center.cc_agent_channel ch WHERE ch.agent_id = _owner AND ch.channel = 'email' FOR UPDATE;
        END IF;
        SELECT * INTO _a FROM call_center.cc_member_attempt a WHERE a.id = _id AND a.leaving_at IS NULL FOR UPDATE;
    END IF;

    IF _a.id IS NULL OR _a.state = 'leaving' THEN
        _result := 'not_active';
        _a := NULL;

        -- Queue of the last finished attempt, whether SaveToHistory has moved it or not.
        SELECT x.queue_id INTO _fallback
        FROM (SELECT a.queue_id, a.leaving_at, a.id
              FROM call_center.cc_member_attempt a
              WHERE a.domain_id = _domain_id AND a.member_call_id = _thread_id::text AND a.channel = 'email'
                AND a.leaving_at IS NOT NULL AND a.queue_id IS NOT NULL
              UNION ALL
              SELECT h.queue_id, h.leaving_at, h.id
              FROM call_center.cc_member_attempt_history h
              WHERE h.domain_id = _domain_id AND h.member_call_id = _thread_id::text AND h.channel = 'email'
                AND h.queue_id IS NOT NULL) x
        ORDER BY x.leaving_at DESC NULLS LAST, x.id DESC
        LIMIT 1;

        -- Opens the Thread as New without an attempt; its sequence follows the last snapshot of the old attempt.
        INSERT INTO call_center.cc_email_attempt_outbox (domain_id, thread_id, queue_id, transition, source, causation_id)
        VALUES (_domain_id, _thread_id, _fallback, 'inbound_reopened', 'system', _event_id::text);
    ELSIF _a.state = 'postponed' THEN
        IF _a.agent_id IS DISTINCT FROM _owner OR _state <> 'postponed' THEN
            RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'email wake-up: attempt changed while locking';
        END IF;
        _a := call_center.cc_email_wake_postponed(_a, 'woken', 'queued', _event_id::text);
        _result := CASE WHEN _a.state = 'active' THEN 'woken' ELSE 'queued' END;
    ELSIF _a.state = 'processing' THEN
        UPDATE call_center.cc_member_attempt a
        SET state = 'active', timeout = NULL, last_state_change = now(), version = a.version + 1
        WHERE a.id = _a.id
        RETURNING * INTO _a;
        PERFORM call_center.cc_email_attempt_snapshot(_a, 'reopened', 'system', NULL, NULL, _event_id::text);
        _result := 'reopened';
    ELSE
        _result := 'noop';
    END IF;

    UPDATE call_center.cc_email_wakeup w
    SET state = 'applied', result = _result, attempt_id = _a.id, attempt_state = _a.state, attempt_version = _a.version,
        fallback_queue_id = _fallback
    WHERE w.event_id = _event_id;

    RETURN QUERY SELECT _result, _a.id, _a.state::text, _a.version, false, _fallback;
END;
$$;

COMMIT;

-- As in email_attempt_lifecycle.sql (the eight arguments of stage 10), under the Thread lock of the wake-up.
CREATE OR REPLACE FUNCTION call_center.cc_email_join_to_queue(
    _event_id uuid, _domain_id bigint, _thread_id bigint, _queue_id integer,
    _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT 0,
    _extra_email_count boolean DEFAULT false, _from_address text DEFAULT '')
    RETURNS TABLE (join_result text, join_attempt_id bigint, join_queue_id integer, join_requested_queue_id integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _join          call_center.cc_email_join;
    _queue         call_center.cc_queue;
    _call_id       varchar := _thread_id::text;
    _attempt_id    bigint;
    _attempt_queue integer;
    _candidate     integer;
    _address       text := lower(btrim(coalesce(_from_address, '')));
    _result        text;
    _att           call_center.cc_member_attempt;
BEGIN
    IF _priority IS NULL OR _priority < 0 OR _priority > 100 THEN
        RAISE EXCEPTION USING ERRCODE = 'EMPRI', MESSAGE = 'store.sql_member.email_join.invalid_priority';
    END IF;
    IF _event_id IS NULL OR coalesce(_domain_id, 0) <= 0 OR coalesce(_thread_id, 0) <= 0
        OR coalesce(_queue_id, 0) <= 0 OR coalesce(_sticky_agent_id, 0) < 0 OR _extra_email_count IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email join: invalid arguments';
    END IF;

    -- Thread lock shared with the wake-up (class 'EMAT'), taken before the event is reserved.
    PERFORM pg_advisory_xact_lock(1162690900, hashtext(_domain_id::text || ':' || _thread_id::text));

    -- Missing or malformed initial From never creates an address lookup key.
    IF _address !~ '^[^[:space:]@<>(),;:"]+@[^[:space:]@<>(),;:"]+$' THEN
        _address := '';
    END IF;

    -- Reserve before candidate checks; valid replays never re-evaluate routing.
    INSERT INTO call_center.cc_email_join
        (event_id, domain_id, thread_id, requested_queue_id, priority, sticky_agent_id, extra_email_count, from_address)
    VALUES (_event_id, _domain_id, _thread_id, _queue_id, _priority, nullif(_sticky_agent_id, 0), _extra_email_count, _address)
    ON CONFLICT (event_id) DO NOTHING;

    IF NOT FOUND THEN
        SELECT * INTO STRICT _join FROM call_center.cc_email_join j WHERE j.event_id = _event_id;
        IF _join.domain_id <> _domain_id OR _join.thread_id <> _thread_id THEN
            RAISE EXCEPTION USING ERRCODE = 'EMKEY',
                MESSAGE = format('email join: event %s belongs to another thread', _event_id);
        END IF;
        RETURN QUERY SELECT 'replayed'::text, _join.attempt_id, _join.queue_id, _join.requested_queue_id;
        RETURN;
    END IF;

    SELECT * INTO _queue FROM call_center.cc_queue q WHERE q.id = _queue_id AND q.domain_id = _domain_id FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'EMQNF', MESSAGE = format('email join: queue %s not found', _queue_id);
    END IF;
    IF _queue.type <> 11 OR NOT _queue.enabled THEN
        RAISE EXCEPTION USING ERRCODE = 'EMQFP',
            MESSAGE = format('email join: queue %s is disabled or not an inbound email queue', _queue_id);
    END IF;

    -- Presence and available base/Extra capacity are checked by the allocator.
    IF _queue.sticky_agent AND coalesce(_sticky_agent_id, 0) > 0
        AND call_center.cc_email_agent_assignable(_queue.id, _sticky_agent_id) THEN
        _candidate := _sticky_agent_id;
    END IF;

    FOR _try IN 1..3 LOOP
        INSERT INTO call_center.cc_member_attempt
            (domain_id, channel, state, queue_id, member_call_id, weight, destination, queue_params, queue_type,
             sticky_agent_id, email_extra_allowed)
        VALUES (_domain_id, 'email', 'waiting', _queue.id, _call_id, _priority,
                jsonb_build_object('thread_id', _thread_id) ||
                    CASE WHEN _address <> '' THEN jsonb_build_object('number', _address) ELSE '{}'::jsonb END,
                call_center.cc_queue_params(_queue), _queue.type, _candidate, _extra_email_count)
        ON CONFLICT (domain_id, member_call_id) WHERE channel = 'email' AND leaving_at IS NULL DO NOTHING
        RETURNING * INTO _att;

        IF FOUND THEN
            _attempt_id := _att.id;
            _attempt_queue := _att.queue_id;
            _result := 'created';
            -- New of the Thread; already_active and replayed change nothing and write no snapshot.
            PERFORM call_center.cc_email_attempt_snapshot(_att, 'created', 'system', NULL, NULL, _event_id::text);
            EXIT;
        END IF;

        SELECT a.id, a.queue_id INTO _attempt_id, _attempt_queue
        FROM call_center.cc_member_attempt a
        WHERE a.domain_id = _domain_id AND a.member_call_id = _call_id
          AND a.channel = 'email' AND a.leaving_at IS NULL;
        IF FOUND THEN
            _result := 'already_active';
            EXIT;
        END IF;
    END LOOP;

    IF _result IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'email join: active attempt kept changing';
    END IF;

    UPDATE call_center.cc_email_join
    SET state = 'applied', queue_id = _attempt_queue, attempt_id = _attempt_id, result = _result
    WHERE event_id = _event_id;
    RETURN QUERY SELECT _result, _attempt_id, _attempt_queue, _queue_id;
END;
$$;

-- Lease of the snapshot publisher; published_at alone marks a publish the broker confirmed.
ALTER TABLE call_center.cc_email_attempt_outbox
    ADD COLUMN IF NOT EXISTS locked_by text,
    ADD COLUMN IF NOT EXISTS locked_until timestamp with time zone,
    ADD COLUMN IF NOT EXISTS next_attempt_at timestamp with time zone DEFAULT now() NOT NULL,
    ADD COLUMN IF NOT EXISTS attempts integer DEFAULT 0 NOT NULL,
    ADD COLUMN IF NOT EXISTS last_error text;

-- No failed state: a row is retried until published, attempts and last_error only explain delays.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_email_attempt_outbox'::regclass
          AND conname = 'cc_email_attempt_outbox_lease_valid'
    ) THEN
        ALTER TABLE call_center.cc_email_attempt_outbox
            ADD CONSTRAINT cc_email_attempt_outbox_lease_valid
                CHECK (
                    (locked_by IS NULL) = (locked_until IS NULL)
                    AND (published_at IS NULL OR locked_by IS NULL)
                    AND attempts >= 0
                    AND (last_error IS NULL OR char_length(last_error) <= 1024)
                ) NOT VALID;
    END IF;
END
$$;

ALTER TABLE call_center.cc_email_attempt_outbox
    VALIDATE CONSTRAINT cc_email_attempt_outbox_lease_valid;

-- A failed CONCURRENTLY build leaves an invalid index that IF NOT EXISTS would skip; it is dropped
-- CONCURRENTLY too, so a repeated run does not lock the outbox.
SELECT format('DROP INDEX CONCURRENTLY call_center.%I', c.relname)
FROM pg_index i
         JOIN pg_class c ON c.oid = i.indexrelid
WHERE c.oid IN (to_regclass('call_center.cc_email_attempt_outbox_ready_idx'),
                to_regclass('call_center.cc_email_attempt_outbox_published_idx'))
  AND NOT i.indisvalid
\gexec

-- Rows the publisher may claim, in the order it claims them; replaces the pending index of stage 11.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_email_attempt_outbox_ready_idx
    ON call_center.cc_email_attempt_outbox (next_attempt_at, sequence)
    WHERE published_at IS NULL;

DROP INDEX CONCURRENTLY IF EXISTS call_center.cc_email_attempt_outbox_pending_idx;

-- Published rows that retention may delete, oldest first; command rows keep their response.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_email_attempt_outbox_published_idx
    ON call_center.cc_email_attempt_outbox (published_at)
    WHERE published_at IS NOT NULL AND command_id IS NULL;
