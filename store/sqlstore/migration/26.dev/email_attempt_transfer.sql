-- Email commands of engine (EM-25): the session user in operator commands and the reason of a manual return,
-- the Email Transfer to a queue or an agent, skill and preset locks before the attempt for a direct transfer,
-- a resume and a wake-up, and the candidates of a direct transfer.
-- Run with psql -v ON_ERROR_STOP=1 -f after email_status_sync.sql and email_route.sql, with Email writers
-- stopped and outside a transaction: the retention index is built CONCURRENTLY. Every step can be repeated.

DO $$
BEGIN
    IF to_regprocedure('call_center.cc_email_wakeup_thread(uuid,bigint,bigint)') IS NULL
        OR to_regprocedure('call_center.cc_email_high_priority()') IS NULL
        OR to_regprocedure('call_center.cc_email_agent_strategy_refresh(integer,timestamp with time zone)') IS NULL
        OR to_regprocedure('call_center.cc_email_queue_candidates(integer,integer,boolean)') IS NULL
        OR NOT EXISTS (
            SELECT 1 FROM pg_attribute
            WHERE attrelid = to_regclass('call_center.cc_email_attempt_outbox')
              AND attname = 'locked_by' AND NOT attisdropped
        ) OR NOT EXISTS (
            SELECT 1 FROM pg_attribute
            WHERE attrelid = to_regclass('call_center.cc_email_wakeup')
              AND attname = 'fallback_queue_id' AND NOT attisdropped
        ) THEN
        RAISE EXCEPTION 'email attempt transfer: EM-24 Email status sync is required';
    END IF;
END
$$;

-- Author, comment and target of a command, set only by engine.
ALTER TABLE call_center.cc_email_attempt_outbox
    ADD COLUMN IF NOT EXISTS actor_user_id bigint,
    ADD COLUMN IF NOT EXISTS comment text,
    ADD COLUMN IF NOT EXISTS transfer_to_queue_id integer,
    ADD COLUMN IF NOT EXISTS transfer_to_user_id bigint;

ALTER TABLE call_center.cc_email_attempt_outbox
    DROP CONSTRAINT IF EXISTS cc_email_attempt_outbox_result_valid,
    ADD CONSTRAINT cc_email_attempt_outbox_result_valid
        CHECK (result IS NULL OR result IN ('processed', 'processing_timeout', 'transfer')) NOT VALID,
    DROP CONSTRAINT IF EXISTS cc_email_attempt_outbox_transition_valid,
    ADD CONSTRAINT cc_email_attempt_outbox_transition_valid
        CHECK (transition IN ('created', 'assigned', 'taken', 'postponed', 'resumed', 'woken', 'queued', 'reopened',
                              'deadline_woken', 'deadline_queued', 'returned', 'auto_released', 'logged_out',
                              'processing_started', 'renewed', 'completed', 'processing_timeout',
                              'inbound_reopened', 'transferred', 'transfer_created')) NOT VALID,
    DROP CONSTRAINT IF EXISTS cc_email_attempt_outbox_actor_valid,
    ADD CONSTRAINT cc_email_attempt_outbox_actor_valid
        CHECK (actor_user_id IS NULL OR (source = 'engine' AND actor_user_id > 0)) NOT VALID,
    DROP CONSTRAINT IF EXISTS cc_email_attempt_outbox_comment_valid,
    ADD CONSTRAINT cc_email_attempt_outbox_comment_valid
        CHECK (comment IS NULL OR (char_length(comment) >= 1 AND char_length(comment) <= 500 AND source = 'engine'
                                   AND transition IN ('returned', 'transferred'))) NOT VALID,
    DROP CONSTRAINT IF EXISTS cc_email_attempt_outbox_transfer_valid,
    ADD CONSTRAINT cc_email_attempt_outbox_transfer_valid
        CHECK ((transition = 'transferred' AND num_nonnulls(transfer_to_queue_id, transfer_to_user_id) = 1)
            OR (transition <> 'transferred' AND transfer_to_queue_id IS NULL AND transfer_to_user_id IS NULL)) NOT VALID;

ALTER TABLE call_center.cc_email_attempt_outbox VALIDATE CONSTRAINT cc_email_attempt_outbox_result_valid;
ALTER TABLE call_center.cc_email_attempt_outbox VALIDATE CONSTRAINT cc_email_attempt_outbox_transition_valid;
ALTER TABLE call_center.cc_email_attempt_outbox VALIDATE CONSTRAINT cc_email_attempt_outbox_actor_valid;
ALTER TABLE call_center.cc_email_attempt_outbox VALIDATE CONSTRAINT cc_email_attempt_outbox_comment_valid;
ALTER TABLE call_center.cc_email_attempt_outbox VALIDATE CONSTRAINT cc_email_attempt_outbox_transfer_valid;

-- Skill and preset locks of an eligible agent, waited for or skipped.
CREATE OR REPLACE FUNCTION call_center.cc_email_agent_lock_eligible(_queue_id integer, _agent_id integer, _skip_locked boolean)
    RETURNS text
    LANGUAGE plpgsql
AS $$
DECLARE
    _status_id integer;
    _system    boolean;
BEGIN
    -- The caller holds the agent and its Email channel; the allocator calls it after the attempt.
    -- Domain, team and channels here, a qualifying skill in the locking query below.
    SELECT a.status_id INTO _status_id
    FROM call_center.cc_agent a
             JOIN call_center.cc_queue q ON q.id = _queue_id AND q.domain_id = a.domain_id
    WHERE a.id = _agent_id AND (q.team_id IS NULL OR a.team_id = q.team_id) AND 'email' = ANY (a.allow_channels);
    IF NOT FOUND THEN
        RETURN 'ineligible';
    END IF;

    IF _status_id IS NOT NULL THEN
        IF _skip_locked THEN
            SELECT os.is_system INTO _system FROM call_center.cc_online_skills os WHERE os.id = _status_id FOR SHARE SKIP LOCKED;
        ELSE
            SELECT os.is_system INTO _system FROM call_center.cc_online_skills os WHERE os.id = _status_id FOR SHARE;
        END IF;
        IF NOT FOUND THEN
            RETURN CASE WHEN _skip_locked AND EXISTS (SELECT 1 FROM call_center.cc_online_skills os WHERE os.id = _status_id)
                        THEN 'lock_skipped' ELSE 'ineligible' END;
        END IF;
    END IF;

    -- Without a preset or with the system one any qualifying skill counts, otherwise only a skill of the preset.
    IF _status_id IS NULL OR _system IS TRUE THEN
        IF _skip_locked THEN
            PERFORM 1
            FROM call_center.cc_queue_skill qs
                     JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
            WHERE qs.queue_id = _queue_id AND qs.enabled
              AND sia.agent_id = _agent_id AND sia.enabled
              AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
            LIMIT 1 FOR SHARE OF qs, sia SKIP LOCKED;
        ELSE
            PERFORM 1
            FROM call_center.cc_queue_skill qs
                     JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
            WHERE qs.queue_id = _queue_id AND qs.enabled
              AND sia.agent_id = _agent_id AND sia.enabled
              AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
            LIMIT 1 FOR SHARE OF qs, sia;
        END IF;
    ELSIF _skip_locked THEN
        PERFORM 1
        FROM call_center.cc_queue_skill qs
                 JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
                 JOIN call_center.cc_skills_in_online_skills sp ON sp.online_skill_id = _status_id AND sp.skill_id = sia.skill_id
        WHERE qs.queue_id = _queue_id AND qs.enabled
          AND sia.agent_id = _agent_id AND sia.enabled
          AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
        LIMIT 1 FOR SHARE OF qs, sia, sp SKIP LOCKED;
    ELSE
        PERFORM 1
        FROM call_center.cc_queue_skill qs
                 JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
                 JOIN call_center.cc_skills_in_online_skills sp ON sp.online_skill_id = _status_id AND sp.skill_id = sia.skill_id
        WHERE qs.queue_id = _queue_id AND qs.enabled
          AND sia.agent_id = _agent_id AND sia.enabled
          AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
        LIMIT 1 FOR SHARE OF qs, sia, sp;
    END IF;
    IF FOUND THEN
        RETURN 'eligible';
    END IF;

    -- Nothing was locked: a busy row in the skip-locked mode, otherwise no qualifying skill.
    IF _skip_locked AND EXISTS (
        SELECT 1
        FROM call_center.cc_queue_skill qs
                 JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
        WHERE qs.queue_id = _queue_id AND qs.enabled
          AND sia.agent_id = _agent_id AND sia.enabled
          AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
          AND (_status_id IS NULL OR _system IS TRUE OR EXISTS (
              SELECT 1 FROM call_center.cc_skills_in_online_skills sp
              WHERE sp.online_skill_id = _status_id AND sp.skill_id = sia.skill_id))
    ) THEN
        RETURN 'lock_skipped';
    END IF;
    RETURN 'ineligible';
END;
$$;

-- Snapshot, operator commands and the postponed wake-up get new parameters with defaults; the old
-- signatures are dropped in the same transaction, without CASCADE.
BEGIN;

DROP FUNCTION IF EXISTS call_center.cc_email_attempt_snapshot(call_center.cc_member_attempt, text, text, text, text, text);

CREATE OR REPLACE FUNCTION call_center.cc_email_attempt_snapshot(_a call_center.cc_member_attempt, _transition text, _source text,
                                                                 _command_id text DEFAULT NULL, _fingerprint text DEFAULT NULL,
                                                                 _causation_id text DEFAULT NULL, _actor_user_id bigint DEFAULT NULL,
                                                                 _comment text DEFAULT NULL, _transfer_to_queue_id integer DEFAULT NULL,
                                                                 _transfer_to_user_id bigint DEFAULT NULL)
    RETURNS bigint
    LANGUAGE plpgsql
AS $$
DECLARE
    _sequence bigint;
    _result   text := CASE WHEN _a.state = 'leaving' THEN _a.result END;
BEGIN
    INSERT INTO call_center.cc_email_attempt_outbox (domain_id, thread_id, attempt_id, attempt_version, attempt_state, result,
                                                     queue_id, agent_id, agent_user_id, postponed_until, transition, source,
                                                     command_id, fingerprint, response, causation_id, actor_user_id, comment,
                                                     transfer_to_queue_id, transfer_to_user_id)
    VALUES (_a.domain_id, _a.member_call_id::bigint, _a.id, _a.version, _a.state, _result, _a.queue_id, _a.agent_id,
            (SELECT ag.user_id FROM call_center.cc_agent ag WHERE ag.id = _a.agent_id),
            _a.postponed_until, _transition, _source, _command_id, _fingerprint,
            CASE WHEN _command_id IS NOT NULL THEN jsonb_build_object('attempt_id', _a.id, 'state', _a.state,
                'attempt_version', _a.version, 'result', _result, 'agent_id', _a.agent_id, 'postponed_until', _a.postponed_until) END,
            _causation_id, _actor_user_id, _comment, _transfer_to_queue_id, _transfer_to_user_id)
    RETURNING sequence INTO _sequence;

    RETURN _sequence;
END;
$$;

DROP FUNCTION IF EXISTS call_center.cc_email_attempt_command(text, text, text, bigint, bigint, bigint, integer, bigint, uuid,
                                                             timestamp with time zone, integer, integer);

CREATE OR REPLACE FUNCTION call_center.cc_email_attempt_command(_op text, _source text, _command_id text, _domain_id bigint,
                                                                _thread_id bigint, _attempt_id bigint, _agent_id integer,
                                                                _expected_version bigint, _email_event_id uuid,
                                                                _postponed_until timestamp with time zone,
                                                                _postpone_for_sec integer, _renewal_sec integer,
                                                                _user_id bigint DEFAULT NULL, _reason text DEFAULT NULL)
    RETURNS TABLE (replayed boolean, attempt_id bigint, thread_id bigint, attempt_state text, attempt_version bigint,
                   projection_version bigint, result text, queue_id integer, agent_id integer,
                   postponed_until timestamp with time zone)
    LANGUAGE plpgsql
AS $$
DECLARE
    _fingerprint text;
    _id          bigint;
    _owner       integer;
    _a           call_center.cc_member_attempt;
    _q           call_center.cc_queue;
    _deadline    timestamp with time zone;
    _horizon     integer;
    _limit       integer;
    _used        integer;
    _online      boolean;
    _slot        text;
    _w_id        bigint;
    _w_state     text;
    _w_version   bigint;
    _w_response  jsonb;
    _transition  text;
    _sequence    bigint;
    _queue_id    integer;
    _eligible    text;
BEGIN
    _reason := nullif(btrim(_reason), '');
    IF _op NOT IN ('take', 'postpone', 'resume', 'return', 'complete', 'renew') OR _source NOT IN ('engine', 'flow')
        OR coalesce(char_length(_command_id), 0) NOT BETWEEN 1 AND 128
        OR coalesce(_domain_id, 0) <= 0 OR coalesce(_thread_id, 0) <= 0
        OR (_source = 'engine' AND (coalesce(_attempt_id, 0) <= 0 OR coalesce(_agent_id, 0) <= 0
                                    OR coalesce(_expected_version, -1) < 0 OR _email_event_id IS NOT NULL))
        OR (_source = 'flow' AND (_op NOT IN ('postpone', 'resume') OR _email_event_id IS NULL
                                  OR _attempt_id IS NOT NULL OR _agent_id IS NOT NULL OR _expected_version IS NOT NULL))
        OR (_op = 'postpone' AND (_postponed_until IS NULL) = (_postpone_for_sec IS NULL))
        OR (_op = 'postpone' AND coalesce(_postpone_for_sec, 1) <= 0)
        OR (_op <> 'postpone' AND (_postponed_until IS NOT NULL OR _postpone_for_sec IS NOT NULL))
        OR (_op = 'renew') <> (coalesce(_renewal_sec, 0) > 0)
        -- The operator form carries the session user; a manual return needs its reason.
        OR (_source = 'engine') <> (coalesce(_user_id, 0) > 0) OR (_source = 'flow' AND _user_id IS NOT NULL)
        OR (_op = 'return' AND _source = 'engine') <> (_reason IS NOT NULL)
        OR coalesce(char_length(_reason), 0) > 500 THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAAR', MESSAGE = 'email attempt: invalid command arguments';
    END IF;

    -- A relative deadline keeps its duration in the fingerprint, so a retry matches the first call.
    -- The author and the reason count for the operator form only, so Flow fingerprints keep their value.
    _fingerprint := call_center.cc_email_command_fingerprint(VARIADIC ARRAY[_op, _source, _domain_id::text, _thread_id::text,
        _attempt_id::text, _agent_id::text, _expected_version::text, _email_event_id::text,
        to_char(_postponed_until AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'), _postpone_for_sec::text, _renewal_sec::text]
        || CASE WHEN _source = 'engine' THEN ARRAY[_user_id::text, _reason] ELSE ARRAY[]::text[] END);

    RETURN QUERY SELECT * FROM call_center.cc_email_command_replay(_domain_id, _source, _command_id, _fingerprint);
    IF FOUND THEN
        RETURN;
    END IF;

    -- Serializes the same command only; class 'EMAC', apart from the allocator lock 'EMAI'.
    PERFORM pg_advisory_xact_lock(1162690883, hashtext(_domain_id::text || ':' || _source || ':' || _command_id));
    RETURN QUERY SELECT * FROM call_center.cc_email_command_replay(_domain_id, _source, _command_id, _fingerprint);
    IF FOUND THEN
        RETURN;
    END IF;

    IF _source = 'flow' THEN
        PERFORM 1
        FROM call_center.cc_email_wakeup w
        WHERE w.event_id = _email_event_id AND w.domain_id = _domain_id AND w.thread_id = _thread_id AND w.state = 'applied';
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAWK', MESSAGE = format('email attempt: event %s did not wake thread %s', _email_event_id, _thread_id);
        END IF;
        -- A repeated Flow resume that was a no-op returns its first response, whatever happened since.
        IF _op = 'resume' THEN
            SELECT w.resume_response INTO _w_response FROM call_center.cc_email_wakeup w WHERE w.event_id = _email_event_id;
            IF _w_response IS NOT NULL THEN
                RETURN QUERY SELECT true, (_w_response ->> 'attempt_id')::bigint, (_w_response ->> 'thread_id')::bigint,
                                    _w_response ->> 'state', (_w_response ->> 'attempt_version')::bigint, 0::bigint, NULL::text,
                                    (_w_response ->> 'queue_id')::integer, (_w_response ->> 'agent_id')::integer,
                                    NULL::timestamp with time zone;
                RETURN;
            END IF;
        END IF;
    END IF;

    -- The candidate is read without a lock; it is locked in the agreed order and checked again.
    SELECT a.id, a.agent_id, a.queue_id INTO _id, _owner, _queue_id
    FROM call_center.cc_member_attempt a
    WHERE a.domain_id = _domain_id
      AND a.channel = 'email'
      AND a.leaving_at IS NULL
      AND CASE WHEN _source = 'flow' THEN a.member_call_id = _thread_id::text ELSE a.id = _attempt_id END;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'EMANF', MESSAGE = 'email attempt: active attempt not found';
    END IF;

    -- The operator acts on its own attempt as the user its agent is linked to now.
    IF _source = 'engine' THEN
        IF _owner IS DISTINCT FROM _agent_id THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAOW', MESSAGE = format('email attempt: attempt %s is not assigned to agent %s', _id, _agent_id);
        END IF;
        PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _agent_id AND ag.user_id = _user_id FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAOW', MESSAGE = format('email attempt: agent %s is not linked to user %s', _agent_id, _user_id);
        END IF;
    END IF;

    -- Metric and slot transitions: agent, Email channel, skills and preset of a resume, attempt.
    IF _op IN ('take', 'postpone', 'resume', 'return', 'complete') AND _owner IS NOT NULL THEN
        PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _owner FOR SHARE;
        PERFORM 1 FROM call_center.cc_agent_channel ch WHERE ch.agent_id = _owner AND ch.channel = 'email' FOR UPDATE;
        IF _op = 'resume' THEN
            _eligible := call_center.cc_email_agent_lock_eligible(_queue_id, _owner, false);
        END IF;
    END IF;

    SELECT * INTO _a FROM call_center.cc_member_attempt a WHERE a.id = _id FOR UPDATE;
    IF NOT FOUND OR _a.leaving_at IS NOT NULL OR _a.state = 'leaving' THEN
        RAISE EXCEPTION USING ERRCODE = 'EMANF', MESSAGE = 'email attempt: active attempt not found';
    END IF;
    IF _a.member_call_id <> _thread_id::text THEN
        RAISE EXCEPTION USING ERRCODE = 'EMANF', MESSAGE = 'email attempt: attempt belongs to another thread';
    END IF;
    IF _source = 'engine' AND _a.agent_id IS DISTINCT FROM _agent_id THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAOW', MESSAGE = format('email attempt: attempt %s is not assigned to agent %s', _a.id, _agent_id);
    END IF;
    IF _source = 'engine' AND _a.version <> _expected_version THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAVR', MESSAGE = format('email attempt: version %s, expected %s', _a.version, _expected_version);
    END IF;
    -- Returned to the queue meanwhile: the state check answers. Another agent was not locked: retry.
    IF _op IN ('take', 'postpone', 'resume', 'return', 'complete') AND _a.agent_id IS NOT NULL AND _a.agent_id IS DISTINCT FROM _owner THEN
        RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'email attempt: agent changed while locking';
    END IF;

    SELECT * INTO _q FROM call_center.cc_queue q WHERE q.id = _a.queue_id;

    IF _op = 'take' THEN
        IF _a.state <> 'offering' THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAST', MESSAGE = format('email attempt: cannot take in state %s', _a.state);
        END IF;
        UPDATE call_center.cc_member_attempt a
        SET state = 'active', timeout = NULL, bridged_at = now(), last_state_change = now(), version = a.version + 1
        WHERE a.id = _a.id
        RETURNING * INTO _a;
        _transition := 'taken';

    ELSIF _op = 'postpone' THEN
        IF _a.state <> 'active' THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAST', MESSAGE = format('email attempt: cannot postpone in state %s', _a.state);
        END IF;
        _horizon := coalesce(call_center.cc_email_payload_sec(_q.payload, 'email_postpone_max_sec'), 2592000);
        _deadline := coalesce(_postponed_until, now() + make_interval(secs => _postpone_for_sec));
        IF _deadline <= now() OR _deadline > now() + make_interval(secs => _horizon) THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAAR', MESSAGE = format('email attempt: postpone deadline must be within %s seconds', _horizon);
        END IF;
        SELECT ag.email_postponed_count INTO _limit FROM call_center.cc_agent ag WHERE ag.id = _a.agent_id;
        SELECT count(*) INTO _used
        FROM call_center.cc_member_attempt p
        WHERE p.agent_id = _a.agent_id AND p.channel = 'email' AND p.leaving_at IS NULL AND p.state = 'postponed';
        -- NULL: no limit; 0 disables postponing.
        IF _limit IS NOT NULL AND _used >= _limit THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAPL', MESSAGE = format('email attempt: agent %s has %s of %s postponed', _a.agent_id, _used, _limit);
        END IF;
        UPDATE call_center.cc_member_attempt a
        SET state = 'postponed', email_slot_type = NULL, postponed_until = _deadline, timeout = NULL, last_state_change = now(), version = a.version + 1
        WHERE a.id = _a.id
        RETURNING * INTO _a;
        _transition := 'postponed';

    ELSIF _op = 'resume' THEN
        -- The wake-up of its event left the email active and no Flow postpone of the event followed: nothing to
        -- resume. Unchanged since, a no-op kept for repeats (projection_version 0); changed, too late to apply.
        IF _source = 'flow' THEN
            SELECT w.attempt_id, w.attempt_state, w.attempt_version INTO _w_id, _w_state, _w_version
            FROM call_center.cc_email_wakeup w
            WHERE w.event_id = _email_event_id;
            IF _w_state = 'active' AND NOT EXISTS (
                SELECT 1 FROM call_center.cc_email_attempt_outbox o
                WHERE o.domain_id = _domain_id AND o.source = 'flow' AND o.command_id = _email_event_id::text || ':postpone') THEN
                IF _a.id IS DISTINCT FROM _w_id OR _a.version <> _w_version THEN
                    RAISE EXCEPTION USING ERRCODE = 'EMAST', MESSAGE = format('email attempt: attempt %s changed after the wake-up of event %s', _a.id, _email_event_id);
                END IF;
                UPDATE call_center.cc_email_wakeup w
                SET resume_response = jsonb_build_object('attempt_id', _a.id, 'thread_id', _a.member_call_id::bigint,
                    'state', _a.state, 'attempt_version', _a.version, 'queue_id', _a.queue_id, 'agent_id', _a.agent_id)
                WHERE w.event_id = _email_event_id;
                RETURN QUERY SELECT false, _a.id, _a.member_call_id::bigint, _a.state::text, _a.version, 0::bigint,
                                    NULL::text, _a.queue_id, _a.agent_id, _a.postponed_until;
                RETURN;
            END IF;
        END IF;
        IF _a.state <> 'postponed' THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAST', MESSAGE = format('email attempt: cannot resume in state %s', _a.state);
        END IF;
        SELECT ag.status = 'online' AND coalesce(ch.online, false) INTO _online
        FROM call_center.cc_agent ag
                 LEFT JOIN call_center.cc_agent_channel ch ON ch.agent_id = ag.id AND ch.channel = 'email'
        WHERE ag.id = _a.agent_id;
        IF NOT coalesce(_online, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAOF', MESSAGE = format('email attempt: agent %s or its Email channel is not online', _a.agent_id);
        END IF;
        IF _eligible IS DISTINCT FROM 'eligible' THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAEL', MESSAGE = format('email attempt: agent %s can no longer take emails of queue %s', _a.agent_id, _a.queue_id);
        END IF;
        -- Under the channel lock, as the allocator: eligibility with the online preset, base first, Extra if allowed.
        SELECT c.slot_type INTO _slot
        FROM call_center.cc_email_queue_candidates(_a.queue_id, _a.agent_id, _a.email_extra_allowed) c;
        IF _slot IS NULL THEN
            SELECT c.slot_type, c.used_slots, c.base_limit + CASE WHEN _a.email_extra_allowed THEN c.extra_limit ELSE 0 END
            INTO _slot, _used, _limit
            FROM call_center.cc_email_agent_capacity(_a.agent_id, _a.email_extra_allowed) c;
            IF _slot IS NULL THEN
                RAISE EXCEPTION USING ERRCODE = 'EMASL', MESSAGE = format('email attempt: agent %s has %s of %s emails', _a.agent_id, _used, _limit);
            END IF;
            RAISE EXCEPTION USING ERRCODE = 'EMAEL', MESSAGE = format('email attempt: agent %s can no longer take emails of queue %s', _a.agent_id, _a.queue_id);
        END IF;
        UPDATE call_center.cc_member_attempt a
        SET state = 'active', email_slot_type = _slot, postponed_until = NULL, last_state_change = now(), version = a.version + 1
        WHERE a.id = _a.id
        RETURNING * INTO _a;
        _transition := 'resumed';

    ELSIF _op = 'return' THEN
        IF _a.state NOT IN ('offering', 'active', 'postponed') THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAST', MESSAGE = format('email attempt: cannot return in state %s', _a.state);
        END IF;
        -- High in the general order with the original joined_at; the sticky decision is already made.
        UPDATE call_center.cc_member_attempt a
        SET state = 'waiting', agent_id = NULL, email_slot_type = NULL, timeout = NULL, postponed_until = NULL, weight = greatest(a.weight, call_center.cc_email_high_priority()),
            sticky_agent_id = NULL, sticky_until = now(), last_state_change = now(), version = a.version + 1
        WHERE a.id = _a.id
        RETURNING * INTO _a;
        _transition := 'returned';

    ELSIF _op = 'complete' THEN
        IF _a.state = 'active' AND _q.processing THEN
            UPDATE call_center.cc_member_attempt a
            SET state = 'processing', last_state_change = now(), version = a.version + 1,
                timeout = CASE WHEN _q.processing_sec > 0 THEN now() + make_interval(secs => _q.processing_sec) END
            WHERE a.id = _a.id
            RETURNING * INTO _a;
            _transition := 'processing_started';
        ELSIF _a.state IN ('active', 'processing') THEN
            -- SaveToHistory moves the attempt; the Email channel of the agent is not changed.
            UPDATE call_center.cc_member_attempt a
            SET state = 'leaving', result = 'processed', leaving_at = now(), reporting_at = now(), timeout = NULL,
                last_state_change = now(), version = a.version + 1
            WHERE a.id = _a.id
            RETURNING * INTO _a;
            _transition := 'completed';
        ELSE
            RAISE EXCEPTION USING ERRCODE = 'EMAST', MESSAGE = format('email attempt: cannot complete in state %s', _a.state);
        END IF;

    ELSE
        IF _a.state <> 'processing' THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAST', MESSAGE = format('email attempt: cannot renew in state %s', _a.state);
        END IF;
        -- As RenewalProcessing: with prolongation enabled, at most its number of renewals.
        IF coalesce(_q.prolongation_enabled, false)
            AND _a.available_prolongation_quant + 1 > coalesce(_q.prolongation_repeats_number, 0) THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAPX', MESSAGE = 'email attempt: no prolongations left';
        END IF;
        UPDATE call_center.cc_member_attempt a
        SET timeout = coalesce(a.timeout, now()) + make_interval(secs => _renewal_sec),
            available_prolongation_quant = CASE WHEN coalesce(_q.prolongation_enabled, false)
                                                THEN a.available_prolongation_quant + 1 ELSE a.available_prolongation_quant END,
            version = a.version + 1
        WHERE a.id = _a.id
        RETURNING * INTO _a;
        _transition := 'renewed';
    END IF;

    IF _owner IS NOT NULL AND _op IN ('take', 'postpone', 'resume', 'return', 'complete') THEN
        PERFORM call_center.cc_email_agent_strategy_refresh(_owner,
            CASE WHEN _op = 'take' THEN _a.bridged_at END);
    END IF;

    _sequence := call_center.cc_email_attempt_snapshot(_a, _transition, _source, _command_id, _fingerprint, _email_event_id::text,
        CASE WHEN _source = 'engine' THEN _user_id END, CASE WHEN _op = 'return' THEN _reason END);

    RETURN QUERY SELECT false, _a.id, _a.member_call_id::bigint, _a.state::text, _a.version, _sequence,
                        CASE WHEN _a.state = 'leaving' THEN _a.result::text END, _a.queue_id, _a.agent_id, _a.postponed_until;
END;
$$;

DROP FUNCTION IF EXISTS call_center.cc_email_wake_postponed(call_center.cc_member_attempt, text, text, text);

-- Wake a postponed attempt only for an owner found eligible under the locks.
CREATE OR REPLACE FUNCTION call_center.cc_email_wake_postponed(_a call_center.cc_member_attempt, _woken text, _queued text,
                                                               _causation_id text, _eligible boolean DEFAULT true)
    RETURNS call_center.cc_member_attempt
    LANGUAGE plpgsql
AS $$
DECLARE
    _owner  integer := _a.agent_id;
    _online boolean;
    _slot   text;
    _q      call_center.cc_queue;
    _wait   integer;
    _ignore boolean;
    _sticky boolean;
BEGIN
    -- Only an owner found eligible under the skill and preset locks may take a slot again.
    IF _eligible THEN
        SELECT c.slot_type INTO _slot
        FROM call_center.cc_email_queue_candidates(_a.queue_id, _a.agent_id, _a.email_extra_allowed) c;
    END IF;

    IF _slot IS NOT NULL THEN
        UPDATE call_center.cc_member_attempt a
        SET state = 'active', email_slot_type = _slot, postponed_until = NULL, last_state_change = now(), version = a.version + 1
        WHERE a.id = _a.id
        RETURNING * INTO _a;
        PERFORM call_center.cc_email_agent_strategy_refresh(_owner);
        PERFORM call_center.cc_email_attempt_snapshot(_a, _woken, 'system', NULL, NULL, _causation_id);
        RETURN _a;
    END IF;

    SELECT * INTO _q FROM call_center.cc_queue q WHERE q.id = _a.queue_id;
    _wait := call_center.cc_email_sticky_wait_sec(_q.payload);
    _ignore := CASE WHEN jsonb_typeof(_q.payload -> 'sticky_ignore_status') = 'boolean'
                    THEN (_q.payload ->> 'sticky_ignore_status')::boolean ELSE false END;
    SELECT ag.status = 'online' AND coalesce(ch.online, false) INTO _online
    FROM call_center.cc_agent ag
             LEFT JOIN call_center.cc_agent_channel ch ON ch.agent_id = ag.id AND ch.channel = 'email'
    WHERE ag.id = _a.agent_id;
    -- As cc_email_sticky_prepare: a candidate only if eligible, with a slot type for this email and online or
    -- ignored as offline; its timer starts there, in an open calendar.
    _sticky := coalesce(_q.sticky_agent, false) AND _wait > 0
        AND call_center.cc_email_agent_assignable(_a.queue_id, _a.agent_id)
        AND coalesce((SELECT c.has_slot_type FROM call_center.cc_email_agent_capacity(_a.agent_id, _a.email_extra_allowed) c), false)
        AND (coalesce(_online, false) OR _ignore);
    UPDATE call_center.cc_member_attempt a
    SET state = 'waiting', agent_id = NULL, email_slot_type = NULL, timeout = NULL, postponed_until = NULL,
        weight = greatest(a.weight, call_center.cc_email_high_priority()),
        sticky_agent_id = CASE WHEN _sticky THEN _a.agent_id END,
        sticky_until = CASE WHEN _sticky THEN NULL ELSE now() END,
        last_state_change = now(), version = a.version + 1
    WHERE a.id = _a.id
    RETURNING * INTO _a;
    PERFORM call_center.cc_email_agent_strategy_refresh(_owner);
    PERFORM call_center.cc_email_attempt_snapshot(_a, _queued, 'system', NULL, NULL, _causation_id);
    RETURN _a;
END;
$$;

-- The allocator uses the shared skill and preset check, keeping its lock order and SKIP LOCKED.
CREATE OR REPLACE FUNCTION call_center.cc_email_try_assign(_attempt_id bigint, _queue_id integer, _agent_id integer,
    _failed_attempt_ids bigint[] DEFAULT '{}'::bigint[], _failed_agent_ids integer[] DEFAULT '{}'::integer[])
    RETURNS boolean
    LANGUAGE plpgsql
AS $$
DECLARE
    _q         call_center.cc_queue;
    _att       call_center.cc_member_attempt;
    _team_id   integer;
    _status_id integer;
    _slot      text;
    _wait      integer;
    _release   integer;
BEGIN
    IF NOT call_center.cc_email_failed_pairs_valid(_failed_attempt_ids, _failed_agent_ids) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email assign: invalid failed-pair arrays';
    END IF;
    SELECT q.* INTO _q FROM call_center.cc_queue q
    WHERE q.id = _queue_id AND q.type = 11 AND q.enabled FOR SHARE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    PERFORM 1 FROM flow.calendar c WHERE c.id = _q.calendar_id FOR SHARE SKIP LOCKED;
    IF NOT FOUND OR call_center.cc_email_queue_calendar(_q.domain_id, _q.calendar_id) <> 'open' THEN
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

    -- Keep a qualifying skill pair and online preset stable until commit, skipping locked rows.
    IF call_center.cc_email_agent_lock_eligible(_q.id, _agent_id, true) <> 'eligible' THEN
        RETURN false;
    END IF;

    SELECT c.team_id, c.slot_type INTO _team_id, _slot
    FROM call_center.cc_email_queue_candidates(_q.id, _agent_id, _att.email_extra_allowed) c;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    IF NOT call_center.cc_email_pair_available(_att, _agent_id, _att.sticky_agent_id,
        _failed_attempt_ids, _failed_agent_ids) THEN
        RETURN false;
    END IF;

    -- Read now, so a later change of the Queue applies to new offers only; 0, unset or invalid keeps the offer.
    _release := coalesce(call_center.cc_email_payload_sec(_q.payload, 'email_auto_release_sec'), 0);

    UPDATE call_center.cc_member_attempt a
    SET state = 'offering', agent_id = _agent_id, team_id = _team_id, email_slot_type = _slot,
        offering_at = now(), last_state_change = now(),
        offered_agent_ids = CASE WHEN _agent_id = ANY (a.offered_agent_ids) THEN a.offered_agent_ids
                                ELSE array_append(a.offered_agent_ids, _agent_id) END,
        timeout = CASE WHEN _release > 0 THEN now() + make_interval(secs => _release) END,
        last_released_agent_id = NULL,
        version = a.version + 1
    WHERE a.id = _att.id AND a.queue_id = _q.id AND a.domain_id = _q.domain_id
      AND a.channel = 'email' AND a.queue_type = 11 AND a.state = 'waiting'
      AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.email_slot_type IS NULL
      AND (a.sticky_agent_id IS NULL OR
           (a.sticky_agent_id = _agent_id AND a.sticky_until IS NOT NULL
            AND ((_wait = 0 AND a.sticky_until >= transaction_timestamp())
                 OR (_wait > 0 AND a.sticky_until > clock_timestamp()))))
    RETURNING * INTO _att;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    PERFORM call_center.cc_email_attempt_snapshot(_att, 'assigned', 'system');

    UPDATE call_center.cc_agent_channel SET last_offering_at = now()
    WHERE agent_id = _agent_id AND channel = 'email';
    RETURN true;
END;
$$;

COMMIT;

-- Wake-up: skills and preset of a postponed owner are locked before the attempt.
CREATE OR REPLACE FUNCTION call_center.cc_email_wakeup_thread(_event_id uuid, _domain_id bigint, _thread_id bigint)
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
    _queue_id integer;
    _eligible boolean := true;
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

    SELECT a.id, a.agent_id, a.state, a.queue_id INTO _id, _owner, _state, _queue_id
    FROM call_center.cc_member_attempt a
    WHERE a.domain_id = _domain_id AND a.member_call_id = _thread_id::text AND a.channel = 'email' AND a.leaving_at IS NULL;

    IF FOUND THEN
        -- Wake-up metrics and slots: agent, Email channel, skills and preset of a postponed owner, attempt.
        IF _state IN ('postponed', 'processing') AND _owner IS NOT NULL THEN
            PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _owner FOR SHARE;
            PERFORM 1 FROM call_center.cc_agent_channel ch WHERE ch.agent_id = _owner AND ch.channel = 'email' FOR UPDATE;
            IF _state = 'postponed' THEN
                _eligible := call_center.cc_email_agent_lock_eligible(_queue_id, _owner, false) = 'eligible';
            END IF;
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
        _a := call_center.cc_email_wake_postponed(_a, 'woken', 'queued', _event_id::text, _eligible);
        _result := CASE WHEN _a.state = 'active' THEN 'woken' ELSE 'queued' END;
    ELSIF _a.state = 'processing' THEN
        IF _a.agent_id IS DISTINCT FROM _owner OR _state <> 'processing' THEN
            RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'email wake-up: attempt changed while locking';
        END IF;
        UPDATE call_center.cc_member_attempt a
        SET state = 'active', timeout = NULL, last_state_change = now(), version = a.version + 1
        WHERE a.id = _a.id
        RETURNING * INTO _a;
        PERFORM call_center.cc_email_agent_strategy_refresh(_owner);
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

-- Postponed deadline: a busy skill or preset row leaves the attempt to the next cycle.
CREATE OR REPLACE FUNCTION call_center.cc_email_lifecycle_watch(_batch integer, _max_duration interval)
    RETURNS TABLE (released integer, processing_timeouts integer, postponed_woken integer, postponed_queued integer,
                   offline_returned integer, lock_skipped integer, time_limited boolean)
    LANGUAGE plpgsql
AS $$
DECLARE
    _deadline timestamp with time zone := clock_timestamp() + _max_duration;
    _r        record;
    _a        call_center.cc_member_attempt;
    _status   text;
    _eligible text;
BEGIN
    IF coalesce(_batch, 0) <= 0 OR _max_duration IS NULL OR _max_duration <= interval '0' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email lifecycle: batch and max duration must be positive';
    END IF;
    released := 0;
    processing_timeouts := 0;
    postponed_woken := 0;
    postponed_queued := 0;
    offline_returned := 0;
    lock_skipped := 0;
    time_limited := false;

    -- Slot releases use agent, Email channel, attempt locks without waiting.
    FOR _r IN
        SELECT a.id, a.agent_id, a.state, a.timeout, a.version
        FROM call_center.cc_member_attempt a
        WHERE a.channel = 'email'
          AND a.state IN ('offering', 'processing')
          AND a.timeout IS NOT NULL
          AND a.leaving_at IS NULL
          AND a.timeout <= now()
        ORDER BY a.timeout, a.id
        LIMIT _batch
    LOOP
        IF clock_timestamp() >= _deadline THEN
            time_limited := true;
            RETURN NEXT;
            RETURN;
        END IF;

        IF _r.agent_id IS NOT NULL THEN
            PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _r.agent_id FOR SHARE SKIP LOCKED;
            IF NOT FOUND THEN
                lock_skipped := lock_skipped + 1;
                CONTINUE;
            END IF;
            PERFORM 1 FROM call_center.cc_agent_channel ch
            WHERE ch.agent_id = _r.agent_id AND ch.channel = 'email' FOR UPDATE SKIP LOCKED;
            IF NOT FOUND AND EXISTS (SELECT 1 FROM call_center.cc_agent_channel ch
                WHERE ch.agent_id = _r.agent_id AND ch.channel = 'email') THEN
                lock_skipped := lock_skipped + 1;
                CONTINUE;
            END IF;
        END IF;
        SELECT * INTO _a FROM call_center.cc_member_attempt a WHERE a.id = _r.id FOR UPDATE SKIP LOCKED;
        IF NOT FOUND THEN
            lock_skipped := lock_skipped + (SELECT count(*) FROM call_center.cc_member_attempt a WHERE a.id = _r.id)::integer;
            CONTINUE;
        END IF;
        -- Changed since it was read: a command or wake-up came first.
        CONTINUE WHEN _a.leaving_at IS NOT NULL OR _a.state <> _r.state OR _a.timeout IS DISTINCT FROM _r.timeout
            OR _a.version <> _r.version OR _a.agent_id IS DISTINCT FROM _r.agent_id;

        IF _a.state = 'offering' THEN
            UPDATE call_center.cc_member_attempt a
            SET state = 'waiting', agent_id = NULL, email_slot_type = NULL, timeout = NULL, weight = greatest(a.weight, call_center.cc_email_high_priority()), sticky_agent_id = NULL,
                sticky_until = now(), last_released_agent_id = _a.agent_id, last_state_change = now(),
                version = a.version + 1
            WHERE a.id = _a.id
            RETURNING * INTO _a;
            PERFORM call_center.cc_email_agent_strategy_refresh(_r.agent_id);
            PERFORM call_center.cc_email_attempt_snapshot(_a, 'auto_released', 'system');
            released := released + 1;
        ELSE
            UPDATE call_center.cc_member_attempt a
            SET state = 'leaving', result = 'processing_timeout', leaving_at = now(), reporting_at = now(), timeout = NULL,
                last_state_change = now(), version = a.version + 1
            WHERE a.id = _a.id
            RETURNING * INTO _a;
            PERFORM call_center.cc_email_agent_strategy_refresh(_r.agent_id);
            PERFORM call_center.cc_email_attempt_snapshot(_a, 'processing_timeout', 'system');
            processing_timeouts := processing_timeouts + 1;
        END IF;
    END LOOP;

    -- A postponed deadline may take a slot: agent, Email channel, skills and preset, attempt, none waited for.
    FOR _r IN
        SELECT a.id, a.agent_id, a.postponed_until, a.version, a.queue_id
        FROM call_center.cc_member_attempt a
        WHERE a.channel = 'email'
          AND a.state = 'postponed'
          AND a.leaving_at IS NULL
          AND a.postponed_until <= now()
        ORDER BY a.postponed_until, a.id
        LIMIT _batch
    LOOP
        IF clock_timestamp() >= _deadline THEN
            time_limited := true;
            RETURN NEXT;
            RETURN;
        END IF;

        PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _r.agent_id FOR SHARE SKIP LOCKED;
        IF NOT FOUND THEN
            lock_skipped := lock_skipped + 1;
            CONTINUE;
        END IF;
        PERFORM 1 FROM call_center.cc_agent_channel ch WHERE ch.agent_id = _r.agent_id AND ch.channel = 'email' FOR UPDATE SKIP LOCKED;
        IF NOT FOUND AND EXISTS (SELECT 1 FROM call_center.cc_agent_channel ch WHERE ch.agent_id = _r.agent_id AND ch.channel = 'email') THEN
            lock_skipped := lock_skipped + 1;
            CONTINUE;
        END IF;
        -- Skills and preset before the attempt; a busy row leaves the attempt to the next cycle.
        _eligible := call_center.cc_email_agent_lock_eligible(_r.queue_id, _r.agent_id, true);
        IF _eligible = 'lock_skipped' THEN
            lock_skipped := lock_skipped + 1;
            CONTINUE;
        END IF;
        SELECT * INTO _a FROM call_center.cc_member_attempt a WHERE a.id = _r.id FOR UPDATE SKIP LOCKED;
        IF NOT FOUND THEN
            lock_skipped := lock_skipped + (SELECT count(*) FROM call_center.cc_member_attempt a WHERE a.id = _r.id)::integer;
            CONTINUE;
        END IF;
        -- The exact deadline under the locks keeps a deadline from waking the attempt twice.
        CONTINUE WHEN _a.leaving_at IS NOT NULL OR _a.state <> 'postponed' OR _a.postponed_until IS DISTINCT FROM _r.postponed_until
            OR _a.agent_id IS DISTINCT FROM _r.agent_id OR _a.version <> _r.version;

        _a := call_center.cc_email_wake_postponed(_a, 'deadline_woken', 'deadline_queued', NULL, _eligible = 'eligible');
        IF _a.state = 'active' THEN
            postponed_woken := postponed_woken + 1;
        ELSE
            postponed_queued := postponed_queued + 1;
        END IF;
    END LOOP;

    -- Repair sweep: Emails still held by an agent that is actually offline, e.g. set offline by another path.
    FOR _r IN
        SELECT a.id, a.agent_id, a.state, a.version
        FROM call_center.cc_member_attempt a
                 JOIN call_center.cc_agent ag ON ag.id = a.agent_id
        WHERE a.channel = 'email'
          AND a.agent_id IS NOT NULL
          AND a.leaving_at IS NULL
          AND a.state IN ('offering', 'active', 'postponed')
          AND ag.status = 'offline'
        ORDER BY a.id
        LIMIT _batch
    LOOP
        IF clock_timestamp() >= _deadline THEN
            time_limited := true;
            RETURN NEXT;
            RETURN;
        END IF;

        SELECT ag.status INTO _status FROM call_center.cc_agent ag WHERE ag.id = _r.agent_id FOR SHARE SKIP LOCKED;
        IF NOT FOUND THEN
            lock_skipped := lock_skipped + 1;
            CONTINUE;
        END IF;
        CONTINUE WHEN _status <> 'offline';
        PERFORM 1 FROM call_center.cc_agent_channel ch
        WHERE ch.agent_id = _r.agent_id AND ch.channel = 'email' FOR UPDATE SKIP LOCKED;
        IF NOT FOUND AND EXISTS (SELECT 1 FROM call_center.cc_agent_channel ch
            WHERE ch.agent_id = _r.agent_id AND ch.channel = 'email') THEN
            lock_skipped := lock_skipped + 1;
            CONTINUE;
        END IF;
        SELECT * INTO _a FROM call_center.cc_member_attempt a WHERE a.id = _r.id FOR UPDATE SKIP LOCKED;
        IF NOT FOUND THEN
            lock_skipped := lock_skipped + (SELECT count(*) FROM call_center.cc_member_attempt a WHERE a.id = _r.id)::integer;
            CONTINUE;
        END IF;
        CONTINUE WHEN _a.leaving_at IS NOT NULL OR _a.state <> _r.state OR _a.agent_id IS DISTINCT FROM _r.agent_id
            OR _a.version <> _r.version;

        PERFORM call_center.cc_email_return_to_queue(_a, 'logged_out');
        offline_returned := offline_returned + 1;
    END LOOP;

    RETURN NEXT;
END;
$$;

-- Repeat of a Transfer with both attempts of its first result.
CREATE OR REPLACE FUNCTION call_center.cc_email_transfer_replay(_domain_id bigint, _command_id text, _fingerprint text)
    RETURNS TABLE (part text, replayed boolean, attempt_id bigint, thread_id bigint, attempt_state text, attempt_version bigint,
                   projection_version bigint, result text, queue_id integer, agent_id integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _o call_center.cc_email_attempt_outbox;
BEGIN
    SELECT * INTO _o
    FROM call_center.cc_email_attempt_outbox o
    WHERE o.domain_id = _domain_id AND o.source = 'engine' AND o.command_id = _command_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    IF _o.fingerprint <> _fingerprint THEN
        RAISE EXCEPTION USING ERRCODE = 'EMACF', MESSAGE = format('email attempt: command %s was used with other arguments', _command_id);
    END IF;

    -- Both attempts as the first execution returned them.
    RETURN QUERY
    SELECT p.key, true, (p.value ->> 'attempt_id')::bigint, (p.value ->> 'thread_id')::bigint, p.value ->> 'state',
           (p.value ->> 'attempt_version')::bigint, (p.value ->> 'projection_version')::bigint, p.value ->> 'result',
           (p.value ->> 'queue_id')::integer, (p.value ->> 'agent_id')::integer
    FROM jsonb_each(_o.response) p
    WHERE p.key IN ('email', 'transferred_to')
    ORDER BY p.key;
END;
$$;

-- Email Transfer to a queue or to an agent of the queue.
CREATE OR REPLACE FUNCTION call_center.cc_email_attempt_transfer(_command_id text, _domain_id bigint, _thread_id bigint,
                                                                 _attempt_id bigint, _agent_id integer, _user_id bigint,
                                                                 _expected_version bigint, _to_queue_id integer,
                                                                 _to_agent_id integer, _comment text)
    RETURNS TABLE (part text, replayed boolean, attempt_id bigint, thread_id bigint, attempt_state text, attempt_version bigint,
                   projection_version bigint, result text, queue_id integer, agent_id integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _fingerprint text;
    _id          bigint;
    _owner       integer;
    _cur_queue   integer;
    _q           call_center.cc_queue;
    _to_user     bigint;
    _online      boolean;
    _slot        text;
    _team_id     integer;
    _used        integer;
    _limit       integer;
    _release     integer := 0;
    _a           call_center.cc_member_attempt;
    _n           call_center.cc_member_attempt;
    _old_seq     bigint;
    _new_seq     bigint;
    _eligible    text;
BEGIN
    _comment := nullif(btrim(_comment), '');
    _to_queue_id := nullif(_to_queue_id, 0);
    _to_agent_id := nullif(_to_agent_id, 0);
    IF coalesce(char_length(_command_id), 0) NOT BETWEEN 1 AND 128
        OR coalesce(_domain_id, 0) <= 0 OR coalesce(_thread_id, 0) <= 0 OR coalesce(_attempt_id, 0) <= 0
        OR coalesce(_agent_id, 0) <= 0 OR coalesce(_user_id, 0) <= 0 OR coalesce(_expected_version, -1) < 0
        OR (_to_queue_id IS NULL) = (_to_agent_id IS NULL) OR coalesce(_to_queue_id, 1) <= 0 OR coalesce(_to_agent_id, 1) <= 0
        OR _to_agent_id = _agent_id OR coalesce(char_length(_comment), 0) > 500 THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAAR', MESSAGE = 'email transfer: invalid command arguments';
    END IF;

    _fingerprint := call_center.cc_email_command_fingerprint('transfer', 'engine', _domain_id::text, _thread_id::text,
        _attempt_id::text, _agent_id::text, _user_id::text, _expected_version::text, _to_queue_id::text,
        _to_agent_id::text, _comment);

    -- A repeat returns the first result before any check of the current state; same lock as other commands.
    RETURN QUERY SELECT * FROM call_center.cc_email_transfer_replay(_domain_id, _command_id, _fingerprint);
    IF FOUND THEN
        RETURN;
    END IF;
    PERFORM pg_advisory_xact_lock(1162690883, hashtext(_domain_id::text || ':engine:' || _command_id));
    RETURN QUERY SELECT * FROM call_center.cc_email_transfer_replay(_domain_id, _command_id, _fingerprint);
    IF FOUND THEN
        RETURN;
    END IF;

    -- Thread lock shared with join and wake-up.
    PERFORM pg_advisory_xact_lock(1162690900, hashtext(_domain_id::text || ':' || _thread_id::text));

    -- The candidate is read without a lock; it is locked in the agreed order and checked again.
    SELECT a.id, a.agent_id, a.queue_id INTO _id, _owner, _cur_queue
    FROM call_center.cc_member_attempt a
    WHERE a.id = _attempt_id AND a.domain_id = _domain_id AND a.channel = 'email' AND a.leaving_at IS NULL
      AND a.member_call_id = _thread_id::text;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'EMANF', MESSAGE = 'email transfer: active attempt not found';
    END IF;
    IF _owner IS DISTINCT FROM _agent_id THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAOW', MESSAGE = format('email transfer: attempt %s is not assigned to agent %s', _id, _agent_id);
    END IF;
    IF _to_queue_id = _cur_queue THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAAR', MESSAGE = 'email transfer: the attempt is already in this queue';
    END IF;

    -- Queues by ID, then the calendar of a direct transfer.
    PERFORM 1 FROM call_center.cc_queue q WHERE q.id IN (_cur_queue, _to_queue_id) ORDER BY q.id FOR SHARE;
    SELECT q.* INTO _q FROM call_center.cc_queue q WHERE q.id = coalesce(_to_queue_id, _cur_queue);
    IF NOT FOUND OR _q.domain_id <> _domain_id THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAQN', MESSAGE = format('email transfer: queue %s not found', coalesce(_to_queue_id, _cur_queue));
    END IF;
    IF _q.type <> 11 OR NOT _q.enabled THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAQP', MESSAGE = format('email transfer: queue %s is not an enabled Email queue', _q.id);
    END IF;
    IF _to_agent_id IS NOT NULL THEN
        PERFORM 1 FROM flow.calendar c WHERE c.id = _q.calendar_id FOR SHARE;
        IF call_center.cc_email_queue_calendar(_q.domain_id, _q.calendar_id) <> 'open' THEN
            RAISE EXCEPTION USING ERRCODE = 'EMACL', MESSAGE = format('email transfer: queue %s is outside its calendar', _q.id);
        END IF;
    END IF;

    -- Agents by ID: the sender as the session user and the recipient of the same domain.
    PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id IN (_agent_id, _to_agent_id) ORDER BY ag.id FOR SHARE;
    PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _agent_id AND ag.user_id = _user_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAOW', MESSAGE = format('email transfer: agent %s is not linked to user %s', _agent_id, _user_id);
    END IF;
    IF _to_agent_id IS NOT NULL THEN
        SELECT ag.user_id INTO _to_user FROM call_center.cc_agent ag WHERE ag.id = _to_agent_id AND ag.domain_id = _domain_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION USING ERRCODE = 'EMATN', MESSAGE = format('email transfer: agent %s not found', _to_agent_id);
        END IF;
    END IF;

    -- Email channels by agent ID, then the skills and preset of the recipient, then the attempt.
    PERFORM 1 FROM call_center.cc_agent_channel ch
    WHERE ch.agent_id IN (_agent_id, _to_agent_id) AND ch.channel = 'email'
    ORDER BY ch.agent_id FOR UPDATE;
    IF _to_agent_id IS NOT NULL THEN
        _eligible := call_center.cc_email_agent_lock_eligible(_q.id, _to_agent_id, false);
    END IF;

    SELECT * INTO _a FROM call_center.cc_member_attempt a WHERE a.id = _id FOR UPDATE;
    IF NOT FOUND OR _a.leaving_at IS NOT NULL OR _a.state = 'leaving' OR _a.member_call_id <> _thread_id::text THEN
        RAISE EXCEPTION USING ERRCODE = 'EMANF', MESSAGE = 'email transfer: active attempt not found';
    END IF;
    IF _a.agent_id IS DISTINCT FROM _agent_id THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAOW', MESSAGE = format('email transfer: attempt %s is not assigned to agent %s', _a.id, _agent_id);
    END IF;
    IF _a.version <> _expected_version THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAVR', MESSAGE = format('email transfer: version %s, expected %s', _a.version, _expected_version);
    END IF;
    IF _a.state NOT IN ('active', 'postponed') THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAST', MESSAGE = format('email transfer: cannot transfer in state %s', _a.state);
    END IF;
    IF _a.queue_id <> _cur_queue THEN
        RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'email transfer: queue changed while locking';
    END IF;

    -- A direct transfer is an offer: as the allocator, online, eligible with the preset, base first, Extra if allowed.
    IF _to_agent_id IS NOT NULL THEN
        SELECT ag.status = 'online' AND coalesce(ch.online, false) INTO _online
        FROM call_center.cc_agent ag
                 LEFT JOIN call_center.cc_agent_channel ch ON ch.agent_id = ag.id AND ch.channel = 'email'
        WHERE ag.id = _to_agent_id;
        IF NOT coalesce(_online, false) THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAOF', MESSAGE = format('email transfer: agent %s or its Email channel is not online', _to_agent_id);
        END IF;
        IF _eligible <> 'eligible' THEN
            RAISE EXCEPTION USING ERRCODE = 'EMAEL', MESSAGE = format('email transfer: agent %s can not take emails of queue %s', _to_agent_id, _q.id);
        END IF;
        SELECT c.team_id, c.slot_type INTO _team_id, _slot
        FROM call_center.cc_email_queue_candidates(_q.id, _to_agent_id, _a.email_extra_allowed) c;
        IF _slot IS NULL THEN
            SELECT c.slot_type, c.used_slots, c.base_limit + CASE WHEN _a.email_extra_allowed THEN c.extra_limit ELSE 0 END
            INTO _slot, _used, _limit
            FROM call_center.cc_email_agent_capacity(_to_agent_id, _a.email_extra_allowed) c;
            IF _slot IS NULL THEN
                RAISE EXCEPTION USING ERRCODE = 'EMASL', MESSAGE = format('email transfer: agent %s has %s of %s emails', _to_agent_id, _used, _limit);
            END IF;
            RAISE EXCEPTION USING ERRCODE = 'EMAEL', MESSAGE = format('email transfer: agent %s can not take emails of queue %s', _to_agent_id, _q.id);
        END IF;
        _release := coalesce(call_center.cc_email_payload_sec(_q.payload, 'email_auto_release_sec'), 0);
    END IF;

    UPDATE call_center.cc_member_attempt a
    SET state = 'leaving', result = 'transfer', leaving_at = now(), reporting_at = now(), timeout = NULL, postponed_until = NULL,
        last_state_change = now(), version = a.version + 1
    WHERE a.id = _a.id
    RETURNING * INTO _a;

    -- The Thread keeps its address, Extra permission and waiting time; Sticky is decided, priority is at least High.
    INSERT INTO call_center.cc_member_attempt
        (domain_id, channel, state, queue_id, member_call_id, weight, destination, queue_params, queue_type, joined_at,
         email_extra_allowed, sticky_agent_id, sticky_until, last_released_agent_id,
         agent_id, team_id, email_slot_type, offering_at, offered_agent_ids, timeout)
    VALUES (_domain_id, 'email', CASE WHEN _to_agent_id IS NULL THEN 'waiting' ELSE 'offering' END, _q.id, _a.member_call_id,
            greatest(_a.weight, call_center.cc_email_high_priority()), _a.destination, call_center.cc_queue_params(_q), _q.type,
            _a.joined_at, _a.email_extra_allowed, NULL, now(), CASE WHEN _to_agent_id IS NULL THEN _agent_id END,
            _to_agent_id, _team_id, _slot, CASE WHEN _to_agent_id IS NOT NULL THEN now() END,
            CASE WHEN _to_agent_id IS NOT NULL THEN ARRAY[_to_agent_id] END,
            CASE WHEN _release > 0 THEN now() + make_interval(secs => _release) END)
    RETURNING * INTO _n;

    PERFORM call_center.cc_email_agent_strategy_refresh(_agent_id);
    IF _to_agent_id IS NOT NULL THEN
        PERFORM call_center.cc_email_agent_strategy_refresh(_to_agent_id);
        UPDATE call_center.cc_agent_channel ch SET last_offering_at = now()
        WHERE ch.agent_id = _to_agent_id AND ch.channel = 'email';
    END IF;

    _old_seq := call_center.cc_email_attempt_snapshot(_a, 'transferred', 'engine', _command_id, _fingerprint, NULL,
        _user_id, _comment, _to_queue_id, _to_user);
    _new_seq := call_center.cc_email_attempt_snapshot(_n, 'transfer_created', 'engine', NULL, NULL, NULL, _user_id);

    -- The transferred row keeps the response of both attempts for a repeat.
    UPDATE call_center.cc_email_attempt_outbox o
    SET response = jsonb_build_object(
        'email', jsonb_build_object('attempt_id', _a.id, 'thread_id', _thread_id, 'state', _a.state,
                                    'attempt_version', _a.version, 'projection_version', _old_seq, 'result', _a.result,
                                    'queue_id', _a.queue_id, 'agent_id', _a.agent_id),
        'transferred_to', jsonb_build_object('attempt_id', _n.id, 'thread_id', _thread_id, 'state', _n.state,
                                             'attempt_version', _n.version, 'projection_version', _new_seq, 'result', NULL,
                                             'queue_id', _n.queue_id, 'agent_id', _n.agent_id))
    WHERE o.sequence = _old_seq;

    RETURN QUERY
    SELECT v.* FROM (VALUES
        ('email'::text, false, _a.id, _thread_id, _a.state::text, _a.version, _old_seq, _a.result::text, _a.queue_id, _a.agent_id),
        ('transferred_to'::text, false, _n.id, _thread_id, _n.state::text, _n.version, _new_seq, NULL::text, _n.queue_id, _n.agent_id)
    ) v;
END;
$$;

-- Candidates of a direct transfer, read without locks.
CREATE OR REPLACE FUNCTION call_center.cc_email_transfer_candidates(_domain_id bigint, _attempt_id bigint, _agent_id integer)
    RETURNS TABLE (agent_id integer, user_id bigint, online boolean, slot_type text, available boolean)
    LANGUAGE plpgsql
    STABLE
AS $$
DECLARE
    _a call_center.cc_member_attempt;
BEGIN
    SELECT * INTO _a
    FROM call_center.cc_member_attempt a
    WHERE a.id = _attempt_id AND a.domain_id = _domain_id AND a.channel = 'email' AND a.leaving_at IS NULL;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'EMANF', MESSAGE = 'email transfer: active attempt not found';
    END IF;
    IF _a.agent_id IS DISTINCT FROM _agent_id THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAOW', MESSAGE = format('email transfer: attempt %s is not assigned to agent %s', _a.id, _agent_id);
    END IF;

    -- Without locks: available repeats the allocator check, the transfer checks it again under its locks.
    RETURN QUERY
    SELECT ag.id, ag.user_id, ag.status = 'online' AND coalesce(ch.online, false), c.slot_type,
           EXISTS (SELECT 1 FROM call_center.cc_email_queue_candidates(_a.queue_id, ag.id, _a.email_extra_allowed) k)
    FROM call_center.cc_agent ag
             LEFT JOIN call_center.cc_agent_channel ch ON ch.agent_id = ag.id AND ch.channel = 'email'
             CROSS JOIN LATERAL call_center.cc_email_agent_capacity(ag.id, _a.email_extra_allowed) c
    WHERE ag.domain_id = _domain_id AND ag.id <> _agent_id
      AND call_center.cc_email_agent_assignable(_a.queue_id, ag.id)
    ORDER BY ag.id;
END;
$$;

-- A failed CONCURRENTLY build leaves an invalid index that IF NOT EXISTS would skip.
SELECT format('DROP INDEX CONCURRENTLY call_center.%I', c.relname)
FROM pg_index i
         JOIN pg_class c ON c.oid = i.indexrelid
WHERE c.oid = to_regclass('call_center.cc_email_attempt_outbox_command_published_idx')
  AND NOT i.indisvalid
\gexec

-- Published rows of commands that their retention may delete, oldest first.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_email_attempt_outbox_command_published_idx
    ON call_center.cc_email_attempt_outbox (published_at)
    WHERE published_at IS NOT NULL AND command_id IS NOT NULL;
