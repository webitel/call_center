-- Inbound Email distribution: per-agent Email limit, Email channel rows and sticky deadline.
-- Run with psql -v ON_ERROR_STOP=1 -f outside a transaction: the indexes are built CONCURRENTLY.

-- Hard limit of concurrently assigned Email attempts; 0 keeps Email off for the agent.
ALTER TABLE call_center.cc_agent
    ADD COLUMN IF NOT EXISTS email_count smallint DEFAULT 0 NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_agent'::regclass
          AND conname = 'cc_agent_email_count_c'
    ) THEN
        ALTER TABLE call_center.cc_agent
            ADD CONSTRAINT cc_agent_email_count_c CHECK (email_count >= 0);
    END IF;
END
$$;

-- Absolute end of waiting for the previous agent of the Thread; the generic timeout stays unused.
ALTER TABLE call_center.cc_member_attempt
    ADD COLUMN IF NOT EXISTS sticky_until timestamp with time zone;

CREATE OR REPLACE FUNCTION call_center.cc_agent_init_channel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
        insert into call_center.cc_agent_channel (agent_id, channel, state)
        select new.id, c, 'waiting'
        from unnest('{chat,call,task,out_call,im,email}'::text[]) c;
        RETURN NEW;
    END;
$$;

-- Email channel for existing agents; online follows their chat channel.
INSERT INTO call_center.cc_agent_channel (agent_id, channel, state, online)
SELECT a.id, 'email', 'waiting', coalesce(ch.online, false)
FROM call_center.cc_agent a
         LEFT JOIN call_center.cc_agent_channel ch ON ch.agent_id = a.id AND ch.channel = 'chat'
ON CONFLICT (agent_id, channel) DO NOTHING;

-- An assigned Email does not count as another chat of the agent.
CREATE OR REPLACE FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp without time zone DEFAULT NULL::timestamp without time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, per_number_ boolean DEFAULT false, only_current_communication_ boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
    agent_timeout_ timestamptz;
    time_ int8 = extract(EPOCH  from now()) * 1000;
    user_id_ int8 = null;
    domain_id_ int8;
    wrap_time_ int;
    other_cnt_ int;
    stop_cause_ varchar;
    agent_channel_ varchar;
begin

    if next_offering_at_ notnull and not attempt.result in ('success', 'cancel', 'canceled_by_timeout') and next_offering_at_ < now() then
        -- todo move to application
        raise exception 'bad parameter: next distribute at';
    end if;


    update call_center.cc_member_attempt
    set state  =  'leaving',
        reporting_at = now(),
        leaving_at = case when leaving_at isnull then now() else leaving_at end,
        result = status_,
        variables = case when variables_ notnull then coalesce(variables::jsonb, '{}') || variables_ else variables end,
        description = description_
    where id = attempt_id_ and state != 'leaving'
    returning * into attempt;

    if attempt.id isnull then
        return null;
--         raise exception  'not found %', attempt_id_;
    end if;

    if attempt.member_id notnull then
        update call_center.cc_member m
        set last_hangup_at  = time_,
            variables = case when variables_ notnull then coalesce(m.variables::jsonb, '{}') || variables_ else m.variables end,
            expire_at = case when expire_at_ isnull then m.expire_at else expire_at_ end,
            agent_id = case when sticky_agent_id_ isnull then m.agent_id else sticky_agent_id_ end,

            stop_at = case when next_offering_at_ notnull or
                                m.stop_at notnull or
                                only_current_communication_ or
                                (not attempt.result in ('success', 'cancel', 'canceled_by_timeout') and
                                 case when per_number_ is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                    )
                               then m.stop_at else  attempt.leaving_at end,
            stop_cause = case when next_offering_at_ notnull or
                                   m.stop_at notnull or
                                   only_current_communication_ or
                                   (not attempt.result in ('success', 'cancel', 'canceled_by_timeout') and
                                    case when per_number_ is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                       )
                                  then m.stop_cause else  attempt.result end,

            ready_at = (case when next_offering_at_ notnull then (next_offering_at_)::timestamp at time zone tz.names[1]
                            else (now() + (wait_between_retries_ || ' sec')::interval)::timestamptz end)::timestamptz,

            last_agent      = coalesce(attempt.agent_id, m.last_agent),
            communications =  jsonb_set(
                --WTEL-5908
                    case when only_current_communication_
                             then (select jsonb_agg(x || case
                                                             when coalesce((x->>'stop_at')::int8, 0) = 0 and rn - 1 != attempt.communication_idx::int
                                                                 then jsonb_build_object('stop_at', time_)
                                                             else '{}'
                            end order by rn)
                                   from jsonb_array_elements(m.communications) WITH ORDINALITY AS t (x, rn)
                        ) else m.communications end
                , (array[attempt.communication_idx::int])::text[], m.communications->(attempt.communication_idx::int) ||
                                                                   jsonb_build_object('last_activity_at', case when next_offering_at_ notnull then '0'::text::jsonb else time_::text::jsonb end) ||
                                                                   jsonb_build_object('attempt_id', attempt_id_) ||
                                                                   jsonb_build_object('attempts', coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                                                                   case when exclude_dest or
                                                                             (per_number_ is true and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= max_attempts_) then jsonb_build_object('stop_at', time_) else '{}'::jsonb end
                ),
            attempts        = m.attempts + 1                     --TODO
        from call_center.cc_member m2
                 left join flow.calendar_timezone_offsets tz on tz.id = m2.sys_offset_id
        where m.id = attempt.member_id and m.id = m2.id
        returning m.stop_cause into stop_cause_;
    end if;

    if attempt.agent_id notnull then
        select a.user_id, a.domain_id, case when a.on_demand then null else coalesce(tm.wrap_up_time, 0) end,
               case when attempt.channel = 'chat' then (select count(1)
                                                        from call_center.cc_member_attempt aa
                                                        where aa.agent_id = attempt.agent_id and aa.id != attempt.id and aa.state != 'leaving'
                                                          and aa.channel != 'email') else 0 end as other
        into user_id_, domain_id_, wrap_time_, other_cnt_
        from call_center.cc_agent a
                 left join call_center.cc_team tm on tm.id = attempt.team_id
        where a.id = attempt.agent_id;

        if other_cnt_ > 0 then
            update call_center.cc_agent_channel c
            set last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning null, channel into agent_timeout_, agent_channel_;
        elseif wrap_time_ > 0 or wrap_time_ isnull then
            update call_center.cc_agent_channel c
            set state = 'wrap_time',
                joined_at = now(),
                timeout = case when wrap_time_ > 0 then now() + (wrap_time_ || ' sec')::interval end,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning timeout, channel into agent_timeout_, agent_channel_;
        else
            update call_center.cc_agent_channel c
            set state = 'waiting',
                joined_at = now(),
                timeout = null,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id),
                queue_id = null
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning timeout, channel into agent_timeout_, agent_channel_;
        end if;
    end if;

    return row(call_center.cc_view_timestamp(now()),
        attempt.channel,
        attempt.queue_id,
        attempt.agent_call_id,
        attempt.agent_id,
        user_id_,
        domain_id_,
        call_center.cc_view_timestamp(agent_timeout_),
        stop_cause_,
        attempt.member_id
        );
end;
$$;

-- Confirming a progressive call does not cancel Email attempts of the agent.
CREATE OR REPLACE FUNCTION call_center.cc_confirm_agent_attempt(_agent_id bigint, _attempt_id bigint) RETURNS SETOF character varying
    LANGUAGE plpgsql
    AS $$
BEGIN
    return query update call_center.cc_member_attempt
    set result = case when id = _attempt_id then null else 'cancel' end,
        leaving_at = case when id = _attempt_id then null else now() end,
        answered_at = case when id = _attempt_id then now() end
    where agent_id = _agent_id and channel != 'email' and not exists(
       select 1
       from call_center.cc_member_attempt a
       where a.agent_id = _agent_id and a.channel != 'email' and a.leaving_at notnull and a.result = 'cancel'
       for update
    )
    returning member_call_id;
END;
$$;

-- Email Queues get their own channel and counters instead of task ones.
CREATE OR REPLACE VIEW call_center.cc_agent_in_queue_view
 AS
 WITH users_with_calls AS (
          SELECT DISTINCT c.user_id
            FROM call_center.cc_calls c
           WHERE c.user_id IS NOT NULL AND (c.hangup_at IS NULL AND NOT (EXISTS ( SELECT 1
                    FROM call_center.cc_calls cc
                   WHERE cc.parent_id = c.id AND cc.hangup_at IS NOT NULL)) OR c.hangup_at IS NOT NULL AND c.attempt_id IS NOT NULL AND (EXISTS ( SELECT 1
                    FROM call_center.cc_agent_channel ch
                   WHERE ch.agent_id = c.agent_id AND (ch.channel::text = ANY (ARRAY['call'::character varying::text, 'out_call'::character varying::text])) AND ch.state::text = 'processing'::text)))
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
             WHEN q.min_online_agents > 0 THEN GREATEST(COALESCE(array_length(a.agent_p_ids, 1), 0) + COALESCE(array_length(a.agent_on_ids, 1), 0) - q.min_online_agents, 0)
             ELSE NULL::integer
         END, 'busy', COALESCE(array_length(a.agent_b_ids, 1), 0)) AS agents,
     q.max_member_limit
    FROM ( SELECT call_center.cc_get_lookup(q_1.id::bigint, q_1.name) AS queue,
             q_1.priority,
             q_1.type,
             q_1.strategy,
             q_1.enabled,
             COALESCE((q_1.payload -> 'min_online_agents'::text)::integer, 0) AS min_online_agents,
             COALESCE((q_1.payload -> 'max_member_limit'::text)::integer, 0) AS max_member_limit,
             COALESCE(sum(cqs.member_count), 0::bigint) AS count_members,
                 CASE
                     WHEN q_1.type = ANY (ARRAY[1, 6]) THEN ( SELECT count(*) AS count
                        FROM call_center.cc_member_attempt a_1_1
                       WHERE a_1_1.queue_id = q_1.id AND (a_1_1.state::text = ANY (ARRAY['wait_agent'::character varying::text, 'offering'::character varying::text])) AND a_1_1.leaving_at IS NULL)
                     WHEN q_1.type = 11 THEN ( SELECT count(*) AS count
                        FROM call_center.cc_member_attempt a_1_1
                       WHERE a_1_1.queue_id = q_1.id AND a_1_1.agent_id IS NULL AND a_1_1.state::text = 'waiting'::text AND a_1_1.leaving_at IS NULL)
                     ELSE COALESCE(sum(cqs.member_waiting), 0::bigint)
                 END AS waiting_members,
             ( SELECT count(*) AS count
                    FROM call_center.cc_member_attempt a_1_1
                   WHERE a_1_1.queue_id = q_1.id) AS active_members,
             q_1.id AS queue_id,
             q_1.name AS queue_name,
             q_1.team_id,
             a_1.domain_id,
             a_1.id AS agent_id,
                 CASE
                     WHEN q_1.type >= 0 AND q_1.type <= 5 THEN 'call'::text
                     WHEN q_1.type = 6 THEN 'chat'::text
                     WHEN q_1.type = 11 THEN 'email'::text
                     ELSE 'task'::text
                 END AS chan_name
            FROM call_center.cc_agent a_1
              JOIN call_center.cc_queue q_1 ON q_1.domain_id = a_1.domain_id
              LEFT JOIN call_center.cc_queue_statistics cqs ON q_1.id = cqs.queue_id
           WHERE (q_1.team_id IS NULL OR a_1.team_id = q_1.team_id) AND (EXISTS (
                   SELECT qs.queue_id
                    FROM call_center.cc_queue_skill qs
                    JOIN call_center.cc_skill_in_agent csia ON csia.skill_id = qs.skill_id
                   WHERE qs.enabled AND csia.enabled AND csia.agent_id = a_1.id AND qs.queue_id = q_1.id AND csia.capacity >= qs.min_capacity AND csia.capacity <= qs.max_capacity))
           GROUP BY a_1.id, q_1.id, q_1.priority) q
      LEFT JOIN LATERAL ( SELECT DISTINCT array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = 'online'::text AND (a_1.status_id IS NULL OR sp.is_system IS TRUE OR spp.skill_id IS NOT NULL)) AS agent_on_ids,
             array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = 'offline'::text) AS agent_off_ids,
             array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = ANY (ARRAY['pause'::character varying::text, 'break_out'::character varying::text])) AS agent_p_ids,
             array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = 'online'::text AND (a_1.status_id IS NULL OR sp.is_system IS TRUE OR spp.skill_id IS NOT NULL) AND
                 CASE
                     WHEN ac.channel::text = 'email'::text THEN ac.online AND 'email'::character varying::text = ANY (a_1.allow_channels::text[]) AND a_1.email_count > (( SELECT count(*) AS count
                        FROM call_center.cc_member_attempt ea
                       WHERE ea.agent_id = a_1.id AND ea.channel::text = 'email'::text AND ea.leaving_at IS NULL AND ea.state::text <> 'leaving'::text))
                     ELSE ac.state::text = 'waiting'::text AND (ac_call.user_id IS NULL OR (ac.channel::text = ANY (ARRAY['chat'::text, 'task'::text])))
                 END) AS free,
             array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = 'online'::text AND (a_1.status_id IS NULL OR sp.is_system IS TRUE OR spp.skill_id IS NOT NULL) AND ac_call.user_id IS NOT NULL) AS agent_b_ids,
             array_agg(DISTINCT a_1.id) AS total
            FROM call_center.cc_agent a_1
              JOIN call_center.cc_agent_channel ac ON ac.agent_id = a_1.id AND ac.channel::text = q.chan_name
              LEFT JOIN users_with_calls ac_call ON ac_call.user_id = a_1.user_id
              JOIN call_center.cc_queue_skill qs ON qs.queue_id = q.queue_id AND qs.enabled
              JOIN call_center.cc_skill_in_agent sia ON sia.agent_id = a_1.id AND sia.enabled
              LEFT JOIN call_center.cc_online_skills sp ON sp.id = a_1.status_id AND a_1.status::text = 'online'::text
              LEFT JOIN call_center.cc_skills_in_online_skills spp ON spp.online_skill_id = a_1.status_id AND spp.skill_id = sia.skill_id AND a_1.status::text = 'online'::text
           WHERE a_1.domain_id = q.domain_id AND (q.team_id IS NULL OR a_1.team_id = q.team_id) AND qs.skill_id = sia.skill_id AND sia.capacity >= qs.min_capacity AND sia.capacity <= qs.max_capacity
           GROUP BY ROLLUP(q.queue_id)) a ON true;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_attribute
        WHERE attrelid = 'call_center.cc_agent_list'::regclass
          AND attname = 'activity_type'
          AND NOT attisdropped
    ) THEN
        ALTER VIEW call_center.cc_agent_list RENAME COLUMN activity_type TO status_type;
    END IF;
END
$$;

CREATE OR REPLACE VIEW call_center.cc_agent_list
       AS
       SELECT a.domain_id,
          a.id,
          COALESCE(ct.name, ct.username::text COLLATE "default")::character varying AS name,
          a.status,
          a.description,
          (date_part('epoch'::text, a.last_state_change) * 1000::double precision)::bigint AS last_status_change,
          date_part('epoch'::text, now() - a.last_state_change)::bigint AS status_duration,
          a.progressive_count,
          ch.x AS channel,
          json_build_object('id', ct.id, 'name', COALESCE(ct.name, ct.username::text))::jsonb AS "user",
          call_center.cc_get_lookup(a.greeting_media_id::bigint, g.name) AS greeting_media,
          a.allow_channels,
          a.chat_count,
          ( SELECT jsonb_agg(sag."user") AS jsonb_agg
                 FROM call_center.cc_agent_with_user sag
                WHERE sag.id = ANY (a.supervisor_ids)) AS supervisor,
          ( SELECT jsonb_agg(call_center.cc_get_lookup(aud.id, COALESCE(aud.name, aud.username::text)::character varying)) AS jsonb_agg
                 FROM directory.wbt_user aud
                WHERE aud.id = ANY (a.auditor_ids)) AS auditor,
          call_center.cc_get_lookup(t.id, t.name) AS team,
          call_center.cc_get_lookup(r.id::bigint, r.name) AS region,
          a.supervisor AS is_supervisor,
          ( SELECT jsonb_agg(call_center.cc_get_lookup(sa.skill_id::bigint, cs.name)) AS jsonb_agg
                 FROM call_center.cc_skill_in_agent sa
                   JOIN call_center.cc_skill cs ON sa.skill_id = cs.id
                WHERE sa.agent_id = a.id) AS skills,
          a.team_id,
          a.region_id,
          a.supervisor_ids,
          a.auditor_ids,
          a.user_id,
          ct.extension,
          a.task_count,
          a.screen_control,
          t.screen_control IS FALSE AS allow_set_screen_control,
          row_number() OVER (PARTITION BY a.domain_id ORDER BY (
              CASE
                  WHEN a.status::text = 'online'::text THEN 0
                  WHEN a.status::text = 'pause'::text THEN 1
                  WHEN a.status::text = 'offline'::text THEN 2
                  ELSE 3
              END), (COALESCE(ct.name, ct.username::text))) AS "position",
          COALESCE(( SELECT array_agg(status.open) AS array_agg
                 FROM ( SELECT 'dnd'::name AS "?column?"
                         FROM directory.wbt_user_status stt
                        WHERE stt.user_id = a.user_id AND stt.dnd
                      UNION ALL
                      ( SELECT stt.status
                         FROM directory.wbt_user_presence stt
                        WHERE stt.user_id = a.user_id AND stt.status IS NOT NULL AND stt.open > 0
                        ORDER BY stt.prior, stt.status)) status(open)), '{}'::name[]) AS user_presence_status,
          a.extra_chat_count,
	coalesce(a.status_payload, os.name, '') as status_type,
          a.email_count
         FROM call_center.cc_agent a
           LEFT JOIN directory.wbt_user ct ON ct.id = a.user_id
           LEFT JOIN storage.media_files g ON g.id = a.greeting_media_id
           LEFT JOIN call_center.cc_team t ON t.id = a.team_id
           LEFT JOIN flow.region r ON r.id = a.region_id
           LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', (date_part('epoch'::text, c.joined_at) * 1000::double precision)::bigint)) AS x
                 FROM call_center.cc_agent_channel c
                WHERE c.agent_id = a.id) ch ON true
	 left join call_center.cc_online_skills os on a.status_id is not null and a.status_id = os.id and os.is_system is false;

-- Calendar state of an Inbound Email Queue: open, closed or invalid. Only open allows assignment.
CREATE OR REPLACE FUNCTION call_center.cc_email_queue_calendar(_domain_id bigint, _calendar_id integer)
    RETURNS text
    LANGUAGE plpgsql
    STABLE
AS $$
DECLARE
    _open boolean;
BEGIN
    IF _calendar_id IS NULL THEN
        RETURN 'invalid';
    END IF;

    SELECT x.accept AND x.excepted IS NULL AND NOT coalesce(x.expire, false)
    INTO _open
    FROM flow.calendar_check_timing(_domain_id, _calendar_id, null)
             AS x (name varchar, excepted varchar, accept bool, expire bool)
    WHERE x.name IS NOT NULL;

    IF NOT FOUND THEN
        RETURN 'invalid';
    END IF;

    RETURN CASE WHEN _open THEN 'open' ELSE 'closed' END;
EXCEPTION
    -- A lock or statement timeout must roll the whole cycle back, not mark the calendar invalid.
    WHEN lock_not_available OR query_canceled OR deadlock_detected THEN
        RAISE;
    WHEN OTHERS THEN
        RETURN 'invalid';
END;
$$;

-- Agents that may take one more Email of the Queue now, best first. Reads without locks:
-- the allocator locks a candidate and calls it again with _agent_id to recheck.
CREATE OR REPLACE FUNCTION call_center.cc_email_queue_candidates(_queue_id integer, _agent_id integer DEFAULT NULL)
    RETURNS TABLE (agent_id integer, team_id integer, used_slots integer, email_count integer, last_offering_at timestamp with time zone)
    LANGUAGE sql
    STABLE
AS $$
    SELECT a.id, a.team_id, u.used::integer, a.email_count::integer, ch.last_offering_at
    FROM call_center.cc_queue q
             JOIN call_center.cc_agent a
                  ON a.domain_id = q.domain_id AND (q.team_id IS NULL OR a.team_id = q.team_id)
             JOIN call_center.cc_agent_channel ch ON ch.agent_id = a.id AND ch.channel = 'email'
             LEFT JOIN call_center.cc_online_skills os ON os.id = a.status_id
             CROSS JOIN LATERAL (
                 SELECT count(*) AS used
                 FROM call_center.cc_member_attempt ea
                 WHERE ea.agent_id = a.id
                   AND ea.channel = 'email'
                   AND ea.leaving_at IS NULL
                   AND ea.state <> 'leaving'
             ) u
    WHERE q.id = _queue_id
      AND (_agent_id IS NULL OR a.id = _agent_id)
      AND a.status = 'online'
      AND ch.online
      AND 'email' = ANY (a.allow_channels)
      AND a.email_count > u.used
      AND EXISTS (
          SELECT 1
          FROM call_center.cc_queue_skill qs
                   JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
          WHERE qs.queue_id = q.id
            AND qs.enabled
            AND sia.agent_id = a.id
            AND sia.enabled
            AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
            -- An online skill preset narrows the skills, as for the other channels.
            AND (a.status_id IS NULL OR os.is_system IS TRUE OR EXISTS (
                SELECT 1
                FROM call_center.cc_skills_in_online_skills sp
                WHERE sp.online_skill_id = a.status_id
                  AND sp.skill_id = sia.skill_id
            ))
      )
    ORDER BY u.used, ch.last_offering_at NULLS FIRST, a.id
$$;

-- Whether the agent could ever take an Email of the Queue without a configuration change:
-- domain, team, allowed channel, non-zero limit and a matching skill. Presence is not checked.
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
          AND a.email_count > 0
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

-- Sticky upkeep of an open Queue, bounded by _limit rows per step: decides the oldest new Threads,
-- ends waits that ran out or whose agent left. True when nothing is left for a next cycle.
CREATE OR REPLACE FUNCTION call_center.cc_email_sticky_prepare(_queue call_center.cc_queue, _candidates integer[], _limit integer)
    RETURNS boolean
    LANGUAGE plpgsql
AS $$
DECLARE
    _wait     integer;
    _horizon  integer;
    _n        integer;
    _complete boolean := true;
BEGIN
    _wait := CASE WHEN jsonb_typeof(_queue.payload -> 'sticky_agent_sec') = 'number'
                  THEN (_queue.payload ->> 'sticky_agent_sec')::integer ELSE 30 END;
    _horizon := CASE WHEN jsonb_typeof(_queue.payload -> 'email_sticky_history_sec') = 'number'
                     THEN (_queue.payload ->> 'email_sticky_history_sec')::integer ELSE 0 END;

    -- sticky_agent_id is kept only while the Thread waits; without it the attempt is in the general order.
    IF NOT _queue.sticky_agent OR _wait <= 0 THEN
        UPDATE call_center.cc_member_attempt a
        SET sticky_agent_id = NULL
        WHERE a.id IN (
            SELECT w.id
            FROM call_center.cc_member_attempt w
            WHERE w.queue_id = _queue.id
              AND w.channel = 'email'
              AND w.state = 'waiting'
              AND w.agent_id IS NULL
              AND w.leaving_at IS NULL
              AND w.sticky_agent_id IS NOT NULL
            ORDER BY w.sticky_until
            LIMIT _limit
                FOR UPDATE SKIP LOCKED
        );
    ELSE
        UPDATE call_center.cc_member_attempt a
        SET sticky_agent_id = NULL
        WHERE a.id IN (
            SELECT w.id
            FROM call_center.cc_member_attempt w
            WHERE w.queue_id = _queue.id
              AND w.channel = 'email'
              AND w.state = 'waiting'
              AND w.agent_id IS NULL
              AND w.leaving_at IS NULL
              AND w.sticky_agent_id IS NOT NULL
              AND w.sticky_until <= now()
            ORDER BY w.sticky_until
            LIMIT _limit
                FOR UPDATE SKIP LOCKED
        );
    END IF;
    GET DIAGNOSTICS _n = ROW_COUNT;
    _complete := _n < _limit;

    IF _queue.sticky_agent AND _wait > 0 THEN
        -- Agents that left the team, skills or Email while their Threads waited: found by a skip
        -- scan over the distinct waiting agents, at most _limit of them and of their Threads.
        WITH RECURSIVE d(agent_id, n) AS (
            (SELECT w.sticky_agent_id, 1
             FROM call_center.cc_member_attempt w
             WHERE w.queue_id = _queue.id AND w.channel = 'email' AND w.state = 'waiting'
               AND w.agent_id IS NULL AND w.leaving_at IS NULL AND w.sticky_agent_id IS NOT NULL
             ORDER BY w.sticky_agent_id
             LIMIT 1)
            UNION ALL
            SELECT (SELECT w.sticky_agent_id
                    FROM call_center.cc_member_attempt w
                    WHERE w.queue_id = _queue.id AND w.channel = 'email' AND w.state = 'waiting'
                      AND w.agent_id IS NULL AND w.leaving_at IS NULL AND w.sticky_agent_id > d.agent_id
                    ORDER BY w.sticky_agent_id
                    LIMIT 1), d.n + 1
            FROM d
            WHERE d.agent_id IS NOT NULL AND d.n < _limit
        ), gone AS (
            SELECT d.agent_id
            FROM d
            WHERE d.agent_id IS NOT NULL
              AND NOT d.agent_id = ANY (_candidates)
              AND NOT call_center.cc_email_agent_assignable(_queue.id, d.agent_id)
        )
        UPDATE call_center.cc_member_attempt a
        SET sticky_agent_id = NULL,
            sticky_until    = now()
        WHERE a.id IN (
            SELECT x.id
            FROM gone
                     CROSS JOIN LATERAL (
                SELECT w.id
                FROM call_center.cc_member_attempt w
                WHERE w.queue_id = _queue.id
                  AND w.channel = 'email'
                  AND w.state = 'waiting'
                  AND w.agent_id IS NULL
                  AND w.leaving_at IS NULL
                  AND w.sticky_agent_id = gone.agent_id
                ORDER BY w.weight DESC, w.joined_at, w.id
                LIMIT _limit
                    FOR UPDATE SKIP LOCKED
                ) x
            LIMIT _limit
        );
        GET DIAGNOSTICS _n = ROW_COUNT;
        _complete := _complete AND _n < _limit;
    END IF;

    IF NOT _queue.sticky_agent THEN
        RETURN _complete;
    END IF;

    -- Decided once: sticky_until is set even without a previous agent, so history is read once.
    WITH todo AS (
        SELECT a.id, a.member_call_id, a.domain_id
        FROM call_center.cc_member_attempt a
        WHERE a.queue_id = _queue.id
          AND a.channel = 'email'
          AND a.state = 'waiting'
          AND a.agent_id IS NULL
          AND a.leaving_at IS NULL
          AND a.sticky_until IS NULL
        ORDER BY a.joined_at, a.id
        LIMIT _limit
            FOR UPDATE SKIP LOCKED
    ), found AS (
        SELECT t.id,
               (SELECT h.agent_id
                FROM call_center.cc_member_attempt_history h
                WHERE h.member_call_id = t.member_call_id
                  AND h.domain_id = t.domain_id
                  AND h.channel = 'email'
                  AND h.agent_id IS NOT NULL
                  AND (_horizon <= 0 OR h.leaving_at >= now() - make_interval(secs => _horizon))
                ORDER BY h.leaving_at DESC NULLS LAST, h.id DESC
                LIMIT 1) AS prev
        FROM todo t
    ), decided AS (
        SELECT f.id, f.prev,
               f.prev IS NOT NULL AND _wait > 0 AND call_center.cc_email_agent_assignable(_queue.id, f.prev) AS waits
        FROM found f
    )
    UPDATE call_center.cc_member_attempt a
    SET sticky_agent_id = CASE WHEN d.waits THEN d.prev END,
        sticky_until    = CASE WHEN d.waits THEN now() + make_interval(secs => _wait) ELSE now() END,
        weight          = CASE WHEN d.prev IS NULL THEN a.weight ELSE 1 END
    FROM decided d
    WHERE a.id = d.id;

    -- Normal emails wait while any Thread of the Queue may still turn out High.
    RETURN _complete AND (
        SELECT a.id
        FROM call_center.cc_member_attempt a
        WHERE a.queue_id = _queue.id
          AND a.channel = 'email'
          AND a.state = 'waiting'
          AND a.agent_id IS NULL
          AND a.leaving_at IS NULL
          AND a.sticky_until IS NULL
        ORDER BY a.joined_at, a.id
        LIMIT 1
    ) IS NULL;
END;
$$;

-- Locks the agent and its Email channel without waiting, rechecks the agent under the locks
-- and assigns the waiting attempt to it. False leaves the attempt and the agent unchanged.
CREATE OR REPLACE FUNCTION call_center.cc_email_try_assign(_attempt_id bigint, _queue_id integer, _agent_id integer)
    RETURNS boolean
    LANGUAGE plpgsql
AS $$
DECLARE
    _team_id   integer;
    _status_id integer;
    _system    boolean;
BEGIN
    -- Always agent before channel, as cc_agent_set_login and SetStatus do.
    PERFORM 1 FROM call_center.cc_agent a WHERE a.id = _agent_id FOR SHARE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;
    PERFORM 1
    FROM call_center.cc_agent_channel ch
    WHERE ch.agent_id = _agent_id
      AND ch.channel = 'email'
        FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    -- Hold one qualifying skill pair and the online skill preset until commit: engine changes
    -- skills without locking the agent. A row being changed right now skips the agent.
    SELECT a.status_id INTO _status_id FROM call_center.cc_agent a WHERE a.id = _agent_id;
    IF _status_id IS NOT NULL THEN
        SELECT os.is_system INTO _system FROM call_center.cc_online_skills os WHERE os.id = _status_id FOR SHARE SKIP LOCKED;
        IF NOT FOUND AND EXISTS (SELECT 1 FROM call_center.cc_online_skills os WHERE os.id = _status_id) THEN
            RETURN false;
        END IF;
    END IF;

    IF _status_id IS NULL OR _system IS TRUE THEN
        PERFORM 1
        FROM call_center.cc_queue_skill qs
                 JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
        WHERE qs.queue_id = _queue_id
          AND qs.enabled
          AND sia.agent_id = _agent_id
          AND sia.enabled
          AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
        LIMIT 1
            FOR SHARE OF qs, sia SKIP LOCKED;
    ELSE
        PERFORM 1
        FROM call_center.cc_queue_skill qs
                 JOIN call_center.cc_skill_in_agent sia ON sia.skill_id = qs.skill_id
                 JOIN call_center.cc_skills_in_online_skills sp
                      ON sp.online_skill_id = _status_id AND sp.skill_id = sia.skill_id
        WHERE qs.queue_id = _queue_id
          AND qs.enabled
          AND sia.agent_id = _agent_id
          AND sia.enabled
          AND sia.capacity BETWEEN qs.min_capacity AND qs.max_capacity
        LIMIT 1
            FOR SHARE OF qs, sia, sp SKIP LOCKED;
    END IF;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    SELECT c.team_id INTO _team_id
    FROM call_center.cc_email_queue_candidates(_queue_id, _agent_id) c;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE call_center.cc_member_attempt a
    SET state             = 'offering',
        agent_id          = _agent_id,
        team_id           = _team_id,
        offering_at       = now(),
        last_state_change = now(),
        offered_agent_ids = CASE WHEN _agent_id = ANY (a.offered_agent_ids) THEN a.offered_agent_ids
                                 ELSE array_append(a.offered_agent_ids, _agent_id) END
    WHERE a.id = _attempt_id
      AND a.state = 'waiting'
      AND a.agent_id IS NULL
      AND a.leaving_at IS NULL;
    IF NOT FOUND THEN
        RETURN false;
    END IF;

    UPDATE call_center.cc_agent_channel ch
    SET last_offering_at = now()
    WHERE ch.agent_id = _agent_id
      AND ch.channel = 'email';

    RETURN true;
END;
$$;

-- An earlier version had a default for _max_duration, which is now required.
DROP FUNCTION IF EXISTS call_center.cc_email_distribute(integer, interval);

-- One cycle of Email distribution on one node at a time; a busy lock returns a 'busy' row.
-- A safeguard stops it after _max_duration with a 'time_limit' row, keeping what it assigned.
CREATE FUNCTION call_center.cc_email_distribute(_queue_batch integer, _max_duration interval)
    RETURNS TABLE (result text, queue_id integer, attempt_id bigint, agent_id integer)
    LANGUAGE plpgsql
AS $$
DECLARE
    _deadline timestamp with time zone := clock_timestamp() + _max_duration;
    _queue_id integer;
    _q        call_center.cc_queue;
    _calendar text;
    _att      record;
    _assigned integer;
    _done     boolean;
    _ids      integer[];
    _free     integer[];
    _used     integer[];
    _lo       timestamp with time zone[];
    _taken    integer[];
    _dead     boolean[];
    _slots    integer[];
    _slot_k   integer[];
    _pos      integer;
    _i        integer;
    _agent    integer;
    _complete boolean;
BEGIN
    IF coalesce(_queue_batch, 0) <= 0 THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email distribute: queue batch must be positive';
    END IF;
    IF _max_duration IS NULL OR _max_duration <= interval '0' THEN
        RAISE EXCEPTION USING ERRCODE = '22023', MESSAGE = 'email distribute: max duration must be positive';
    END IF;

    -- Email allocator lock (class 0x454D4149 'EMAI', key 1); generic cc_distribute uses another key.
    IF NOT pg_try_advisory_xact_lock(1162690889, 1) THEN
        RETURN QUERY SELECT 'busy'::text, NULL::integer, NULL::bigint, NULL::integer;
        RETURN;
    END IF;

    FOR _queue_id IN
        SELECT q.id
        FROM call_center.cc_queue q
        WHERE q.type = 11
          AND q.enabled
          -- Ordered LIMIT 1 probes keep to the Email indexes; EXISTS could plan a table scan.
          AND ((SELECT a.id
                FROM call_center.cc_member_attempt a
                WHERE a.queue_id = q.id AND a.channel = 'email' AND a.state = 'waiting'
                  AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.sticky_agent_id IS NULL
                ORDER BY a.weight DESC, a.joined_at, a.id
                LIMIT 1) IS NOT NULL
            OR (SELECT a.id
                FROM call_center.cc_member_attempt a
                WHERE a.queue_id = q.id AND a.channel = 'email' AND a.state = 'waiting'
                  AND a.agent_id IS NULL AND a.leaving_at IS NULL AND a.sticky_agent_id IS NOT NULL
                ORDER BY a.sticky_until
                LIMIT 1) IS NOT NULL)
        ORDER BY q.priority DESC, q.domain_id, q.id
    LOOP
        -- The time limit also covers skipped Queues and the preparation of each Queue.
        IF clock_timestamp() >= _deadline THEN
            RETURN QUERY SELECT 'time_limit'::text, _queue_id, NULL::bigint, NULL::integer;
            RETURN;
        END IF;

        -- Hold the Queue and its calendar until commit, so a disable, type or calendar change
        -- waits for the cycle; a row being changed right now skips the Queue for this cycle.
        SELECT q.* INTO _q
        FROM call_center.cc_queue q
        WHERE q.id = _queue_id
          AND q.type = 11
          AND q.enabled
            FOR SHARE SKIP LOCKED;
        CONTINUE WHEN NOT FOUND;

        PERFORM 1 FROM flow.calendar c WHERE c.id = _q.calendar_id FOR SHARE SKIP LOCKED;
        CONTINUE WHEN NOT FOUND AND EXISTS (SELECT 1 FROM flow.calendar c WHERE c.id = _q.calendar_id);

        _calendar := call_center.cc_email_queue_calendar(_q.domain_id, _q.calendar_id);
        IF clock_timestamp() >= _deadline THEN
            RETURN QUERY SELECT 'time_limit'::text, _queue_id, NULL::bigint, NULL::integer;
            RETURN;
        END IF;
        IF _calendar <> 'open' THEN
            RETURN QUERY SELECT 'calendar_' || _calendar, _q.id, NULL::bigint, NULL::integer;
            CONTINUE;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM call_center.cc_queue_skill qs WHERE qs.queue_id = _q.id AND qs.enabled) THEN
            RETURN QUERY SELECT 'no_skills'::text, _q.id, NULL::bigint, NULL::integer;
            CONTINUE;
        END IF;

        -- Free slots of the Queue, read once: fewest used first, an agent's next slot only
        -- after the other agents of that level, then the oldest last offer.
        SELECT coalesce(array_agg(c.agent_id), '{}'), coalesce(array_agg(c.email_count - c.used_slots), '{}'),
               coalesce(array_agg(c.used_slots), '{}'), coalesce(array_agg(c.last_offering_at), '{}')
        INTO _ids, _free, _used, _lo
        FROM call_center.cc_email_queue_candidates(_q.id) c;

        SELECT coalesce(array_agg(x.id ORDER BY x.used + k, k, x.lo NULLS FIRST, x.id), '{}'),
               coalesce(array_agg(k ORDER BY x.used + k, k, x.lo NULLS FIRST, x.id), '{}')
        INTO _slots, _slot_k
        FROM unnest(_ids, _free, _used, _lo) AS x(id, free, used, lo)
                 CROSS JOIN LATERAL generate_series(1, least(x.free, _queue_batch)) k;
        IF clock_timestamp() >= _deadline THEN
            RETURN QUERY SELECT 'time_limit'::text, _queue_id, NULL::bigint, NULL::integer;
            RETURN;
        END IF;

        -- Before the order is read; 1000 rows per step keep a large backlog from delaying other Queues.
        _complete := call_center.cc_email_sticky_prepare(_q, _ids, 1000);
        IF clock_timestamp() >= _deadline THEN
            RETURN QUERY SELECT 'time_limit'::text, _queue_id, NULL::bigint, NULL::integer;
            RETURN;
        END IF;

        _taken := array_fill(0, ARRAY [cardinality(_ids)]);
        _dead := array_fill(false, ARRAY [cardinality(_ids)]);
        _pos := 1;
        _assigned := 0;

        -- One order for the Queue, High then oldest: at most a batch of the general order and, per
        -- agent with free slots, as many of its waiting Threads; each list is cut at the other's end.
        <<attempts>>
        FOR _att IN
            WITH g AS (
                SELECT a.id, a.weight, a.joined_at, a.sticky_until, NULL::integer AS sticky_agent
                FROM call_center.cc_member_attempt a
                WHERE a.queue_id = _q.id
                  AND a.channel = 'email'
                  AND a.state = 'waiting'
                  AND a.agent_id IS NULL
                  AND a.leaving_at IS NULL
                  AND a.sticky_agent_id IS NULL
                ORDER BY a.weight DESC, a.joined_at, a.id
                LIMIT _queue_batch
            ), s AS (
                SELECT x.id, x.weight, x.joined_at, x.sticky_until, c.agent_id AS sticky_agent
                FROM unnest(_ids, _free) AS c(agent_id, free)
                         CROSS JOIN LATERAL (
                    SELECT a.id, a.weight, a.joined_at, a.sticky_until
                    FROM call_center.cc_member_attempt a
                    WHERE a.queue_id = _q.id
                      AND a.channel = 'email'
                      AND a.state = 'waiting'
                      AND a.agent_id IS NULL
                      AND a.leaving_at IS NULL
                      AND a.sticky_agent_id = c.agent_id
                    ORDER BY a.weight DESC, a.joined_at, a.id
                    LIMIT least(c.free, _queue_batch)
                    ) x
                WHERE _q.sticky_agent
                  AND x.sticky_until > now()
                ORDER BY x.weight DESC, x.joined_at, x.id
                LIMIT _queue_batch
            ), g_end AS (
                SELECT -g.weight AS w, g.joined_at AS j, g.id FROM g
                WHERE (SELECT count(*) FROM g) = _queue_batch
                ORDER BY g.weight, g.joined_at DESC, g.id DESC LIMIT 1
            ), s_end AS (
                SELECT -s.weight AS w, s.joined_at AS j, s.id FROM s
                WHERE (SELECT count(*) FROM s) = _queue_batch
                ORDER BY s.weight, s.joined_at DESC, s.id DESC LIMIT 1
            )
            SELECT u.id AS attempt_id, u.weight, u.sticky_until, u.sticky_agent
            FROM (SELECT g.* FROM g
                  WHERE NOT EXISTS (SELECT 1 FROM s_end e WHERE (-g.weight, g.joined_at, g.id) > (e.w, e.j, e.id))
                  UNION ALL
                  SELECT s.* FROM s
                  WHERE NOT EXISTS (SELECT 1 FROM g_end e WHERE (-s.weight, s.joined_at, s.id) > (e.w, e.j, e.id))) u
            ORDER BY u.weight DESC, u.joined_at, u.id
        LOOP
            EXIT attempts WHEN _assigned >= _queue_batch;
            IF clock_timestamp() >= _deadline THEN
                RETURN QUERY SELECT 'time_limit'::text, _q.id, NULL::bigint, NULL::integer;
                RETURN;
            END IF;

            -- Normal waits for pending sticky upkeep; an undecided Thread is newer than all decided.
            EXIT attempts WHEN _att.sticky_agent IS NULL
                AND ((_att.weight = 0 AND NOT _complete) OR (_q.sticky_agent AND _att.sticky_until IS NULL));

            IF _att.sticky_agent IS NOT NULL THEN
                -- A Thread waiting for its agent: only that agent, or skipped while it is full.
                _i := array_position(_ids, _att.sticky_agent);
                CONTINUE attempts WHEN _dead[_i] OR _taken[_i] >= _free[_i];
            END IF;

            -- Another transaction is changing this attempt: leave it to the next cycle.
            PERFORM 1
            FROM call_center.cc_member_attempt a
            WHERE a.id = _att.attempt_id
              AND a.state = 'waiting'
              AND a.agent_id IS NULL
              AND a.leaving_at IS NULL
                FOR UPDATE SKIP LOCKED;
            CONTINUE attempts WHEN NOT FOUND;

            IF _att.sticky_agent IS NOT NULL THEN
                IF call_center.cc_email_try_assign(_att.attempt_id, _q.id, _att.sticky_agent) THEN
                    _taken[_i] := _taken[_i] + 1;
                    _assigned := _assigned + 1;
                    RETURN QUERY SELECT 'assigned'::text, _q.id, _att.attempt_id, _att.sticky_agent;
                ELSE
                    _dead[_i] := true;
                END IF;
                CONTINUE attempts;
            END IF;

            _done := false;
            WHILE _pos <= cardinality(_slots) AND NOT _done LOOP
                _agent := _slots[_pos];
                _i := array_position(_ids, _agent);
                _pos := _pos + 1;
                -- Skip a slot already taken, also by a sticky assignment of the agent.
                CONTINUE WHEN _dead[_i] OR _taken[_i] >= _slot_k[_pos - 1];

                IF call_center.cc_email_try_assign(_att.attempt_id, _q.id, _agent) THEN
                    _done := true;
                    _taken[_i] := _taken[_i] + 1;
                ELSE
                    -- Locked, changed or full under the locks: not used again in this cycle.
                    _dead[_i] := true;
                END IF;
            END LOOP;

            IF _done THEN
                _assigned := _assigned + 1;
                RETURN QUERY SELECT 'assigned'::text, _q.id, _att.attempt_id, _agent;
                CONTINUE attempts;
            END IF;

            -- Later attempts of the Queue have the same eligible agents: stop this Queue only.
            RETURN QUERY SELECT 'no_agent'::text, _q.id, _att.attempt_id, NULL::integer;
            EXIT attempts;
        END LOOP;
    END LOOP;
END;
$$;

-- A failed CONCURRENTLY build leaves an invalid index that IF NOT EXISTS would skip.
DO $$
DECLARE
    _name text;
BEGIN
    FOREACH _name IN ARRAY ARRAY ['cc_member_attempt_email_agent_idx', 'cc_member_attempt_email_queue_idx',
        'cc_member_attempt_email_undecided_idx', 'cc_member_attempt_email_sticky_idx', 'cc_member_attempt_email_sticky_until_idx']
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

-- Used Email slots of an agent; state is kept for the future postponed exclusion.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_agent_idx
    ON call_center.cc_member_attempt (agent_id) INCLUDE (state)
    WHERE channel = 'email' AND agent_id IS NOT NULL AND leaving_at IS NULL;

-- General order of waiting Emails of a Queue: High, then oldest.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_queue_idx
    ON call_center.cc_member_attempt (queue_id, weight DESC, joined_at, id)
    WHERE channel = 'email' AND state = 'waiting' AND agent_id IS NULL AND leaving_at IS NULL AND sticky_agent_id IS NULL;

-- Waiting Emails without a sticky decision yet, oldest first.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_undecided_idx
    ON call_center.cc_member_attempt (queue_id, joined_at, id)
    WHERE channel = 'email' AND state = 'waiting' AND agent_id IS NULL AND leaving_at IS NULL AND sticky_until IS NULL;

-- Emails waiting for their previous agent: per agent in order, and by the end of the wait.
CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_sticky_idx
    ON call_center.cc_member_attempt (queue_id, sticky_agent_id, weight DESC, joined_at, id)
    WHERE channel = 'email' AND state = 'waiting' AND agent_id IS NULL AND leaving_at IS NULL AND sticky_agent_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS cc_member_attempt_email_sticky_until_idx
    ON call_center.cc_member_attempt (queue_id, sticky_until)
    WHERE channel = 'email' AND state = 'waiting' AND agent_id IS NULL AND leaving_at IS NULL AND sticky_agent_id IS NOT NULL;
