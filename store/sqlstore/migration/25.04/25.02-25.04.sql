
--
-- Name: cc_attempt_offering(bigint, integer, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_attempt_offering(attempt_id_ bigint, agent_id_ integer, agent_call_id_ character varying, member_call_id_ character varying, dest_ character varying, displ_ character varying) RETURNS record
    LANGUAGE plpgsql
AS $$declare
    attempt call_center.cc_member_attempt%rowtype;
begin

    update call_center.cc_member_attempt
    set state             = 'offering',
        last_state_change = now(),
        offered_agent_ids = case when coalesce(agent_id, agent_id_) = any (cc_member_attempt.offered_agent_ids)
                                     then cc_member_attempt.offered_agent_ids else array_append(offered_agent_ids, coalesce(agent_id, agent_id_)) end,
        display = displ_,
        offering_at       = now(),
        agent_id          = coalesce(agent_id, agent_id_),
        agent_call_id     = coalesce(agent_call_id, agent_call_id_::varchar),
        -- todo for queue preview
        member_call_id    = coalesce(member_call_id, member_call_id_)
    where id = attempt_id_
    returning * into attempt;


    if attempt.agent_id notnull then
        update call_center.cc_agent_channel ch
        set state            = 'offering',
            joined_at        = now(),
            last_offering_at = now(),
            queue_id         = attempt.queue_id,
            attempt_id         = case when attempt.channel = 'call' then attempt.id else null end,
            last_bucket_id   = coalesce(attempt.bucket_id, last_bucket_id)
        where (ch.agent_id, ch.channel) = (attempt.agent_id, attempt.channel);
    end if;

    return row (attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_distribute(boolean); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE OR REPLACE PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean)
    LANGUAGE plpgsql
AS $$begin
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
                                                   communication_idx, member_call_id, team_id, resource_group_id, domain_id, import_id, sticky_agent_id, queue_params, queue_type)
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
                   case when q.type = 5 and q.sticky_agent and m.agent_id notnull then dis.agent_id end,
                   call_center.cc_queue_params(q),
                   q.type
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
               and (q.type is null or q.type in (6, 7) or not exists(select 1 from call_center.cc_calls cc where cc.user_id = a.user_id and cc.hangup_at isnull ))
         ) t
    where t.id = a.id
      and a.agent_id isnull;

end;
$$;



--
-- Name: cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
    LANGUAGE plpgsql
AS $$declare
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
    _sticky_ignore_status bool;
    _max_waiting_size int;
    _qparams jsonb;
    _ignore_calendar bool;
BEGIN
    select c.timezone_id,
           (coalesce(payload->>'discard_abandoned_after', '0'))::int discard_abandoned_after,
           q.domain_id,
           q.dnc_list_id,
           q.calendar_id,
           q.updated_at,
           ct.updated_at,
           q.team_id,
           q.enabled,
           q.type,
           q.sticky_agent,
           (payload->>'max_waiting_size')::int max_size,
           case when jsonb_typeof(payload->'sticky_ignore_status') = 'boolean'
                    then (payload->'sticky_ignore_status')::bool else false end sticky_ignore_status,
           call_center.cc_queue_params(q),
           case when jsonb_typeof(q.payload->'ignore_calendar') = 'boolean' then (q.payload->'ignore_calendar')::bool else false end
    from call_center.cc_queue q
             left join flow.calendar c on q.calendar_id = c.id
             left join call_center.cc_team ct on q.team_id = ct.id
    where  q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _sticky_ignore_status, _qparams, _ignore_calendar;

    if not _q_type = 6 then
        raise exception 'queue type not inbound chat';
    end if;

    if not _enabled = true then
        raise exception 'queue disabled';
    end if;

    if not _calendar_id isnull  and (not _ignore_calendar and not exists(select accept
                                                                         from flow.calendar_check_timing(_domain_id, _calendar_id, null)
                                                                                  as x (name varchar, excepted varchar, accept bool, expire bool)
                                                                         where accept and excepted is null and not expire)) then
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
                        and (a.status = 'online' or _sticky_ignore_status is true)
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

    insert into call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_id, bucket_id, weight, member_call_id,
                                               destination, node_id, sticky_agent_id, list_communication_id, queue_params, queue_type)
    values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id::varchar,
            jsonb_build_object('destination', _con_name, 'name', _client_name, 'msg', _last_msg, 'chat', _con_type),
            _node_name, _sticky_agent_id, (select clc.id
                                           from call_center.cc_list_communications clc
                                           where (clc.list_id = dnc_list_id_ and clc.number = _con_name)), _qparams, 6) -- todo inbound chat queue
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
        call_center.cc_view_timestamp(_con_created)::int8,
        _attempt.list_communication_id::int8
        );
END;
$$;



--
-- Name: cc_is_lookup(text, text); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_is_lookup(_table_name text, _col_name text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
AS $$
begin
    return exists(select 1
                  from information_schema.columns
                  where table_name = _table_name
                    and column_name = _col_name
                    and _col_name != 'value'
                    and data_type in ('json', 'jsonb'));
end;
$$;


--
-- Name: cc_set_agent_change_status(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_set_agent_change_status() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    if TG_OP = 'INSERT' then
        return new;
    end if;

    insert into call_center.cc_agent_state_history (agent_id, joined_at, state, duration, payload)
    values (old.id, old.last_state_change, old.status,  new.last_state_change - old.last_state_change, old.status_payload);


    insert into call_center.cc_agent_status_log (agent_id, joined_at, status, duration, payload)
    values (old.id, old.last_state_change, old.status,  new.last_state_change - old.last_state_change, old.status_payload)
    on conflict do nothing ;
    RETURN new;
END;
$$;



--
-- Name: cc_trigger_ins_upd(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_trigger_ins_upd() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    if NEW.type <> 'cron' then
        return NEW;
    end if;
    if call_center.cc_cron_valid(NEW.expression) is not true then
        raise exception 'invalid expression % [%]', NEW.expression, NEW.type using errcode ='20808';
    end if;

    if old.enabled != new.enabled or old.expression != new.expression or old.timezone_id != new.timezone_id then
        select
            call_center.cc_cron_next_after_now(new.expression, (now() at time zone tz.sys_name)::timestamp, (now() at time zone tz.sys_name)::timestamp)
        into new.schedule_at
        from flow.calendar_timezones tz
        where tz.id = NEW.timezone_id;
    end if;

    RETURN NEW;
END;
$$;


drop VIEW call_center.cc_agent_in_queue_view;

--
-- Name: cc_agent_in_queue_view _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_agent_in_queue_view AS
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
                              END) AS agents,
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
    LEFT JOIN LATERAL ( SELECT DISTINCT array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = 'online'::text)) AS agent_on_ids,
                                        array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = 'offline'::text)) AS agent_off_ids,
                                        array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = ANY (ARRAY[('pause'::character varying)::text, ('break_out'::character varying)::text]))) AS agent_p_ids,
                                        array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND ((ac.state)::text = 'waiting'::text))) AS free,
                                        array_agg(DISTINCT a_1.id) AS total
                        FROM (((call_center.cc_agent a_1
                            JOIN call_center.cc_agent_channel ac ON (((ac.agent_id = a_1.id) AND ((ac.channel)::text = q.chan_name))))
                            JOIN call_center.cc_queue_skill qs ON (((qs.queue_id = q.queue_id) AND qs.enabled)))
                            JOIN call_center.cc_skill_in_agent sia ON (((sia.agent_id = a_1.id) AND sia.enabled)))
                        WHERE ((a_1.domain_id = q.domain_id) AND ((q.team_id IS NULL) OR (a_1.team_id = q.team_id)) AND (qs.skill_id = sia.skill_id) AND (sia.capacity >= qs.min_capacity) AND (sia.capacity <= qs.max_capacity))
                        GROUP BY ROLLUP(q.queue_id)) a ON (true));


alter table call_center.cc_member_attempt_history add column offered_agent_ids integer[];
alter table call_center.cc_member_attempt add column offered_agent_ids integer[];

DROP MATERIALIZED VIEW call_center.cc_agent_today_stats;
CREATE MATERIALIZED VIEW call_center.cc_agent_today_stats AS
WITH agents AS MATERIALIZED (
    SELECT a_1.id,
           usr.id AS user_id,
           CASE
               WHEN (a_1.last_state_change < d."from") THEN d."from"
               WHEN (a_1.last_state_change < d."to") THEN a_1.last_state_change
               ELSE a_1.last_state_change
               END AS cur_state_change,
           a_1.status,
           a_1.status_payload,
           a_1.last_state_change,
           lasts.last_at,
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
                                   CASE
                                       WHEN (((((now())::date + '1 day'::interval) - COALESCE(t.utc_offset, '00:00:00'::interval)))::timestamp with time zone < now()) THEN ((((now())::date + '1 day'::interval) - COALESCE(t.utc_offset, '00:00:00'::interval)))::timestamp with time zone
                                       ELSE (((now())::date - COALESCE(t.utc_offset, '00:00:00'::interval)))::timestamp with time zone
                                       END AS "from") d ON (true))
        LEFT JOIN LATERAL ( SELECT aa.state,
                                   d."from" AS last_at,
                                   aa.payload AS status_payload
                            FROM call_center.cc_agent_state_history aa
                            WHERE ((aa.agent_id = a_1.id) AND (aa.channel IS NULL) AND ((aa.state)::text = ANY (ARRAY[('pause'::character varying)::text, ('online'::character varying)::text, ('offline'::character varying)::text])) AND (aa.joined_at < d."from"))
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
    WHERE ((h.joined_at > now()::date - interval '1d') and (h.domain_id = agents.domain_id) AND (h.joined_at >= agents."from") AND (h.joined_at <= agents."to") AND ((h.channel)::text = 'call'::text))
    GROUP BY h.agent_id
), attempts AS MATERIALIZED (
    WITH rng(agent_id, c, s, e, b, ac) AS (
        SELECT h.agent_id,
               h.channel,
               h.offering_at,
               COALESCE(h.reporting_at, h.leaving_at) AS e,
               h.bridged_at AS v,
               CASE
                   WHEN (h.bridged_at IS NOT NULL) THEN 1
                   ELSE 0
                   END AS ac
        FROM (agents a_1
            JOIN call_center.cc_member_attempt_history h ON ((h.agent_id = a_1.id)))
        WHERE ((h.leaving_at > ((now())::date - '2 days'::interval)) AND ((h.leaving_at >= a_1."from") AND (h.leaving_at <= a_1."to")) AND ((h.channel)::text = ANY (ARRAY['chat'::text, 'task'::text])) AND (h.agent_id IS NOT NULL) AND (1 = 1))
    )
    SELECT t.agent_id,
           t.c AS channel,
           sum(t.delta) AS sht,
           sum(t.ac) AS bridged_cnt,
           (EXTRACT(epoch FROM avg((t.e - t.b))))::bigint AS aht
    FROM ( SELECT rng.agent_id,
                  rng.c,
                  rng.s,
                  rng.e,
                  rng.b,
                  rng.ac,
                  GREATEST((rng.e - GREATEST(max(rng.e) OVER (PARTITION BY rng.agent_id, rng.c ORDER BY rng.s, rng.e ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), rng.s)), '00:00:00'::interval) AS delta
           FROM rng) t
    GROUP BY t.agent_id, t.c
), calls AS (
    SELECT h.user_id,
           count(*) FILTER (WHERE ((h.direction)::text = 'inbound'::text)) AS all_inb,
           count(*) FILTER (WHERE (h.bridged_at IS NOT NULL)) AS handled,
           count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.bridged_at IS NOT NULL))) AS inbound_bridged,
           count(*) FILTER (WHERE ((cq.type = 1) AND (h.bridged_at IS NOT NULL) AND (h.parent_id IS NOT NULL))) AS "inbound queue",
           count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.queue_id IS NULL))) AS "direct inbound",
           count(*) FILTER (WHERE ((h.parent_id IS NOT NULL) AND (h.bridged_at IS NOT NULL) AND (h.queue_id IS NULL) AND (pc.user_id IS NOT NULL))) AS internal_inb,
           count(*) FILTER (WHERE ((h.bridged_at IS NOT NULL) AND (h.queue_id IS NULL) AND (pc.user_id IS NOT NULL))) AS user_2user,
           count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.bridged_at IS NULL) AND (NOT (h.hide_missed IS TRUE)) AND (pc.bridged_at IS NULL))) AS missed,
           count(h.parent_id) FILTER (WHERE ((h.bridged_at IS NULL) AND (NOT (h.hide_missed IS TRUE)) AND (h.queue_id IS NOT NULL))) AS queue_missed,
           count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.bridged_at IS NULL) AND (h.queue_id IS NOT NULL) AND ((h.cause)::text = ANY (ARRAY[('NO_ANSWER'::character varying)::text, ('USER_BUSY'::character varying)::text])))) AS abandoned,
           count(*) FILTER (WHERE ((cq.type = ANY (ARRAY[(3)::smallint, (4)::smallint, (5)::smallint])) AND (h.bridged_at IS NOT NULL))) AS outbound_queue,
           count(*) FILTER (WHERE ((h.parent_id IS NULL) AND ((h.direction)::text = 'outbound'::text) AND (h.queue_id IS NULL))) AS manual_call,
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
    WHERE ((h.domain_id = agents.domain_id) AND (h.created_at > ((now())::date - '2 days'::interval)) AND (h.created_at >= agents."from") AND (h.created_at <= agents."to"))
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
       COALESCE(c.queue_missed, (0)::bigint) AS call_queue_missed,
       COALESCE(c.abandoned, (0)::bigint) AS call_abandoned,
       COALESCE(c.inbound_bridged, (0)::bigint) AS call_inbound,
       COALESCE(c."inbound queue", (0)::bigint) AS call_inbound_queue,
       COALESCE(c.outbound_queue, (0)::bigint) AS call_dialer_queue,
       COALESCE(c.manual_call, (0)::bigint) AS call_manual,
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
       COALESCE(chc.aht, (0)::bigint) AS chat_aht,
       (((COALESCE(cht.bridged_cnt, (0)::bigint) + COALESCE(chc.bridged_cnt, (0)::bigint)) + COALESCE(c.handled, (0)::bigint)) - COALESCE(c.user_2user, (0)::bigint)) AS task_accepts,
       (COALESCE(EXTRACT(epoch FROM (stats.online - COALESCE(stats.lunch, '00:00:00'::interval))), (0)::numeric))::bigint AS online,
       COALESCE(chc.bridged_cnt, (0)::bigint) AS chat_accepts,
       COALESCE(rate.count, (0)::bigint) AS score_count,
       (COALESCE(EXTRACT(epoch FROM eff.processing), ((0)::bigint)::numeric))::integer AS processing,
       COALESCE(rate.score_optional_avg, (0)::numeric) AS score_optional_avg,
       COALESCE(rate.score_optional_sum, ((0)::bigint)::numeric) AS score_optional_sum,
       COALESCE(rate.score_required_avg, (0)::numeric) AS score_required_avg,
       COALESCE(rate.score_required_sum, ((0)::bigint)::numeric) AS score_required_sum
FROM (((((((agents a
    LEFT JOIN call_center.cc_agent_with_user u ON ((u.id = a.id)))
    LEFT JOIN stats ON ((stats.agent_id = a.id)))
    LEFT JOIN eff ON ((eff.agent_id = a.id)))
    LEFT JOIN calls c ON ((c.user_id = a.user_id)))
    LEFT JOIN attempts chc ON (((chc.agent_id = a.id) AND ((chc.channel)::text = 'chat'::text))))
    LEFT JOIN attempts cht ON (((cht.agent_id = a.id) AND ((chc.channel)::text = 'task'::text))))
    LEFT JOIN rate ON ((rate.user_id = a.user_id)))
WITH NO DATA;


--
-- Name: cc_agent_today_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_uidx ON call_center.cc_agent_today_stats USING btree (agent_id);


--
-- Name: cc_agent_today_stats_usr_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_usr_uidx ON call_center.cc_agent_today_stats USING btree (user_id);

REFRESH MATERIALIZED VIEW call_center.cc_agent_today_stats;


DROP VIEW call_center.cc_audit_rate_view;
--
-- Name: cc_audit_rate_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_audit_rate_view AS
SELECT r.id,
       r.domain_id,
       r.form_id,
       r.created_at,
       call_center.cc_get_lookup(uc.id, COALESCE((uc.name)::character varying, (uc.username)::character varying)) AS created_by,
       r.updated_at,
       call_center.cc_get_lookup(u.id, COALESCE((u.name)::character varying, (u.username)::character varying)) AS updated_by,
       call_center.cc_get_lookup(ur.id, (ur.name)::character varying) AS rated_user,
       call_center.cc_get_lookup((f.id)::bigint, f.name) AS form,
       ans.v AS answers,
       r.score_required,
       r.score_optional,
       r.comment,
       r.call_id,
       f.questions,
       r.rated_user_id,
       r.created_by AS grantor
FROM (((((call_center.cc_audit_rate r
    LEFT JOIN LATERAL ( SELECT jsonb_agg(
                                       CASE
                                           WHEN (u_1.id IS NOT NULL) THEN (x.j || jsonb_build_object('updated_by', call_center.cc_get_lookup(u_1.id, (COALESCE(u_1.name, (u_1.username)::text))::character varying)))
                                           ELSE x.j
                                           END ORDER BY x.i) AS v
                        FROM (jsonb_array_elements(r.answers) WITH ORDINALITY x(j, i)
                            LEFT JOIN directory.wbt_user u_1 ON ((u_1.id = (((x.j -> 'updated_by'::text) -> 'id'::text))::bigint)))) ans ON (true))
    LEFT JOIN call_center.cc_audit_form f ON ((f.id = r.form_id)))
    LEFT JOIN directory.wbt_user ur ON ((ur.id = r.rated_user_id)))
    LEFT JOIN directory.wbt_user uc ON ((uc.id = r.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = r.updated_by)));


ALTER TABLE call_center.cc_communication ALTER COLUMN domain_id set not null ;


DROP VIEW call_center.cc_member_view_attempt_history;
--
-- Name: cc_member_view_attempt_history; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_member_view_attempt_history AS
SELECT t.id,
       t.joined_at,
       t.offering_at,
       t.bridged_at,
       t.reporting_at,
       t.leaving_at,
       t.channel,
       call_center.cc_get_lookup((t.queue_id)::bigint, cq.name) AS queue,
       call_center.cc_get_lookup(t.member_id, cm.name) AS member,
       t.member_call_id,
       COALESCE(cm.variables, '{}'::jsonb) AS variables,
       call_center.cc_get_lookup((t.agent_id)::bigint, (COALESCE(u.name, (u.username)::text))::character varying) AS agent,
       ( SELECT jsonb_agg(ofa."user") AS jsonb_agg
         FROM call_center.cc_agent_with_user ofa
         WHERE (ofa.id = ANY (t.offered_agent_ids))) AS offered_agents,
       t.agent_call_id,
       t.weight AS "position",
       call_center.cc_get_lookup((t.resource_id)::bigint, r.name) AS resource,
       call_center.cc_get_lookup(t.bucket_id, (cb.name)::character varying) AS bucket,
       call_center.cc_get_lookup(t.list_communication_id, l.name) AS list,
       COALESCE(t.display, ''::character varying) AS display,
       t.destination,
       t.result,
       t.domain_id,
       t.queue_id,
       t.bucket_id,
       t.member_id,
       t.agent_id,
       t.seq AS attempts,
       c.amd_result,
       t.offered_agent_ids
FROM ((((((((call_center.cc_member_attempt_history t
    LEFT JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
    LEFT JOIN call_center.cc_member cm ON ((t.member_id = cm.id)))
    LEFT JOIN call_center.cc_agent a ON ((t.agent_id = a.id)))
    LEFT JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (u.dc = a.domain_id))))
    LEFT JOIN call_center.cc_outbound_resource r ON ((r.id = t.resource_id)))
    LEFT JOIN call_center.cc_bucket cb ON ((cb.id = t.bucket_id)))
    LEFT JOIN call_center.cc_list l ON ((l.id = t.list_communication_id)))
    LEFT JOIN call_center.cc_calls_history c ON (((c.domain_id = t.domain_id) AND (c.id = (t.member_call_id)::uuid))));


DROP VIEW if exists call_center.cc_quick_reply_list;
DROP TABLE if exists call_center.cc_quick_reply;

--
-- Name: cc_quick_reply; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_quick_reply (
                                            id bigint NOT NULL,
                                            name text NOT NULL,
                                            text text NOT NULL,
                                            created_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
                                            created_by bigint NOT NULL,
                                            updated_at timestamp without time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
                                            updated_by bigint NOT NULL,
                                            article bigint,
                                            domain_id bigint NOT NULL,
                                            teams bigint[],
                                            queues integer[]
);


--
-- Name: cc_quick_reply_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_quick_reply_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_quick_reply_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_quick_reply_id_seq OWNED BY call_center.cc_quick_reply.id;


--
-- Name: cc_quick_reply_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_quick_reply_list AS
SELECT a.domain_id,
       a.id,
       a.text,
       ( SELECT jsonb_agg(call_center.cc_get_lookup((q.id)::bigint, q.name)) AS jsonb_agg
         FROM call_center.cc_queue q
         WHERE (q.id = ANY (a.queues))) AS queues,
       a.queues AS queue_ids,
       a.teams AS team_ids,
       ( SELECT jsonb_agg(call_center.cc_get_lookup(t.id, t.name)) AS jsonb_agg
         FROM call_center.cc_team t
         WHERE (t.id = ANY (a.teams))) AS teams,
       a.name,
       a.created_at,
       call_center.cc_get_lookup(uc.id, (uc.name)::character varying) AS created_by,
       a.updated_at,
       call_center.cc_get_lookup(uu.id, (uu.name)::character varying) AS updated_by
FROM ((call_center.cc_quick_reply a
    LEFT JOIN directory.wbt_user uc ON ((uc.id = a.created_by)))
    LEFT JOIN directory.wbt_user uu ON ((uu.id = a.updated_by)));



--
-- Name: cc_quick_reply id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_quick_reply ALTER COLUMN id SET DEFAULT nextval('call_center.cc_quick_reply_id_seq'::regclass);

--
-- Name: cc_quick_reply cc_quick_reply_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_quick_reply
    ADD CONSTRAINT cc_quick_reply_pk PRIMARY KEY (id);


--
-- Name: cc_quick_reply cc_quick_reply_article_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

-- TODO
-- ALTER TABLE ONLY call_center.cc_quick_reply
--     ADD CONSTRAINT cc_quick_reply_article_fk FOREIGN KEY (article) REFERENCES knowledge_base.article(id) ON DELETE SET NULL;


--
-- Name: cc_quick_reply cc_quick_reply_wbt_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_quick_reply
    ADD CONSTRAINT cc_quick_reply_wbt_domain_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


ALTER TABLE call_center.cc_trigger ALTER COLUMN timezone_id drop not null ;
ALTER TABLE call_center.cc_trigger ADD COLUMN object text DEFAULT ''::text;
ALTER TABLE call_center.cc_trigger ADD COLUMN event text DEFAULT ''::text;


DROP VIEW call_center.cc_trigger_list;
--
-- Name: cc_trigger_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_trigger_list AS
SELECT t.domain_id,
       t.schema_id,
       t.timezone_id,
       t.id,
       t.name,
       t.enabled,
       t.type,
       call_center.cc_get_lookup(s.id, s.name) AS schema,
       COALESCE(t.variables, '{}'::jsonb) AS variables,
       t.description,
       t.expression,
       call_center.cc_get_lookup((tz.id)::bigint, tz.name) AS timezone,
       t.timeout_sec AS timeout,
       call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
       call_center.cc_get_lookup(uu.id, (COALESCE(uu.name, (uu.username)::text))::character varying) AS updated_by,
       t.created_at,
       t.updated_at,
       t.object,
       t.event
FROM ((((call_center.cc_trigger t
    LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.schema_id)))
    LEFT JOIN flow.calendar_timezones tz ON ((tz.id = t.timezone_id)))
    LEFT JOIN directory.wbt_user uc ON ((uc.id = t.created_by)))
    LEFT JOIN directory.wbt_user uu ON ((uu.id = t.updated_by)));

--
-- Name: cc_communication_fkey; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_communication_fkey ON call_center.cc_communication USING btree (id, domain_id);

--
-- Name: cc_member_attempt_history_offered_agent_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_offered_agent_ids_index ON call_center.cc_member_attempt_history USING gin (offered_agent_ids gin__int_ops) WHERE (offered_agent_ids IS NOT NULL);

DROP INDEX IF EXISTS call_center.cc_member_reset_by_queue;
--
-- Name: cc_member_reset_by_queue; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_reset_by_queue ON call_center.cc_member USING btree (domain_id, queue_id) INCLUDE (id) WHERE ((stop_at IS NOT NULL) AND ((stop_cause)::text <> ALL ('{success,expired,cancel,terminate,no_communications}'::text[])));


DROP VIEW call_center.cc_distribute_stage_1;
--
-- Name: cc_distribute_stage_1 _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_distribute_stage_1 AS
WITH queues AS MATERIALIZED (
    SELECT q_1.domain_id,
           q_1.id,
           q_1.calendar_id,
           q_1.type,
           q_1.sticky_agent,
           q_1.recall_calendar,
           CASE
               WHEN (jsonb_typeof((q_1.payload -> 'ignore_calendar'::text)) = 'boolean'::text) THEN ((q_1.payload -> 'ignore_calendar'::text))::boolean
               ELSE false
               END AS ignore_calendar,
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
           COALESCE((q_1.payload ->> 'resource_strategy'::text), ''::text) AS rs,
           ((q_1.payload -> 'wait_between_retries_desc'::text))::boolean AS wait_between_retries_desc,
           COALESCE(((q_1.payload -> 'strict_circuit'::text))::boolean, false) AS strict_circuit,
           array_agg(ROW((m.bucket_id)::integer, (m.member_waiting)::integer, m.op)::call_center.cc_sys_distribute_bucket ORDER BY cbiq.priority DESC NULLS LAST, cbiq.ratio DESC NULLS LAST, m.bucket_id) AS buckets,
           m.op,
           min(m.min_wt) AS min_wt
    FROM ((( WITH mem AS MATERIALIZED (
        SELECT a.queue_id,
               a.bucket_id,
               count(*) AS member_waiting,
               false AS op,
               min((EXTRACT(epoch FROM a.joined_at))::bigint) AS min_wt
        FROM call_center.cc_member_attempt a
        WHERE ((a.bridged_at IS NULL) AND (a.leaving_at IS NULL) AND ((a.state)::text = 'wait_agent'::text))
        GROUP BY a.queue_id, a.bucket_id
        UNION ALL
        SELECT q_2.queue_id,
               q_2.bucket_id,
               q_2.member_waiting,
               true AS op,
               0 AS min_wt
        FROM call_center.cc_queue_statistics q_2
        WHERE (q_2.member_waiting > 0)
    )
             SELECT rank() OVER (PARTITION BY mem.queue_id ORDER BY mem.op) AS pos,
                    mem.queue_id,
                    mem.bucket_id,
                    mem.member_waiting,
                    mem.op,
                    mem.min_wt
             FROM mem) m
        JOIN call_center.cc_queue q_1 ON ((q_1.id = m.queue_id)))
        LEFT JOIN call_center.cc_bucket_in_queue cbiq ON (((cbiq.queue_id = m.queue_id) AND (cbiq.bucket_id = m.bucket_id))))
    WHERE ((m.member_waiting > 0) AND q_1.enabled AND (q_1.type > 0) AND (NOT COALESCE(((q_1.payload -> 'manual_distribution'::text))::boolean, false)) AND ((cbiq.bucket_id IS NULL) OR (NOT cbiq.disabled)))
    GROUP BY q_1.domain_id, q_1.id, q_1.calendar_id, q_1.type, m.op
    LIMIT 1024
), calend AS MATERIALIZED (
    SELECT c.id AS calendar_id,
           queues.id AS queue_id,
           queues.rs,
           CASE
               WHEN (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) THEN ((array_agg(DISTINCT o1.id))::integer[] + (tz.offset_id)::integer)
               ELSE (array_agg(DISTINCT o1.id))::integer[]
               END AS l,
           (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) AS recall_calendar,
           (tz.offset_id = ANY (array_agg(DISTINCT o1.id))) AS in_calendar
    FROM ((((flow.calendar c
        LEFT JOIN flow.calendar_timezones tz ON ((tz.id = c.timezone_id)))
        JOIN queues ON ((queues.calendar_id = c.id)))
        JOIN LATERAL unnest(c.accepts) a(disabled, day, start_time_of_day, end_time_of_day) ON (true))
        JOIN flow.calendar_timezone_offsets o1 ON ((((a.day + 1) = (date_part('isodow'::text, timezone(o1.names[1], now())))::integer) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) >= a.start_time_of_day) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) <= a.end_time_of_day))))
    WHERE ((NOT (a.disabled IS TRUE)) AND (NOT (EXISTS ( SELECT 1
                                                         FROM unnest(c.excepts) x(disabled, date, name, repeat, work_start, work_stop, working)
                                                         WHERE ((NOT (x.disabled IS TRUE)) AND
                                                                CASE
                                                                    WHEN (x.repeat IS TRUE) THEN (to_char((((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name))::date)::timestamp with time zone, 'MM-DD'::text) = to_char((((to_timestamp(((x.date / 1000))::double precision) AT TIME ZONE tz.sys_name))::date)::timestamp with time zone, 'MM-DD'::text))
                                                                    ELSE (((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name))::date = ((to_timestamp(((x.date / 1000))::double precision) AT TIME ZONE tz.sys_name))::date)
                                                                    END AND (NOT (x.working AND (((to_char((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name), 'SSSS'::text))::integer / 60) >= x.work_start) AND (((to_char((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name), 'SSSS'::text))::integer / 60) <= x.work_stop))))))))
    GROUP BY c.id, queues.id, queues.rs, queues.recall_calendar, tz.offset_id
), resources AS MATERIALIZED (
    SELECT l_1.queue_id,
           array_agg(ROW(cor.communication_id, (cor.id)::bigint, ((l_1.l & (l2.x)::integer[]))::smallint[], (cor.resource_group_id)::integer)::call_center.cc_sys_distribute_type ORDER BY
               CASE
                   WHEN (l_1.rs = 'priority-based'::text) THEN cor.priority
                   ELSE NULL::integer
                   END, (random())) AS types,
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
SELECT q.id,
       q.type,
       (q.strategy)::smallint AS strategy,
       q.team_id,
       q.buckets,
       r.types,
       r.resources,
       CASE
           WHEN (q.type = ANY ('{7,8}'::smallint[])) THEN calend.l
           ELSE r.offset_ids
           END AS offset_ids,
       CASE
           WHEN (q.lim = '-1'::integer) THEN NULL::integer
           ELSE GREATEST(((q.lim - COALESCE(l.usage, (0)::bigint)))::integer, 0)
           END AS lim,
       q.domain_id,
       q.priority,
       q.sticky_agent,
       q.sticky_agent_sec,
       calend.recall_calendar,
       q.wait_between_retries_desc,
       q.strict_circuit,
       q.op AS ins,
       q.min_wt
FROM (((queues q
    LEFT JOIN calend ON ((calend.queue_id = q.id)))
    LEFT JOIN resources r ON ((q.op AND (r.queue_id = q.id))))
    LEFT JOIN LATERAL ( SELECT count(*) AS usage
                        FROM call_center.cc_member_attempt a
                        WHERE ((a.queue_id = q.id) AND ((a.state)::text <> 'leaving'::text))) l ON ((q.lim > 0)))
WHERE ((q.type = 7) OR ((q.type = ANY (ARRAY[1, 6])) AND ((NOT q.ignore_calendar) OR calend.in_calendar OR (calend.in_calendar IS NULL))) OR ((q.type = 8) AND (GREATEST(((q.lim - COALESCE(l.usage, (0)::bigint)))::integer, 0) > 0)) OR ((q.type = 5) AND (NOT q.op)) OR (q.op AND (q.type = ANY (ARRAY[2, 3, 4, 5])) AND (r.* IS NOT NULL)))
ORDER BY q.domain_id, q.priority DESC, q.op;

