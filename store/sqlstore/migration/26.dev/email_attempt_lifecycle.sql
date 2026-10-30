-- Email attempt lifecycle: postponed limit and deadlines, version, transition outbox, wake-up journal.
-- After this release's shared prepare, validate and runtime with cc_sql 1.5; stop Email writers on all nodes.
-- Run with psql -v ON_ERROR_STOP=1 -f outside a transaction: the indexes are built CONCURRENTLY.

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_attribute
        WHERE attrelid = to_regclass('call_center.cc_email_attempt_outbox')
          AND attname = 'agent_user_id' AND NOT attisdropped) THEN
        RAISE EXCEPTION 'email lifecycle: EM-24 schema detected; do not reapply lifecycle after status sync';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_extension e
        JOIN pg_depend d ON d.refclassid = 'pg_extension'::regclass AND d.refobjid = e.oid AND d.deptype = 'e'
        JOIN pg_proc p ON d.classid = 'pg_proc'::regclass AND d.objid = p.oid
        WHERE e.extname = 'cc_sql' AND e.extversion = '1.5'
          AND e.extnamespace = 'call_center'::regnamespace
          AND p.oid = to_regprocedure('call_center.cc_sys_distribute_email(integer[],integer[],bigint[],bigint[],integer[])')
          AND p.prosrc = 'cc_sys_distribute_email' AND p.proretset
          AND NOT p.proisstrict AND p.provolatile = 'v' AND p.proparallel = 'u'
    ) THEN
        RAISE EXCEPTION 'email lifecycle: extension-owned cc_sql 1.5 Email entry is required';
    END IF;
    IF to_regclass('call_center.cc_email_distribute_stage_1') IS NULL
       OR to_regclass('call_center.cc_email_distribution_cursor') IS NULL
       OR to_regprocedure('call_center.cc_email_high_priority()') IS NULL
       OR to_regprocedure('call_center.cc_email_sticky_prepare(call_center.cc_queue,integer[],integer,bigint)') IS NULL
       OR to_regprocedure('call_center.cc_email_sticky_route(call_center.cc_queue,integer,boolean,timestamp with time zone,integer)') IS NULL
       OR to_regprocedure('call_center.cc_email_distribute_queue_status(bigint,integer,integer)') IS NULL
       OR to_regprocedure('call_center.cc_email_agent_strategy_refresh(integer,timestamp with time zone)') IS NULL
       OR to_regprocedure('call_center.cc_email_pair_available(call_center.cc_member_attempt,integer,integer,bigint[],integer[])') IS NULL
       OR (to_regprocedure('call_center.cc_email_apply_distributed(bigint,integer,integer)') IS NULL
           AND to_regprocedure('call_center.cc_email_apply_distributed(bigint,integer,integer,bigint[],integer[])') IS NULL)
       OR NOT EXISTS (
           SELECT 1 FROM pg_attribute
           WHERE attrelid = to_regclass('call_center.cc_agent_channel')
             AND attname = 'email_idle_since' AND atttypid = 'timestamptz'::regtype AND NOT attisdropped
       ) OR NOT EXISTS (
           SELECT 1 FROM pg_constraint
           WHERE conrelid = to_regclass('call_center.cc_email_join')
             AND conname = 'cc_email_join_priority_c' AND contype = 'c' AND convalidated
       ) OR to_regprocedure('call_center.cc_email_agent_head(integer,bigint[])') IS NOT NULL
         OR EXISTS (
           SELECT 1 FROM pg_attribute
           WHERE attrelid = to_regclass('call_center.cc_email_distribution_cursor')
             AND attname = 'last_agent_id' AND NOT attisdropped
       ) THEN
        RAISE EXCEPTION 'email lifecycle: apply matching shared prepare, validate and runtime before lifecycle';
    END IF;
END
$$;

-- Maximum of postponed Email attempts of the agent; NULL means no limit, 0 disables postponing.
ALTER TABLE call_center.cc_agent
    ADD COLUMN IF NOT EXISTS email_postponed_count smallint;

-- An earlier version added the column as NOT NULL DEFAULT 0, which forbade postponing by
-- default. Converted once, while it still has that shape: 0 becomes no limit.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid = 'call_center.cc_agent'::regclass
          AND attname = 'email_postponed_count' AND attnotnull AND NOT attisdropped
    ) THEN
        ALTER TABLE call_center.cc_agent
            ALTER COLUMN email_postponed_count DROP DEFAULT,
            ALTER COLUMN email_postponed_count DROP NOT NULL;
        UPDATE call_center.cc_agent SET email_postponed_count = NULL WHERE email_postponed_count = 0;
    END IF;
END
$$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_agent'::regclass
          AND conname = 'cc_agent_email_postponed_count_c'
    ) THEN
        ALTER TABLE call_center.cc_agent
            ADD CONSTRAINT cc_agent_email_postponed_count_c CHECK (email_postponed_count >= 0);
    END IF;
END
$$;

-- Agent search of engine reads the limits from this view.
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
    a.extra_email_count,
    a.email_postponed_count
   FROM ((((((call_center.cc_agent a
     LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
     LEFT JOIN storage.media_files g ON ((g.id = a.greeting_media_id)))
     LEFT JOIN call_center.cc_team t ON ((t.id = a.team_id)))
     LEFT JOIN flow.region r ON ((r.id = a.region_id)))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint)) AS x
           FROM call_center.cc_agent_channel c
          WHERE (c.agent_id = a.id)) ch ON (true))
     LEFT JOIN call_center.cc_online_skills os ON (((a.status_id IS NOT NULL) AND (a.status_id = os.id) AND (os.is_system IS FALSE))));

-- Deadline of a postponed Email attempt; generic timeout keeps auto-release and processing deadlines.
ALTER TABLE call_center.cc_member_attempt
    ADD COLUMN IF NOT EXISTS postponed_until timestamp with time zone;

-- Grows with every Email transition; operator commands compare it with expected_version.
ALTER TABLE call_center.cc_member_attempt
    ADD COLUMN IF NOT EXISTS version bigint DEFAULT 0 NOT NULL;

-- Agent that let the offer expire; the allocator tries other agents first.
ALTER TABLE call_center.cc_member_attempt
    ADD COLUMN IF NOT EXISTS last_released_agent_id integer;

-- A postponed Email attempt keeps its agent and deadline; no other attempt has a deadline.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_member_attempt'::regclass
          AND conname = 'cc_member_attempt_email_postponed_chk'
    ) THEN
        ALTER TABLE call_center.cc_member_attempt
            ADD CONSTRAINT cc_member_attempt_email_postponed_chk
                CHECK (
                    (postponed_until IS NULL AND (channel <> 'email' OR state <> 'postponed'))
                    OR
                    (postponed_until IS NOT NULL AND channel = 'email' AND state = 'postponed' AND agent_id IS NOT NULL)
                ) NOT VALID;
    END IF;
END
$$;

ALTER TABLE call_center.cc_member_attempt
    VALIDATE CONSTRAINT cc_member_attempt_email_postponed_chk;

-- Full snapshot of every Email attempt transition, written in its transaction; published later.
-- sequence is the projection_version of the Thread. Not an action audit; no foreign keys.
CREATE TABLE IF NOT EXISTS call_center.cc_email_attempt_outbox
(
    sequence        bigint GENERATED BY DEFAULT AS IDENTITY (CACHE 1),
    domain_id       bigint NOT NULL,
    thread_id       bigint NOT NULL,
    attempt_id      bigint NOT NULL,
    attempt_version bigint NOT NULL,
    attempt_state   text NOT NULL,
    result          text,
    queue_id        integer NOT NULL,
    agent_id        integer,
    postponed_until timestamp with time zone,
    transition      text NOT NULL,
    source          text NOT NULL,
    -- Set only for engine and flow commands, which a retry may repeat.
    command_id      text,
    fingerprint     text,
    response        jsonb,
    causation_id    text,
    occurred_at     timestamp with time zone NOT NULL DEFAULT now(),
    published_at    timestamp with time zone,

    CONSTRAINT cc_email_attempt_outbox_pkey PRIMARY KEY (sequence),
    CONSTRAINT cc_email_attempt_outbox_ids_valid
        CHECK (domain_id > 0 AND thread_id > 0 AND attempt_id > 0 AND attempt_version >= 0 AND queue_id > 0),
    CONSTRAINT cc_email_attempt_outbox_state_valid
        CHECK (attempt_state IN ('waiting', 'offering', 'active', 'postponed', 'processing', 'leaving')),
    CONSTRAINT cc_email_attempt_outbox_result_valid
        CHECK (result IS NULL OR result IN ('processed', 'processing_timeout')),
    CONSTRAINT cc_email_attempt_outbox_agent_valid
        CHECK ((attempt_state = 'waiting') = (agent_id IS NULL) OR attempt_state = 'leaving'),
    CONSTRAINT cc_email_attempt_outbox_postponed_valid
        CHECK ((attempt_state = 'postponed') = (postponed_until IS NOT NULL)),
    CONSTRAINT cc_email_attempt_outbox_transition_valid
        CHECK (transition IN ('created', 'assigned', 'taken', 'postponed', 'resumed', 'woken', 'queued', 'reopened',
                              'deadline_woken', 'deadline_queued', 'returned', 'auto_released', 'logged_out',
                              'processing_started', 'renewed', 'completed', 'processing_timeout')),
    CONSTRAINT cc_email_attempt_outbox_source_valid
        CHECK (source IN ('engine', 'flow', 'system')),
    CONSTRAINT cc_email_attempt_outbox_command_valid
        CHECK (command_id IS NULL OR char_length(command_id) BETWEEN 1 AND 128),
    -- A command row keeps what a retry needs: its fingerprint and the response; system rows have none.
    CONSTRAINT cc_email_attempt_outbox_command_complete
        CHECK ((command_id IS NULL AND fingerprint IS NULL AND response IS NULL)
            OR (command_id IS NOT NULL AND source <> 'system' AND fingerprint IS NOT NULL AND response IS NOT NULL)),
    CONSTRAINT cc_email_attempt_outbox_response_size
        CHECK (response IS NULL OR pg_column_size(response) <= 4096)
);

-- Replay of an engine or flow command; the last guard against a duplicate command.
CREATE UNIQUE INDEX IF NOT EXISTS cc_email_attempt_outbox_command_uidx
    ON call_center.cc_email_attempt_outbox (domain_id, source, command_id)
    WHERE command_id IS NOT NULL;

-- Rows the future publisher has yet to send; read by state, never by a sequence watermark.
CREATE INDEX IF NOT EXISTS cc_email_attempt_outbox_pending_idx
    ON call_center.cc_email_attempt_outbox (sequence)
    WHERE published_at IS NULL;

-- Result of each wake-up by an inbound Email event, including those that changed nothing.
-- Never cleaned automatically: a replayed event must not wake its Thread again.
CREATE TABLE IF NOT EXISTS call_center.cc_email_wakeup
(
    event_id        uuid NOT NULL,
    domain_id       bigint NOT NULL,
    thread_id       bigint NOT NULL,
    attempt_id      bigint,
    result          text,
    attempt_state   text,
    attempt_version bigint,
    -- reserved exists only inside the waking transaction and is never committed.
    state           text NOT NULL DEFAULT 'reserved',
    created_at      timestamp with time zone NOT NULL DEFAULT now(),

    CONSTRAINT cc_email_wakeup_pkey PRIMARY KEY (event_id),
    CONSTRAINT cc_email_wakeup_ids_valid
        CHECK (domain_id > 0 AND thread_id > 0 AND (attempt_id IS NULL OR attempt_id > 0)),
    CONSTRAINT cc_email_wakeup_state_valid
        CHECK (state IN ('reserved', 'applied')),
    CONSTRAINT cc_email_wakeup_result_valid
        CHECK (result IS NULL OR result IN ('woken', 'queued', 'reopened', 'noop', 'not_active')),
    -- reserved carries no result; applied carries one, with the attempt unless none was active.
    -- Null-safe comparisons: a NULL result must fail the check, not pass it.
    CONSTRAINT cc_email_wakeup_state_complete
        CHECK (
            (state = 'reserved'
                AND result IS NULL AND attempt_id IS NULL AND attempt_state IS NULL AND attempt_version IS NULL)
            OR
            (state = 'applied' AND result IS NOT DISTINCT FROM 'not_active'
                AND attempt_id IS NULL AND attempt_state IS NULL AND attempt_version IS NULL)
            OR
            (state = 'applied' AND result IS NOT NULL AND result IS DISTINCT FROM 'not_active'
                AND attempt_id IS NOT NULL AND attempt_state IS NOT NULL AND attempt_version IS NOT NULL)
        )
);

-- Response of a Flow resume that found nothing to resume after this wake-up; a repeat returns it.
ALTER TABLE call_center.cc_email_wakeup
    ADD COLUMN IF NOT EXISTS resume_response jsonb;

-- A failed CONCURRENTLY build leaves an invalid index that IF NOT EXISTS would skip.
DO $$
DECLARE
    _name text;
BEGIN
    FOREACH _name IN ARRAY ARRAY ['cc_member_attempt_email_timeout_idx', 'cc_member_attempt_email_postponed_idx']
    LOOP
        IF EXISTS (
            SELECT 1
            FROM pg_index i
            WHERE i.indexrelid = to_regclass('call_center.' || _name)
              AND NOT i.indisvalid
        ) THEN
            EXECUTE format('DROP INDEX call_center.%I', _name);
        END IF;
    END LOOP;
END
$$;

-- Due auto-release of offers and processing deadlines, earliest first.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_timeout_idx
    ON call_center.cc_member_attempt (timeout, id)
    WHERE channel = 'email' AND state IN ('offering', 'processing') AND timeout IS NOT NULL AND leaving_at IS NULL;

-- Due postponed deadlines, earliest first.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_postponed_idx
    ON call_center.cc_member_attempt (postponed_until, id)
    WHERE channel = 'email' AND state = 'postponed' AND leaving_at IS NULL;

-- Email load of the agent as in stage 10; a postponed Email holds no slot.
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
                   AND ea.leaving_at IS NULL AND ea.state NOT IN ('leaving', 'postponed')
             ) u
    WHERE a.id = _agent_id
$$;

CREATE OR REPLACE FUNCTION call_center.cc_email_failed_pairs_valid(_attempt_ids bigint[], _agent_ids integer[])
    RETURNS boolean
    LANGUAGE sql
    IMMUTABLE
AS $$
    SELECT _attempt_ids IS NOT NULL AND _agent_ids IS NOT NULL
        AND coalesce(array_ndims(_attempt_ids), 0) <= 1 AND coalesce(array_ndims(_agent_ids), 0) <= 1
        AND cardinality(_attempt_ids) = cardinality(_agent_ids)
        AND NOT EXISTS (SELECT 1 FROM unnest(_attempt_ids, _agent_ids) f(attempt_id, agent_id)
            WHERE coalesce(f.attempt_id, 0) <= 0 OR coalesce(f.agent_id, 0) <= 0)
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
        AND ((_attempt).last_released_agent_id IS DISTINCT FROM _agent_id OR NOT EXISTS (
            SELECT 1 FROM call_center.cc_email_queue_candidates(
                (_attempt).queue_id, _candidate_id, (_attempt).email_extra_allowed) c
            WHERE c.agent_id <> _agent_id
              AND NOT EXISTS (SELECT 1 FROM unnest(_failed_attempt_ids, _failed_agent_ids) f(attempt_id, agent_id)
                  WHERE f.attempt_id = (_attempt).id AND f.agent_id = c.agent_id)))
$$;

-- Replace each entry point atomically; omitted pair arrays stay valid.
BEGIN;
DROP FUNCTION IF EXISTS call_center.cc_email_apply_distributed(bigint, integer, integer);

CREATE OR REPLACE FUNCTION call_center.cc_email_apply_distributed(
    _attempt_id bigint, _queue_id integer, _agent_id integer,
    _failed_attempt_ids bigint[] DEFAULT '{}'::bigint[], _failed_agent_ids integer[] DEFAULT '{}'::integer[])
    RETURNS TABLE (result text, queue_id integer, attempt_id bigint, agent_id integer)
    LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT call_center.cc_email_failed_pairs_valid(_failed_attempt_ids, _failed_agent_ids) THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email apply: invalid failed-pair arrays';
    END IF;
    IF coalesce(_attempt_id, 0) <= 0 OR coalesce(_queue_id, 0) <= 0 OR coalesce(_agent_id, 0) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email distribution: positive attempt, queue and agent IDs are required';
    END IF;
    IF NOT pg_try_advisory_xact_lock(1162690889, 1) THEN
        RETURN QUERY SELECT 'busy'::text, NULL::integer, NULL::bigint, NULL::integer;
        RETURN;
    END IF;

    IF call_center.cc_email_try_assign(_attempt_id, _queue_id, _agent_id, _failed_attempt_ids, _failed_agent_ids) THEN
        PERFORM call_center.cc_email_agent_strategy_refresh(_agent_id);
        RETURN QUERY SELECT 'assigned'::text, _queue_id, _attempt_id, _agent_id;
    ELSE
        RETURN QUERY SELECT 'no_agent'::text, _queue_id, _attempt_id, NULL::integer;
    END IF;
END;
$$;
COMMIT;


-- Fingerprint of a command: its operation, caller form and normalized arguments; NULL is kept apart.
CREATE OR REPLACE FUNCTION call_center.cc_email_command_fingerprint(VARIADIC _parts text[])
    RETURNS text
    LANGUAGE sql
    IMMUTABLE
AS $$
    SELECT encode(sha256(convert_to(array_to_string(ARRAY(SELECT quote_nullable(p) FROM unnest(_parts) p), '|'), 'UTF8')), 'hex')
$$;

-- Writes the full snapshot of an Email attempt after a transition; the sequence is its projection_version.
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
                                                     queue_id, agent_id, postponed_until, transition, source, command_id,
                                                     fingerprint, response, causation_id)
    VALUES (_a.domain_id, _a.member_call_id::bigint, _a.id, _a.version, _a.state, _result, _a.queue_id, _a.agent_id,
            _a.postponed_until, _transition, _source, _command_id, _fingerprint,
            CASE WHEN _command_id IS NOT NULL THEN jsonb_build_object('attempt_id', _a.id, 'state', _a.state,
                'attempt_version', _a.version, 'result', _result, 'agent_id', _a.agent_id, 'postponed_until', _a.postponed_until) END,
            _causation_id)
    RETURNING sequence INTO _sequence;

    RETURN _sequence;
END;
$$;

-- Previous result of a command, or nothing; the same command_id with other arguments is a conflict.
CREATE OR REPLACE FUNCTION call_center.cc_email_command_replay(_domain_id bigint, _source text, _command_id text, _fingerprint text)
    RETURNS TABLE (replayed boolean, attempt_id bigint, thread_id bigint, attempt_state text, attempt_version bigint,
                   projection_version bigint, result text, queue_id integer, agent_id integer,
                   postponed_until timestamp with time zone)
    LANGUAGE plpgsql
AS $$
DECLARE
    _o call_center.cc_email_attempt_outbox;
BEGIN
    SELECT * INTO _o
    FROM call_center.cc_email_attempt_outbox o
    WHERE o.domain_id = _domain_id AND o.source = _source AND o.command_id = _command_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;
    IF _o.fingerprint <> _fingerprint THEN
        RAISE EXCEPTION USING ERRCODE = 'EMACF', MESSAGE = format('email attempt: command %s was used with other arguments', _command_id);
    END IF;

    RETURN QUERY SELECT true, _o.attempt_id, _o.thread_id, _o.attempt_state, _o.attempt_version, _o.sequence, _o.result,
                        _o.queue_id, _o.agent_id, _o.postponed_until;
END;
$$;

-- Take, Postpone, Resume, Return, Complete and renewal of an Email attempt; errors: EMAAR, EMANF, EMAWK, EMAOW, EMAVR,
-- EMAST, EMAOF agent offline, EMAEL agent ineligible, EMASL no slot, EMAPL/EMAPX limits, EMACF reused id, 40001.
CREATE OR REPLACE FUNCTION call_center.cc_email_attempt_command(_op text, _source text, _command_id text, _domain_id bigint,
                                                                _thread_id bigint, _attempt_id bigint, _agent_id integer,
                                                                _expected_version bigint, _email_event_id uuid,
                                                                _postponed_until timestamp with time zone,
                                                                _postpone_for_sec integer, _renewal_sec integer)
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
BEGIN
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
        OR (_op = 'renew') <> (coalesce(_renewal_sec, 0) > 0) THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAAR', MESSAGE = 'email attempt: invalid command arguments';
    END IF;

    -- A relative deadline keeps its duration in the fingerprint, so a retry matches the first call.
    _fingerprint := call_center.cc_email_command_fingerprint(_op, _source, _domain_id::text, _thread_id::text,
        _attempt_id::text, _agent_id::text, _expected_version::text, _email_event_id::text,
        to_char(_postponed_until AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'), _postpone_for_sec::text, _renewal_sec::text);

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
    SELECT a.id, a.agent_id INTO _id, _owner
    FROM call_center.cc_member_attempt a
    WHERE a.domain_id = _domain_id
      AND a.channel = 'email'
      AND a.leaving_at IS NULL
      AND CASE WHEN _source = 'flow' THEN a.member_call_id = _thread_id::text ELSE a.id = _attempt_id END;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'EMANF', MESSAGE = 'email attempt: active attempt not found';
    END IF;

    -- Metric and slot transitions: agent, Email channel, attempt.
    IF _op IN ('take', 'postpone', 'resume', 'return', 'complete') AND _owner IS NOT NULL THEN
        PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _owner FOR SHARE;
        PERFORM 1 FROM call_center.cc_agent_channel ch WHERE ch.agent_id = _owner AND ch.channel = 'email' FOR UPDATE;
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

    _sequence := call_center.cc_email_attempt_snapshot(_a, _transition, _source, _command_id, _fingerprint, _email_event_id::text);

    RETURN QUERY SELECT false, _a.id, _a.member_call_id::bigint, _a.state::text, _a.version, _sequence,
                        CASE WHEN _a.state = 'leaving' THEN _a.result::text END, _a.queue_id, _a.agent_id, _a.postponed_until;
END;
$$;

-- Joins a Thread as in stage 10 and writes the snapshot of a created attempt in the same transaction.
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

-- Postponed attempt locked with its agent and Email channel: back to work when the allocator could give it to the
-- agent now, else to the queue as High, the agent kept as Sticky candidate by the rules of stage 10.
CREATE OR REPLACE FUNCTION call_center.cc_email_wake_postponed(_a call_center.cc_member_attempt, _woken text, _queued text,
                                                               _causation_id text)
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
    SELECT c.slot_type INTO _slot
    FROM call_center.cc_email_queue_candidates(_a.queue_id, _a.agent_id, _a.email_extra_allowed) c;

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

-- Wakes the active attempt of a Thread once per inbound Email event; a replay returns the kept result.
-- Errors: EMAAR arguments, EMWKY event of another Thread or domain, 40001 attempt changed agent.
CREATE OR REPLACE FUNCTION call_center.cc_email_wakeup_thread(_event_id uuid, _domain_id bigint, _thread_id bigint)
    RETURNS TABLE (wakeup_result text, wakeup_attempt_id bigint, wakeup_attempt_state text,
                   wakeup_attempt_version bigint, wakeup_replayed boolean)
    LANGUAGE plpgsql
AS $$
DECLARE
    _w      call_center.cc_email_wakeup;
    _id     bigint;
    _owner  integer;
    _state  text;
    _a      call_center.cc_member_attempt;
    _result text;
BEGIN
    IF _event_id IS NULL OR coalesce(_domain_id, 0) <= 0 OR coalesce(_thread_id, 0) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = 'EMAAR', MESSAGE = 'email wake-up: invalid arguments';
    END IF;

    -- Reserve the event first: a concurrent replay waits for this transaction.
    INSERT INTO call_center.cc_email_wakeup (event_id, domain_id, thread_id)
    VALUES (_event_id, _domain_id, _thread_id)
    ON CONFLICT (event_id) DO NOTHING;

    IF NOT FOUND THEN
        SELECT * INTO STRICT _w FROM call_center.cc_email_wakeup w WHERE w.event_id = _event_id;
        IF _w.domain_id <> _domain_id OR _w.thread_id <> _thread_id THEN
            RAISE EXCEPTION USING ERRCODE = 'EMWKY', MESSAGE = format('email wake-up: event %s belongs to another thread', _event_id);
        END IF;
        RETURN QUERY SELECT _w.result, _w.attempt_id, _w.attempt_state, _w.attempt_version, true;
        RETURN;
    END IF;

    SELECT a.id, a.agent_id, a.state INTO _id, _owner, _state
    FROM call_center.cc_member_attempt a
    WHERE a.domain_id = _domain_id AND a.member_call_id = _thread_id::text AND a.channel = 'email' AND a.leaving_at IS NULL;

    IF FOUND THEN
        -- Wake-up metrics and slots: agent, Email channel, attempt.
        IF _state IN ('postponed', 'processing') AND _owner IS NOT NULL THEN
            PERFORM 1 FROM call_center.cc_agent ag WHERE ag.id = _owner FOR SHARE;
            PERFORM 1 FROM call_center.cc_agent_channel ch WHERE ch.agent_id = _owner AND ch.channel = 'email' FOR UPDATE;
        END IF;
        SELECT * INTO _a FROM call_center.cc_member_attempt a WHERE a.id = _id AND a.leaving_at IS NULL FOR UPDATE;
    END IF;

    IF _a.id IS NULL OR _a.state = 'leaving' THEN
        _result := 'not_active';
        _a := NULL;
    ELSIF _a.state = 'postponed' THEN
        IF _a.agent_id IS DISTINCT FROM _owner OR _state <> 'postponed' THEN
            RAISE EXCEPTION USING ERRCODE = '40001', MESSAGE = 'email wake-up: attempt changed while locking';
        END IF;
        _a := call_center.cc_email_wake_postponed(_a, 'woken', 'queued', _event_id::text);
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
    SET state = 'applied', result = _result, attempt_id = _a.id, attempt_state = _a.state, attempt_version = _a.version
    WHERE w.event_id = _event_id;

    RETURN QUERY SELECT _result, _a.id, _a.state::text, _a.version, false;
END;
$$;

-- As in stage 10, and the offer gets the auto-release deadline of the Queue, a new version and its snapshot.
-- False leaves the attempt and the agent unchanged and writes no snapshot.
BEGIN;
DROP FUNCTION IF EXISTS call_center.cc_email_try_assign(bigint, integer, integer);

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
    _system    boolean;
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


-- Shared Email cycle; failed pairs keep other recipients and the released-agent fallback available.
CREATE OR REPLACE FUNCTION call_center.cc_email_distribute(_queue_batch integer, _max_duration interval)
    RETURNS TABLE (result text, queue_id integer, attempt_id bigint, agent_id integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _deadline timestamp with time zone := clock_timestamp() + _max_duration;
    _prep_deadline timestamp with time zone := clock_timestamp() + _max_duration / 4;
    _last_queue integer;
    _queue_start integer;
    _queue_id integer;
    _status record;
    _pair record;
    _applied record;
    _q call_center.cc_queue;
    _before call_center.cc_member_attempt;
    _after call_center.cc_member_attempt;
    _queue_ids integer[];
    _queue_limits integer[];
    _assigned_queues integer[] := '{}';
    _assigned_counts integer[] := '{}';
    _skip bigint[] := '{}';
    _failed_attempts bigint[] := '{}';
    _failed_agents integer[] := '{}';
    _prepared bigint[] := '{}';
    _batch_agents integer[];
    _batch_attempts bigint[];
    _pos integer;
    _count_pos integer;
    _failed boolean;
    _selected boolean;
    _reselect boolean;
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
    SELECT c.last_queue_id INTO _last_queue
    FROM call_center.cc_email_distribution_cursor c WHERE c.singleton FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'busy'::text, NULL::integer, NULL::bigint, NULL::integer;
        RETURN;
    END IF;

    <<work>>
    BEGIN
        -- Diagnostics do not depend on the bounded maintenance cursor.
        FOR _status IN
            SELECT s.id, s.result FROM call_center.cc_email_distribute_stage_1 s
            WHERE s.result IS NOT NULL ORDER BY s.id
        LOOP
            IF clock_timestamp() >= _deadline THEN
                _timed_out := true;
                EXIT work;
            END IF;
            RETURN QUERY SELECT _status.result::text, _status.id::integer, NULL::bigint, NULL::integer;
        END LOOP;

        FOR _status IN
            SELECT s.id FROM call_center.cc_email_distribute_stage_1 s
            JOIN call_center.cc_queue q ON q.id = s.id
            WHERE s.can_prepare_sticky
              AND jsonb_typeof(q.payload -> 'email_auto_release_sec') <> 'null'
              AND call_center.cc_email_payload_sec(q.payload, 'email_auto_release_sec') IS NULL
            ORDER BY s.id
        LOOP
            IF clock_timestamp() >= _deadline THEN
                _timed_out := true;
                EXIT work;
            END IF;
            RETURN QUERY SELECT 'payload_invalid'::text, _status.id::integer, NULL::bigint, NULL::integer;
        END LOOP;

        _queue_start := _last_queue;
        FOR _queue_id IN
            SELECT s.id FROM call_center.cc_email_distribute_stage_1 s
            WHERE s.can_prepare_sticky ORDER BY (s.id <= _queue_start), s.id
        LOOP
            EXIT WHEN clock_timestamp() >= _prep_deadline;
            _last_queue := _queue_id;
            SELECT q.* INTO _q FROM call_center.cc_queue q
            WHERE q.id = _queue_id AND q.type = 11 AND q.enabled;
            CONTINUE WHEN NOT FOUND;
            PERFORM call_center.cc_email_sticky_prepare(_q, ARRAY[]::integer[], least(_queue_batch, 128), NULL);
        END LOOP;

        LOOP
            _progress := false;
            <<selection>>
            LOOP
                IF clock_timestamp() >= _deadline THEN
                    _timed_out := true;
                    EXIT work;
                END IF;
                SELECT coalesce(array_agg(s.id ORDER BY s.id), '{}'::integer[]),
                       coalesce(array_agg(_queue_batch - coalesce(_assigned_counts[
                           array_position(_assigned_queues, s.id)], 0) ORDER BY s.id), '{}'::integer[])
                INTO _queue_ids, _queue_limits
                FROM call_center.cc_email_distribute_stage_1 s
                WHERE s.can_distribute
                  AND coalesce(_assigned_counts[array_position(_assigned_queues, s.id)], 0) < _queue_batch;
                EXIT work WHEN cardinality(_queue_ids) = 0;

                _selected := false;
                _reselect := false;
                _batch_agents := '{}';
                _batch_attempts := '{}';
                FOR _pair IN
                    SELECT c.* FROM call_center.cc_sys_distribute_email(_queue_ids, _queue_limits, _skip, _failed_attempts, _failed_agents) c
                LOOP
                    -- Apply the whole selected batch; the budget is checked before the next C call.
                    _selected := true;
                    _pos := array_position(_queue_ids, _pair.queue_id);
                    IF coalesce(_pair.agent_id, 0) <= 0 OR coalesce(_pair.id, 0) <= 0 OR _pos IS NULL
                       OR _pair.ins IS DISTINCT FROM false OR _pair.bucket_id IS NOT NULL
                       OR _pair.resource_id IS NOT NULL OR _pair.resource_group_id IS NOT NULL OR _pair.comm_idx IS NOT NULL
                       OR _pair.agent_id = ANY (_batch_agents) OR _pair.id = ANY (_batch_attempts)
                       OR _pair.id = ANY (_skip) OR _queue_limits[_pos] <= 0
                       OR EXISTS (SELECT 1 FROM unnest(_failed_attempts, _failed_agents) f(attempt_id, agent_id)
                           WHERE f.attempt_id = _pair.id AND f.agent_id = _pair.agent_id) THEN
                        RAISE EXCEPTION USING ERRCODE = 'XX000', MESSAGE = 'email distribute: invalid shared distributor result';
                    END IF;
                    _batch_agents := array_append(_batch_agents, _pair.agent_id);
                    _batch_attempts := array_append(_batch_attempts, _pair.id);
                    _queue_limits[_pos] := _queue_limits[_pos] - 1;

                    SELECT a.* INTO _before
                    FROM call_center.cc_member_attempt a
                    JOIN call_center.cc_queue q ON q.id = a.queue_id AND q.domain_id = a.domain_id
                    WHERE a.id = _pair.id AND a.queue_id = _pair.queue_id AND q.type = 11 AND q.enabled
                      AND a.queue_type = 11 AND a.channel = 'email' AND a.state = 'waiting'
                      AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.email_slot_type IS NULL;
                    _failed := NOT FOUND;
                    IF NOT _failed AND _before.sticky_agent_id IS NOT NULL THEN
                        SELECT q.* INTO _q FROM call_center.cc_queue q
                        WHERE q.id = _before.queue_id AND q.domain_id = _before.domain_id AND q.type = 11 AND q.enabled;
                        _failed := NOT FOUND;
                        IF NOT _failed THEN
                            PERFORM call_center.cc_email_sticky_prepare(_q, ARRAY[_pair.agent_id], 1, _pair.id);
                            SELECT a.* INTO _after FROM call_center.cc_member_attempt a
                            WHERE a.id = _before.id AND a.queue_id = _before.queue_id AND a.domain_id = _before.domain_id
                              AND a.queue_type = 11 AND a.channel = 'email' AND a.state = 'waiting'
                              AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.email_slot_type IS NULL;
                            _failed := NOT FOUND;
                            -- The helper's boolean is not a mutation flag.
                            IF NOT _failed AND ROW(_before.sticky_agent_id, _before.sticky_until, _before.weight)
                                IS DISTINCT FROM ROW(_after.sticky_agent_id, _after.sticky_until, _after.weight) THEN
                                IF NOT _pair.id = ANY (_prepared) THEN
                                    _prepared := array_append(_prepared, _pair.id);
                                    _reselect := true;
                                    EXIT;
                                END IF;
                                _failed := true;
                            END IF;
                        END IF;
                    END IF;

                    IF NOT _failed THEN
                        SELECT a.* INTO STRICT _applied
                        FROM call_center.cc_email_apply_distributed(_pair.id, _pair.queue_id, _pair.agent_id, _failed_attempts, _failed_agents) a;
                        IF _applied.result = 'assigned' AND _applied.queue_id = _pair.queue_id
                           AND _applied.attempt_id = _pair.id AND _applied.agent_id = _pair.agent_id THEN
                            _count_pos := array_position(_assigned_queues, _pair.queue_id);
                            IF _count_pos IS NULL THEN
                                _assigned_queues := array_append(_assigned_queues, _pair.queue_id);
                                _assigned_counts := array_append(_assigned_counts, 1);
                            ELSE
                                _assigned_counts[_count_pos] := _assigned_counts[_count_pos] + 1;
                            END IF;
                            _progress := true;
                            RETURN QUERY SELECT 'assigned'::text, _pair.queue_id::integer, _pair.id::bigint, _pair.agent_id::integer;
                            CONTINUE;
                        ELSIF _applied.result IS DISTINCT FROM 'no_agent'
                           OR _applied.queue_id IS DISTINCT FROM _pair.queue_id
                           OR _applied.attempt_id IS DISTINCT FROM _pair.id OR _applied.agent_id IS NOT NULL THEN
                            RAISE EXCEPTION USING ERRCODE = 'XX000', MESSAGE = 'email distribute: invalid assignment adapter result';
                        END IF;
                    END IF;
                    IF _failed THEN
                        IF NOT _pair.id = ANY (_skip) THEN
                            _skip := array_append(_skip, _pair.id);
                            _progress := true;
                        END IF;
                    ELSIF NOT EXISTS (SELECT 1 FROM unnest(_failed_attempts, _failed_agents) f(attempt_id, agent_id)
                        WHERE f.attempt_id = _pair.id AND f.agent_id = _pair.agent_id) THEN
                        _failed_attempts := array_append(_failed_attempts, _pair.id);
                        _failed_agents := array_append(_failed_agents, _pair.agent_id);
                        _progress := true;
                    END IF;
                    RETURN QUERY SELECT 'no_agent'::text, _pair.queue_id::integer, _pair.id::bigint, NULL::integer;
                END LOOP;
                IF NOT _selected THEN
                    FOREACH _queue_id IN ARRAY _queue_ids LOOP
                        RETURN QUERY SELECT 'no_agent'::text, _queue_id, NULL::bigint, NULL::integer;
                    END LOOP;
                    EXIT work;
                END IF;
                EXIT selection WHEN NOT _reselect;
            END LOOP selection;
            EXIT WHEN NOT _progress;
        END LOOP;
    END work;

    UPDATE call_center.cc_email_distribution_cursor c SET last_queue_id = _last_queue WHERE c.singleton;
    IF _timed_out OR clock_timestamp() >= _deadline THEN
        RETURN QUERY SELECT 'time_limit'::text, NULL::integer, NULL::bigint, NULL::integer;
    END IF;
END;
$$;

-- The result gained offline_returned in 11.7; a changed result needs the function dropped.
DROP FUNCTION IF EXISTS call_center.cc_email_lifecycle_watch(integer, interval);

-- One cycle of the Email lifecycle watcher on database time: expired offers back to the queue, processing
-- deadlines to leaving, postponed deadlines to work or the queue, Emails of offline agents back to the queue.
CREATE FUNCTION call_center.cc_email_lifecycle_watch(_batch integer, _max_duration interval)
    RETURNS TABLE (released integer, processing_timeouts integer, postponed_woken integer, postponed_queued integer,
                   offline_returned integer, lock_skipped integer, time_limited boolean)
    LANGUAGE plpgsql
AS $$
DECLARE
    _deadline timestamp with time zone := clock_timestamp() + _max_duration;
    _r        record;
    _a        call_center.cc_member_attempt;
    _status   text;
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

    -- A postponed deadline may take a slot: agent, then its Email channel, then the attempt, none waited for.
    FOR _r IN
        SELECT a.id, a.agent_id, a.postponed_until, a.version
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
        SELECT * INTO _a FROM call_center.cc_member_attempt a WHERE a.id = _r.id FOR UPDATE SKIP LOCKED;
        IF NOT FOUND THEN
            lock_skipped := lock_skipped + (SELECT count(*) FROM call_center.cc_member_attempt a WHERE a.id = _r.id)::integer;
            CONTINUE;
        END IF;
        -- The exact deadline under the locks keeps a deadline from waking the attempt twice.
        CONTINUE WHEN _a.leaving_at IS NOT NULL OR _a.state <> 'postponed' OR _a.postponed_until IS DISTINCT FROM _r.postponed_until
            OR _a.agent_id IS DISTINCT FROM _r.agent_id OR _a.version <> _r.version;

        _a := call_center.cc_email_wake_postponed(_a, 'deadline_woken', 'deadline_queued', NULL);
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

-- Seconds of a Queue payload key: a JSON integer from 0 to 2147483647; NULL when unset, null or invalid.
CREATE OR REPLACE FUNCTION call_center.cc_email_payload_sec(_payload jsonb, _key text)
    RETURNS integer
    LANGUAGE plpgsql
    IMMUTABLE
AS $$
DECLARE
    _v jsonb := _payload -> _key;
    _n numeric;
BEGIN
    IF jsonb_typeof(_v) IS DISTINCT FROM 'number' THEN
        RETURN NULL;
    END IF;
    _n := _v::numeric;
    IF _n < 0 OR _n > 2147483647 OR _n <> trunc(_n) THEN
        RETURN NULL;
    END IF;
    RETURN _n::integer;
END;
$$;

-- Returns a locked offered, active or postponed Email to its queue as High with joined_at kept;
-- the sticky decision is made, so the allocator does not look the history up again.
CREATE OR REPLACE FUNCTION call_center.cc_email_return_to_queue(_a call_center.cc_member_attempt, _transition text)
    RETURNS call_center.cc_member_attempt
    LANGUAGE plpgsql
AS $$
DECLARE
    _owner integer := _a.agent_id;
BEGIN
    UPDATE call_center.cc_member_attempt a
    SET state = 'waiting', agent_id = NULL, email_slot_type = NULL, timeout = NULL, postponed_until = NULL, weight = greatest(a.weight, call_center.cc_email_high_priority()),
        sticky_agent_id = NULL, sticky_until = now(), last_state_change = now(), version = a.version + 1
    WHERE a.id = _a.id
    RETURNING * INTO _a;
    PERFORM call_center.cc_email_agent_strategy_refresh(_owner);
    PERFORM call_center.cc_email_attempt_snapshot(_a, _transition, 'system');
    RETURN _a;
END;
$$;

-- Logout and auto-offline instead of SetStatus: Emails go back to the queue only when the status really
-- changed; processing stays. Outcomes: offline, already_offline, status_not_changed_wait_agent, not_found.
CREATE OR REPLACE FUNCTION call_center.cc_agent_set_offline(_agent_id integer, _payload character varying,
                                                            _comment character varying)
    RETURNS TABLE (outcome text, emails_returned integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _old      character varying;
    _a        call_center.cc_member_attempt;
    _returned integer := 0;
BEGIN
    SELECT ag.status INTO _old FROM call_center.cc_agent ag WHERE ag.id = _agent_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN QUERY SELECT 'not_found'::text, 0;
        RETURN;
    END IF;

    -- The condition of SetStatus: an attempt waiting for this agent keeps its status.
    PERFORM 1 FROM call_center.cc_member_attempt att WHERE att.agent_id = _agent_id AND att.state = 'wait_agent' FOR UPDATE;
    IF FOUND THEN
        RETURN QUERY SELECT 'status_not_changed_wait_agent'::text, 0;
        RETURN;
    END IF;

    UPDATE call_center.cc_agent ag
    SET status = 'offline', status_payload = _payload, status_comment = _comment, last_state_change = now(), status_id = NULL
    WHERE ag.id = _agent_id;

    IF _old IS DISTINCT FROM 'offline' THEN
        PERFORM 1 FROM call_center.cc_agent_channel ch WHERE ch.agent_id = _agent_id AND ch.channel = 'email' FOR UPDATE;
        -- A separate statement sees an offer the allocator committed while this one waited for the agent.
        FOR _a IN
            SELECT *
            FROM call_center.cc_member_attempt a
            WHERE a.agent_id = _agent_id
              AND a.channel = 'email'
              AND a.leaving_at IS NULL
              AND a.state IN ('offering', 'active', 'postponed')
            ORDER BY a.id
                FOR UPDATE
        LOOP
            PERFORM call_center.cc_email_return_to_queue(_a, 'logged_out');
            _returned := _returned + 1;
        END LOOP;
    END IF;

    UPDATE call_center.cc_agent_channel c SET online = false WHERE c.agent_id = _agent_id;

    RETURN QUERY SELECT CASE WHEN _old IS DISTINCT FROM 'offline' THEN 'offline' ELSE 'already_offline' END, _returned;
END;
$$;
