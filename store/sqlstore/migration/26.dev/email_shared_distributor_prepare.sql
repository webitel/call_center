-- After the EM-21 routing migrations; stop Email writers on all nodes.
-- EM-23/EM-24 overrides must be adapted separately before this can follow them.
BEGIN;
SET LOCAL lock_timeout = '5s';

DO $$
BEGIN
    IF to_regclass('call_center.cc_email_attempt_outbox') IS NOT NULL OR EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'call_center.cc_member_attempt'::regclass
          AND attname IN ('version', 'postponed_until', 'last_released_agent_id')
          AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'email shared distributor preparation: EM-23/EM-24 overrides require an adapted migration';
    END IF;
END
$$;

ALTER TABLE call_center.cc_agent_channel
    ADD COLUMN IF NOT EXISTS email_idle_since timestamp with time zone;

-- integer bounds the upper end; NULL keeps legacy journal entries replayable.
ALTER TABLE call_center.cc_email_join
    DROP CONSTRAINT IF EXISTS cc_email_join_priority_c,
    ADD CONSTRAINT cc_email_join_priority_c CHECK (priority >= 0) NOT VALID;

-- Temporary High until the business value is confirmed.
CREATE OR REPLACE FUNCTION call_center.cc_email_high_priority()
    RETURNS integer
    LANGUAGE sql
    STABLE
AS $$
    SELECT 10
$$;

CREATE OR REPLACE FUNCTION call_center.cc_email_sticky_prepare(
    _queue call_center.cc_queue, _candidates integer[], _limit integer, _attempt_id bigint DEFAULT NULL)
    RETURNS boolean
    LANGUAGE plpgsql
AS $$
DECLARE
    _q          call_center.cc_queue;
    _att        call_center.cc_member_attempt;
    _wait       integer;
    _ignore     boolean;
    _eligible   boolean;
    _configured boolean;
    _online     boolean;
    _slot       text;
    _until      timestamp with time zone;
    _now        timestamp with time zone := clock_timestamp();
    _candidate  integer;
    _weight     integer;
    _n          integer := 0;
BEGIN
    IF coalesce(_limit, 0) <= 0 THEN
        RETURN false;
    END IF;

    SELECT q.* INTO _q FROM call_center.cc_queue q
    WHERE q.id = _queue.id AND q.domain_id = _queue.domain_id AND q.type = 11 AND q.enabled
        FOR SHARE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    PERFORM 1 FROM flow.calendar c WHERE c.id = _q.calendar_id FOR SHARE SKIP LOCKED;
    IF NOT FOUND OR call_center.cc_email_queue_calendar(_q.domain_id, _q.calendar_id) <> 'open' THEN
        RETURN false;
    END IF;

    _wait := call_center.cc_email_sticky_wait_sec(_q.payload);
    _ignore := CASE WHEN jsonb_typeof(_q.payload -> 'sticky_ignore_status') = 'boolean'
                    THEN (_q.payload ->> 'sticky_ignore_status')::boolean ELSE false END;

    -- _candidates is retained for SQL compatibility, not used as authoritative agent state.
    -- Only actionable rows: unchanged full/offline waiters must not consume the entire batch.
    FOR _att IN
        SELECT w.*
        FROM call_center.cc_member_attempt w
                 LEFT JOIN call_center.cc_agent ag ON ag.id = w.sticky_agent_id
                 LEFT JOIN call_center.cc_agent_channel ch ON ch.agent_id = ag.id AND ch.channel = 'email'
        WHERE w.queue_id = _q.id AND w.domain_id = _q.domain_id
          AND (_attempt_id IS NULL OR w.id = _attempt_id)
          AND w.channel = 'email' AND w.queue_type = 11 AND w.state = 'waiting'
          AND w.agent_id IS NULL AND w.leaving_at IS NULL
          AND (w.sticky_until IS NULL OR
              (w.sticky_agent_id IS NOT NULL AND (
                  NOT _q.sticky_agent
                  OR NOT call_center.cc_email_agent_assignable(_q.id, w.sticky_agent_id)
                  OR NOT coalesce(ag.email_count > 0 OR (w.email_extra_allowed AND ag.extra_email_count > 0), false)
                  OR (NOT _ignore AND NOT coalesce(ag.status = 'online' AND ch.online, false))
                  OR (_wait > 0 AND w.sticky_until <= _now)
                  OR _wait <= 0
              )))
        ORDER BY w.sticky_until NULLS LAST, w.weight DESC, w.joined_at, w.id
        LIMIT _limit
            FOR UPDATE OF w SKIP LOCKED
    LOOP
        _now := clock_timestamp();
        _candidate := _att.sticky_agent_id;
        _until := coalesce(_att.sticky_until, _now);
        _weight := _att.weight;

        IF NOT _q.sticky_agent OR _candidate IS NULL THEN
            _candidate := NULL; -- R1/R2, no automatic Thread lookup or priority change.
        ELSE
            SELECT call_center.cc_email_agent_assignable(_q.id, ag.id), c.has_slot_type,
                   ag.status = 'online' AND coalesce(ch.online, false), c.slot_type
            INTO _eligible, _configured, _online, _slot
            FROM call_center.cc_agent ag
                     CROSS JOIN LATERAL call_center.cc_email_agent_capacity(ag.id, _att.email_extra_allowed) c
                     LEFT JOIN call_center.cc_agent_channel ch ON ch.agent_id = ag.id AND ch.channel = 'email'
            WHERE ag.id = _candidate;

            IF NOT FOUND OR NOT _eligible OR NOT _configured THEN
                _candidate := NULL; -- Permanent/configuration fallback is not R5.
                _until := _now;
            ELSIF NOT _online AND NOT _ignore THEN
                _candidate := NULL; -- R5.
                _until := _now;
                _weight := greatest(_weight, call_center.cc_email_high_priority());
            ELSIF _att.sticky_until IS NULL AND _wait > 0 THEN
                _until := _now + make_interval(secs => _wait);
            ELSIF (_wait > 0 AND _until <= _now) OR
                  (_wait <= 0 AND ((_att.sticky_until IS NOT NULL AND _att.sticky_until < transaction_timestamp())
                                  OR NOT _online OR _slot IS NULL)) THEN
                _candidate := NULL;
                _until := _now;
                _weight := greatest(_weight, call_center.cc_email_high_priority());
            END IF;
        END IF;

        UPDATE call_center.cc_member_attempt
        SET sticky_agent_id = _candidate, sticky_until = _until, weight = _weight
        WHERE id = _att.id;
        _n := _n + 1;
    END LOOP;

    -- A false result no longer blocks priority-0 work behind pending Sticky upkeep.
    RETURN _n < _limit;
END;
$$;

CREATE OR REPLACE FUNCTION call_center.cc_email_sticky_route(
    _queue call_center.cc_queue, _candidate integer, _extra_allowed boolean,
    _until timestamp with time zone, _priority integer)
    RETURNS TABLE (candidate_id integer, priority integer)
    LANGUAGE sql
    STABLE
AS $$
    SELECT CASE
               WHEN e.cancelled OR e.expired THEN NULL::integer
               ELSE _candidate
           END,
           CASE WHEN NOT e.cancelled AND e.expired THEN greatest(_priority, call_center.cc_email_high_priority()) ELSE _priority END
    FROM (
        SELECT NOT coalesce(_queue.sticky_agent, false) OR _candidate IS NULL
                   OR NOT call_center.cc_email_agent_assignable(_queue.id, _candidate)
                   OR NOT coalesce(a.email_count > 0 OR (_extra_allowed AND a.extra_email_count > 0), false)
                   AS cancelled,
               (NOT p.ignore_status AND NOT coalesce(a.status = 'online' AND ch.online, false))
                   OR (p.wait_sec > 0 AND _until <= clock_timestamp())
                   OR (p.wait_sec = 0 AND (
                       _until < transaction_timestamp()
                       OR NOT coalesce(a.status = 'online' AND ch.online, false)
                       OR NOT EXISTS (SELECT 1 FROM call_center.cc_email_agent_capacity(a.id, _extra_allowed) c
                                      WHERE c.slot_type IS NOT NULL)
                   )) AS expired
        FROM (SELECT call_center.cc_email_sticky_wait_sec(_queue.payload) AS wait_sec,
                     CASE WHEN jsonb_typeof(_queue.payload -> 'sticky_ignore_status') = 'boolean'
                          THEN (_queue.payload ->> 'sticky_ignore_status')::boolean ELSE false END AS ignore_status) p
                 LEFT JOIN call_center.cc_agent a ON a.id = _candidate
                 LEFT JOIN call_center.cc_agent_channel ch ON ch.agent_id = a.id AND ch.channel = 'email'
    ) e
$$;

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
BEGIN
    IF _priority IS NULL OR _priority < 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'EMPRI', MESSAGE = 'store.sql_member.email_join.invalid_priority';
    END IF;
    IF _event_id IS NULL OR coalesce(_domain_id, 0) <= 0 OR coalesce(_thread_id, 0) <= 0
        OR coalesce(_queue_id, 0) <= 0 OR coalesce(_sticky_agent_id, 0) < 0 OR _extra_email_count IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email join: invalid arguments';
    END IF;

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
        RETURNING id, queue_id INTO _attempt_id, _attempt_queue;

        IF FOUND THEN
            _result := 'created';
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

CREATE OR REPLACE FUNCTION call_center.cc_email_distribute_queue_status(
    _domain_id bigint, _calendar_id integer, _queue_id integer)
    RETURNS TABLE (calendar_state text, result text)
    LANGUAGE plpgsql
    STABLE
AS $$
BEGIN
    calendar_state := call_center.cc_email_queue_calendar(_domain_id, _calendar_id);
    IF calendar_state <> 'open' THEN
        result := 'calendar_' || calendar_state;
    ELSIF NOT EXISTS (
        SELECT 1 FROM call_center.cc_queue_skill qs
        WHERE qs.queue_id = _queue_id AND qs.enabled
    ) THEN
        result := 'no_skills';
    ELSIF NOT EXISTS (
        SELECT 1 FROM call_center.cc_email_queue_candidates(_queue_id, NULL, true)
    ) THEN
        result := 'no_agent';
    END IF;
    RETURN NEXT;
END;
$$;

CREATE OR REPLACE VIEW call_center.cc_email_distribute_stage_1 AS
SELECT q.id,
       q.type,
       q.domain_id,
       q.team_id,
       t.strategy AS team_strategy,
       q.priority,
       q.calendar_id,
       q.sticky_agent,
       call_center.cc_email_sticky_wait_sec(q.payload) AS sticky_agent_sec,
       s.calendar_state,
       s.result,
       s.calendar_state = 'open' AND s.result IS DISTINCT FROM 'no_skills' AS can_prepare_sticky,
       s.result IS NULL AS can_distribute
FROM call_center.cc_queue q
         LEFT JOIN call_center.cc_team t ON t.id = q.team_id
         CROSS JOIN LATERAL call_center.cc_email_distribute_queue_status(q.domain_id, q.calendar_id, q.id) s
WHERE q.type = 11 AND q.enabled
  AND (EXISTS (
      SELECT 1 FROM call_center.cc_member_attempt a
      WHERE a.queue_id = q.id AND a.domain_id = q.domain_id AND a.queue_type = 11
        AND a.channel = 'email' AND a.state = 'waiting'
        AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.sticky_agent_id IS NULL
  ) OR EXISTS (
      SELECT 1 FROM call_center.cc_member_attempt a
      WHERE a.queue_id = q.id AND a.domain_id = q.domain_id AND a.queue_type = 11
        AND a.channel = 'email' AND a.state = 'waiting'
        AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.sticky_agent_id IS NOT NULL
  ));

CREATE OR REPLACE FUNCTION call_center.cc_email_agent_strategy_refresh(
    _agent_id integer, _taken_at timestamp with time zone DEFAULT NULL)
    RETURNS void
    LANGUAGE plpgsql
AS $$
BEGIN
    IF coalesce(_agent_id, 0) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email strategy: positive agent ID is required';
    END IF;
    -- Caller holds agent/Email-channel locks before changing the slot ledger.
    UPDATE call_center.cc_agent_channel ch
    SET email_idle_since = CASE WHEN c.used_slots > 0 THEN NULL
                                ELSE coalesce(ch.email_idle_since, now()) END,
        last_bridged_at = CASE WHEN _taken_at IS NULL THEN ch.last_bridged_at
                               ELSE greatest(ch.last_bridged_at, _taken_at) END
    FROM call_center.cc_email_agent_capacity(_agent_id, true) c
    WHERE ch.agent_id = _agent_id AND ch.channel = 'email';
END;
$$;

CREATE OR REPLACE FUNCTION call_center.cc_email_apply_distributed(
    _attempt_id bigint, _queue_id integer, _agent_id integer)
    RETURNS TABLE (result text, queue_id integer, attempt_id bigint, agent_id integer)
    LANGUAGE plpgsql
AS $$
BEGIN
    IF coalesce(_attempt_id, 0) <= 0 OR coalesce(_queue_id, 0) <= 0 OR coalesce(_agent_id, 0) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email distribution: positive attempt, queue and agent IDs are required';
    END IF;
    IF NOT pg_try_advisory_xact_lock(1162690889, 1) THEN
        RETURN QUERY SELECT 'busy'::text, NULL::integer, NULL::bigint, NULL::integer;
        RETURN;
    END IF;

    IF call_center.cc_email_try_assign(_attempt_id, _queue_id, _agent_id) THEN
        PERFORM call_center.cc_email_agent_strategy_refresh(_agent_id);
        RETURN QUERY SELECT 'assigned'::text, _queue_id, _attempt_id, _agent_id;
    ELSE
        RETURN QUERY SELECT 'no_agent'::text, _queue_id, _attempt_id, NULL::integer;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION call_center.cc_email_pair_available(
    _attempt call_center.cc_member_attempt, _agent_id integer, _candidate_id integer,
    _failed_attempt_ids bigint[], _failed_agent_ids integer[])
    RETURNS boolean
    LANGUAGE sql
    STABLE
AS $$
    SELECT (_candidate_id IS NULL OR _candidate_id = _agent_id)
        AND NOT EXISTS (SELECT 1 FROM unnest(_failed_attempt_ids, _failed_agent_ids) f(attempt_id, agent_id)
            WHERE f.attempt_id = (_attempt).id AND f.agent_id = _agent_id)
$$;

COMMIT;
