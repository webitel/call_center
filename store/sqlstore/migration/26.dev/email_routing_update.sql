-- After email_queue_join.sql and email_agent_distribution.sql, with Email writers stopped.
-- Repeatable upgrade from the original EM-21; no deletes or priority conversion.
-- After commit, run email_routing_validate.sql separately, outside a transaction wrapper.
BEGIN;
SET LOCAL lock_timeout = '5s';
LOCK TABLE call_center.cc_member_attempt IN ACCESS EXCLUSIVE MODE;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'call_center.cc_member_attempt'::regclass
          AND attname = 'email_slot_type' AND NOT attisdropped
    ) AND EXISTS (SELECT 1 FROM call_center.cc_member_attempt WHERE channel = 'email') THEN
        RAISE EXCEPTION 'email routing upgrade: finish and archive old Email attempts before adding email_slot_type';
    END IF;
END
$$;

-- Preserve existing agents, including installations that did not yet add email_count.
ALTER TABLE call_center.cc_agent
    ADD COLUMN IF NOT EXISTS email_count smallint NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS extra_email_count smallint NOT NULL DEFAULT 0;
ALTER TABLE call_center.cc_agent ALTER COLUMN email_count SET DEFAULT 1;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'call_center.cc_agent'::regclass
                   AND conname = 'cc_agent_email_count_c') THEN
        ALTER TABLE call_center.cc_agent
            ADD CONSTRAINT cc_agent_email_count_c CHECK (email_count >= 0) NOT VALID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'call_center.cc_agent'::regclass
                   AND conname = 'cc_agent_extra_email_count_c') THEN
        ALTER TABLE call_center.cc_agent
            ADD CONSTRAINT cc_agent_extra_email_count_c CHECK (extra_email_count >= 0) NOT VALID;
    END IF;
END
$$;

ALTER TABLE call_center.cc_member_attempt
    ADD COLUMN IF NOT EXISTS email_extra_allowed boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS email_slot_type text;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'call_center.cc_member_attempt'::regclass
                   AND conname = 'cc_member_attempt_email_slot_c') THEN
        ALTER TABLE call_center.cc_member_attempt ADD CONSTRAINT cc_member_attempt_email_slot_c CHECK (
            email_slot_type IS NULL OR
            (channel IS NOT DISTINCT FROM 'email' AND agent_id IS NOT NULL
             AND (email_slot_type = 'base' OR (email_slot_type = 'extra' AND email_extra_allowed)))) NOT VALID;
    END IF;
END
$$;

-- NULL routing fields identify old journal entries; their stored result stays replayable.
ALTER TABLE call_center.cc_email_join
    ADD COLUMN IF NOT EXISTS priority integer,
    ADD COLUMN IF NOT EXISTS sticky_agent_id integer,
    ADD COLUMN IF NOT EXISTS extra_email_count boolean,
    ADD COLUMN IF NOT EXISTS from_address text;
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'call_center.cc_email_join'::regclass
                   AND conname = 'cc_email_join_priority_c') THEN
        ALTER TABLE call_center.cc_email_join
            ADD CONSTRAINT cc_email_join_priority_c CHECK (priority BETWEEN 0 AND 100) NOT VALID;
    END IF;
END
$$;

CREATE TABLE IF NOT EXISTS call_center.cc_email_distribution_cursor (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    last_agent_id integer NOT NULL DEFAULT 0 CHECK (last_agent_id >= 0),
    last_queue_id integer NOT NULL DEFAULT 0 CHECK (last_queue_id >= 0)
);

-- Permanent eligibility only; presence and per-letter base/Extra capacity are separate.
CREATE OR REPLACE FUNCTION call_center.cc_email_agent_assignable(_queue_id integer, _agent_id integer)
    RETURNS boolean
    LANGUAGE sql
    STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM call_center.cc_queue q
                 JOIN call_center.cc_agent a
                      ON a.domain_id = q.domain_id AND (q.team_id IS NULL OR a.team_id = q.team_id)
        WHERE q.id = _queue_id
          AND a.id = _agent_id
          AND 'email' = ANY (a.allow_channels)
          AND EXISTS (
              SELECT 1
              FROM call_center.cc_queue_skill qs
                       JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
              WHERE qs.queue_id = q.id
                AND qs.enabled
                AND sia.agent_id = a.id
                AND sia.enabled
                AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
          )
    )
$$;

CREATE OR REPLACE FUNCTION call_center.cc_email_agent_capacity(_agent_id integer, _extra_allowed boolean DEFAULT false)
    RETURNS TABLE (used_base integer, used_extra integer, used_slots integer, base_limit integer, extra_limit integer,
                   has_slot_type boolean, slot_type text)
    LANGUAGE sql
    STABLE
AS $$
    SELECT u.used_base::integer, u.used_extra::integer, u.used_slots::integer,
           a.email_count::integer, a.extra_email_count::integer,
           a.email_count > 0 OR (_extra_allowed AND a.extra_email_count > 0),
           CASE
               -- A partial/unsupported upgrade must not make unclassified assignments invisible.
               WHEN u.unknown_slots > 0 THEN NULL::text
               WHEN u.used_base < a.email_count THEN 'base'
               WHEN _extra_allowed AND u.used_extra < a.extra_email_count THEN 'extra'
           END
    FROM call_center.cc_agent a
             CROSS JOIN LATERAL (
                 SELECT count(*) FILTER (WHERE ea.email_slot_type = 'base') AS used_base,
                        count(*) FILTER (WHERE ea.email_slot_type = 'extra') AS used_extra,
                        count(*) AS used_slots,
                        count(*) FILTER (WHERE ea.email_slot_type IS NULL OR ea.email_slot_type NOT IN ('base', 'extra')) AS unknown_slots
                 FROM call_center.cc_member_attempt ea
                 WHERE ea.agent_id = a.id AND ea.channel = 'email'
                   AND ea.leaving_at IS NULL AND ea.state <> 'leaving'
             ) u
    WHERE a.id = _agent_id
$$;

DROP FUNCTION IF EXISTS call_center.cc_email_queue_candidates(integer, integer);
CREATE OR REPLACE FUNCTION call_center.cc_email_queue_candidates(
    _queue_id integer, _agent_id integer DEFAULT NULL, _extra_allowed boolean DEFAULT false)
    RETURNS TABLE (agent_id integer, team_id integer, used_slots integer, email_count integer,
                   last_offering_at timestamp with time zone, used_base integer, used_extra integer,
                   extra_email_count integer, slot_type text)
    LANGUAGE sql
    STABLE
AS $$
    SELECT a.id, a.team_id, c.used_slots, c.base_limit, ch.last_offering_at,
           c.used_base, c.used_extra, c.extra_limit, c.slot_type
    FROM call_center.cc_queue q
             JOIN call_center.cc_agent a
                  ON a.domain_id = q.domain_id AND (q.team_id IS NULL OR a.team_id = q.team_id)
             JOIN call_center.cc_agent_channel ch ON ch.agent_id = a.id AND ch.channel = 'email'
             LEFT JOIN call_center.cc_online_skills os ON os.id = a.status_id
             CROSS JOIN LATERAL call_center.cc_email_agent_capacity(a.id, _extra_allowed) c
    WHERE q.id = _queue_id AND q.type = 11 AND q.enabled
      AND (_agent_id IS NULL OR a.id = _agent_id)
      AND a.status = 'online' AND ch.online
      AND 'email' = ANY (a.allow_channels)
      AND c.slot_type IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM call_center.cc_queue_skill qs
                   JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
          WHERE qs.queue_id = q.id AND qs.enabled
            AND sia.agent_id = a.id AND sia.enabled
            AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
            AND (a.status_id IS NULL OR os.is_system IS TRUE OR EXISTS (
                SELECT 1 FROM call_center.cc_skills_in_online_skills sp
                WHERE sp.online_skill_id = a.status_id AND sp.skill_id = sia.skill_id
            ))
      )
    ORDER BY c.used_slots, ch.last_offering_at NULLS FIRST, a.id
$$;

CREATE OR REPLACE FUNCTION call_center.cc_email_sticky_wait_sec(_payload jsonb)
    RETURNS integer
    LANGUAGE plpgsql
    IMMUTABLE
AS $$
DECLARE
    _value jsonb := _payload -> 'sticky_agent_sec';
    _seconds numeric;
BEGIN
    IF jsonb_typeof(_value) IS DISTINCT FROM 'number' THEN
        RETURN 30;
    END IF;
    _seconds := _value::numeric;
    IF _seconds <> trunc(_seconds) OR _seconds < -2147483648 OR _seconds > 2147483647 THEN
        RETURN 30;
    END IF;
    -- Preserve signed-int32 nonpositive settings as no-wait; validate before casting.
    RETURN greatest(_seconds, 0)::integer;
END;
$$;

DROP FUNCTION IF EXISTS call_center.cc_email_sticky_prepare(call_center.cc_queue, integer[], integer);
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
                _weight := greatest(_weight, 10);
            ELSIF _att.sticky_until IS NULL AND _wait > 0 THEN
                _until := _now + make_interval(secs => _wait);
            ELSIF (_wait > 0 AND _until <= _now) OR
                  (_wait <= 0 AND ((_att.sticky_until IS NOT NULL AND _att.sticky_until < transaction_timestamp())
                                  OR NOT _online OR _slot IS NULL)) THEN
                _candidate := NULL;
                _until := _now;
                _weight := greatest(_weight, 10);
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

CREATE OR REPLACE FUNCTION call_center.cc_email_try_assign(_attempt_id bigint, _queue_id integer, _agent_id integer)
    RETURNS boolean
    LANGUAGE plpgsql
AS $$
DECLARE
    _q         call_center.cc_queue;
    _att       call_center.cc_member_attempt;
    _team_id   integer;
    _status_id integer;
    _system    boolean;
    _slot      text;
    _wait      integer;
BEGIN
    SELECT q.* INTO _q FROM call_center.cc_queue q
    WHERE q.id = _queue_id AND q.type = 11 AND q.enabled FOR SHARE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    PERFORM 1 FROM flow.calendar c WHERE c.id = _q.calendar_id FOR SHARE SKIP LOCKED;
    IF NOT FOUND OR call_center.cc_email_queue_calendar(_q.domain_id, _q.calendar_id) <> 'open' THEN
        RETURN false;
    END IF;

    SELECT a.* INTO _att FROM call_center.cc_member_attempt a
    WHERE a.id = _attempt_id AND a.queue_id = _q.id AND a.domain_id = _q.domain_id
      AND a.channel = 'email' AND a.queue_type = 11 AND a.state = 'waiting'
      AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.email_slot_type IS NULL
        FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    _wait := call_center.cc_email_sticky_wait_sec(_q.payload);
    IF _att.sticky_agent_id IS NOT NULL AND (
        NOT _q.sticky_agent OR _att.sticky_agent_id <> _agent_id OR _att.sticky_until IS NULL
        OR (_wait > 0 AND _att.sticky_until <= clock_timestamp())
        OR (_wait = 0 AND _att.sticky_until < transaction_timestamp())
    ) THEN
        RETURN false;
    END IF;

    -- Serialize all assignments of this agent: agent before Email channel.
    SELECT a.status_id INTO _status_id FROM call_center.cc_agent a
    WHERE a.id = _agent_id FOR SHARE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    PERFORM 1 FROM call_center.cc_agent_channel ch
    WHERE ch.agent_id = _agent_id AND ch.channel = 'email' FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Keep a qualifying skill pair and online preset stable until commit.
    IF _status_id IS NOT NULL THEN
        SELECT os.is_system INTO _system FROM call_center.cc_online_skills os
        WHERE os.id = _status_id FOR SHARE SKIP LOCKED;
        IF NOT FOUND THEN
            RETURN false;
        END IF;
    END IF;
    IF _status_id IS NULL OR _system IS TRUE THEN
        PERFORM 1
        FROM call_center.cc_queue_skill qs
                 JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
        WHERE qs.queue_id = _q.id AND qs.enabled
          AND sia.agent_id = _agent_id AND sia.enabled
          AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
        LIMIT 1 FOR SHARE OF qs, sia SKIP LOCKED;
    ELSE
        PERFORM 1
        FROM call_center.cc_queue_skill qs
                 JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
                 JOIN call_center.cc_skills_in_online_skills sp
                      ON sp.online_skill_id = _status_id AND sp.skill_id = sia.skill_id
        WHERE qs.queue_id = _q.id AND qs.enabled
          AND sia.agent_id = _agent_id AND sia.enabled
          AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
        LIMIT 1 FOR SHARE OF qs, sia, sp SKIP LOCKED;
    END IF;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    SELECT c.team_id, c.slot_type INTO _team_id, _slot
    FROM call_center.cc_email_queue_candidates(_q.id, _agent_id, _att.email_extra_allowed) c;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE call_center.cc_member_attempt a
    SET state = 'offering', agent_id = _agent_id, team_id = _team_id, email_slot_type = _slot,
        offering_at = now(), last_state_change = now(),
        offered_agent_ids = CASE WHEN _agent_id = ANY (a.offered_agent_ids) THEN a.offered_agent_ids
                                ELSE array_append(a.offered_agent_ids, _agent_id) END
    WHERE a.id = _att.id AND a.queue_id = _q.id AND a.domain_id = _q.domain_id
      AND a.channel = 'email' AND a.queue_type = 11 AND a.state = 'waiting'
      AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.email_slot_type IS NULL
      AND (a.sticky_agent_id IS NULL OR
           (a.sticky_agent_id = _agent_id AND a.sticky_until IS NOT NULL
            AND ((_wait = 0 AND a.sticky_until >= transaction_timestamp())
                 OR (_wait > 0 AND a.sticky_until > clock_timestamp()))));
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE call_center.cc_agent_channel SET last_offering_at = now()
    WHERE agent_id = _agent_id AND channel = 'email';
    RETURN true;
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
           CASE WHEN NOT e.cancelled AND e.expired THEN greatest(_priority, 10) ELSE _priority END
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

CREATE OR REPLACE FUNCTION call_center.cc_email_agent_head(_agent_id integer, _skip_attempts bigint[] DEFAULT '{}'::bigint[])
    RETURNS TABLE (attempt_id bigint, queue_id integer, priority integer, joined_at timestamp with time zone,
                   sticky_agent_id integer, sticky_until timestamp with time zone, extra_allowed boolean)
    LANGUAGE sql
    STABLE
AS $$
    WITH agent AS MATERIALIZED (
        SELECT a.id, a.domain_id, a.status_id, os.is_system, c.slot_type
        FROM call_center.cc_agent a
                 JOIN call_center.cc_agent_channel ch ON ch.agent_id = a.id AND ch.channel = 'email'
                 LEFT JOIN call_center.cc_online_skills os ON os.id = a.status_id
                 CROSS JOIN LATERAL call_center.cc_email_agent_capacity(a.id, true) c
        WHERE a.id = _agent_id AND a.status = 'online' AND ch.online
          AND 'email' = ANY (a.allow_channels) AND c.slot_type IS NOT NULL
    ), queues AS (
        SELECT q AS queue_row, q.id, q.sticky_agent, call_center.cc_email_sticky_wait_sec(q.payload) AS wait_sec
        FROM call_center.cc_queue q JOIN agent ag ON ag.domain_id = q.domain_id
        WHERE q.type = 11 AND q.enabled AND call_center.cc_email_agent_assignable(q.id, ag.id)
          AND call_center.cc_email_queue_calendar(q.domain_id, q.calendar_id) = 'open'
          AND (ag.status_id IS NULL OR ag.is_system IS TRUE OR EXISTS (
              SELECT 1
              FROM call_center.cc_queue_skill qs
                       JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
                       JOIN call_center.cc_skills_in_online_skills sp
                            ON sp.online_skill_id = ag.status_id AND sp.skill_id = sia.skill_id
              WHERE qs.queue_id = q.id AND qs.enabled AND sia.agent_id = ag.id AND sia.enabled
                AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
          ))
    )
    SELECT w.id, q.id, w.weight, w.joined_at, w.sticky_agent_id, w.sticky_until, w.email_extra_allowed
    FROM queues q CROSS JOIN agent ag
             CROSS JOIN LATERAL (
                 SELECT choices.* FROM (
                     (SELECT a.id, a.weight, a.joined_at, a.sticky_agent_id, a.sticky_until, a.email_extra_allowed
                      FROM call_center.cc_member_attempt a
                      WHERE a.queue_id = q.id AND a.channel = 'email' AND a.queue_type = 11
                        AND a.state = 'waiting' AND a.agent_id IS NULL AND a.leaving_at IS NULL
                        AND NOT a.id = ANY (_skip_attempts) AND ag.slot_type = 'base'
                        AND a.sticky_agent_id IS NULL
                      ORDER BY a.weight DESC, a.joined_at, a.id LIMIT 1)
                     UNION ALL
                     (SELECT a.id, a.weight, a.joined_at, a.sticky_agent_id, a.sticky_until, a.email_extra_allowed
                      FROM call_center.cc_member_attempt a
                      WHERE a.queue_id = q.id AND a.channel = 'email' AND a.queue_type = 11
                        AND a.state = 'waiting' AND a.agent_id IS NULL AND a.leaving_at IS NULL
                        AND NOT a.id = ANY (_skip_attempts) AND ag.slot_type = 'extra'
                        AND a.email_extra_allowed
                        AND a.sticky_agent_id IS NULL
                      ORDER BY a.weight DESC, a.joined_at, a.id LIMIT 1)
                     UNION ALL
                     (SELECT a.id, a.weight, a.joined_at, a.sticky_agent_id, a.sticky_until, a.email_extra_allowed
                      FROM call_center.cc_member_attempt a
                      WHERE a.queue_id = q.id AND a.channel = 'email' AND a.queue_type = 11
                        AND a.state = 'waiting' AND a.agent_id IS NULL AND a.leaving_at IS NULL
                        AND NOT a.id = ANY (_skip_attempts) AND ag.slot_type = 'base'
                        AND q.sticky_agent AND a.sticky_agent_id = ag.id
                        AND (a.sticky_until IS NULL OR q.wait_sec = 0 OR a.sticky_until > clock_timestamp())
                      ORDER BY a.weight DESC, a.joined_at, a.id LIMIT 1)
                     UNION ALL
                     (SELECT a.id, a.weight, a.joined_at, a.sticky_agent_id, a.sticky_until, a.email_extra_allowed
                      FROM call_center.cc_member_attempt a
                      WHERE a.queue_id = q.id AND a.channel = 'email' AND a.queue_type = 11
                        AND a.state = 'waiting' AND a.agent_id IS NULL AND a.leaving_at IS NULL
                        AND NOT a.id = ANY (_skip_attempts) AND ag.slot_type = 'extra'
                        AND a.email_extra_allowed
                        AND q.sticky_agent AND a.sticky_agent_id = ag.id
                        AND (a.sticky_until IS NULL OR q.wait_sec = 0 OR a.sticky_until > clock_timestamp())
                      ORDER BY a.weight DESC, a.joined_at, a.id LIMIT 1)
                     UNION ALL
                     (WITH sticky_routes AS MATERIALIZED (
                         -- Check each candidate/Extra pair once, without a letter deadline.
                         SELECT g.sticky_agent_id, g.email_extra_allowed, r.candidate_id, r.priority AS fallback_priority
                         FROM (
                             SELECT DISTINCT a.sticky_agent_id, a.email_extra_allowed
                             FROM call_center.cc_member_attempt a
                             WHERE a.queue_id = q.id AND a.channel = 'email' AND a.queue_type = 11
                               AND a.state = 'waiting' AND a.agent_id IS NULL AND a.leaving_at IS NULL
                               AND a.sticky_agent_id IS NOT NULL AND NOT a.id = ANY (_skip_attempts)
                               AND (ag.slot_type = 'base' OR a.email_extra_allowed)
                         ) g
                                  CROSS JOIN LATERAL call_center.cc_email_sticky_route(
                                      q.queue_row, g.sticky_agent_id, g.email_extra_allowed, NULL::timestamptz, 0) r
                     )
                      SELECT a.id,
                             -- Cancellation keeps priority; immediate/deadline fallback raises it.
                             CASE WHEN r.candidate_id IS NULL AND r.fallback_priority = 0 THEN a.weight
                                  ELSE greatest(a.weight, 10) END AS weight,
                             a.joined_at, a.sticky_agent_id,
                             a.sticky_until, a.email_extra_allowed
                      FROM sticky_routes r
                               JOIN call_center.cc_member_attempt a
                                    ON a.sticky_agent_id = r.sticky_agent_id AND a.email_extra_allowed = r.email_extra_allowed
                      WHERE a.queue_id = q.id AND a.channel = 'email' AND a.queue_type = 11
                        AND a.state = 'waiting' AND a.agent_id IS NULL AND a.leaving_at IS NULL
                        AND a.sticky_agent_id IS NOT NULL AND NOT a.id = ANY (_skip_attempts)
                        AND (ag.slot_type = 'base' OR a.email_extra_allowed)
                        AND (r.candidate_id IS NULL
                            OR (q.wait_sec > 0 AND a.sticky_until <= clock_timestamp())
                            OR (q.wait_sec = 0 AND a.sticky_until < transaction_timestamp()))
                      ORDER BY weight DESC, a.joined_at, a.id LIMIT 1)
                 ) choices
                 ORDER BY choices.weight DESC, choices.joined_at, choices.id LIMIT 1
             ) w
    ORDER BY w.weight DESC, w.joined_at, w.id LIMIT 1
$$;

CREATE OR REPLACE FUNCTION call_center.cc_email_distribute(_queue_batch integer, _max_duration interval)
    RETURNS TABLE (result text, queue_id integer, attempt_id bigint, agent_id integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _deadline timestamp with time zone := clock_timestamp() + _max_duration;
    _prep_deadline timestamp with time zone := clock_timestamp() + _max_duration / 4;
    _last_queue integer;
    _last_agent integer;
    _queue_start integer;
    _agent_start integer;
    _queue_id integer;
    _agent_id integer;
    _q call_center.cc_queue;
    _calendar text;
    _head record;
    _other_head record;
    _candidate record;
    _skip bigint[] := '{}';
    _queues integer[] := '{}';
    _counts integer[] := '{}';
    _pos integer;
    _tries integer;
    _head_id bigint;
    _done boolean;
    _progress boolean;
    _timed_out boolean := false;
BEGIN
    IF coalesce(_queue_batch, 0) <= 0 OR _max_duration IS NULL OR _max_duration <= interval '0' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email distribute: positive batch and duration are required';
    END IF;
    IF NOT pg_try_advisory_xact_lock(1162690889, 1) THEN
        RETURN QUERY SELECT 'busy'::text, NULL::integer, NULL::bigint, NULL::integer;
        RETURN;
    END IF;
    INSERT INTO call_center.cc_email_distribution_cursor(singleton) VALUES (true) ON CONFLICT DO NOTHING;
    SELECT c.last_queue_id, c.last_agent_id INTO _last_queue, _last_agent
    FROM call_center.cc_email_distribution_cursor c WHERE c.singleton FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'busy'::text, NULL::integer, NULL::bigint, NULL::integer;
        RETURN;
    END IF;

    <<work>>
    BEGIN
        -- Fair upkeep also advances offline candidates when no online agent can take work.
        _queue_start := _last_queue;
        FOR _queue_id IN
            SELECT q.id FROM call_center.cc_queue q
            WHERE q.type = 11 AND q.enabled
              AND ((SELECT a.id FROM call_center.cc_member_attempt a
                    WHERE a.queue_id = q.id AND a.channel = 'email' AND a.state = 'waiting'
                      AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.sticky_agent_id IS NULL
                    ORDER BY a.weight DESC, a.joined_at, a.id LIMIT 1) IS NOT NULL
                OR (SELECT a.id FROM call_center.cc_member_attempt a
                    WHERE a.queue_id = q.id AND a.channel = 'email' AND a.state = 'waiting'
                      AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.sticky_agent_id IS NOT NULL
                    ORDER BY a.sticky_until LIMIT 1) IS NOT NULL)
            ORDER BY (q.id <= _queue_start), q.id
        LOOP
            EXIT WHEN clock_timestamp() >= _prep_deadline;
            _last_queue := _queue_id;
            SELECT q.* INTO _q FROM call_center.cc_queue q
            WHERE q.id = _queue_id AND q.type = 11 AND q.enabled FOR SHARE SKIP LOCKED;
            CONTINUE WHEN NOT FOUND;
            PERFORM 1 FROM flow.calendar c WHERE c.id = _q.calendar_id FOR SHARE SKIP LOCKED;
            CONTINUE WHEN NOT FOUND AND EXISTS (SELECT 1 FROM flow.calendar c WHERE c.id = _q.calendar_id);
            _calendar := call_center.cc_email_queue_calendar(_q.domain_id, _q.calendar_id);
            IF _calendar <> 'open' THEN
                RETURN QUERY SELECT 'calendar_' || _calendar, _q.id, NULL::bigint, NULL::integer;
                CONTINUE;
            END IF;
            IF NOT EXISTS (SELECT 1 FROM call_center.cc_queue_skill qs WHERE qs.queue_id = _q.id AND qs.enabled) THEN
                RETURN QUERY SELECT 'no_skills'::text, _q.id, NULL::bigint, NULL::integer;
                CONTINUE;
            END IF;
            PERFORM call_center.cc_email_sticky_prepare(_q, ARRAY[]::integer[], least(_queue_batch, 128), NULL);
            IF NOT EXISTS (SELECT 1 FROM call_center.cc_email_queue_candidates(_q.id, NULL, true)) THEN
                RETURN QUERY SELECT 'no_agent'::text, _q.id, NULL::bigint, NULL::integer;
            END IF;
        END LOOP;

        LOOP
            _progress := false;
            _agent_start := _last_agent;
            FOR _agent_id IN
                SELECT a.id FROM call_center.cc_agent a
                         JOIN call_center.cc_agent_channel ch ON ch.agent_id = a.id AND ch.channel = 'email'
                WHERE a.status = 'online' AND ch.online AND 'email' = ANY (a.allow_channels)
                  AND (a.email_count > 0 OR a.extra_email_count > 0)
                ORDER BY (a.id <= _agent_start), a.id
            LOOP
                IF clock_timestamp() >= _deadline THEN
                    _timed_out := true;
                    EXIT work;
                END IF;
                _last_agent := _agent_id;
                _tries := 0;
                LOOP
                    IF clock_timestamp() >= _deadline THEN
                        _timed_out := true;
                        EXIT work;
                    END IF;
                    EXIT WHEN _tries >= _queue_batch;
                    SELECT h.* INTO _head FROM call_center.cc_email_agent_head(_agent_id, _skip) h;
                    EXIT WHEN NOT FOUND;
                    _tries := _tries + 1;
                    _pos := array_position(_queues, _head.queue_id);
                    IF _pos IS NOT NULL AND _counts[_pos] >= _queue_batch THEN
                        -- Do not demote this agent to lower-priority work because of a queue batch cap.
                        EXIT;
                    END IF;

                    IF _head.sticky_agent_id IS NOT NULL THEN
                        _head_id := _head.attempt_id;
                        SELECT q.* INTO _q FROM call_center.cc_queue q WHERE q.id = _head.queue_id;
                        PERFORM call_center.cc_email_sticky_prepare(_q, ARRAY[_agent_id], 1, _head.attempt_id);
                        -- A fallback may have changed priority/owner restriction; select again.
                        SELECT h.* INTO _head FROM call_center.cc_email_agent_head(_agent_id, _skip) h;
                        EXIT WHEN NOT FOUND;
                        CONTINUE WHEN _head.attempt_id <> _head_id;
                        _pos := array_position(_queues, _head.queue_id);
                        EXIT WHEN _pos IS NOT NULL AND _counts[_pos] >= _queue_batch;
                    END IF;

                    _done := false;
                    FOR _candidate IN
                        SELECT c.agent_id FROM call_center.cc_email_queue_candidates(_head.queue_id, NULL, _head.extra_allowed) c
                        ORDER BY c.used_slots, c.last_offering_at NULLS FIRST, c.agent_id
                    LOOP
                        IF clock_timestamp() >= _deadline THEN
                            _timed_out := true;
                            EXIT work;
                        END IF;
                        IF _candidate.agent_id <> _agent_id THEN
                            SELECT h.* INTO _other_head FROM call_center.cc_email_agent_head(_candidate.agent_id, _skip) h;
                            CONTINUE WHEN NOT FOUND OR _other_head.attempt_id <> _head.attempt_id;
                        END IF;
                        IF call_center.cc_email_try_assign(_head.attempt_id, _head.queue_id, _candidate.agent_id) THEN
                            _done := true;
                            _progress := true;
                            IF _pos IS NULL THEN
                                _queues := array_append(_queues, _head.queue_id);
                                _counts := array_append(_counts, 1);
                            ELSE
                                _counts[_pos] := _counts[_pos] + 1;
                            END IF;
                            RETURN QUERY SELECT 'assigned'::text, _head.queue_id, _head.attempt_id, _candidate.agent_id;
                            EXIT;
                        END IF;
                    END LOOP;
                    IF _done THEN
                        EXIT; -- One assignment per visitor/round; actual winner remains deterministic.
                    END IF;
                    _skip := array_append(_skip, _head.attempt_id);
                    RETURN QUERY SELECT 'no_agent'::text, _head.queue_id, _head.attempt_id, NULL::integer;
                END LOOP;
            END LOOP;
            EXIT WHEN NOT _progress;
        END LOOP;
    END work;

    UPDATE call_center.cc_email_distribution_cursor
    SET last_queue_id = _last_queue, last_agent_id = _last_agent WHERE singleton;
    IF _timed_out OR clock_timestamp() >= _deadline THEN
        RETURN QUERY SELECT 'time_limit'::text, NULL::integer, NULL::bigint, NULL::integer;
    END IF;
END;
$$;

-- Default arguments keep four-argument SQL callers compatible without an old overload.
DROP FUNCTION IF EXISTS call_center.cc_email_join_to_queue(uuid, bigint, bigint, integer);
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
    IF _priority IS NULL OR _priority < 0 OR _priority > 100 THEN
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

-- Append-only Agent read mapping; existing view columns retain their positions.
CREATE OR REPLACE VIEW call_center.cc_agent_list AS
 SELECT a.domain_id,
    a.id,
    (COALESCE(ct.name, ((ct.username)::text COLLATE "default")))::character varying AS name,
    a.status,
    a.description,
    ((date_part('epoch'::text, a.last_state_change) * (1000)::double precision))::bigint AS last_status_change,
    (date_part('epoch'::text, (now() - a.last_state_change)))::bigint AS status_duration,
    a.progressive_count,
    ch.x AS channel,
    (json_build_object('id', ct.id, 'name', COALESCE(ct.name, (ct.username)::text)))::jsonb AS "user",
    call_center.cc_get_lookup((a.greeting_media_id)::bigint, g.name) AS greeting_media,
    a.allow_channels,
    a.chat_count,
    ( SELECT jsonb_agg(sag."user") AS jsonb_agg
           FROM call_center.cc_agent_with_user sag
          WHERE (sag.id = ANY (a.supervisor_ids))) AS supervisor,
    ( SELECT jsonb_agg(call_center.cc_get_lookup(aud.id, (COALESCE(aud.name, (aud.username)::text))::character varying)) AS jsonb_agg
           FROM directory.wbt_user aud
          WHERE (aud.id = ANY (a.auditor_ids))) AS auditor,
    call_center.cc_get_lookup(t.id, t.name) AS team,
    call_center.cc_get_lookup((r.id)::bigint, r.name) AS region,
    a.supervisor AS is_supervisor,
    ( SELECT jsonb_agg(call_center.cc_get_lookup((sa.skill_id)::bigint, cs.name)) AS jsonb_agg
           FROM (call_center.cc_skill_in_agent sa
             JOIN call_center.cc_skill cs ON ((sa.skill_id = cs.id)))
          WHERE (sa.agent_id = a.id)) AS skills,
    a.team_id,
    a.region_id,
    a.supervisor_ids,
    a.auditor_ids,
    a.user_id,
    ct.extension,
    a.task_count,
    a.screen_control,
    (t.screen_control IS FALSE) AS allow_set_screen_control,
    row_number() OVER (PARTITION BY a.domain_id ORDER BY
        CASE
            WHEN ((a.status)::text = 'online'::text) THEN 0
            WHEN ((a.status)::text = 'pause'::text) THEN 1
            WHEN ((a.status)::text = 'offline'::text) THEN 2
            ELSE 3
        END, COALESCE(ct.name, (ct.username)::text)) AS "position",
    COALESCE(( SELECT array_agg(status.open) AS array_agg
           FROM ( SELECT 'dnd'::name AS "?column?"
                   FROM directory.wbt_user_status stt
                  WHERE ((stt.user_id = a.user_id) AND stt.dnd)
                UNION ALL
                ( SELECT stt.status
                   FROM directory.wbt_user_presence stt
                  WHERE ((stt.user_id = a.user_id) AND (stt.status IS NOT NULL) AND (stt.open > 0))
                  ORDER BY stt.prior, stt.status)) status(open)), '{}'::name[]) AS user_presence_status,
    a.extra_chat_count,
    COALESCE(a.status_payload, (os.name)::character varying, ''::character varying) AS status_type,
    a.email_count,
    a.extra_email_count
   FROM ((((((call_center.cc_agent a
     LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
     LEFT JOIN storage.media_files g ON ((g.id = a.greeting_media_id)))
     LEFT JOIN call_center.cc_team t ON ((t.id = a.team_id)))
     LEFT JOIN flow.region r ON ((r.id = a.region_id)))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint)) AS x
           FROM call_center.cc_agent_channel c
          WHERE (c.agent_id = a.id)) ch ON (true))
     LEFT JOIN call_center.cc_online_skills os ON (((a.status_id IS NOT NULL) AND (a.status_id = os.id) AND (os.is_system IS FALSE))));

CREATE OR REPLACE VIEW call_center.cc_agent_in_queue_view AS
 WITH users_with_calls AS (
         SELECT DISTINCT c.user_id
           FROM call_center.cc_calls c
          WHERE ((c.user_id IS NOT NULL) AND (((c.hangup_at IS NULL) AND (NOT (EXISTS ( SELECT 1
                   FROM call_center.cc_calls cc
                  WHERE ((cc.parent_id = c.id) AND (cc.hangup_at IS NOT NULL)))))) OR ((c.hangup_at IS NOT NULL) AND (c.attempt_id IS NOT NULL) AND (EXISTS ( SELECT 1
                   FROM call_center.cc_agent_channel ch
                  WHERE ((ch.agent_id = c.agent_id) AND ((ch.channel)::text = ANY (ARRAY[('call'::character varying)::text, ('out_call'::character varying)::text])) AND ((ch.state)::text = 'processing'::text)))))))
        )
 SELECT q.queue,
    q.priority,
    q.type,
    q.strategy,
    q.enabled,
    q.count_members,
    q.waiting_members,
    q.active_members,
    q.queue_id,
    q.queue_name,
    q.team_id,
    q.domain_id,
    q.agent_id,
    jsonb_build_object('online', COALESCE(array_length(a.agent_on_ids, 1), 0), 'pause', COALESCE(array_length(a.agent_p_ids, 1), 0), 'offline', COALESCE(array_length(a.agent_off_ids, 1), 0), 'free', COALESCE(array_length(a.free, 1), 0), 'total', COALESCE(array_length(a.total, 1), 0), 'allow_pause',
        CASE
            WHEN (q.min_online_agents > 0) THEN GREATEST(((COALESCE(array_length(a.agent_p_ids, 1), 0) + COALESCE(array_length(a.agent_on_ids, 1), 0)) - q.min_online_agents), 0)
            ELSE NULL::integer
        END, 'busy', COALESCE(array_length(a.agent_b_ids, 1), 0)) AS agents,
    q.max_member_limit
   FROM (( SELECT call_center.cc_get_lookup((q_1.id)::bigint, q_1.name) AS queue,
            q_1.priority,
            q_1.type,
            q_1.strategy,
            q_1.enabled,
            COALESCE(((q_1.payload -> 'min_online_agents'::text))::integer, 0) AS min_online_agents,
            COALESCE(((q_1.payload -> 'max_member_limit'::text))::integer, 0) AS max_member_limit,
            COALESCE(sum(cqs.member_count), (0)::bigint) AS count_members,
                CASE
                    WHEN (q_1.type = ANY (ARRAY[1, 6])) THEN ( SELECT count(*) AS count
                       FROM call_center.cc_member_attempt a_1_1
                      WHERE ((a_1_1.queue_id = q_1.id) AND ((a_1_1.state)::text = ANY (ARRAY[('wait_agent'::character varying)::text, ('offering'::character varying)::text])) AND (a_1_1.leaving_at IS NULL)))
                    WHEN (q_1.type = 11) THEN ( SELECT count(*) AS count
                       FROM call_center.cc_member_attempt a_1_1
                      WHERE ((a_1_1.queue_id = q_1.id) AND (a_1_1.agent_id IS NULL) AND ((a_1_1.state)::text = 'waiting'::text) AND (a_1_1.leaving_at IS NULL)))
                    ELSE COALESCE(sum(cqs.member_waiting), (0)::bigint)
                END AS waiting_members,
            ( SELECT count(*) AS count
                   FROM call_center.cc_member_attempt a_1_1
                  WHERE (a_1_1.queue_id = q_1.id)) AS active_members,
            q_1.id AS queue_id,
            q_1.name AS queue_name,
            q_1.team_id,
            a_1.domain_id,
            a_1.id AS agent_id,
                CASE
                    WHEN ((q_1.type >= 0) AND (q_1.type <= 5)) THEN 'call'::text
                    WHEN (q_1.type = 6) THEN 'chat'::text
                    WHEN (q_1.type = 11) THEN 'email'::text
                    ELSE 'task'::text
                END AS chan_name
           FROM ((call_center.cc_agent a_1
             JOIN call_center.cc_queue q_1 ON ((q_1.domain_id = a_1.domain_id)))
             LEFT JOIN call_center.cc_queue_statistics cqs ON ((q_1.id = cqs.queue_id)))
          WHERE (((q_1.team_id IS NULL) OR (a_1.team_id = q_1.team_id)) AND (EXISTS ( SELECT qs.queue_id
                   FROM (call_center.cc_queue_skill qs
                     JOIN call_center.cc_skill_in_agent csia ON ((csia.skill_id = qs.skill_id)))
                  WHERE (qs.enabled AND csia.enabled AND (csia.agent_id = a_1.id) AND (qs.queue_id = q_1.id) AND (csia.capacity >= qs.min_capacity) AND (csia.capacity <= qs.max_capacity)))))
          GROUP BY a_1.id, q_1.id, q_1.priority) q
     LEFT JOIN LATERAL ( SELECT DISTINCT array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND ((a_1.status_id IS NULL) OR (sp.is_system IS TRUE) OR (spp.skill_id IS NOT NULL)))) AS agent_on_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = 'offline'::text)) AS agent_off_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = ANY (ARRAY[('pause'::character varying)::text, ('break_out'::character varying)::text]))) AS agent_p_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND ((a_1.status_id IS NULL) OR (sp.is_system IS TRUE) OR (spp.skill_id IS NOT NULL)) AND
                CASE
                    WHEN ((ac.channel)::text = 'email'::text) THEN (ac.online AND (('email'::character varying)::text = ANY ((a_1.allow_channels)::text[])) AND EXISTS (
                        SELECT 1 FROM call_center.cc_email_agent_capacity(a_1.id, true) ec
                        WHERE ec.slot_type IS NOT NULL))
                    ELSE (((ac.state)::text = 'waiting'::text) AND ((ac_call.user_id IS NULL) OR ((ac.channel)::text = ANY (ARRAY['chat'::text, 'task'::text]))))
                END)) AS free,
            array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND ((a_1.status_id IS NULL) OR (sp.is_system IS TRUE) OR (spp.skill_id IS NOT NULL)) AND (ac_call.user_id IS NOT NULL))) AS agent_b_ids,
            array_agg(DISTINCT a_1.id) AS total
           FROM ((((((call_center.cc_agent a_1
             JOIN call_center.cc_agent_channel ac ON (((ac.agent_id = a_1.id) AND ((ac.channel)::text = q.chan_name))))
             LEFT JOIN users_with_calls ac_call ON ((ac_call.user_id = a_1.user_id)))
             JOIN call_center.cc_queue_skill qs ON (((qs.queue_id = q.queue_id) AND qs.enabled)))
             JOIN call_center.cc_skill_in_agent sia ON (((sia.agent_id = a_1.id) AND sia.enabled)))
             LEFT JOIN call_center.cc_online_skills sp ON (((sp.id = a_1.status_id) AND ((a_1.status)::text = 'online'::text))))
             LEFT JOIN call_center.cc_skills_in_online_skills spp ON (((spp.online_skill_id = a_1.status_id) AND (spp.skill_id = sia.skill_id) AND ((a_1.status)::text = 'online'::text))))
          WHERE ((a_1.domain_id = q.domain_id) AND ((q.team_id IS NULL) OR (a_1.team_id = q.team_id)) AND (qs.skill_id = sia.skill_id) AND (sia.capacity >= qs.min_capacity) AND (sia.capacity <= qs.max_capacity))
          GROUP BY ROLLUP(q.queue_id)) a ON (true));

COMMIT;
