-- Inbound Email Queue: one active attempt per email-service Thread and an
-- idempotency journal of EmailJoinToQueue keyed by email_event_id.
-- Run with psql -v ON_ERROR_STOP=1 -f outside a transaction: the index is built CONCURRENTLY.
-- Every step can be repeated after a partial failure.

-- Stop on Email attempts that would break the new invariants; nothing is deleted.
DO $$
DECLARE
    _bad_ids    bigint;
    _duplicates bigint;
BEGIN
    SELECT count(*)
    INTO _bad_ids
    FROM call_center.cc_member_attempt
    WHERE channel = 'email'
      AND (member_call_id IS NULL OR member_call_id !~ '^[1-9][0-9]*$');

    SELECT count(*)
    INTO _duplicates
    FROM (
        SELECT 1
        FROM call_center.cc_member_attempt
        WHERE channel = 'email' AND leaving_at IS NULL
        GROUP BY domain_id, member_call_id
        HAVING count(*) > 1
    ) d;

    IF _bad_ids > 0 OR _duplicates > 0 THEN
        RAISE EXCEPTION 'cc_member_attempt: % email attempts without a canonical member_call_id, % threads with several active email attempts',
            _bad_ids, _duplicates;
    END IF;
END
$$;

-- member_call_id of an Email attempt is the decimal email.thread.id.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_member_attempt'::regclass
          AND conname = 'cc_member_attempt_email_member_call_id_chk'
    ) THEN
        ALTER TABLE call_center.cc_member_attempt
            ADD CONSTRAINT cc_member_attempt_email_member_call_id_chk
                CHECK (channel <> 'email' OR (member_call_id IS NOT NULL AND member_call_id ~ '^[1-9][0-9]*$')) NOT VALID;
    END IF;
END
$$;

ALTER TABLE call_center.cc_member_attempt
    VALIDATE CONSTRAINT cc_member_attempt_email_member_call_id_chk;

-- A failed CONCURRENTLY build leaves an invalid index that IF NOT EXISTS would skip.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_index i
        WHERE i.indexrelid = to_regclass('call_center.cc_member_attempt_email_active_uidx')
          AND NOT i.indisvalid
    ) THEN
        DROP INDEX call_center.cc_member_attempt_email_active_uidx;
    END IF;
END
$$;

-- At most one active Email attempt per Thread.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_active_uidx
    ON call_center.cc_member_attempt (domain_id, member_call_id)
    WHERE channel = 'email' AND leaving_at IS NULL;

-- Result of each EmailJoinToQueue call. Never cleaned automatically: a replayed
-- event must not join its Thread again. No foreign keys: attempts move to history.
CREATE TABLE IF NOT EXISTS call_center.cc_email_join
(
    event_id           uuid NOT NULL,
    domain_id          bigint NOT NULL,
    thread_id          bigint NOT NULL,
    requested_queue_id integer NOT NULL,
    -- Queue and attempt the Thread ended up in; set once the call is applied.
    queue_id           integer,
    attempt_id         bigint,
    result             text,
    -- reserved exists only inside the joining transaction and is never committed.
    state              text NOT NULL DEFAULT 'reserved',
    created_at         timestamp with time zone NOT NULL DEFAULT now(),

    CONSTRAINT cc_email_join_pkey PRIMARY KEY (event_id),
    CONSTRAINT cc_email_join_ids_valid
        CHECK (domain_id > 0 AND thread_id > 0 AND requested_queue_id > 0),
    CONSTRAINT cc_email_join_state_valid
        CHECK (state IN ('reserved', 'applied')),
    CONSTRAINT cc_email_join_result_valid
        CHECK (result IS NULL OR result IN ('created', 'already_active')),
    -- reserved carries no result; applied carries a complete one. IS NOT NULL keeps NULL from passing.
    CONSTRAINT cc_email_join_state_complete
        CHECK (
            (state = 'reserved'
                AND queue_id IS NULL AND attempt_id IS NULL AND result IS NULL)
            OR
            (state = 'applied'
                AND queue_id IS NOT NULL AND queue_id > 0
                AND attempt_id IS NOT NULL AND attempt_id > 0
                AND result IS NOT NULL)
        ),
    CONSTRAINT cc_email_join_created_in_requested_queue
        CHECK (result IS DISTINCT FROM 'created' OR queue_id = requested_queue_id)
);

-- Joins an email-service Thread to an Inbound Email Queue once per event.
-- Errors: EMQNF queue not found in the domain, EMQFP queue disabled or not
-- Inbound Email, EMKEY event already used for another Thread or domain.
CREATE OR REPLACE FUNCTION call_center.cc_email_join_to_queue(_event_id uuid, _domain_id bigint, _thread_id bigint, _queue_id integer)
    RETURNS TABLE (join_result text, join_attempt_id bigint, join_queue_id integer, join_requested_queue_id integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _join          call_center.cc_email_join;
    _queue         call_center.cc_queue;
    _call_id       varchar := _thread_id::text;
    _attempt_id    bigint;
    _attempt_queue integer;
    _result        text;
BEGIN
    IF _event_id IS NULL OR coalesce(_domain_id, 0) <= 0 OR coalesce(_thread_id, 0) <= 0 OR coalesce(_queue_id, 0) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email join: invalid arguments';
    END IF;

    -- Reserve the event first: a concurrent call with the same event waits for it.
    INSERT INTO call_center.cc_email_join (event_id, domain_id, thread_id, requested_queue_id)
    VALUES (_event_id, _domain_id, _thread_id, _queue_id)
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

    -- Held until commit: a concurrent disable or type change waits for the join.
    SELECT * INTO _queue FROM call_center.cc_queue q WHERE q.id = _queue_id AND q.domain_id = _domain_id FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE = 'EMQNF', MESSAGE = format('email join: queue %s not found', _queue_id);
    END IF;
    IF _queue.type <> 11 OR NOT _queue.enabled THEN
        RAISE EXCEPTION USING ERRCODE = 'EMQFP',
            MESSAGE = format('email join: queue %s is disabled or not an inbound email queue', _queue_id);
    END IF;

    -- Retries only when the conflicting attempt left before it could be read.
    FOR _try IN 1..3 LOOP
        INSERT INTO call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_call_id, weight,
                                                   destination, queue_params, queue_type)
        VALUES (_domain_id, 'email', 'waiting', _queue.id, _call_id, 0,
                jsonb_build_object('thread_id', _thread_id), call_center.cc_queue_params(_queue), _queue.type)
        ON CONFLICT (domain_id, member_call_id) WHERE channel = 'email' AND leaving_at IS NULL DO NOTHING
        RETURNING id, queue_id INTO _attempt_id, _attempt_queue;

        IF FOUND THEN
            _result := 'created';
            EXIT;
        END IF;

        SELECT a.id, a.queue_id
        INTO _attempt_id, _attempt_queue
        FROM call_center.cc_member_attempt a
        WHERE a.domain_id = _domain_id
          AND a.member_call_id = _call_id
          AND a.channel = 'email'
          AND a.leaving_at IS NULL;

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

-- Waiting Email attempts are counted directly, as for inbound call and chat queues:
-- Email joins do not update cc_queue_statistics. Only ARRAY[1, 6] -> ARRAY[1, 6, 11] changes.
CREATE OR REPLACE VIEW call_center.cc_queue_list AS
 SELECT q.id,
    q.strategy,
    q.enabled,
    q.payload,
    q.priority,
    q.updated_at,
    q.name,
    q.variables,
    q.domain_id,
    q.type,
    q.created_at,
    call_center.cc_get_lookup(uc.id, (uc.name)::character varying) AS created_by,
    call_center.cc_get_lookup(u.id, (u.name)::character varying) AS updated_by,
    call_center.cc_get_lookup((c.id)::bigint, c.name) AS calendar,
    call_center.cc_get_lookup(cl.id, cl.name) AS dnc_list,
    call_center.cc_get_lookup(ct.id, ct.name) AS team,
    call_center.cc_get_lookup((q.ringtone_id)::bigint, mf.name) AS ringtone,
    q.description,
    call_center.cc_get_lookup(s.id, s.name) AS schema,
    call_center.cc_get_lookup(ds.id, ds.name) AS do_schema,
    call_center.cc_get_lookup(afs.id, afs.name) AS after_schema,
    call_center.cc_get_lookup(fs.id, fs.name) AS form_schema,
    COALESCE(ss.member_count, (0)::bigint) AS count,
        CASE
            WHEN (q.type = ANY (ARRAY[1, 6, 11])) THEN COALESCE(act.cnt_w, (0)::bigint)
            ELSE COALESCE(ss.member_waiting, (0)::bigint)
        END AS waiting,
    COALESCE(act.cnt, (0)::bigint) AS active,
    q.sticky_agent,
    q.processing,
    q.processing_sec,
    q.processing_renewal_sec,
    jsonb_build_object('enabled', q.processing, 'form_schema', call_center.cc_get_lookup(fs.id, fs.name), 'sec', q.processing_sec, 'renewal_sec', q.processing_renewal_sec, 'processing_autosave', q.processing_autosave) AS task_processing,
    call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
    q.team_id,
    q.tags,
    COALESCE(rg.resource_groups, '[]'::jsonb) AS resource_groups,
    COALESCE(rg.resources, '[]'::jsonb) AS resources
   FROM ((((((((((((((call_center.cc_queue q
     LEFT JOIN flow.calendar c ON ((q.calendar_id = c.id)))
     LEFT JOIN directory.wbt_auth au ON ((au.id = q.grantee_id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = q.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = q.updated_by)))
     LEFT JOIN flow.acr_routing_scheme s ON ((q.schema_id = s.id)))
     LEFT JOIN flow.acr_routing_scheme ds ON ((q.do_schema_id = ds.id)))
     LEFT JOIN flow.acr_routing_scheme afs ON ((q.after_schema_id = afs.id)))
     LEFT JOIN flow.acr_routing_scheme fs ON ((q.form_schema_id = fs.id)))
     LEFT JOIN call_center.cc_list cl ON ((q.dnc_list_id = cl.id)))
     LEFT JOIN call_center.cc_team ct ON ((q.team_id = ct.id)))
     LEFT JOIN storage.media_files mf ON ((q.ringtone_id = mf.id)))
     LEFT JOIN LATERAL ( SELECT sum(s_1.member_waiting) AS member_waiting,
            sum(s_1.member_count) AS member_count
           FROM call_center.cc_queue_statistics s_1
          WHERE (s_1.queue_id = q.id)) ss ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt,
            count(*) FILTER (WHERE (a.agent_id IS NULL)) AS cnt_w
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL) AND ((a.state)::text <> 'leaving'::text))) act ON (true))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(DISTINCT call_center.cc_get_lookup(corg.id, corg.name)) FILTER (WHERE (corg.id IS NOT NULL)) AS resource_groups,
            jsonb_agg(DISTINCT call_center.cc_get_lookup((cor.id)::bigint, cor.name)) FILTER (WHERE (cor.id IS NOT NULL)) AS resources
           FROM (((call_center.cc_queue_resource cqr
             JOIN call_center.cc_outbound_resource_group corg ON ((corg.id = cqr.resource_group_id)))
             LEFT JOIN call_center.cc_outbound_resource_in_group corg_res ON ((corg_res.group_id = corg.id)))
             LEFT JOIN call_center.cc_outbound_resource cor ON ((cor.id = corg_res.resource_id)))
          WHERE (cqr.queue_id = q.id)) rg ON (true));
