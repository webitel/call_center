-- After cc_sql 1.5 and Email preparation/validation; stop Email writers first.
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
        RAISE EXCEPTION 'email shared distributor runtime: EM-23/EM-24 overrides require an adapted migration';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_extension e
        JOIN pg_depend d ON d.refclassid = 'pg_extension'::regclass AND d.refobjid = e.oid AND d.deptype = 'e'
        JOIN pg_proc p ON d.classid = 'pg_proc'::regclass AND d.objid = p.oid
        WHERE e.extname = 'cc_sql' AND e.extversion = '1.5'
          AND e.extnamespace = 'call_center'::regnamespace
          AND p.oid = to_regprocedure('call_center.cc_sys_distribute_email(integer[],integer[],bigint[])')
          AND p.prosrc = 'cc_sys_distribute_email' AND p.proretset
          AND NOT p.proisstrict AND p.provolatile = 'v' AND p.proparallel = 'u'
    ) OR to_regclass('call_center.cc_email_distribute_stage_1') IS NULL
       OR to_regprocedure('call_center.cc_email_apply_distributed(bigint,integer,integer)') IS NULL
       OR to_regprocedure('call_center.cc_email_agent_strategy_refresh(integer,timestamp with time zone)') IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM pg_attribute
           WHERE attrelid = 'call_center.cc_agent_channel'::regclass
             AND attname = 'email_idle_since' AND NOT attisdropped
       ) THEN
        RAISE EXCEPTION 'email shared distributor runtime: cc_sql 1.5 and Email preparation are required';
    END IF;
END
$$;

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
                    SELECT c.* FROM call_center.cc_sys_distribute_email(_queue_ids, _queue_limits, _skip) c
                LOOP
                    IF clock_timestamp() >= _deadline THEN
                        _timed_out := true;
                        EXIT work;
                    END IF;
                    _selected := true;
                    _pos := array_position(_queue_ids, _pair.queue_id);
                    IF coalesce(_pair.agent_id, 0) <= 0 OR coalesce(_pair.id, 0) <= 0 OR _pos IS NULL
                       OR _pair.ins IS DISTINCT FROM false OR _pair.bucket_id IS NOT NULL
                       OR _pair.resource_id IS NOT NULL OR _pair.resource_group_id IS NOT NULL OR _pair.comm_idx IS NOT NULL
                       OR _pair.agent_id = ANY (_batch_agents) OR _pair.id = ANY (_batch_attempts)
                       OR _pair.id = ANY (_skip) OR _queue_limits[_pos] <= 0 THEN
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
                        FROM call_center.cc_email_apply_distributed(_pair.id, _pair.queue_id, _pair.agent_id) a;
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
                    IF NOT _pair.id = ANY (_skip) THEN
                        _skip := array_append(_skip, _pair.id);
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

-- Drop the legacy allocator only after its caller has been replaced.
DROP FUNCTION IF EXISTS call_center.cc_email_agent_head(integer, bigint[]);
ALTER TABLE call_center.cc_email_distribution_cursor DROP COLUMN IF EXISTS last_agent_id;

COMMIT;
