alter table call_center.cc_member_attempt add column if not exists schema_processing boolean DEFAULT false;


create index if not exists cc_calls_history_contact_id_index
    on call_center.cc_calls_history (contact_id);



create or replace function call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, _per_number boolean DEFAULT false) returns record
    language plpgsql
as
$$
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

    if next_offering_at_ notnull and not attempt.result in ('success', 'cancel') and next_offering_at_ < now() then
        -- todo move to application
        raise exception 'bad parameter: next distribute at';
    end if;


    update call_center.cc_member_attempt
    set state  =  'leaving',
        reporting_at = now(),
        leaving_at = case when leaving_at isnull then now() else leaving_at end,
        result = status_,
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
                                (not attempt.result in ('success', 'cancel') and
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                    )
                               then m.stop_at else  attempt.leaving_at end,
            stop_cause = case when next_offering_at_ notnull or
                                   m.stop_at notnull or
                                   (not attempt.result in ('success', 'cancel') and
                                    case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                       )
                                  then m.stop_cause else  attempt.result end,

            ready_at = case when next_offering_at_ notnull then next_offering_at_ at time zone tz.names[1]
                            else now() + (wait_between_retries_ || ' sec')::interval end,

            last_agent      = coalesce(attempt.agent_id, m.last_agent),
            communications =  jsonb_set(m.communications, (array[attempt.communication_idx::int])::text[], m.communications->(attempt.communication_idx::int) ||
                                                                                                           jsonb_build_object('last_activity_at', case when next_offering_at_ notnull then '0'::text::jsonb else time_::text::jsonb end) ||
                                                                                                           jsonb_build_object('attempt_id', attempt_id_) ||
                                                                                                           jsonb_build_object('attempts', coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                                                                                                           case when exclude_dest or
                                                                                                                     (_per_number is true and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= max_attempts_) then jsonb_build_object('stop_at', time_) else '{}'::jsonb end
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
                                                        where aa.agent_id = attempt.agent_id and aa.id != attempt.id and aa.state != 'leaving') else 0 end as other
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

create or replace function call_center.cc_offline_members_ids(_domain_id bigint, _agent_id integer, _lim integer) returns SETOF bigint
    immutable
    language plpgsql
as
$$
begin
    return query
        with queues as (
            select  q_1.domain_id,
                    q_1.id,
                    q_1.calendar_id,
                    q_1.type,
                    q_1.sticky_agent,
                    q_1.recall_calendar,
                    CASE
                        WHEN q_1.sticky_agent THEN COALESCE(((q_1.payload -> 'sticky_agent_sec'::text))::integer, 30)
                        ELSE NULL::integer
                        END AS sticky_agent_sec,
                    CASE
                        WHEN ((q_1.strategy)::text = 'lifo'::text) THEN 1
                        WHEN ((q_1.strategy)::text = 'strict_fifo'::text) THEN 2
                        ELSE 0
                        END AS strategy,
                    q_1.priority,
                    q_1.team_id,
                    ((q_1.payload -> 'max_calls'::text))::integer AS lim,
                    ((q_1.payload -> 'wait_between_retries_desc'::text))::boolean AS wait_between_retries_desc,
                    COALESCE(((q_1.payload -> 'strict_circuit'::text))::boolean, false) AS strict_circuit,
                    array_agg(ROW((m.bucket_id)::integer, (m.member_waiting)::integer, m.op)::call_center.cc_sys_distribute_bucket ORDER BY cbiq.priority DESC NULLS LAST, cbiq.ratio DESC NULLS LAST, m.bucket_id)
                    filter ( where  coalesce(m.bucket_id, 0) = any(bb.bb)) AS buckets,
                    m.op
            FROM ((( WITH mem AS MATERIALIZED (
                SELECT a.queue_id,
                       a.bucket_id,
                       count(*) AS member_waiting,
                       false AS op
                FROM call_center.cc_member_attempt a
                WHERE ((a.bridged_at IS NULL) AND (a.leaving_at IS NULL) AND ((a.state)::text = 'wait_agent'::text))
                GROUP BY a.queue_id, a.bucket_id
                UNION ALL
                SELECT q_2.queue_id,
                       q_2.bucket_id,
                       q_2.member_waiting,
                       true AS op
                FROM call_center.cc_queue_statistics q_2
                WHERE (q_2.member_waiting > 0)
            )
                     SELECT rank() OVER (PARTITION BY mem.queue_id ORDER BY mem.op) AS pos,
                            mem.queue_id,
                            mem.bucket_id,
                            mem.member_waiting,
                            mem.op
                     FROM mem) m
                JOIN call_center.cc_queue q_1 ON ((q_1.id = m.queue_id)))
                LEFT JOIN call_center.cc_bucket_in_queue cbiq ON (((cbiq.queue_id = m.queue_id) AND (cbiq.bucket_id = m.bucket_id))))
                     cross join lateral (
                select cqs.queue_id, array_agg(distinct coalesce(bb, 0)) bb
                from call_center.cc_skill_in_agent sa
                         inner join call_center.cc_queue_skill cqs on cqs.skill_id = sa.skill_id
                    and sa.capacity between cqs.min_capacity and cqs.max_capacity
                         left join lateral unnest(cqs.bucket_ids) bb on true
                where  sa.enabled and cqs.enabled and sa.agent_id = _agent_id
                group by 1
                ) bb
            WHERE ((m.member_waiting > 0) AND q_1.enabled AND  (m.pos = 1) AND ((cbiq.bucket_id IS NULL) OR (NOT cbiq.disabled)))
              and q_1.type = 0
              and q_1.domain_id = _domain_id
              and q_1.id = bb.queue_id
            GROUP BY q_1.domain_id, q_1.id, q_1.calendar_id, q_1.type, m.op
        ), calend AS MATERIALIZED (
            SELECT c.id AS calendar_id,
                   queues.id AS queue_id,
                   CASE
                       WHEN (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) THEN ((array_agg(DISTINCT o1.id))::int2[] + (tz.offset_id)::int2)
                       ELSE (array_agg(DISTINCT o1.id))::int2[]
                       END AS l,
                   (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) AS recall_calendar
            FROM ((((flow.calendar c
                LEFT JOIN flow.calendar_timezones tz ON ((tz.id = c.timezone_id)))
                JOIN queues ON ((queues.calendar_id = c.id)))
                JOIN LATERAL unnest(c.accepts) a(disabled, day, start_time_of_day, end_time_of_day) ON (true))
                JOIN flow.calendar_timezone_offsets o1 ON ((((a.day + 1) = (date_part('isodow'::text, timezone(o1.names[1], now())))::integer) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) >= a.start_time_of_day) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) <= a.end_time_of_day))))
            WHERE (NOT (a.disabled IS TRUE))
            GROUP BY c.id, queues.id, queues.recall_calendar, tz.offset_id
        ), resources AS MATERIALIZED (
            SELECT l_1.queue_id,
                   array_agg(ROW(cor.communication_id, (cor.id)::bigint, ((l_1.l & (l2.x)::integer[]))::smallint[], (cor.resource_group_id)::integer)::call_center.cc_sys_distribute_type) AS types,
                   array_agg(ROW((cor.id)::bigint, ((cor."limit" - used.cnt))::integer, cor.patterns)::call_center.cc_sys_distribute_resource) AS resources,
                   call_center.cc_array_merge_agg((l_1.l & (l2.x)::integer[])) AS offset_ids
            FROM (((calend l_1
                JOIN ( SELECT corg.queue_id,
                              corg.priority,
                              corg.resource_group_id,
                              corg.communication_id,
                              corg."time",
                              (corg.cor).id AS id,
                              (corg.cor)."limit" AS "limit",
                              (corg.cor).enabled AS enabled,
                              (corg.cor).updated_at AS updated_at,
                              (corg.cor).rps AS rps,
                              (corg.cor).domain_id AS domain_id,
                              (corg.cor).reserve AS reserve,
                              (corg.cor).variables AS variables,
                              (corg.cor).number AS number,
                              (corg.cor).max_successively_errors AS max_successively_errors,
                              (corg.cor).name AS name,
                              (corg.cor).last_error_id AS last_error_id,
                              (corg.cor).successively_errors AS successively_errors,
                              (corg.cor).created_at AS created_at,
                              (corg.cor).created_by AS created_by,
                              (corg.cor).updated_by AS updated_by,
                              (corg.cor).error_ids AS error_ids,
                              (corg.cor).gateway_id AS gateway_id,
                              (corg.cor).email_profile_id AS email_profile_id,
                              (corg.cor).payload AS payload,
                              (corg.cor).description AS description,
                              (corg.cor).patterns AS patterns,
                              (corg.cor).failure_dial_delay AS failure_dial_delay,
                              (corg.cor).last_error_at AS last_error_at
                       FROM (calend calend_1
                           JOIN ( SELECT DISTINCT cqr.queue_id,
                                                  corig.priority,
                                                  corg_1.id AS resource_group_id,
                                                  corg_1.communication_id,
                                                  corg_1."time",
                                                  CASE
                                                      WHEN (cor_1.enabled AND gw.enable) THEN ROW(cor_1.id, cor_1."limit", cor_1.enabled, cor_1.updated_at, cor_1.rps, cor_1.domain_id, cor_1.reserve, cor_1.variables, cor_1.number, cor_1.max_successively_errors, cor_1.name, cor_1.last_error_id, cor_1.successively_errors, cor_1.created_at, cor_1.created_by, cor_1.updated_by, cor_1.error_ids, cor_1.gateway_id, cor_1.email_profile_id, cor_1.payload, cor_1.description, cor_1.patterns, cor_1.failure_dial_delay, cor_1.last_error_at, NULL::jsonb)::call_center.cc_outbound_resource
                                                      WHEN (cor2.enabled AND gw2.enable) THEN ROW(cor2.id, cor2."limit", cor2.enabled, cor2.updated_at, cor2.rps, cor2.domain_id, cor2.reserve, cor2.variables, cor2.number, cor2.max_successively_errors, cor2.name, cor2.last_error_id, cor2.successively_errors, cor2.created_at, cor2.created_by, cor2.updated_by, cor2.error_ids, cor2.gateway_id, cor2.email_profile_id, cor2.payload, cor2.description, cor2.patterns, cor2.failure_dial_delay, cor2.last_error_at, NULL::jsonb)::call_center.cc_outbound_resource
                                                      ELSE NULL::call_center.cc_outbound_resource
                                                      END AS cor
                                  FROM ((((((call_center.cc_queue_resource cqr
                                      JOIN call_center.cc_outbound_resource_group corg_1 ON ((cqr.resource_group_id = corg_1.id)))
                                      JOIN call_center.cc_outbound_resource_in_group corig ON ((corg_1.id = corig.group_id)))
                                      JOIN call_center.cc_outbound_resource cor_1 ON ((cor_1.id = (corig.resource_id)::integer)))
                                      JOIN directory.sip_gateway gw ON ((gw.id = cor_1.gateway_id)))
                                      LEFT JOIN call_center.cc_outbound_resource cor2 ON (((cor2.id = corig.reserve_resource_id) AND cor2.enabled)))
                                      LEFT JOIN directory.sip_gateway gw2 ON (((gw2.id = cor2.gateway_id) AND cor2.enabled)))
                                  WHERE (
                                            CASE
                                                WHEN (cor_1.enabled AND gw.enable) THEN cor_1.id
                                                WHEN (cor2.enabled AND gw2.enable) THEN cor2.id
                                                ELSE NULL::integer
                                                END IS NOT NULL)
                                  ORDER BY cqr.queue_id, corig.priority DESC) corg ON ((corg.queue_id = calend_1.queue_id)))) cor ON ((cor.queue_id = l_1.queue_id)))
                JOIN LATERAL ( WITH times AS (
                    SELECT ((e.value -> 'start_time_of_day'::text))::integer AS start,
                           ((e.value -> 'end_time_of_day'::text))::integer AS "end"
                    FROM jsonb_array_elements(cor."time") e(value)
                )
                               SELECT array_agg(DISTINCT t.id) AS x
                               FROM flow.calendar_timezone_offsets t,
                                    times,
                                    LATERAL ( SELECT timezone(t.names[1], CURRENT_TIMESTAMP) AS t) with_timezone
                               WHERE ((((to_char(with_timezone.t, 'SSSS'::text))::integer / 60) >= times.start) AND (((to_char(with_timezone.t, 'SSSS'::text))::integer / 60) <= times."end"))) l2 ON ((l2.* IS NOT NULL)))
                LEFT JOIN LATERAL ( SELECT count(*) AS cnt
                                    FROM ( SELECT 1 AS cnt
                                           FROM call_center.cc_member_attempt c_1
                                           WHERE ((c_1.resource_id = cor.id) AND ((c_1.state)::text <> ALL (ARRAY[('leaving'::character varying)::text, ('processing'::character varying)::text])))) c) used ON (true))
            WHERE (cor.enabled AND ((cor.last_error_at IS NULL) OR (cor.last_error_at <= (now() - ((cor.failure_dial_delay || ' s'::text))::interval))) AND ((cor."limit" - used.cnt) > 0))
            GROUP BY l_1.queue_id
        )
           , request as  (
            SELECT distinct q.id,
                            (q.strategy)::int2 AS strategy,
                            q.team_id,
                            bs.bucket_id::int as bucket_id,
                            r.types,
                            r.resources,
                            q.priority,
                            q.sticky_agent,
                            q.sticky_agent_sec,
                            calend.recall_calendar,
                            q.wait_between_retries_desc,
                            q.strict_circuit,
                            calend.l
            FROM (((queues q
                LEFT JOIN calend ON ((calend.queue_id = q.id)))
                LEFT JOIN resources r ON ((q.op AND (r.queue_id = q.id))))
                LEFT JOIN LATERAL ( SELECT count(*) AS usage
                                    FROM call_center.cc_member_attempt a
                                    WHERE ((a.queue_id = q.id) AND ((a.state)::text <> 'leaving'::text))) l ON ((q.lim > 0)))
                     join lateral unnest(q.buckets) bs on true
            where r.* IS NOT NULL
        )
        select x
        from request
                 left join lateral call_center.cc_distribute_members_list(request.id::int, request.bucket_id::int,
                                                                          request.strategy::int2, request.wait_between_retries_desc, request.l::int2[], _lim::int) x on true
        order by request.priority desc
        limit _lim;
end
$$;

drop function call_center.cc_set_active_members(node character varying);

create or replace function call_center.cc_set_active_members(node character varying)
    returns TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer, communication_idx integer)
    language plpgsql
as
$$
BEGIN
    return query update call_center.cc_member_attempt a
        set state = case when c.member_id isnull then 'leaving' else
            case when c.queue_type in (3, 4) then 'offering' else 'waiting' end
            end
            ,node_id = node
            ,last_state_change = now()
            ,list_communication_id = lc.id
            ,seq = coalesce(c.attempts, -1) + 1
            ,waiting_other_numbers = coalesce(c.waiting_other_numbers, 0)
            ,result = case when c.member_id isnull then 'cancel' else a.result end
            ,leaving_at = case when c.member_id isnull then now() end
        from (
            select c.id,
                   cq.updated_at                                            as queue_updated_at,
                   r.updated_at::bigint as resource_updated_at,
                   call_center.cc_view_timestamp(gw.updated_at at time zone 'utc')::bigint             as gateway_updated_at,
                   c.destination                                            as destination,
                   cm.variables                                             as variables,
                   cm.name                                                  as member_name,
                   c.state                                                  as state,
                   cqs.member_count                                         as queue_cnt,
                   0                                                        as queue_active_cnt,
                   cqs.member_waiting                                       as queue_waiting_cnt,
                   (ca.updated_at - extract(epoch from u.updated_at))::int8 as agent_updated_at,
                   tm.updated_at                                            as team_updated_at,
                   cq.dnc_list_id,
                   cm.attempts,
                   x.cnt                                                    as waiting_other_numbers,
                   cq.type                                                  as queue_type,
                   cm.id as member_id
            from call_center.cc_member_attempt c
                     left join call_center.cc_member cm on c.member_id = cm.id
                     left join lateral (
                select count(*) cnt
                from jsonb_array_elements(cm.communications) WITH ORDINALITY AS x(c, n)
                where coalesce((x.c -> 'stop_at')::int8, 0) < 1
                  and x.n != (c.communication_idx + 1)
                ) x on c.member_id notnull
                     inner join call_center.cc_queue cq on c.queue_id = cq.id
                     left join call_center.cc_team tm on tm.id = cq.team_id
                     left join call_center.cc_outbound_resource r on r.id = c.resource_id
                     left join directory.sip_gateway gw on gw.id = r.gateway_id
                     left join call_center.cc_agent ca on c.agent_id = ca.id
                     left join call_center.cc_queue_statistics cqs on cq.id = cqs.queue_id
                     left join directory.wbt_user u on u.id = ca.user_id
            where c.state = 'idle'
              and c.leaving_at isnull
            order by cq.priority desc, c.weight desc
                for update of c, cq skip locked
        ) c
            left join call_center.cc_list_communications lc on lc.list_id = c.dnc_list_id and
                                                               lc.number = c.destination ->> 'destination'
        where a.id = c.id --and node = 'call_center-igor'
        returning
            a.id::bigint as id,
            a.member_id::bigint as member_id,
            a.result as result,
            a.queue_id::int as qeueue_id,
            c.queue_updated_at::bigint as queue_updated_at,
            c.queue_cnt::int,
            c.queue_active_cnt::int,
            c.queue_waiting_cnt::int,
            a.resource_id::int as resource_id,
            greatest(c.resource_updated_at::bigint, c.gateway_updated_at::bigint) as resource_updated_at,
            greatest(c.resource_updated_at::bigint, c.gateway_updated_at::bigint) as gateway_updated_at,
            c.destination,
            coalesce(c.variables, '{}') ,
            coalesce(c.member_name, ''),
            a.member_call_id,
            a.agent_id,
            c.agent_updated_at,
            c.team_updated_at,
            a.list_communication_id,
            a.seq,
            a.communication_idx;
END;
$$;



alter table storage.upload_file_jobs add column props jsonb;

--
-- Name: web_hook; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.web_hook (
                               id character varying NOT NULL,
                               name character varying NOT NULL,
                               domain_id bigint NOT NULL,
                               description character varying,
                               origin character varying[],
                               rps integer DEFAULT 5 NOT NULL,
                               schema_id integer NOT NULL,
                               enabled boolean DEFAULT true NOT NULL,
                               "authorization" character varying
);


--
-- Name: web_hook web_hook_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.web_hook
    ADD CONSTRAINT web_hook_pk PRIMARY KEY (id);



--
-- Name: cc_agent_set_login(integer, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_agent_set_login(agent_id_ integer, on_demand_ boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
AS $$
declare
    res_ jsonb;
    user_id_
         int8;
begin
    update call_center.cc_agent
    set status            = 'online', -- enum added
        status_payload    = null,
        on_demand         = on_demand_,
--         updated_at = case when on_demand != on_demand_ then cc_view_timestamp(now()) else updated_at end,
        last_state_change = now()     -- todo rename to status
    where call_center.cc_agent.id = agent_id_
    returning user_id into user_id_;

    if
        NOT (exists(select 1
                    from directory.wbt_user_presence p
                    where user_id = user_id_
                      and open > 0
                      and status in ('sip', 'web'))
            or exists(SELECT 1
                      FROM directory.wbt_session s
                      WHERE ((user_id IS NOT NULL) AND (NULLIF((props ->> 'pn-rpid'::text), ''::text) IS NOT NULL))
                        and s.user_id = user_id_::int8
                        and s.access notnull
                        AND s.expires > now() at time zone 'UTC')) then
        raise exception 'not found: sip, web or pn';
    end if;

    with chls as (
        update call_center.cc_agent_channel c
            set state = case when x.x = 1 then c.state else 'waiting' end,
                online = true,
                no_answers = 0,
                timeout = case when x.x = 1 then c.timeout else null end
            from call_center.cc_agent_channel c2
                left join LATERAL (
                    select a.channel, 1 x
                    from call_center.cc_member_attempt a
                    where a.agent_id = agent_id_
                      and a.channel = c2.channel
                    limit 1
                    ) x
                on true
            where c2.agent_id = agent_id_
                and (c.agent_id, c.channel) = (c2.agent_id, c2.channel)
            returning jsonb_build_object('channel'
                , c.channel
                , 'joined_at'
                , call_center.cc_view_timestamp(c.joined_at)
                , 'state'
                , c.state
                , 'no_answers'
                , c.no_answers) xx
    )
    select jsonb_agg(chls.xx)
    from chls
    into res_;

    return row (res_::jsonb, call_center.cc_view_timestamp(now()));
end;
$$;



--
-- Name: cc_attempt_end_reporting(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb, integer, integer, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, _per_number boolean DEFAULT false) RETURNS record
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

    if next_offering_at_ notnull and not attempt.result in ('success', 'cancel') and next_offering_at_ < now() then
        -- todo move to application
        raise exception 'bad parameter: next distribute at';
    end if;


    update call_center.cc_member_attempt
    set state  =  'leaving',
        reporting_at = now(),
        leaving_at = case when leaving_at isnull then now() else leaving_at end,
        result = status_,
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
                                (not attempt.result in ('success', 'cancel') and
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                    )
                               then m.stop_at else  attempt.leaving_at end,
            stop_cause = case when next_offering_at_ notnull or
                                   m.stop_at notnull or
                                   (not attempt.result in ('success', 'cancel') and
                                    case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                       )
                                  then m.stop_cause else  attempt.result end,

            ready_at = case when next_offering_at_ notnull then next_offering_at_ at time zone tz.names[1]
                            else now() + (wait_between_retries_ || ' sec')::interval end,

            last_agent      = coalesce(attempt.agent_id, m.last_agent),
            communications =  jsonb_set(m.communications, (array[attempt.communication_idx::int])::text[], m.communications->(attempt.communication_idx::int) ||
                                                                                                           jsonb_build_object('last_activity_at', case when next_offering_at_ notnull then '0'::text::jsonb else time_::text::jsonb end) ||
                                                                                                           jsonb_build_object('attempt_id', attempt_id_) ||
                                                                                                           jsonb_build_object('attempts', coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                                                                                                           case when exclude_dest or
                                                                                                                     (_per_number is true and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= max_attempts_) then jsonb_build_object('stop_at', time_) else '{}'::jsonb end
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
                                                        where aa.agent_id = attempt.agent_id and aa.id != attempt.id and aa.state != 'leaving') else 0 end as other
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




--
-- Name: cc_communication_set_def(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_communication_set_def() RETURNS trigger
    LANGUAGE plpgsql
AS $$
begin
    if new.default is distinct from old."default" or new.channel is distinct from old."channel"  then
        update call_center.cc_communication c
        set  "default" = false
        where c.domain_id = new.domain_id and c.id != new.id and c.channel = new.channel;
    end if;
    return new;
end;
$$;



drop PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean);
--
-- Name: cc_distribute(boolean); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean)
    LANGUAGE plpgsql
AS $$
begin
    if NOT pg_try_advisory_xact_lock(132132117) then
        raise exception 'LOCK';
    end if;

    with dis as MATERIALIZED (
        select x.*, a.team_id
        from call_center.cc_sys_distribute(disable_omnichannel) x (agent_id int, queue_id int, bucket_id int, ins bool, id int8, resource_id int,
                                                                   resource_group_id int, comm_idx int)
                 left join call_center.cc_agent a on a.id= x.agent_id
    )
       , ins as (
        insert into call_center.cc_member_attempt (channel, member_id, queue_id, resource_id, agent_id, bucket_id, destination,
                                                   communication_idx, member_call_id, team_id, resource_group_id, domain_id, import_id, sticky_agent_id)
            select case when q.type = 7 then 'task' else 'call' end, --todo
                   dis.id,
                   dis.queue_id,
                   dis.resource_id,
                   dis.agent_id,
                   dis.bucket_id,
                   x,
                   dis.comm_idx,
                   uuid_generate_v4(),
                   dis.team_id,
                   dis.resource_group_id,
                   q.domain_id,
                   m.import_id,
                   case when q.type = 5 and q.sticky_agent then dis.agent_id end
            from dis
                     inner join call_center.cc_queue q on q.id = dis.queue_id
                     inner join call_center.cc_member m on m.id = dis.id
                     inner join lateral jsonb_extract_path(m.communications, (dis.comm_idx)::text) x on true
            where dis.ins
    )
    update call_center.cc_member_attempt a
    set agent_id = t.agent_id,
        team_id = t.team_id
    from (
             select dis.id, dis.agent_id, dis.team_id
             from dis
                      inner join call_center.cc_agent a on a.id = dis.agent_id
                      left join call_center.cc_queue q on q.id = dis.queue_id
             where not dis.ins is true
               and (q.type is null or q.type in (6, 7) or not exists(select 1 from call_center.cc_calls cc where cc.user_id = a.user_id and cc.hangup_at notnull ))
         ) t
    where t.id = a.id
      and a.agent_id isnull;

end;
$$;



--
-- Name: cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
    LANGUAGE plpgsql
AS $$
declare
    _timezone_id int4;
    _discard_abandoned_after int4;
    _weight int4;
    dnc_list_id_ int4;
    _domain_id int8;
    _calendar_id int4;
    _queue_updated_at int8;
    _team_updated_at int8;
    _team_id_ int;
    _enabled bool;
    _q_type smallint;
    _attempt record;
    _con_created timestamptz;
    _con_name varchar;
    _con_type varchar;
    _last_msg varchar;
    _client_name varchar;
    _inviter_channel_id varchar;
    _inviter_user_id varchar;
    _sticky bool;
    _max_waiting_size int;
BEGIN
    select c.timezone_id,
           (coalesce(payload->>'discard_abandoned_after', '0'))::int discard_abandoned_after,
           c.domain_id,
           q.dnc_list_id,
           q.calendar_id,
           q.updated_at,
           ct.updated_at,
           q.team_id,
           q.enabled,
           q.type,
           q.sticky_agent,
           (payload->>'max_waiting_size')::int max_size
    from call_center.cc_queue q
             inner join flow.calendar c on q.calendar_id = c.id
             left join call_center.cc_team ct on q.team_id = ct.id
    where  q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size;

    if not _q_type = 6 then
        raise exception 'queue type not inbound chat';
    end if;

    if not _enabled = true then
        raise exception 'queue disabled';
    end if;

    if not exists(select accept
                  from flow.calendar_check_timing(_domain_id, _calendar_id, null)
                           as x (name varchar, excepted varchar, accept bool, expire bool)
                  where accept and excepted is null and not expire) then
        raise exception 'conversation [%] calendar not working [%] [%]', _conversation_id, _calendar_id, _queue_id;
    end if;

    if _max_waiting_size > 0 then
        if (select count(*) from call_center.cc_member_attempt aa
            where aa.queue_id = _queue_id
              and aa.bridged_at isnull
              and aa.leaving_at isnull
              and (bucket_id_ isnull or aa.bucket_id = bucket_id_)) >= _max_waiting_size then
            raise exception using
                errcode='MAXWS',
                message='Queue maximum waiting size';
        end if;
    end if;

    select cli.external_id,
           c.created_at,
           c.id::varchar inviter_channel_id,
           c.user_id,
           c.name,
           lst.message,
           c.type
    from chat.channel c
             left join chat.client cli on cli.id = c.user_id
             left join lateral (
        select coalesce(m.text, m.file_name, 'empty') message
        from chat.message m
        where m.conversation_id = _conversation_id::uuid
        order by created_at desc
        limit 1
        ) lst on true -- todo
    where c.closed_at isnull
      and c.conversation_id = _conversation_id::uuid
      and not c.internal
    into _con_name, _con_created, _inviter_channel_id, _inviter_user_id, _client_name, _last_msg, _con_type;

    if coalesce(_inviter_channel_id, '') = '' or coalesce(_inviter_user_id, '') = '' isnull then
        raise exception using
            errcode='VALID',
            message='Bad request inviter_channel_id or user_id';
    end if;

    --TODO
--   select clc.id
--     into _list_comm_id
--     from cc_list_communications clc
--     where (clc.list_id = dnc_list_id_ and clc.number = _call.from_number)
--   limit 1;

--   if _list_comm_id notnull then
--           insert into cc_member_attempt(channel, queue_id, state, leaving_at, member_call_id, result, list_communication_id)
--           values ('call', _queue_id, 'leaving', now(), _call_id, 'banned', _list_comm_id);
--           raise exception 'number % banned', _call.from_number;
--   end if;

    if  _discard_abandoned_after > 0 then
        select
            case when log.result = 'abandoned' then
                         extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
                 else coalesce(_priority, 0) end
        from call_center.cc_member_attempt_history log
        where log.leaving_at >= (now() -  (_discard_abandoned_after || ' sec')::interval)
          and log.queue_id = _queue_id
          and log.destination->>'destination' = _con_name
        order by log.leaving_at desc
        limit 1
        into _weight;
    end if;

    if _sticky_agent_id notnull and _sticky then
        if not exists(select 1
                      from call_center.cc_agent a
                      where a.id = _sticky_agent_id
                        and a.domain_id = _domain_id
                        and a.status = 'online'
                        and exists(select 1
                                   from call_center.cc_skill_in_agent sa
                                            inner join call_center.cc_queue_skill qs
                                                       on qs.skill_id = sa.skill_id and qs.queue_id = _queue_id
                                   where sa.agent_id = _sticky_agent_id
                                     and sa.enabled
                                     and sa.capacity between qs.min_capacity and qs.max_capacity)
            ) then
            _sticky_agent_id = null;
        end if;
    else
        _sticky_agent_id = null;
    end if;

    insert into call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_id, bucket_id, weight, member_call_id, destination, node_id, sticky_agent_id, list_communication_id)
    values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id::varchar,
            jsonb_build_object('destination', _con_name, 'name', _client_name, 'msg', _last_msg, 'chat', _con_type),
            _node_name, _sticky_agent_id, (select clc.id
                                           from call_center.cc_list_communications clc
                                           where (clc.list_id = dnc_list_id_ and clc.number = _conversation_id)))
    returning * into _attempt;


    return row(
        _attempt.id::int8,
        _attempt.queue_id::int,
        _queue_updated_at::int8,
        _attempt.destination::jsonb,
                coalesce((variables_::jsonb), '{}'::jsonb) || jsonb_build_object('inviter_channel_id', _inviter_channel_id) || jsonb_build_object('inviter_user_id', _inviter_user_id),
        _conversation_id::varchar,
        _team_updated_at::int8,

        _conversation_id::varchar,
        call_center.cc_view_timestamp(_con_created)::int8
        );
END;
$$;



--
-- Name: cc_jsonb_show_fields(jsonb, character varying[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_jsonb_show_fields(j jsonb, keys character varying[]) RETURNS jsonb
    LANGUAGE sql
AS $$select json_object_agg(key, value)
     from jsonb_each(j)
     where key = any(keys)$$;



--
-- Name: cc_offline_members_ids(bigint, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_offline_members_ids(_domain_id bigint, _agent_id integer, _lim integer) RETURNS SETOF bigint
    LANGUAGE plpgsql IMMUTABLE
AS $$
begin
    return query
        with queues as (
            select  q_1.domain_id,
                    q_1.id,
                    q_1.calendar_id,
                    q_1.type,
                    q_1.sticky_agent,
                    q_1.recall_calendar,
                    CASE
                        WHEN q_1.sticky_agent THEN COALESCE(((q_1.payload -> 'sticky_agent_sec'::text))::integer, 30)
                        ELSE NULL::integer
                        END AS sticky_agent_sec,
                    CASE
                        WHEN ((q_1.strategy)::text = 'lifo'::text) THEN 1
                        WHEN ((q_1.strategy)::text = 'strict_fifo'::text) THEN 2
                        ELSE 0
                        END AS strategy,
                    q_1.priority,
                    q_1.team_id,
                    ((q_1.payload -> 'max_calls'::text))::integer AS lim,
                    ((q_1.payload -> 'wait_between_retries_desc'::text))::boolean AS wait_between_retries_desc,
                    COALESCE(((q_1.payload -> 'strict_circuit'::text))::boolean, false) AS strict_circuit,
                    array_agg(ROW((m.bucket_id)::integer, (m.member_waiting)::integer, m.op)::call_center.cc_sys_distribute_bucket ORDER BY cbiq.priority DESC NULLS LAST, cbiq.ratio DESC NULLS LAST, m.bucket_id)
                    filter ( where  coalesce(m.bucket_id, 0) = any(bb.bb)) AS buckets,
                    m.op
            FROM ((( WITH mem AS MATERIALIZED (
                SELECT a.queue_id,
                       a.bucket_id,
                       count(*) AS member_waiting,
                       false AS op
                FROM call_center.cc_member_attempt a
                WHERE ((a.bridged_at IS NULL) AND (a.leaving_at IS NULL) AND ((a.state)::text = 'wait_agent'::text))
                GROUP BY a.queue_id, a.bucket_id
                UNION ALL
                SELECT q_2.queue_id,
                       q_2.bucket_id,
                       q_2.member_waiting,
                       true AS op
                FROM call_center.cc_queue_statistics q_2
                WHERE (q_2.member_waiting > 0)
            )
                     SELECT rank() OVER (PARTITION BY mem.queue_id ORDER BY mem.op) AS pos,
                            mem.queue_id,
                            mem.bucket_id,
                            mem.member_waiting,
                            mem.op
                     FROM mem) m
                JOIN call_center.cc_queue q_1 ON ((q_1.id = m.queue_id)))
                LEFT JOIN call_center.cc_bucket_in_queue cbiq ON (((cbiq.queue_id = m.queue_id) AND (cbiq.bucket_id = m.bucket_id))))
                     cross join lateral (
                select cqs.queue_id, array_agg(distinct coalesce(bb, 0)) bb
                from call_center.cc_skill_in_agent sa
                         inner join call_center.cc_queue_skill cqs on cqs.skill_id = sa.skill_id
                    and sa.capacity between cqs.min_capacity and cqs.max_capacity
                         left join lateral unnest(cqs.bucket_ids) bb on true
                where  sa.enabled and cqs.enabled and sa.agent_id = _agent_id
                group by 1
                ) bb
            WHERE ((m.member_waiting > 0) AND q_1.enabled AND  (m.pos = 1) AND ((cbiq.bucket_id IS NULL) OR (NOT cbiq.disabled)))
              and q_1.type = 0
              and q_1.domain_id = _domain_id
              and q_1.id = bb.queue_id
            GROUP BY q_1.domain_id, q_1.id, q_1.calendar_id, q_1.type, m.op
        ), calend AS MATERIALIZED (
            SELECT c.id AS calendar_id,
                   queues.id AS queue_id,
                   CASE
                       WHEN (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) THEN ((array_agg(DISTINCT o1.id))::int2[] + (tz.offset_id)::int2)
                       ELSE (array_agg(DISTINCT o1.id))::int2[]
                       END AS l,
                   (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) AS recall_calendar
            FROM ((((flow.calendar c
                LEFT JOIN flow.calendar_timezones tz ON ((tz.id = c.timezone_id)))
                JOIN queues ON ((queues.calendar_id = c.id)))
                JOIN LATERAL unnest(c.accepts) a(disabled, day, start_time_of_day, end_time_of_day) ON (true))
                JOIN flow.calendar_timezone_offsets o1 ON ((((a.day + 1) = (date_part('isodow'::text, timezone(o1.names[1], now())))::integer) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) >= a.start_time_of_day) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) <= a.end_time_of_day))))
            WHERE (NOT (a.disabled IS TRUE))
            GROUP BY c.id, queues.id, queues.recall_calendar, tz.offset_id
        ), resources AS MATERIALIZED (
            SELECT l_1.queue_id,
                   array_agg(ROW(cor.communication_id, (cor.id)::bigint, ((l_1.l & (l2.x)::integer[]))::smallint[], (cor.resource_group_id)::integer)::call_center.cc_sys_distribute_type) AS types,
                   array_agg(ROW((cor.id)::bigint, ((cor."limit" - used.cnt))::integer, cor.patterns)::call_center.cc_sys_distribute_resource) AS resources,
                   call_center.cc_array_merge_agg((l_1.l & (l2.x)::integer[])) AS offset_ids
            FROM (((calend l_1
                JOIN ( SELECT corg.queue_id,
                              corg.priority,
                              corg.resource_group_id,
                              corg.communication_id,
                              corg."time",
                              (corg.cor).id AS id,
                              (corg.cor)."limit" AS "limit",
                              (corg.cor).enabled AS enabled,
                              (corg.cor).updated_at AS updated_at,
                              (corg.cor).rps AS rps,
                              (corg.cor).domain_id AS domain_id,
                              (corg.cor).reserve AS reserve,
                              (corg.cor).variables AS variables,
                              (corg.cor).number AS number,
                              (corg.cor).max_successively_errors AS max_successively_errors,
                              (corg.cor).name AS name,
                              (corg.cor).last_error_id AS last_error_id,
                              (corg.cor).successively_errors AS successively_errors,
                              (corg.cor).created_at AS created_at,
                              (corg.cor).created_by AS created_by,
                              (corg.cor).updated_by AS updated_by,
                              (corg.cor).error_ids AS error_ids,
                              (corg.cor).gateway_id AS gateway_id,
                              (corg.cor).email_profile_id AS email_profile_id,
                              (corg.cor).payload AS payload,
                              (corg.cor).description AS description,
                              (corg.cor).patterns AS patterns,
                              (corg.cor).failure_dial_delay AS failure_dial_delay,
                              (corg.cor).last_error_at AS last_error_at
                       FROM (calend calend_1
                           JOIN ( SELECT DISTINCT cqr.queue_id,
                                                  corig.priority,
                                                  corg_1.id AS resource_group_id,
                                                  corg_1.communication_id,
                                                  corg_1."time",
                                                  CASE
                                                      WHEN (cor_1.enabled AND gw.enable) THEN ROW(cor_1.id, cor_1."limit", cor_1.enabled, cor_1.updated_at, cor_1.rps, cor_1.domain_id, cor_1.reserve, cor_1.variables, cor_1.number, cor_1.max_successively_errors, cor_1.name, cor_1.last_error_id, cor_1.successively_errors, cor_1.created_at, cor_1.created_by, cor_1.updated_by, cor_1.error_ids, cor_1.gateway_id, cor_1.email_profile_id, cor_1.payload, cor_1.description, cor_1.patterns, cor_1.failure_dial_delay, cor_1.last_error_at, NULL::jsonb)::call_center.cc_outbound_resource
                                                      WHEN (cor2.enabled AND gw2.enable) THEN ROW(cor2.id, cor2."limit", cor2.enabled, cor2.updated_at, cor2.rps, cor2.domain_id, cor2.reserve, cor2.variables, cor2.number, cor2.max_successively_errors, cor2.name, cor2.last_error_id, cor2.successively_errors, cor2.created_at, cor2.created_by, cor2.updated_by, cor2.error_ids, cor2.gateway_id, cor2.email_profile_id, cor2.payload, cor2.description, cor2.patterns, cor2.failure_dial_delay, cor2.last_error_at, NULL::jsonb)::call_center.cc_outbound_resource
                                                      ELSE NULL::call_center.cc_outbound_resource
                                                      END AS cor
                                  FROM ((((((call_center.cc_queue_resource cqr
                                      JOIN call_center.cc_outbound_resource_group corg_1 ON ((cqr.resource_group_id = corg_1.id)))
                                      JOIN call_center.cc_outbound_resource_in_group corig ON ((corg_1.id = corig.group_id)))
                                      JOIN call_center.cc_outbound_resource cor_1 ON ((cor_1.id = (corig.resource_id)::integer)))
                                      JOIN directory.sip_gateway gw ON ((gw.id = cor_1.gateway_id)))
                                      LEFT JOIN call_center.cc_outbound_resource cor2 ON (((cor2.id = corig.reserve_resource_id) AND cor2.enabled)))
                                      LEFT JOIN directory.sip_gateway gw2 ON (((gw2.id = cor2.gateway_id) AND cor2.enabled)))
                                  WHERE (
                                            CASE
                                                WHEN (cor_1.enabled AND gw.enable) THEN cor_1.id
                                                WHEN (cor2.enabled AND gw2.enable) THEN cor2.id
                                                ELSE NULL::integer
                                                END IS NOT NULL)
                                  ORDER BY cqr.queue_id, corig.priority DESC) corg ON ((corg.queue_id = calend_1.queue_id)))) cor ON ((cor.queue_id = l_1.queue_id)))
                JOIN LATERAL ( WITH times AS (
                    SELECT ((e.value -> 'start_time_of_day'::text))::integer AS start,
                           ((e.value -> 'end_time_of_day'::text))::integer AS "end"
                    FROM jsonb_array_elements(cor."time") e(value)
                )
                               SELECT array_agg(DISTINCT t.id) AS x
                               FROM flow.calendar_timezone_offsets t,
                                    times,
                                    LATERAL ( SELECT timezone(t.names[1], CURRENT_TIMESTAMP) AS t) with_timezone
                               WHERE ((((to_char(with_timezone.t, 'SSSS'::text))::integer / 60) >= times.start) AND (((to_char(with_timezone.t, 'SSSS'::text))::integer / 60) <= times."end"))) l2 ON ((l2.* IS NOT NULL)))
                LEFT JOIN LATERAL ( SELECT count(*) AS cnt
                                    FROM ( SELECT 1 AS cnt
                                           FROM call_center.cc_member_attempt c_1
                                           WHERE ((c_1.resource_id = cor.id) AND ((c_1.state)::text <> ALL (ARRAY[('leaving'::character varying)::text, ('processing'::character varying)::text])))) c) used ON (true))
            WHERE (cor.enabled AND ((cor.last_error_at IS NULL) OR (cor.last_error_at <= (now() - ((cor.failure_dial_delay || ' s'::text))::interval))) AND ((cor."limit" - used.cnt) > 0))
            GROUP BY l_1.queue_id
        )
           , request as  (
            SELECT distinct q.id,
                            (q.strategy)::int2 AS strategy,
                            q.team_id,
                            bs.bucket_id::int as bucket_id,
                            r.types,
                            r.resources,
                            q.priority,
                            q.sticky_agent,
                            q.sticky_agent_sec,
                            calend.recall_calendar,
                            q.wait_between_retries_desc,
                            q.strict_circuit,
                            calend.l
            FROM (((queues q
                LEFT JOIN calend ON ((calend.queue_id = q.id)))
                LEFT JOIN resources r ON ((q.op AND (r.queue_id = q.id))))
                LEFT JOIN LATERAL ( SELECT count(*) AS usage
                                    FROM call_center.cc_member_attempt a
                                    WHERE ((a.queue_id = q.id) AND ((a.state)::text <> 'leaving'::text))) l ON ((q.lim > 0)))
                     join lateral unnest(q.buckets) bs on true
            where r.* IS NOT NULL
        )
        select x
        from request
                 left join lateral call_center.cc_distribute_members_list(request.id::int, request.bucket_id::int,
                                                                          request.strategy::int2, request.wait_between_retries_desc, request.l::int2[], _lim::int) x on true
        order by request.priority desc
        limit _lim;
end
$$;



--
-- Name: cc_set_active_members(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer, communication_idx integer, timezone character varying)
    LANGUAGE plpgsql
AS $$
BEGIN
    return query update call_center.cc_member_attempt a
        set state = case when c.member_id isnull then 'leaving' else
            case when c.queue_type in (3, 4) then 'offering' else 'waiting' end
            end
            ,node_id = node
            ,last_state_change = now()
            ,list_communication_id = lc.id
            ,seq = coalesce(c.attempts, -1) + 1
            ,waiting_other_numbers = coalesce(c.waiting_other_numbers, 0)
            ,result = case when c.member_id isnull then 'cancel' else a.result end
            ,leaving_at = case when c.member_id isnull then now() end
        from (
            select c.id,
                   cq.updated_at                                            as queue_updated_at,
                   r.updated_at::bigint as resource_updated_at,
                   call_center.cc_view_timestamp(gw.updated_at at time zone 'utc')::bigint             as gateway_updated_at,
                   c.destination                                            as destination,
                   cm.variables                                             as variables,
                   cm.name                                                  as member_name,
                   c.state                                                  as state,
                   cqs.member_count                                         as queue_cnt,
                   0                                                        as queue_active_cnt,
                   cqs.member_waiting                                       as queue_waiting_cnt,
                   (ca.updated_at - extract(epoch from u.updated_at))::int8 as agent_updated_at,
                   tm.updated_at                                            as team_updated_at,
                   cq.dnc_list_id,
                   cm.attempts,
                   x.cnt                                                    as waiting_other_numbers,
                   cq.type                                                  as queue_type,
                   cm.id as member_id,
                   tz.sys_name::varchar as member_timezone
            from call_center.cc_member_attempt c
                     left join call_center.cc_member cm on c.member_id = cm.id
                     left join lateral (
                select count(*) cnt
                from jsonb_array_elements(cm.communications) WITH ORDINALITY AS x(c, n)
                where coalesce((x.c -> 'stop_at')::int8, 0) < 1
                  and x.n != (c.communication_idx + 1)
                ) x on c.member_id notnull
                     inner join call_center.cc_queue cq on c.queue_id = cq.id
                     left join call_center.cc_team tm on tm.id = c.team_id
                     left join call_center.cc_outbound_resource r on r.id = c.resource_id
                     left join directory.sip_gateway gw on gw.id = r.gateway_id
                     left join call_center.cc_agent ca on c.agent_id = ca.id
                     left join call_center.cc_queue_statistics cqs on cq.id = cqs.queue_id
                     left join directory.wbt_user u on u.id = ca.user_id
                     left join flow.calendar cr on cr.id = cq.calendar_id
                     left join flow.calendar_timezones tz on tz.id = coalesce(cm.timezone_id, cr.timezone_id)
            where c.state = 'idle'
              and c.leaving_at isnull
            order by cq.priority desc, c.weight desc
                for update of c, cq skip locked
        ) c
            left join call_center.cc_list_communications lc on lc.list_id = c.dnc_list_id and
                                                               lc.number = c.destination ->> 'destination'
        where a.id = c.id --and node = 'call_center-igor'
        returning
            a.id::bigint as id,
            a.member_id::bigint as member_id,
            a.result as result,
            a.queue_id::int as qeueue_id,
            c.queue_updated_at::bigint as queue_updated_at,
            c.queue_cnt::int,
            c.queue_active_cnt::int,
            c.queue_waiting_cnt::int,
            a.resource_id::int as resource_id,
            greatest(c.resource_updated_at::bigint, c.gateway_updated_at::bigint) as resource_updated_at,
            greatest(c.resource_updated_at::bigint, c.gateway_updated_at::bigint) as gateway_updated_at,
            c.destination,
            coalesce(c.variables, '{}') ,
            coalesce(c.member_name, ''),
            a.member_call_id,
            a.agent_id,
            c.agent_updated_at,
            c.team_updated_at,
            a.list_communication_id,
            a.seq,
            a.communication_idx,
            c.member_timezone;
END;
$$;


alter table call_center.cc_team add column if not exists task_accept_timeout smallint DEFAULT 30 NOT NULL;
alter table call_center.cc_calls_history add column if not exists search_number text;




drop materialized view call_center.cc_agent_today_stats;
--
-- Name: cc_agent_today_stats; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_agent_today_stats AS
WITH agents AS MATERIALIZED (
    SELECT a_1.id,
           usr.id AS user_id,
           CASE
               WHEN (a_1.last_state_change < (d."from")::timestamp with time zone) THEN (d."from")::timestamp with time zone
               WHEN (a_1.last_state_change < d."to") THEN a_1.last_state_change
               ELSE a_1.last_state_change
               END AS cur_state_change,
           a_1.status,
           a_1.status_payload,
           a_1.last_state_change,
           (lasts.last_at)::timestamp with time zone AS last_at,
           lasts.state AS last_state,
           lasts.status_payload AS last_payload,
           COALESCE(top.top_at, a_1.last_state_change) AS top_at,
           COALESCE(top.state, a_1.status) AS top_state,
           COALESCE(top.status_payload, a_1.status_payload) AS top_payload,
           d."from",
           d."to",
           usr.dc AS domain_id,
           COALESCE(t.sys_name, 'UTC'::text) AS tz_name
    FROM ((((((call_center.cc_agent a_1
        RIGHT JOIN directory.wbt_user usr ON ((usr.id = a_1.user_id)))
        LEFT JOIN flow.region r ON ((r.id = a_1.region_id)))
        LEFT JOIN flow.calendar_timezones t ON ((t.id = r.timezone_id)))
        LEFT JOIN LATERAL ( SELECT now() AS "to",
                                   ((now())::date + age(now(), (timezone(COALESCE(t.sys_name, 'UTC'::text), now()))::timestamp with time zone)) AS "from") d ON (true))
        LEFT JOIN LATERAL ( SELECT aa.state,
                                   d."from" AS last_at,
                                   aa.payload AS status_payload
                            FROM call_center.cc_agent_state_history aa
                            WHERE ((aa.agent_id = a_1.id) AND (aa.channel IS NULL) AND ((aa.state)::text = ANY (ARRAY[('pause'::character varying)::text, ('online'::character varying)::text, ('offline'::character varying)::text])) AND (aa.joined_at < (d."from")::timestamp with time zone))
                            ORDER BY aa.joined_at DESC
                            LIMIT 1) lasts ON ((a_1.last_state_change > d."from")))
        LEFT JOIN LATERAL ( SELECT a2.state,
                                   d."to" AS top_at,
                                   a2.payload AS status_payload
                            FROM call_center.cc_agent_state_history a2
                            WHERE ((a2.agent_id = a_1.id) AND (a2.channel IS NULL) AND ((a2.state)::text = ANY (ARRAY[('pause'::character varying)::text, ('online'::character varying)::text, ('offline'::character varying)::text])) AND (a2.joined_at > d."to"))
                            ORDER BY a2.joined_at
                            LIMIT 1) top ON (true))
), d AS MATERIALIZED (
    SELECT x.agent_id,
           x.joined_at,
           x.state,
           x.payload
    FROM ( SELECT a_1.agent_id,
                  a_1.joined_at,
                  a_1.state,
                  a_1.payload
           FROM call_center.cc_agent_state_history a_1,
                agents
           WHERE ((a_1.agent_id = agents.id) AND (a_1.joined_at >= agents."from") AND (a_1.joined_at <= agents."to") AND (a_1.channel IS NULL) AND ((a_1.state)::text = ANY (ARRAY[('pause'::character varying)::text, ('online'::character varying)::text, ('offline'::character varying)::text])))
           UNION
           SELECT agents.id,
                  agents.cur_state_change,
                  agents.status,
                  agents.status_payload
           FROM agents
           WHERE (1 = 1)) x
    ORDER BY x.joined_at DESC
), s AS MATERIALIZED (
    SELECT d.agent_id,
           d.joined_at,
           d.state,
           d.payload,
           (COALESCE(lag(d.joined_at) OVER (PARTITION BY d.agent_id ORDER BY d.joined_at DESC), now()) - d.joined_at) AS dur
    FROM d
    ORDER BY d.joined_at DESC
), eff AS (
    SELECT h.agent_id,
           sum((COALESCE(h.reporting_at, h.leaving_at) - h.bridged_at)) FILTER (WHERE (h.bridged_at IS NOT NULL)) AS aht,
           sum((h.reporting_at - h.leaving_at)) FILTER (WHERE ((h.reporting_at IS NOT NULL) AND ((h.reporting_at - h.leaving_at) > '00:00:00'::interval))) AS processing,
           sum(((h.reporting_at - h.leaving_at) - ((q.processing_sec || 's'::text))::interval)) FILTER (WHERE ((h.reporting_at IS NOT NULL) AND q.processing AND ((h.reporting_at - h.leaving_at) > (((q.processing_sec + 1) || 's'::text))::interval))) AS tpause
    FROM ((agents
        JOIN call_center.cc_member_attempt_history h ON ((h.agent_id = agents.id)))
        LEFT JOIN call_center.cc_queue q ON ((q.id = h.queue_id)))
    WHERE ((h.domain_id = agents.domain_id) AND (h.joined_at >= (agents."from")::timestamp with time zone) AND (h.joined_at <= agents."to") AND ((h.channel)::text = 'call'::text))
    GROUP BY h.agent_id
), attempts AS (
    SELECT cma.agent_id,
           count(*) FILTER (WHERE ((cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = 'chat'::text))) AS chat_accepts,
           (avg(EXTRACT(epoch FROM (COALESCE(cma.reporting_at, cma.leaving_at) - cma.bridged_at))) FILTER (WHERE ((cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = 'chat'::text))))::bigint AS chat_aht,
           count(*) FILTER (WHERE ((cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = 'task'::text))) AS task_accepts
    FROM (agents
        JOIN call_center.cc_member_attempt_history cma ON ((cma.agent_id = agents.id)))
    WHERE ((cma.joined_at >= (agents."from")::timestamp with time zone) AND (cma.joined_at <= agents."to") AND (cma.domain_id = agents.domain_id) AND (cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = ANY (ARRAY['chat'::text, 'task'::text])))
    GROUP BY cma.agent_id
), calls AS (
    SELECT h.user_id,
           count(*) FILTER (WHERE ((h.direction)::text = 'inbound'::text)) AS all_inb,
           count(*) FILTER (WHERE (h.bridged_at IS NOT NULL)) AS handled,
           count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.bridged_at IS NOT NULL))) AS inbound_bridged,
           count(*) FILTER (WHERE ((cq.type = 1) AND (h.bridged_at IS NOT NULL) AND (h.parent_id IS NOT NULL))) AS "inbound queue",
           count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.queue_id IS NULL))) AS "direct inbound",
           count(*) FILTER (WHERE ((h.parent_id IS NOT NULL) AND (h.bridged_at IS NOT NULL) AND (h.queue_id IS NULL) AND (pc.user_id IS NOT NULL))) AS internal_inb,
           count(*) FILTER (WHERE ((h.bridged_at IS NOT NULL) AND (h.queue_id IS NULL) AND (pc.user_id IS NOT NULL))) AS user_2user,
           count(*) FILTER (WHERE ((((h.direction)::text = 'inbound'::text) OR (cq.type = 3)) AND (h.bridged_at IS NULL))) AS missed,
           count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.bridged_at IS NULL) AND (h.queue_id IS NOT NULL) AND ((h.cause)::text = ANY (ARRAY[('NO_ANSWER'::character varying)::text, ('USER_BUSY'::character varying)::text])))) AS abandoned,
           count(*) FILTER (WHERE ((cq.type = ANY (ARRAY[(0)::smallint, (3)::smallint, (4)::smallint, (5)::smallint])) AND (h.bridged_at IS NOT NULL))) AS outbound_queue,
           count(*) FILTER (WHERE ((h.parent_id IS NULL) AND ((h.direction)::text = 'outbound'::text) AND (h.queue_id IS NULL))) AS "direct outboud",
           sum((h.hangup_at - h.created_at)) FILTER (WHERE (((h.direction)::text = 'outbound'::text) AND (h.queue_id IS NULL))) AS direct_out_dur,
           avg((h.hangup_at - h.bridged_at)) FILTER (WHERE ((h.bridged_at IS NOT NULL) AND ((h.direction)::text = 'inbound'::text) AND (h.parent_id IS NOT NULL))) AS "avg bill inbound",
           avg((h.hangup_at - h.bridged_at)) FILTER (WHERE ((h.bridged_at IS NOT NULL) AND ((h.direction)::text = 'outbound'::text))) AS "avg bill outbound",
           sum((h.hangup_at - h.bridged_at)) FILTER (WHERE (h.bridged_at IS NOT NULL)) AS "sum bill",
           avg((h.hangup_at - h.bridged_at)) FILTER (WHERE (h.bridged_at IS NOT NULL)) AS avg_talk,
           sum(((h.hold_sec || ' sec'::text))::interval) AS "sum hold",
           avg(((h.hold_sec || ' sec'::text))::interval) FILTER (WHERE (h.hold_sec > 0)) AS avg_hold,
           sum((COALESCE(h.answered_at, h.bridged_at, h.hangup_at) - h.created_at)) AS "Call initiation",
           sum((h.hangup_at - h.bridged_at)) FILTER (WHERE (h.bridged_at IS NOT NULL)) AS "Talk time",
           sum((h.hangup_at - h.bridged_at)) FILTER (WHERE ((h.bridged_at IS NOT NULL) AND (h.queue_id IS NOT NULL))) AS queue_talk_sec,
           sum((cc.reporting_at - cc.leaving_at)) FILTER (WHERE (cc.reporting_at IS NOT NULL)) AS "Post call",
           sum((h.hangup_at - h.bridged_at)) FILTER (WHERE ((h.bridged_at IS NOT NULL) AND ((cc.description)::text = 'Voice mail'::text))) AS vm
    FROM ((((agents
        JOIN call_center.cc_calls_history h ON ((h.user_id = agents.user_id)))
        LEFT JOIN call_center.cc_queue cq ON ((h.queue_id = cq.id)))
        LEFT JOIN call_center.cc_member_attempt_history cc ON (((cc.agent_call_id)::text = (h.id)::text)))
        LEFT JOIN call_center.cc_calls_history pc ON (((pc.id = h.parent_id) AND (pc.created_at > ((now())::date - '2 days'::interval)))))
    WHERE ((h.domain_id = agents.domain_id) AND (h.created_at > ((now())::date - '2 days'::interval)) AND (h.created_at >= (agents."from")::timestamp with time zone) AND (h.created_at <= agents."to"))
    GROUP BY h.user_id
), stats AS MATERIALIZED (
    SELECT s.agent_id,
           min(s.joined_at) FILTER (WHERE ((s.state)::text = ANY (ARRAY[('online'::character varying)::text, ('pause'::character varying)::text]))) AS login,
           max(s.joined_at) FILTER (WHERE ((s.state)::text = 'offline'::text)) AS logout,
           sum(s.dur) FILTER (WHERE ((s.state)::text = ANY (ARRAY[('online'::character varying)::text, ('pause'::character varying)::text]))) AS online,
           sum(s.dur) FILTER (WHERE ((s.state)::text = 'pause'::text)) AS pause,
           sum(s.dur) FILTER (WHERE (((s.state)::text = 'pause'::text) AND ((s.payload)::text = 'Навчання'::text))) AS study,
           sum(s.dur) FILTER (WHERE (((s.state)::text = 'pause'::text) AND ((s.payload)::text = 'Нарада'::text))) AS conference,
           sum(s.dur) FILTER (WHERE (((s.state)::text = 'pause'::text) AND ((s.payload)::text = 'Обід'::text))) AS lunch,
           sum(s.dur) FILTER (WHERE (((s.state)::text = 'pause'::text) AND ((s.payload)::text = 'Технічна перерва'::text))) AS tech
    FROM (((s
        LEFT JOIN agents ON ((agents.id = s.agent_id)))
        LEFT JOIN eff eff_1 ON ((eff_1.agent_id = s.agent_id)))
        LEFT JOIN calls ON ((calls.user_id = agents.user_id)))
    GROUP BY s.agent_id
), rate AS (
    SELECT a_1.user_id,
           count(*) AS count,
           avg(ar.score_required) AS score_required_avg,
           sum(ar.score_required) AS score_required_sum,
           avg(ar.score_optional) AS score_optional_avg,
           sum(ar.score_optional) AS score_optional_sum
    FROM (agents a_1
        JOIN call_center.cc_audit_rate ar ON ((ar.rated_user_id = a_1.user_id)))
    WHERE ((ar.created_at >= (date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) AT TIME ZONE a_1.tz_name)) AND (ar.created_at <= (((date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) + '1 mon'::interval) - '1 day 00:00:01'::interval) AT TIME ZONE a_1.tz_name)))
    GROUP BY a_1.user_id
)
SELECT a.id AS agent_id,
       a.user_id,
       a.domain_id,
       COALESCE(c.missed, (0)::bigint) AS call_missed,
       COALESCE(c.abandoned, (0)::bigint) AS call_abandoned,
       COALESCE(c.inbound_bridged, (0)::bigint) AS call_inbound,
       COALESCE(c.handled, (0)::bigint) AS call_handled,
       COALESCE((EXTRACT(epoch FROM c.avg_talk))::bigint, (0)::bigint) AS avg_talk_sec,
       COALESCE((EXTRACT(epoch FROM c.avg_hold))::bigint, (0)::bigint) AS avg_hold_sec,
       COALESCE((EXTRACT(epoch FROM c."Talk time"))::bigint, (0)::bigint) AS sum_talk_sec,
       COALESCE((EXTRACT(epoch FROM c.queue_talk_sec))::bigint, (0)::bigint) AS queue_talk_sec,
       LEAST(round(COALESCE(
                           CASE
                               WHEN ((stats.online > '00:00:00'::interval) AND (EXTRACT(epoch FROM (stats.online - COALESCE(stats.lunch, '00:00:00'::interval))) > (0)::numeric)) THEN (((((((COALESCE(EXTRACT(epoch FROM c."Call initiation"), (0)::numeric) + COALESCE(EXTRACT(epoch FROM c."Talk time"), (0)::numeric)) + COALESCE(EXTRACT(epoch FROM c."Post call"), (0)::numeric)) - COALESCE(EXTRACT(epoch FROM eff.tpause), (0)::numeric)) + EXTRACT(epoch FROM COALESCE(stats.study, '00:00:00'::interval))) + EXTRACT(epoch FROM COALESCE(stats.conference, '00:00:00'::interval))) / EXTRACT(epoch FROM (stats.online - COALESCE(stats.lunch, '00:00:00'::interval)))) * (100)::numeric)
                               ELSE (0)::numeric
                               END, (0)::numeric), 2), (100)::numeric) AS occupancy,
       round(COALESCE(
                     CASE
                         WHEN (stats.online > '00:00:00'::interval) THEN ((EXTRACT(epoch FROM (stats.online - COALESCE(stats.pause, '00:00:00'::interval))) / EXTRACT(epoch FROM stats.online)) * (100)::numeric)
                         ELSE (0)::numeric
                         END, (0)::numeric), 2) AS utilization,
       (GREATEST(round(COALESCE(
                               CASE
                                   WHEN ((stats.online > '00:00:00'::interval) AND (EXTRACT(epoch FROM (stats.online - COALESCE(stats.lunch, '00:00:00'::interval))) > (0)::numeric)) THEN (EXTRACT(epoch FROM (stats.online - COALESCE(stats.lunch, '00:00:00'::interval))) - (((((COALESCE(EXTRACT(epoch FROM c."Call initiation"), (0)::numeric) + COALESCE(EXTRACT(epoch FROM c."Talk time"), (0)::numeric)) + COALESCE(EXTRACT(epoch FROM c."Post call"), (0)::numeric)) - COALESCE(EXTRACT(epoch FROM eff.tpause), (0)::numeric)) + EXTRACT(epoch FROM COALESCE(stats.study, '00:00:00'::interval))) + EXTRACT(epoch FROM COALESCE(stats.conference, '00:00:00'::interval))))
                                   ELSE (0)::numeric
                                   END, (0)::numeric), 2), (0)::numeric))::integer AS available,
       COALESCE((EXTRACT(epoch FROM c.vm))::bigint, (0)::bigint) AS voice_mail,
       COALESCE(ch.chat_aht, (0)::bigint) AS chat_aht,
       (((COALESCE(ch.task_accepts, (0)::bigint) + COALESCE(ch.chat_accepts, (0)::bigint)) + COALESCE(c.handled, (0)::bigint)) - COALESCE(c.user_2user, (0)::bigint)) AS task_accepts,
       (COALESCE(EXTRACT(epoch FROM (stats.online - COALESCE(stats.lunch, '00:00:00'::interval))), (0)::numeric))::bigint AS online,
       COALESCE(ch.chat_accepts, (0)::bigint) AS chat_accepts,
       COALESCE(rate.count, (0)::bigint) AS score_count,
       (COALESCE(EXTRACT(epoch FROM eff.processing), ((0)::bigint)::numeric))::integer AS processing,
       COALESCE(rate.score_optional_avg, (0)::numeric) AS score_optional_avg,
       COALESCE(rate.score_optional_sum, ((0)::bigint)::numeric) AS score_optional_sum,
       COALESCE(rate.score_required_avg, (0)::numeric) AS score_required_avg,
       COALESCE(rate.score_required_sum, ((0)::bigint)::numeric) AS score_required_sum
FROM ((((((agents a
    LEFT JOIN call_center.cc_agent_with_user u ON ((u.id = a.id)))
    LEFT JOIN stats ON ((stats.agent_id = a.id)))
    LEFT JOIN eff ON ((eff.agent_id = a.id)))
    LEFT JOIN calls c ON ((c.user_id = a.user_id)))
    LEFT JOIN attempts ch ON ((ch.agent_id = a.id)))
    LEFT JOIN rate ON ((rate.user_id = a.user_id)))
WITH NO DATA;


--
-- Name: cc_agent_today_stats_usr_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_usr_uidx ON call_center.cc_agent_today_stats USING btree (user_id);


refresh materialized view call_center.cc_agent_today_stats;



drop view call_center.cc_calls_history_list;
--
-- Name: cc_calls_history_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_calls_history_list AS
SELECT c.id,
       c.app_id,
       'call'::character varying AS type,
       c.parent_id,
       c.transfer_from,
       CASE
           WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND ((c.id)::text <> (lega.bridged_id)::text)) THEN lega.bridged_id
           ELSE c.transfer_to
           END AS transfer_to,
       call_center.cc_get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS "user",
       CASE
           WHEN (cq.type = ANY (ARRAY[4, 5])) THEN cag.extension
           ELSE u.extension
           END AS extension,
       call_center.cc_get_lookup(gw.id, gw.name) AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number', COALESCE(c.from_number, ''::character varying), 'id', COALESCE(c.from_id, ''::character varying), 'name', COALESCE(c.from_name, ''::character varying)) AS "from",
       json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number', COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying), 'name', COALESCE(c.to_name, ''::character varying)) AS "to",
       c.payload AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       c.stored_at,
       COALESCE(c.hangup_by, ''::character varying) AS hangup_by,
       c.cause,
       (date_part('epoch'::text, (c.hangup_at - c.created_at)))::bigint AS duration,
       COALESCE(c.hold_sec, 0) AS hold_sec,
       COALESCE(
               CASE
                   WHEN (c.answered_at IS NOT NULL) THEN (date_part('epoch'::text, (c.answered_at - c.created_at)))::bigint
                   ELSE (date_part('epoch'::text, (c.hangup_at - c.created_at)))::bigint
                   END, (0)::bigint) AS wait_sec,
       CASE
           WHEN (c.answered_at IS NOT NULL) THEN (date_part('epoch'::text, (c.hangup_at - c.answered_at)))::bigint
           ELSE (0)::bigint
           END AS bill_sec,
       c.sip_code,
       f.files,
       call_center.cc_get_lookup((cq.id)::bigint, cq.name) AS queue,
       call_center.cc_get_lookup(c.member_id, cm.name) AS member,
       call_center.cc_get_lookup(ct.id, ct.name) AS team,
       call_center.cc_get_lookup((aa.id)::bigint, (COALESCE(cag.username, (cag.name)::name))::character varying) AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at AS queue_bridged_at,
       CASE
           WHEN (cma.bridged_at IS NOT NULL) THEN (date_part('epoch'::text, (cma.bridged_at - cma.joined_at)))::integer
           ELSE (date_part('epoch'::text, (cma.leaving_at - cma.joined_at)))::integer
           END AS queue_wait_sec,
       (date_part('epoch'::text, (cma.leaving_at - cma.joined_at)))::integer AS queue_duration_sec,
       cma.result,
       CASE
           WHEN (cma.reporting_at IS NOT NULL) THEN (date_part('epoch'::text, (cma.reporting_at - cma.leaving_at)))::integer
           ELSE 0
           END AS reporting_sec,
       c.agent_id,
       c.team_id,
       c.user_id,
       c.queue_id,
       c.member_id,
       c.attempt_id,
       c.domain_id,
       c.gateway_id,
       c.from_number,
       c.to_number,
       c.tags,
       cma.display,
       (EXISTS ( SELECT 1
                 FROM call_center.cc_calls_history hp
                 WHERE ((c.parent_id IS NULL) AND (hp.parent_id = c.id)))) AS has_children,
       (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), (''::character varying)::text))::character varying AS agent_description,
       c.grantee_id,
       ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
         FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                FROM call_center.cc_calls_history chh
                WHERE ((chh.parent_id = c.id) AND (chh.hold IS NOT NULL))
                UNION
                SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
         WHERE (x.hi IS NOT NULL)) AS hold,
       c.gateway_ids,
       c.user_ids,
       c.agent_ids,
       c.queue_ids,
       c.team_ids,
       ( SELECT json_agg(row_to_json(annotations.*)) AS json_agg
         FROM ( SELECT a.id,
                       a.call_id,
                       a.created_at,
                       call_center.cc_get_lookup(cc_1.id, (COALESCE(cc_1.name, (cc_1.username)::text))::character varying) AS created_by,
                       a.updated_at,
                       call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS updated_by,
                       a.note,
                       a.start_sec,
                       a.end_sec
                FROM ((call_center.cc_calls_annotation a
                    LEFT JOIN directory.wbt_user cc_1 ON ((cc_1.id = a.created_by)))
                    LEFT JOIN directory.wbt_user uc ON ((uc.id = a.updated_by)))
                WHERE ((a.call_id)::text = (c.id)::text)
                ORDER BY a.created_at DESC) annotations) AS annotations,
       COALESCE(c.amd_result, c.amd_ai_result) AS amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       c.amd_ai_positive,
       cq.type AS queue_type,
       CASE
           WHEN (c.parent_id IS NOT NULL) THEN ''::text
           WHEN ((c.cause)::text = ANY (ARRAY[('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text])) THEN 'not_answered'::text
           WHEN (((c.cause)::text = 'ORIGINATOR_CANCEL'::text) OR (((c.cause)::text = 'LOSE_RACE'::text) AND (cq.type = 4))) THEN 'cancelled'::text
           WHEN ((c.hangup_by)::text = 'F'::text) THEN 'ended'::text
           WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
               CASE
                   WHEN ((((c.cause)::text = 'NORMAL_CLEARING'::text) AND ((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND (c.user_id IS NOT NULL)) OR (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (c.bridged_at IS NOT NULL)) OR (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (cq.type = ANY (ARRAY[4, 5, 1])) AND (c.bridged_at IS NOT NULL))) THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END AS hangup_disposition,
       c.blind_transfer,
       ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error, 'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
         FROM storage.file_jobs j
         WHERE (j.file_id = ANY (f.file_ids))) AS files_job,
       ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id, 'file', call_center.cc_get_lookup(ff.id, ff.name))) AS data
         FROM (storage.file_transcript tr
             LEFT JOIN storage.files ff ON ((ff.id = tr.file_id)))
         WHERE ((tr.uuid)::text = (c.id)::text)
         GROUP BY (tr.uuid)::text) AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
       ar.id AS rate_id,
       call_center.cc_get_lookup(aru.id, COALESCE((aru.name)::character varying, (aru.username)::character varying)) AS rated_user,
       call_center.cc_get_lookup(arub.id, COALESCE((arub.name)::character varying, (arub.username)::character varying)) AS rated_by,
       ar.score_optional,
       ar.score_required,
       (EXISTS ( SELECT 1
                 FROM call_center.cc_calls_history cr
                 WHERE ((cr.id = c.bridged_id) AND (c.bridged_id IS NOT NULL) AND (c.blind_transfer IS NULL) AND (cr.blind_transfer IS NULL) AND (c.transfer_to IS NULL) AND (cr.transfer_to IS NULL) AND (c.transfer_from IS NULL) AND (cr.transfer_from IS NULL) AND (COALESCE(cr.user_id, c.user_id) IS NOT NULL)))) AS allow_evaluation,
       cma.form_fields,
       c.bridged_id,
       call_center.cc_get_lookup(cc.id, (cc.common_name)::character varying) AS contact,
       c.contact_id,
       c.search_number
FROM (((((((((((((((call_center.cc_calls_history c
    LEFT JOIN LATERAL ( SELECT array_agg(f_1.id) AS file_ids,
                               json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at', ((c.params -> 'record_start'::text))::bigint, 'stop_at', ((c.params -> 'record_stop'::text))::bigint)) AS files
                        FROM ( SELECT f1.id,
                                      f1.size,
                                      f1.mime_type,
                                      f1.name
                               FROM storage.files f1
                               WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.id)::text))
                               UNION ALL
                               SELECT f1.id,
                                      f1.size,
                                      f1.mime_type,
                                      f1.name
                               FROM storage.files f1
                               WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) f ON (((c.answered_at IS NOT NULL) OR (c.bridged_at IS NOT NULL))))
    LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
    LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
    LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
    LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
    LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
    LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
    LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
    LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
    LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
    LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND (lega.id = c.parent_id))))
    LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
    LEFT JOIN directory.wbt_user aru ON (((ar.* IS NOT NULL) AND (aru.id = ar.rated_user_id))))
    LEFT JOIN directory.wbt_user arub ON (((ar.* IS NOT NULL) AND (arub.id = ar.created_by))))
    LEFT JOIN contacts.contact cc ON ((cc.id = c.contact_id)));


alter table call_center.cc_communication add column if not exists "default" boolean DEFAULT false NOT NULL;


drop VIEW call_center.cc_communication_list;
--
-- Name: cc_communication_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_communication_list AS
SELECT c.id,
       c.name,
       c.code,
       c.description,
       c.channel,
       c."default",
       c.domain_id
FROM call_center.cc_communication c;



--
-- Name: system_settings; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE if not exists call_center.system_settings (
                                             id integer NOT NULL,
                                             domain_id bigint NOT NULL,
                                             name character varying NOT NULL,
                                             value jsonb
);


drop MATERIALIZED VIEW call_center.cc_distribute_stats;
--
-- Name: cc_distribute_stats; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_distribute_stats AS
SELECT s.queue_id,
       s.bucket_id,
       s.start_stat,
       s.stop_stat,
       s.call_attempts,
       s.avg_handle,
       s.med_handle,
       s.avg_member_answer,
       s.avg_member_answer_not_bridged,
       s.avg_member_answer_bridged,
       s.max_member_answer,
       s.connected_calls,
       s.bridged_calls,
       s.abandoned_calls,
       s.connection_rate,
       (call_center.cc_wrap_over_dial((s.over_dial)::numeric, (s.abandoned_rate)::numeric, COALESCE(((q.payload -> 'target_abandoned_rate'::text))::numeric, COALESCE(((q.payload -> 'max_abandoned_rate'::text))::numeric, 3.0)), COALESCE(((q.payload -> 'max_abandoned_rate'::text))::numeric, 3.0), COALESCE(((q.payload -> 'load_factor'::text))::numeric, 10.0)))::double precision AS over_dial,
       s.abandoned_rate,
       s.hit_rate,
       s.agents,
       s.aggent_ids
FROM (((call_center.cc_queue q
    LEFT JOIN LATERAL ( SELECT
                            CASE
                                WHEN ((jsonb_typeof(s_1.value) = 'boolean'::text) AND (s_1.value)::boolean) THEN true
                                ELSE false
                                END AS amd_cancel_not_human
                        FROM call_center.system_settings s_1
                        WHERE ((s_1.domain_id = q.domain_id) AND ((s_1.name)::text = 'amd_cancel_not_human'::text))) sys ON (true))
    LEFT JOIN LATERAL ( SELECT
                            CASE
                                WHEN sys.amd_cancel_not_human THEN tmp.v
                                ELSE (tmp.v || 'CANCEL'::text)
                                END AS arr
                        FROM ( SELECT
                                   CASE
                                       WHEN ((((q.payload -> 'amd'::text) -> 'allow_not_sure'::text))::boolean IS TRUE) THEN ARRAY['HUMAN'::text, 'NOTSURE'::text]
                                       ELSE ARRAY['HUMAN'::text]
                                       END AS v) tmp) amd ON (true))
    JOIN LATERAL ( SELECT att.queue_id,
                          att.bucket_id,
                          min(att.joined_at) AS start_stat,
                          max(att.joined_at) AS stop_stat,
                          count(*) AS call_attempts,
                          COALESCE(avg(date_part('epoch'::text, (COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))) FILTER (WHERE (att.bridged_at IS NOT NULL)), (0)::double precision) AS avg_handle,
                          COALESCE(avg(DISTINCT (round(date_part('epoch'::text, (COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))))::real) FILTER (WHERE (att.bridged_at IS NOT NULL)), (0)::double precision) AS med_handle,
                          COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE (ch.answered_at IS NOT NULL)), (0)::double precision) AS avg_member_answer,
                          COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (ch.bridged_at IS NULL))), (0)::double precision) AS avg_member_answer_not_bridged,
                          COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (ch.bridged_at IS NOT NULL))), (0)::double precision) AS avg_member_answer_bridged,
                          COALESCE(max(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE (ch.answered_at IS NOT NULL)), (0)::double precision) AS max_member_answer,
                          count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)) AS connected_calls,
                          count(*) FILTER (WHERE (att.bridged_at IS NOT NULL)) AS bridged_calls,
                          count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (att.bridged_at IS NULL) AND amd_res.human)) AS abandoned_calls,
                          ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) AS connection_rate,
                          CASE
                              WHEN (((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) > (0)::double precision) THEN ((1)::double precision / ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision))
                              ELSE (((count(*) / GREATEST(count(DISTINCT att.agent_id), (1)::bigint)) - 1))::double precision
                              END AS over_dial,
                          COALESCE(((((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (att.bridged_at IS NULL) AND amd_res.human)))::double precision - (COALESCE(((q.payload -> 'abandon_rate_adjustment'::text))::integer, 0))::double precision) / (NULLIF(count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)), 0))::double precision) * (100)::double precision), (0)::double precision) AS abandoned_rate,
                          ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) AS hit_rate,
                          count(DISTINCT att.agent_id) AS agents,
                          array_agg(DISTINCT att.agent_id) FILTER (WHERE (att.agent_id IS NOT NULL)) AS aggent_ids
                   FROM ((call_center.cc_member_attempt_history att
                       LEFT JOIN call_center.cc_calls_history ch ON (((ch.domain_id = att.domain_id) AND (ch.id = (att.member_call_id)::uuid) AND (ch.created_at > ((now())::date - '1 day'::interval)))))
                       LEFT JOIN LATERAL ( SELECT (((ch.amd_result IS NULL) AND (ch.amd_ai_positive IS NULL)) OR ((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_ai_positive IS TRUE)) AS human) amd_res ON (true))
                   WHERE (((att.channel)::text = 'call'::text) AND (att.joined_at > (now() - ((COALESCE(((q.payload -> 'statistic_time'::text))::integer, 60) || ' min'::text))::interval)) AND (att.queue_id = q.id) AND (att.domain_id = q.domain_id))
                   GROUP BY att.queue_id, att.bucket_id) s ON ((s.queue_id IS NOT NULL)))
WHERE ((q.type = 5) AND q.enabled)
WITH NO DATA;


--
-- Name: cc_distribute_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_distribute_stats_uidx ON call_center.cc_distribute_stats USING btree (queue_id, bucket_id);

refresh materialized view call_center.cc_distribute_stats;



drop VIEW call_center.cc_team_list;
--
-- Name: cc_team_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_team_list AS
SELECT t.id,
       t.name,
       t.description,
       t.strategy,
       t.max_no_answer,
       t.wrap_up_time,
       t.no_answer_delay_time,
       t.call_timeout,
       t.updated_at,
       ( SELECT jsonb_agg(adm."user") AS jsonb_agg
         FROM call_center.cc_agent_with_user adm
         WHERE (adm.id = ANY (t.admin_ids))) AS admin,
       t.domain_id,
       t.admin_ids,
       t.invite_chat_timeout,
       t.task_accept_timeout
FROM call_center.cc_team t;



drop VIEW if exists  call_center.cc_user_status_view;
--
-- Name: cc_user_status_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_user_status_view AS
SELECT u.dc AS domain_id,
       u.id,
       COALESCE(u.name, (u.username)::text) AS name,
       pr.status AS presence,
       a.status,
       COALESCE(u.extension, ''::name) AS extension,
       row_number() OVER (PARTITION BY u.dc ORDER BY
           CASE
               WHEN ((a.status)::text = 'online'::text) THEN 0
               WHEN ((a.status)::text = 'pause'::text) THEN 1
               WHEN ((a.status)::text = 'offline'::text) THEN 2
               ELSE 3
               END, pr.status, COALESCE(u.name, (u.username)::text)) AS "position"
FROM ((directory.wbt_user u
    LEFT JOIN call_center.cc_agent a ON ((a.user_id = u.id)))
    LEFT JOIN LATERAL ( SELECT array_agg(status.open) AS array_agg
                        FROM ( SELECT 'dnd'::name AS "?column?"
                               FROM directory.wbt_user_status stt
                               WHERE ((stt.user_id = u.id) AND stt.dnd)
                               UNION ALL
                               ( SELECT stt.status
                                 FROM directory.wbt_user_presence stt
                                 WHERE ((stt.user_id = u.id) AND (stt.status IS NOT NULL) AND (stt.open > 0))
                                 ORDER BY stt.prior, stt.status)) status(open)) pr(status) ON (true));



--
-- Name: systemc_settings_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE if not exists call_center.systemc_settings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: systemc_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.systemc_settings_id_seq OWNED BY call_center.system_settings.id;


--
-- Name: cc_communication cc_communication_set_def_tg; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_communication_set_def_tg BEFORE INSERT OR UPDATE ON call_center.cc_communication FOR EACH ROW WHEN (new."default") EXECUTE FUNCTION call_center.cc_communication_set_def();



ALTER TABLE ONLY call_center.cc_calls_history
    drop constraint if exists cc_calls_history_cc_queue_id_fk;



--
-- Name: cc_calls_history_sn_ops_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_sn_ops_idx ON call_center.cc_calls_history USING gin (search_number gin_trgm_ops);
