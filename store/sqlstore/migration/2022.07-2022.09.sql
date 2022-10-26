drop function if exists call_center.cc_distribute_members_list;
create function call_center.cc_distribute_members_list(_queue_id integer, _bucket_id integer, strategy smallint, wait_between_retries_desc boolean DEFAULT false, l smallint[] DEFAULT '{}'::smallint[], lim integer DEFAULT 40, offs integer DEFAULT 0) returns SETOF bigint
    stable
    language plpgsql
as
$$
begin return query
select m.id::int8
from call_center.cc_member m
where m.queue_id = _queue_id
        and m.stop_at isnull
        and m.skill_id isnull
        and case when _bucket_id isnull then m.bucket_id isnull else m.bucket_id = _bucket_id end
        and (m.expire_at isnull or m.expire_at > now())
        and (m.ready_at isnull or m.ready_at < now())
        and not m.search_destinations && array(select call_center.cc_call_active_numbers())
        and m.id not in (select distinct a.member_id from call_center.cc_member_attempt a where a.member_id notnull)
        and m.sys_offset_id = any($5::int2[])
    order by m.bucket_id nulls last,
             m.skill_id,
             m.agent_id,
             m.priority desc,
             case when coalesce(wait_between_retries_desc, false) then m.ready_at end desc nulls last ,
             case when not coalesce(wait_between_retries_desc, false) then m.ready_at end asc nulls last ,

             case when coalesce(strategy, 0) = 1 then m.id end desc ,
             case when coalesce(strategy, 0) != 1 then m.id end asc
    limit lim
    offset offs
--     for update of m skip locked
        ;
end
$$;



--
-- Name: cc_distribute_inbound_call_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION if exists  call_center.cc_distribute_inbound_call_to_queue;
CREATE FUNCTION call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
    _list_comm_id int8;
    _enabled bool;
    _q_type smallint;
    _sticky bool;
    _call record;
    _attempt record;
    _number varchar;
    _max_waiting_size int;
BEGIN
select c.timezone_id,
       (payload->>'discard_abandoned_after')::int discard_abandoned_after,
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

if not _q_type = 1 then
      raise exception 'queue not inbound';
end if;

  if not _enabled = true then
      raise exception 'queue disabled';
end if;

select *
from call_center.cc_calls c
where c.id = _call_id
--   for update
  into _call;

if _call.domain_id != _domain_id then
      raise exception 'the queue on another domain';
end if;

  if _call.id isnull or _call.direction isnull then
      raise exception 'not found call';
  ELSIF _call.direction <> 'outbound' or _call.user_id notnull then
      _number = _call.from_number;
else
      _number = _call.destination;
end if;

--   raise  exception '%', _number;


  if not exists(select accept
            from flow.calendar_check_timing(_domain_id, _calendar_id, null)
            as x (name varchar, excepted varchar, accept bool, expire bool)
            where accept and excepted is null and not expire)
  then
      raise exception 'number % calendar not working [%]', _number, _calendar_id;
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

  if dnc_list_id_ notnull then
select clc.id
into _list_comm_id
from call_center.cc_list_communications clc
where (clc.list_id = dnc_list_id_ and clc.number = _number)
    limit 1;
end if;

  if _list_comm_id notnull then
          raise exception 'number % banned', _number;
end if;

  if  _discard_abandoned_after > 0 then
select
    case when log.result = 'abandoned' then
             extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
            else coalesce(_priority, 0) end
        from call_center.cc_member_attempt_history log
        where log.leaving_at >= (now() -  (_discard_abandoned_after || ' sec')::interval)
            and log.queue_id = _queue_id
            and log.destination->>'destination' = _number
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

insert into call_center.cc_member_attempt (domain_id, state, queue_id, team_id, member_id, bucket_id, weight, member_call_id, destination, node_id, sticky_agent_id, list_communication_id, parent_id)
values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id, jsonb_build_object('destination', _number),
        _node_name, _sticky_agent_id, null, _call.attempt_id)
    returning * into _attempt;

update call_center.cc_calls
set queue_id  = _attempt.queue_id,
    team_id = _team_id_,
    attempt_id = _attempt.id,
    payload = variables_
where id = _call_id
    returning * into _call;

if _call.id isnull or _call.direction isnull then
      raise exception 'not found call';
end if;

return row(
        _attempt.id::int8,
        _attempt.queue_id::int,
        _queue_updated_at::int8,
        _attempt.destination::jsonb,
        variables_::jsonb,
        _call.from_name::varchar,
        _team_updated_at::int8,

        _call.id::varchar,
        _call.state::varchar,
        _call.direction::varchar,
        _call.destination::varchar,
        call_center.cc_view_timestamp(_call.timestamp)::int8,
        _call.app_id::varchar,
        _number::varchar,
        case when (_call.direction <> 'outbound'
            and _call.to_name::varchar <> ''
            and _call.to_name::varchar notnull)
                 then _call.from_name::varchar
             else _call.to_name::varchar end,
        call_center.cc_view_timestamp(_call.answered_at)::int8,
        call_center.cc_view_timestamp(_call.bridged_at)::int8,
        call_center.cc_view_timestamp(_call.created_at)::int8
    );

END;
$$;



--
-- Name: cc_distribute_members_list(integer, integer, smallint, boolean, smallint[], integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION if exists call_center.cc_distribute_members_list;
CREATE FUNCTION call_center.cc_distribute_members_list(_queue_id integer, _bucket_id integer, strategy smallint, wait_between_retries_desc boolean DEFAULT false, l smallint[] DEFAULT '{}'::smallint[], lim integer DEFAULT 40, offs integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STABLE
    AS $_$
begin return query
select m.id::int8
from call_center.cc_member m
where m.queue_id = _queue_id
        and m.stop_at isnull
        and m.skill_id isnull
        and case when _bucket_id isnull then m.bucket_id isnull else m.bucket_id = _bucket_id end
        and (m.expire_at isnull or m.expire_at > now())
        and (m.ready_at isnull or m.ready_at < now())
        and not m.search_destinations && array(select call_center.cc_call_active_numbers())
        and m.id not in (select distinct a.member_id from call_center.cc_member_attempt a where a.member_id notnull)
        and m.sys_offset_id = any($5::int2[])
    order by m.bucket_id nulls last,
             m.skill_id,
             m.agent_id,
             m.priority desc,
             case when coalesce(wait_between_retries_desc, false) then m.ready_at end desc nulls last ,
             case when not coalesce(wait_between_retries_desc, false) then m.ready_at end asc nulls last ,

             case when coalesce(strategy, 0) = 1 then m.id end desc ,
             case when coalesce(strategy, 0) != 1 then m.id end asc
    limit lim
    offset offs
--     for update of m skip locked
        ;
end
$_$;



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
            array_agg(ROW((m.bucket_id)::integer, (m.member_waiting)::integer, m.op)::call_center.cc_sys_distribute_bucket ORDER BY cbiq.priority DESC NULLS LAST, cbiq.ratio DESC NULLS LAST, m.bucket_id) AS buckets,
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
          WHERE ((m.member_waiting > 0) AND q_1.enabled AND (q_1.type > 0) AND (m.pos = 1) AND ((cbiq.bucket_id IS NULL) OR (NOT cbiq.disabled)))
          GROUP BY q_1.domain_id, q_1.id, q_1.calendar_id, q_1.type, m.op
         LIMIT 1024
        ), calend AS MATERIALIZED (
         SELECT c.id AS calendar_id,
            queues.id AS queue_id,
                CASE
                    WHEN (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) THEN ((array_agg(DISTINCT o1.id))::integer[] + (tz.offset_id)::integer)
                    ELSE (array_agg(DISTINCT o1.id))::integer[]
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
    q.strict_circuit
   FROM (((queues q
     LEFT JOIN calend ON ((calend.queue_id = q.id)))
     LEFT JOIN resources r ON ((q.op AND (r.queue_id = q.id))))
     LEFT JOIN LATERAL ( SELECT count(*) AS usage
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND ((a.state)::text <> 'leaving'::text))) l ON ((q.lim > 0)))
  WHERE ((q.type = ANY (ARRAY[1, 6, 7])) OR ((q.type = 8) AND (GREATEST(((q.lim - COALESCE(l.usage, (0)::bigint)))::integer, 0) > 0)) OR ((q.type = 5) AND (NOT q.op)) OR (q.op AND (q.type = ANY (ARRAY[2, 3, 4, 5])) AND (r.* IS NOT NULL)));





--
-- Name: cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION if exists call_center.cc_distribute_inbound_chat_to_queue;
CREATE FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
      raise exception 'conversation [%] calendar not working', _conversation_id;
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
       c.id inviter_channel_id,
       c.user_id
from chat.channel c
         left join chat.client cli on cli.id = c.user_id
where c.closed_at isnull
        and c.conversation_id = _conversation_id
    and not c.internal
into _con_name, _con_created, _inviter_channel_id, _inviter_user_id;
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
values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id, jsonb_build_object('destination', _con_name),
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
-- Name: cc_scheduler_jobs(); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_scheduler_jobs()
    LANGUAGE plpgsql
    AS $$
begin
    if NOT pg_try_advisory_xact_lock(132132118) then
        raise exception 'LOCKED cc_scheduler_jobs';
end if;

with del as (
delete from call_center.cc_trigger_job
where stopped_at notnull
        returning id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
    )
insert into call_center.cc_trigger_job_log (id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id)
select id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
from del
;

with u as (
update cc_trigger t2
set schedule_at = t.schedule_at
    from (select t.id,
                         jsonb_build_object('variables', t.variables,
                                            'schema_id', t.schema_id,
                                            'timeout', t.timeout_sec
                             ) as                                      params,
                         now() schedule_at
                  from call_center.cc_trigger t
                           inner join flow.calendar_timezones tz on tz.id = t.timezone_id
                  where t.enabled
                    and now() > call_center.cc_cron_next(t.expression, t.schedule_at + tz.utc_offset)
                    and not exists(select 1 from call_center.cc_trigger_job tj where tj.trigger_id = t.id and tj.state = 0)
                      for update skip locked) t
where t2.id = t.id
    returning t.*)
insert
into call_center.cc_trigger_job(trigger_id, parameters)
select id, params
from u;

end;
$$;





--
-- Name: cc_trigger; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_trigger (
                                        id integer NOT NULL,
                                        domain_id bigint NOT NULL,
                                        name character varying NOT NULL,
                                        enabled boolean DEFAULT false NOT NULL,
                                        type character varying DEFAULT 'cron'::character varying NOT NULL,
                                        schema_id integer NOT NULL,
                                        variables jsonb,
                                        description text,
                                        expression character varying,
                                        timezone_id integer NOT NULL,
                                        created_by bigint,
                                        updated_by bigint,
                                        created_at timestamp with time zone DEFAULT now() NOT NULL,
                                        updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                        timeout_sec integer DEFAULT 0 NOT NULL,
                                        schedule_at timestamp without time zone DEFAULT (now())::timestamp without time zone
);


--
-- Name: cc_trigger_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_trigger_acl (
                                            id bigint NOT NULL,
                                            dc bigint NOT NULL,
                                            grantor bigint,
                                            subject bigint NOT NULL,
                                            access smallint DEFAULT 0 NOT NULL,
                                            object bigint NOT NULL
);


--
-- Name: cc_trigger_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_trigger_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_trigger_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_trigger_acl_id_seq OWNED BY call_center.cc_trigger_acl.id;


--
-- Name: cc_trigger_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_trigger_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_trigger_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_trigger_id_seq OWNED BY call_center.cc_trigger.id;


--
-- Name: cc_trigger_job; Type: TABLE; Schema: call_center; Owner: -
--

CREATE UNLOGGED TABLE call_center.cc_trigger_job (
    id bigint NOT NULL,
    trigger_id integer NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    stopped_at timestamp with time zone,
    parameters jsonb,
    error text,
    result jsonb,
    node_id character varying,
    domain_id bigint
);


--
-- Name: cc_trigger_job_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_trigger_job_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_trigger_job_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_trigger_job_id_seq OWNED BY call_center.cc_trigger_job.id;


--
-- Name: cc_trigger_job_log; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_trigger_job_log (
                                                id bigint,
                                                trigger_id integer NOT NULL,
                                                state integer,
                                                created_at timestamp with time zone,
                                                started_at timestamp with time zone NOT NULL,
                                                stopped_at timestamp with time zone,
                                                parameters jsonb,
                                                error text,
                                                result jsonb,
                                                node_id character varying,
                                                domain_id bigint NOT NULL
);


--
-- Name: cc_trigger_job_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_trigger_job_list AS
SELECT j.id,
       j.domain_id,
       call_center.cc_get_lookup((t.id)::bigint, t.name) AS trigger,
       j.state,
       j.created_at,
       j.started_at,
       j.stopped_at,
       j.parameters,
       j.error,
       j.result,
       j.trigger_id
FROM (call_center.cc_trigger_job j
    LEFT JOIN call_center.cc_trigger t ON ((t.id = j.trigger_id)))
UNION ALL
SELECT j.id,
       j.domain_id,
       call_center.cc_get_lookup((t.id)::bigint, t.name) AS trigger,
       j.state,
       j.created_at,
       j.started_at,
       j.stopped_at,
       j.parameters,
       j.error,
       j.result,
       j.trigger_id
FROM (call_center.cc_trigger_job_log j
    LEFT JOIN call_center.cc_trigger t ON ((t.id = j.trigger_id)));


--
-- Name: cc_trigger_job_log_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_trigger_job_log_list AS
SELECT j.id,
       j.domain_id,
       call_center.cc_get_lookup((t.id)::bigint, t.name) AS trigger,
       j.state,
       j.created_at,
       j.started_at,
       j.stopped_at,
       j.parameters,
       j.error,
       j.result
FROM (call_center.cc_trigger_job_log j
    LEFT JOIN call_center.cc_trigger t ON ((t.id = j.trigger_id)));


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
    t.variables,
    t.description,
    t.expression,
    call_center.cc_get_lookup((tz.id)::bigint, tz.name) AS timezone,
    t.timeout_sec AS timeout,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
    call_center.cc_get_lookup(uu.id, (COALESCE(uu.name, (uu.username)::text))::character varying) AS updated_by,
    t.created_at,
    t.updated_at
   FROM ((((call_center.cc_trigger t
     LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.schema_id)))
     LEFT JOIN flow.calendar_timezones tz ON ((tz.id = t.timezone_id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = t.created_by)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = t.updated_by)));




--
-- Name: cc_trigger id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger ALTER COLUMN id SET DEFAULT nextval('call_center.cc_trigger_id_seq'::regclass);


--
-- Name: cc_trigger_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_trigger_acl_id_seq'::regclass);


--
-- Name: cc_trigger_job id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_job ALTER COLUMN id SET DEFAULT nextval('call_center.cc_trigger_job_id_seq'::regclass);




--
-- Name: cc_trigger_acl cc_trigger_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_pk PRIMARY KEY (id);


--
-- Name: cc_trigger_job cc_trigger_job_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_job
    ADD CONSTRAINT cc_trigger_job_pk PRIMARY KEY (id);


--
-- Name: cc_trigger cc_trigger_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger
    ADD CONSTRAINT cc_trigger_pk PRIMARY KEY (id);



--
-- Name: cc_trigger_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_trigger_acl_grantor_idx ON call_center.cc_trigger_acl USING btree (grantor);


--
-- Name: cc_trigger_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_trigger_acl_object_subject_udx ON call_center.cc_trigger_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_trigger_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_trigger_acl_subject_object_udx ON call_center.cc_trigger_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_trigger_id_domain_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_trigger_id_domain_id_uindex ON call_center.cc_trigger USING btree (id, domain_id);


--
-- Name: cc_trigger_job_log_trigger_id_started_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_trigger_job_log_trigger_id_started_at_index ON call_center.cc_trigger_job_log USING btree (trigger_id, started_at DESC);

--
-- Name: cc_trigger cc_trigger_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_trigger_set_rbac_acl AFTER INSERT ON call_center.cc_trigger FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_trigger');



--
-- Name: cc_trigger_acl cc_trigger_acl_cc_trigger_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_cc_trigger_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_trigger(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_trigger_acl cc_trigger_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_trigger_acl cc_trigger_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_trigger_acl cc_trigger_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_trigger_acl cc_trigger_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_trigger(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_trigger_acl cc_trigger_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_trigger cc_trigger_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger
    ADD CONSTRAINT cc_trigger_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id);


--
-- Name: cc_trigger cc_trigger_calendar_timezones_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger
    ADD CONSTRAINT cc_trigger_calendar_timezones_id_fk FOREIGN KEY (timezone_id) REFERENCES flow.calendar_timezones(id);


--
-- Name: cc_trigger_job cc_trigger_job_cc_trigger_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_job
    ADD CONSTRAINT cc_trigger_job_cc_trigger_id_fk FOREIGN KEY (trigger_id) REFERENCES call_center.cc_trigger(id);


--
-- Name: cc_trigger_job_log cc_trigger_job_log_cc_trigger_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_job_log
    ADD CONSTRAINT cc_trigger_job_log_cc_trigger_id_fk FOREIGN KEY (trigger_id) REFERENCES call_center.cc_trigger(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_trigger cc_trigger_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger
    ADD CONSTRAINT cc_trigger_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;





--
-- Name: cc_cron_next_after_now(character varying, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION if exists call_center.cc_cron_next_after_now;
CREATE FUNCTION call_center.cc_cron_next_after_now(expression character varying, shed timestamp without time zone, nowtz timestamp without time zone) RETURNS timestamp without time zone
    LANGUAGE plpgsql
    AS $$
declare n timestamp = (call_center.cc_cron_next(expression, shed))::timestamp;
    declare i int = 0;
begin
        if n < nowtz then
            n = nowtz;
end if;

        while n <= nowtz and i < 1000 loop -- TODO
            n = (call_center.cc_cron_next(expression, n) )::timestamp;
            i = i + 1;
end loop;


return n;
end;
$$;




--
-- Name: cc_scheduler_jobs(); Type: PROCEDURE; Schema: call_center; Owner: -
--
drop PROCEDURE if exists call_center.cc_scheduler_jobs;
CREATE PROCEDURE call_center.cc_scheduler_jobs()
    LANGUAGE plpgsql
    AS $$
begin

    if NOT pg_try_advisory_xact_lock(132132118) then
        raise exception 'LOCKED cc_scheduler_jobs';
end if;

with del as (
delete from call_center.cc_trigger_job
where stopped_at notnull
        returning id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
    )
insert into call_center.cc_trigger_job_log (id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id)
select id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
from del
;

with u as (
update call_center.cc_trigger t2
set schedule_at = (t.new_schedule_at)::timestamp
from (select t.id,
    jsonb_build_object('variables', t.variables,
    'schema_id', t.schema_id,
    'timeout', t.timeout_sec
    ) as                                      params,
    call_center.cc_cron_next_after_now(t.expression, (t.schedule_at)::timestamp, (now() at time zone tz.sys_name)::timestamp) new_schedule_at,
    t.domain_id,
    (t.schedule_at)::timestamp as old_schedule_at
    from call_center.cc_trigger t
    inner join flow.calendar_timezones tz on tz.id = t.timezone_id
    where t.enabled
    and (t.schedule_at)::timestamp <= (now() at time zone tz.sys_name)::timestamp
    and not exists(select 1 from call_center.cc_trigger_job tj where tj.trigger_id = t.id and tj.state = 0)
    for update of t skip locked) t
where t2.id = t.id
    returning t.*
    )
insert
into call_center.cc_trigger_job(trigger_id, parameters, domain_id)
select id, params, domain_id
from u;
end;
$$;



--
-- Name: cc_trigger_ins_upd(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_trigger_ins_upd() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
        if call_center.cc_cron_valid(NEW.expression) is not true then
            raise exception 'invalid expression %', NEW.expression using errcode ='20808';
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


alter table call_center.cc_trigger alter column expression drop not null;





--
-- Name: cc_queue_report_general _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_queue_report_general AS
SELECT call_center.cc_get_lookup((q.id)::bigint, q.name) AS queue,
       call_center.cc_get_lookup(ct.id, ct.name) AS team,
       ( SELECT sum(s.member_waiting) AS sum
FROM call_center.cc_queue_statistics s
WHERE (s.queue_id = q.id)) AS waiting,
    ( SELECT count(*) AS count
FROM call_center.cc_member_attempt a
WHERE (a.queue_id = q.id)) AS processed,
    count(*) AS cnt,
    count(*) FILTER (WHERE (t.offering_at IS NOT NULL)) AS calls,
    count(*) FILTER (WHERE ((t.result)::text = 'abandoned'::text)) AS abandoned,
    date_part('epoch'::text, sum((t.leaving_at - t.bridged_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS bill_sec,
    date_part('epoch'::text, avg((t.leaving_at - t.reporting_at)) FILTER (WHERE (t.reporting_at IS NOT NULL))) AS avg_wrap_sec,
    date_part('epoch'::text, avg((t.bridged_at - t.offering_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_awt_sec,
    date_part('epoch'::text, max((t.bridged_at - t.offering_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS max_awt_sec,
    date_part('epoch'::text, avg((t.bridged_at - t.joined_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_asa_sec,
    date_part('epoch'::text, avg((GREATEST(t.leaving_at, t.reporting_at) - t.bridged_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_aht_sec,
    q.id AS queue_id,
    q.team_id
FROM ((call_center.cc_member_attempt_history t
    JOIN call_center.cc_queue q ON ((q.id = t.queue_id)))
    LEFT JOIN call_center.cc_team ct ON ((q.team_id = ct.id)))
GROUP BY q.id, ct.id;


--
-- Name: cc_sys_queue_distribute_resources _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_sys_queue_distribute_resources AS
 WITH res AS (
         SELECT cqr.queue_id,
            corg.communication_id,
            cor.id,
            cor."limit",
            call_center.cc_outbound_resource_timing(corg."time") AS t,
            cor.patterns
           FROM (((call_center.cc_queue_resource cqr
             JOIN call_center.cc_outbound_resource_group corg ON ((cqr.resource_group_id = corg.id)))
             JOIN call_center.cc_outbound_resource_in_group corig ON ((corg.id = corig.group_id)))
             JOIN call_center.cc_outbound_resource cor ON ((corig.resource_id = cor.id)))
          WHERE (cor.enabled AND (NOT cor.reserve))
          GROUP BY cqr.queue_id, corg.communication_id, corg."time", cor.id, cor."limit"
        )
SELECT res.queue_id,
       array_agg(DISTINCT ROW(res.communication_id, (res.id)::bigint, res.t, 0)::call_center.cc_sys_distribute_type) AS types,
       array_agg(DISTINCT ROW((res.id)::bigint, ((res."limit" - ac.count))::integer, res.patterns)::call_center.cc_sys_distribute_resource) AS resources,
       array_agg(DISTINCT f.f) AS ran
FROM res,
     (LATERAL ( SELECT count(*) AS count
         FROM call_center.cc_member_attempt a
         WHERE (a.resource_id = res.id)) ac
         JOIN LATERAL ( SELECT f_1.f
                        FROM unnest(res.t) f_1(f)) f ON (true))
WHERE ((res."limit" - ac.count) > 0)
GROUP BY res.queue_id;




--
-- Name: cc_trigger cc_trigger_ins_upd_tg; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_trigger_ins_upd_tg BEFORE INSERT OR UPDATE ON call_center.cc_trigger FOR EACH ROW EXECUTE FUNCTION call_center.cc_trigger_ins_upd();


alter TABLE call_center.cc_list_communications add column expire_at timestamp with time zone;

drop VIEW if exists call_center.cc_list_communications_view;
CREATE VIEW call_center.cc_list_communications_view AS
SELECT i.id,
       i.number,
       i.description,
       i.list_id,
       cl.domain_id,
       i.expire_at
FROM (call_center.cc_list_communications i
    LEFT JOIN call_center.cc_list cl ON ((cl.id = i.list_id)));



drop INDEX if exists call_center.cc_agent_state_history_dev_g;
CREATE INDEX cc_agent_state_history_dev_g ON call_center.cc_agent_state_history USING btree (agent_id, joined_at DESC) INCLUDE (state, payload) WHERE ((channel IS NULL) AND ((state)::text = ANY (ARRAY[('pause'::character varying)::text, ('online'::character varying)::text, ('offline'::character varying)::text])));

drop INDEX if exists call_center.cc_calls_history_user_ids_index2 ;


--
-- Name: cc_list_communications_expire_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_list_communications_expire_at_index ON call_center.cc_list_communications USING btree (expire_at) WHERE (expire_at IS NOT NULL);


--
-- Name: cc_email cc_email_cc_email_profiles_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--
ALTER TABLE ONLY call_center.cc_email
drop CONSTRAINT if exists cc_email_cc_email_profiles_id_fk;
ALTER TABLE ONLY call_center.cc_email
    ADD CONSTRAINT cc_email_cc_email_profiles_id_fk FOREIGN KEY (profile_id) REFERENCES call_center.cc_email_profile(id) ON UPDATE CASCADE ON DELETE CASCADE;




--
-- Name: cc_agent_set_login(integer, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION if exists call_center.cc_agent_set_login;
CREATE FUNCTION call_center.cc_agent_set_login(agent_id_ integer, on_demand_ boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
res_ jsonb;
    user_id_ int8;
begin
update call_center.cc_agent
set status            = 'online', -- enum added
    status_payload = null,
    on_demand = on_demand_,
--         updated_at = case when on_demand != on_demand_ then cc_view_timestamp(now()) else updated_at end,
    last_state_change = now()     -- todo rename to status
where call_center.cc_agent.id = agent_id_
    returning user_id into user_id_;

if NOT (exists(select 1
from directory.wbt_user_presence p
where user_id = user_id_ and open > 0 and status in ('sip', 'web'))
      or exists(SELECT 1
FROM directory.wbt_session s
WHERE ((user_id IS NOT NULL) AND (NULLIF((props ->> 'pn-rpid'::text), ''::text) IS NOT NULL))
    and s.user_id = user_id_::int8
    and s.access notnull
    AND s.expires > now() at time zone 'UTC')) then
        raise exception 'not found: sip, web or pn';
end if;

update call_center.cc_agent_channel c
set  channel = case when x.x = 1 then c.channel end,
     state = case when x.x = 1 then c.state else 'waiting' end,
     online = true,
     no_answers = 0
    from call_center.cc_agent_channel c2
        left join LATERAL (
            select 1 x
            from call_center.cc_member_attempt a where a.agent_id = agent_id_
            limit 1
        ) x on true
where c2.agent_id = agent_id_ and c.agent_id = c2.agent_id
    returning jsonb_build_object('channel', c.channel, 'joined_at', call_center.cc_view_timestamp(c.joined_at), 'state', c.state, 'no_answers', c.no_answers)
into res_;

return row(res_::jsonb, call_center.cc_view_timestamp(now()));
end;
$$;





--
-- Name: cc_distribute_direct_member_to_queue(character varying, bigint, integer, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION if exists call_center.cc_distribute_direct_member_to_queue;
CREATE FUNCTION call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint, seq integer)
    LANGUAGE plpgsql
    AS $$
declare
_weight      int4;
    _destination jsonb;
BEGIN

return query with attempts as (
        insert into call_center.cc_member_attempt (state, queue_id, member_id, destination, node_id, agent_id, resource_id,
                                       bucket_id, seq, team_id, domain_id)
            select 1,
                   m.queue_id,
                   m.id,
                   m.communications -> (_communication_id::int2),
                   _node_name,
                   _agent_id,
                   r.resource_id,
                   m.bucket_id,
                   m.attempts + 1,
                   q.team_id,
                   q.domain_id
            from call_center.cc_member m
                     inner join call_center.cc_queue q on q.id = m.queue_id
                     inner join lateral (
                select (t::call_center.cc_sys_distribute_type).resource_id
                from call_center.cc_sys_queue_distribute_resources r,
                     unnest(r.types) t
                where r.queue_id = m.queue_id
                  and (t::call_center.cc_sys_distribute_type).type_id =
                      (m.communications -> (_communication_id::int2) -> 'type' -> 'id')::int4
                limit 1
                ) r on true
                     left join call_center.cc_outbound_resource cor on cor.id = r.resource_id
            where m.id = _member_id
              and m.communications -> (_communication_id::int2) notnull
              and not exists(select 1 from call_center.cc_member_attempt ma where ma.member_id = _member_id)
            returning call_center.cc_member_attempt.*
    )
select a.id,
       a.member_id,
       null::varchar          result,
        a.queue_id,
       cq.updated_at as       queue_updated_at,
       0::integer             queue_count,
        0::integer             queue_active_count,
        0::integer             queue_waiting_count,
        a.resource_id::integer resource_id,
        r.updated_at::bigint   resource_updated_at,
        null::bigint           gateway_updated_at,
        a.destination          destination,
       cm.variables,
       cm.name,
       null::varchar,
        a.agent_id::bigint     agent_id,
        ag.updated_at::bigint  agent_updated_at,
        t.updated_at::bigint   team_updated_at,
        a.seq::int seq
from attempts a
         left join call_center.cc_member cm on a.member_id = cm.id
         inner join call_center.cc_queue cq on a.queue_id = cq.id
         left join call_center.cc_outbound_resource r on r.id = a.resource_id
         left join call_center.cc_agent ag on ag.id = a.agent_id
         inner join call_center.cc_team t on t.id = ag.team_id;

--raise notice '%', _attempt_id;

END;
$$;

drop VIEW  if exists call_center.cc_email_profile_list;
alter table call_center.cc_email add column html text;
alter table call_center.cc_email_profile add column imap_host character varying;
alter table call_center.cc_email_profile add column smtp_host character varying;

update call_center.cc_email_profile p
set imap_host = p.host,
    smtp_host = p.host
where p.host notnull;
alter table call_center.cc_email_profile drop column if exists "host";



--
-- Name: cc_email_profile_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_email_profile_list AS
SELECT t.id,
       t.domain_id,
       call_center.cc_view_timestamp(t.created_at) AS created_at,
       call_center.cc_get_lookup(t.created_by, (cc.name)::character varying) AS created_by,
       call_center.cc_view_timestamp(t.updated_at) AS updated_at,
       call_center.cc_get_lookup(t.updated_by, (cu.name)::character varying) AS updated_by,
       call_center.cc_view_timestamp(t.last_activity_at) AS activity_at,
       t.name,
       t.imap_host,
       t.smtp_host,
       t.login,
       t.mailbox,
       t.smtp_port,
       t.imap_port,
       t.fetch_err AS fetch_error,
       t.fetch_interval,
       t.state,
       call_center.cc_get_lookup((t.flow_id)::bigint, s.name) AS schema,
    t.description,
    t.enabled,
    t.password
   FROM (((call_center.cc_email_profile t
     LEFT JOIN directory.wbt_user cc ON ((cc.id = t.created_by)))
     LEFT JOIN directory.wbt_user cu ON ((cu.id = t.updated_by)))
     LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.flow_id)));





--
-- Name: cc_email_in_reply_to_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_in_reply_to_index ON call_center.cc_email USING btree (in_reply_to) WHERE (in_reply_to IS NOT NULL);


--
-- Name: cc_email_message_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_message_id_index ON call_center.cc_email USING btree (message_id);


--
-- Name: calendar_day_range(integer, integer); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_day_range(calendar_id integer, days integer) RETURNS SETOF date
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare i int = 0;
    declare y int = 0;
    declare r record;
    declare d timestamp = null;
begin
select c.excepts, c.accepts, tz.sys_name
into r
from  flow.calendar c
          inner join flow.calendar_timezones tz on tz.id = c.timezone_id
where c.id = calendar_id
    limit 1
;

while r notnull and i < days and y < 1000 loop
            d = (now() at time zone r.sys_name + (y || 'd')::interval)::timestamp;
            y = y + 1;

            if exists(select 1 from unnest(r.accepts) x
                where not x.disabled and x.day = (extract(isodow from d)  ) - 1)
               and not exists(
                    select 1
                       from unnest(r.excepts) as x
                       where not x.disabled is true
                         and case
                                 when x.repeat is true then
                                         to_char((d AT TIME ZONE r.sys_name)::date, 'MM-DD') =
                                         to_char((to_timestamp(x.date / 1000) at time zone r.sys_name)::date, 'MM-DD')
                                 else
                                         (d AT TIME ZONE r.sys_name)::date =
                                         (to_timestamp(x.date / 1000) at time zone r.sys_name)::date
                           end
                ) then
                i = i + 1;
                return next d::timestamp;
end if;
end loop;
end;
$$;

drop VIEW if exists flow.acr_routing_scheme_view;
alter table flow.acr_routing_scheme alter column type SET default 'voice'::character;
alter table flow.acr_routing_scheme add column tags character varying[];
--
-- Name: acr_routing_scheme_view; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.acr_routing_scheme_view AS
SELECT s.id,
       s.domain_id,
       s.name,
       s.created_at,
       flow.get_lookup(c.id, (c.name)::character varying) AS created_by,
       s.updated_at,
       flow.get_lookup(u.id, (u.name)::character varying) AS updated_by,
       s.debug,
       s.scheme AS schema,
    s.payload,
    s.type,
    s.editor,
    s.tags
   FROM ((flow.acr_routing_scheme s
     LEFT JOIN directory.wbt_user c ON ((c.id = s.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = s.updated_by)));


--
-- Name: region region_calendar_timezones_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.region
    ADD CONSTRAINT region_calendar_timezones_id_fk FOREIGN KEY (timezone_id) REFERENCES flow.calendar_timezones(id);




--
-- Name: cc_calls_history_list; Type: VIEW; Schema: call_center; Owner: -
--
drop VIEW if exists call_center.cc_calls_history_list;
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
    call_center.cc_get_lookup((cm.id)::bigint, cm.name) AS member,
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
          WHERE ((c.parent_id IS NULL) AND ((hp.parent_id)::text = (c.id)::text)))) AS has_children,
    (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), (''::character varying)::text))::character varying AS agent_description,
    c.grantee_id,
    holds.res AS hold,
    c.gateway_ids,
    c.user_ids,
    c.agent_ids,
    c.queue_ids,
    c.team_ids,
    ( SELECT json_agg(row_to_json(annotations.*)) AS json_agg
           FROM ( SELECT a.id,
                    a.call_id,
                    a.created_at,
                    call_center.cc_get_lookup(cc.id, (COALESCE(cc.name, (cc.username)::text))::character varying) AS created_by,
                    a.updated_at,
                    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS updated_by,
                    a.note,
                    a.start_sec,
                    a.end_sec
                   FROM ((call_center.cc_calls_annotation a
                     LEFT JOIN directory.wbt_user cc ON ((cc.id = a.created_by)))
                     LEFT JOIN directory.wbt_user uc ON ((uc.id = a.updated_by)))
                  WHERE ((a.call_id)::text = (c.id)::text)
                  ORDER BY a.created_at DESC) annotations) AS annotations,
    c.amd_result,
    c.amd_duration,
    cq.type AS queue_type,
        CASE
            WHEN (c.parent_id IS NOT NULL) THEN ''::text
            WHEN ((c.cause)::text = ANY (ARRAY[('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text])) THEN 'not_answered'::text
            WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
            WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
            CASE
                WHEN (((c.cause)::text = 'NORMAL_CLEARING'::text) AND ((((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND (c.user_id IS NOT NULL)) OR (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (c.bridged_at IS NOT NULL)) OR (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (cq.type = ANY (ARRAY[4, 5])) AND (c.bridged_at IS NOT NULL)))) THEN 'agent_dropped'::text
                ELSE 'client_dropped'::text
END
ELSE 'error'::text
END AS hangup_disposition,
    c.blind_transfer,
    ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error, 'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
           FROM storage.file_jobs j
          WHERE (j.file_id = ANY (f.file_ids))) AS files_job,
    transcripts.data AS transcripts,
    c.talk_sec,
    call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee
   FROM (((((((((((((call_center.cc_calls_history c
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
     LEFT JOIN LATERAL ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
           FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                   FROM call_center.cc_calls_history chh
                  WHERE (((chh.parent_id)::text = (c.id)::text) AND (chh.hold IS NOT NULL))
                UNION
                 SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
          WHERE (x.hi IS NOT NULL)) holds ON ((c.parent_id IS NULL)))
     LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
     LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
     LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
     LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
     LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
     LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
     LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
     LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))))
     LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id, 'file', call_center.cc_get_lookup(ff.id, ff.name))) AS data
           FROM (storage.file_transcript tr
             LEFT JOIN storage.files ff ON ((ff.id = tr.file_id)))
          WHERE ((tr.uuid)::text = ((c.id)::character varying(50))::text)
          GROUP BY (tr.uuid)::text) transcripts ON (true));




drop MATERIALIZED VIEW if exists call_center.cc_distribute_stats;
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
       s.over_dial,
       s.abandoned_rate,
       s.hit_rate,
       s.agents,
       s.aggent_ids
FROM ((call_center.cc_queue q
    LEFT JOIN LATERAL ( SELECT
                            CASE
                                WHEN ((((q.payload -> 'amd'::text) -> 'allow_not_sure'::text))::boolean IS TRUE) THEN ARRAY['HUMAN'::text, 'NOTSURE'::text]
                    ELSE ARRAY['HUMAN'::text]
END AS arr) amd ON (true))
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
            count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_result IS NULL)))) AS connected_calls,
            count(*) FILTER (WHERE (att.bridged_at IS NOT NULL)) AS bridged_calls,
            count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (att.bridged_at IS NULL) AND (((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_result IS NULL)))) AS abandoned_calls,
            ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_result IS NULL)))))::double precision / (count(*))::double precision) AS connection_rate,
                CASE
                    WHEN (((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_result IS NULL)))))::double precision / (count(*))::double precision) > (0)::double precision) THEN (((1)::double precision / ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_result IS NULL)))))::double precision / (count(*))::double precision)) - (1)::double precision)
                    ELSE (((count(*) / GREATEST(count(DISTINCT att.agent_id), (1)::bigint)) - 1))::double precision
                END AS over_dial,
            COALESCE(((((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (att.bridged_at IS NULL) AND (((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_result IS NULL)))))::double precision - (COALESCE(((q.payload -> 'abandon_rate_adjustment'::text))::integer, 0))::double precision) / (NULLIF(count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_result IS NULL)))), 0))::double precision) * (100)::double precision), (0)::double precision) AS abandoned_rate,
            ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_result IS NULL)))))::double precision / (count(*))::double precision) AS hit_rate,
            count(DISTINCT att.agent_id) AS agents,
            array_agg(DISTINCT att.agent_id) FILTER (WHERE (att.agent_id IS NOT NULL)) AS aggent_ids
           FROM (call_center.cc_member_attempt_history att
             LEFT JOIN call_center.cc_calls_history ch ON (((ch.domain_id = att.domain_id) AND ((ch.id)::text = (att.member_call_id)::text))))
          WHERE (((att.channel)::text = 'call'::text) AND (att.joined_at > (now() - ((COALESCE(((q.payload -> 'statistic_time'::text))::integer, 60) || ' min'::text))::interval)) AND (att.queue_id = q.id) AND (att.domain_id = q.domain_id))
          GROUP BY att.queue_id, att.bucket_id) s ON ((s.queue_id IS NOT NULL)))
  WHERE ((q.type = 5) AND q.enabled)
  WITH NO DATA;
refresh materialized view call_center.cc_distribute_stats;

alter table call_center.cc_email add column attachment_ids bigint[];



--
-- Name: cc_queue_list; Type: VIEW; Schema: call_center; Owner: -
--
drop VIEW if exists call_center.cc_queue_list;
CREATE VIEW call_center.cc_queue_list AS
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
    COALESCE(ss.member_waiting, (0)::bigint) AS waiting,
    COALESCE(act.cnt, (0)::bigint) AS active,
    q.sticky_agent,
    q.processing,
    q.processing_sec,
    q.processing_renewal_sec,
    jsonb_build_object('enabled', q.processing, 'form_schema', call_center.cc_get_lookup(fs.id, fs.name), 'sec', q.processing_sec, 'renewal_sec', q.processing_renewal_sec) AS task_processing,
    call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee
   FROM (((((((((((((call_center.cc_queue q
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
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL) AND ((a.state)::text <> 'leaving'::text))) act ON (true));




--
-- Name: cc_distribute_inbound_call_to_agent(character varying, character varying, jsonb, integer); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION if exists call_center.cc_distribute_inbound_call_to_agent;
CREATE FUNCTION call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
_domain_id int8;
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;

    _call record;
    _attempt record;

    _a_status varchar;
    _a_channel varchar;
    _number varchar;
    _busy_ext bool;
BEGIN

select *
from call_center.cc_calls c
where c.id = _call_id
--   for update
  into _call;

if _call.id isnull or _call.direction isnull then
      raise exception 'not found call';
end if;

    if _call.id isnull or _call.direction isnull then
      raise exception 'not found call';
  ELSIF _call.direction <> 'outbound' then
      _number = _call.from_number;
else
      _number = _call.destination;
end if;

select
    a.team_id,
    t.updated_at,
    a.status,
    cac.channel,
    a.domain_id,
    (a.updated_at - extract(epoch from u.updated_at))::int8,
        exists (select 1 from call_center.cc_calls c where c.user_id = a.user_id and c.queue_id isnull and c.hangup_at isnull ) busy_ext
from call_center.cc_agent a
         inner join call_center.cc_team t on t.id = a.team_id
         inner join call_center.cc_agent_channel cac on a.id = cac.agent_id
         inner join directory.wbt_user u on u.id = a.user_id
where a.id = _agent_id -- check attempt
    and length(coalesce(u.extension, '')) > 0
  for update
                               into _team_id_,
                               _team_updated_at,
                               _a_status,
                               _a_channel,
                               _domain_id,
                               _agent_updated_at,
                               _busy_ext
;

if _call.domain_id != _domain_id then
      raise exception 'the queue on another domain';
end if;

  if _team_id_ isnull then
      raise exception 'not found agent';
end if;

  if not _a_status = 'online' then
      raise exception 'agent not in online';
end if;

  if not _a_channel isnull  then
      raise exception 'agent is busy';
end if;

  if _busy_ext then
      raise exception 'agent has external call';
end if;


insert into call_center.cc_member_attempt (domain_id, state, team_id, member_call_id, destination, node_id, agent_id, parent_id)
values (_domain_id, 'waiting', _team_id_, _call_id, jsonb_build_object('destination', _number),
        _node_name, _agent_id, _call.attempt_id)
    returning * into _attempt;

update call_center.cc_calls
set team_id = _team_id_,
    attempt_id = _attempt.id,
    payload = variables_
where id = _call_id
    returning * into _call;

if _call.id isnull or _call.direction isnull then
      raise exception 'not found call';
end if;

return row(
        _attempt.id::int8,
        _attempt.destination::jsonb,
        variables_::jsonb,
        _call.from_name::varchar,
        _team_id_::int,
        _team_updated_at::int8,
        _agent_updated_at::int8,

        _call.id::varchar,
        _call.state::varchar,
        _call.direction::varchar,
        _call.destination::varchar,
        call_center.cc_view_timestamp(_call.timestamp)::int8,
        _call.app_id::varchar,
        _number::varchar,
        case when (_call.direction <> 'outbound'
            and _call.to_name::varchar <> ''
            and _call.to_name::varchar notnull)
                 then _call.from_name::varchar
             else _call.to_name::varchar end,
        call_center.cc_view_timestamp(_call.answered_at)::int8,
        call_center.cc_view_timestamp(_call.bridged_at)::int8,
        call_center.cc_view_timestamp(_call.created_at)::int8
    );
END;
$$;


drop FUNCTION if exists call_center.cc_set_active_members;
CREATE FUNCTION call_center.cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
return query update call_center.cc_member_attempt a
        set state = case when c.queue_type = 4 then 'offering' else 'waiting' end
            ,node_id = node
            ,last_state_change = now()
            ,list_communication_id = lc.id
            ,seq = c.attempts + 1
            ,waiting_other_numbers = c.waiting_other_numbers
        from (
            select c.id,
       cq.updated_at                                            as queue_updated_at,
       r.updated_at                                             as resource_updated_at,
       call_center.cc_view_timestamp(gw.updated_at)             as gateway_updated_at,
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
       cq.type                                                  as queue_type
from call_center.cc_member_attempt c
         inner join call_center.cc_member cm on c.member_id = cm.id
         left join lateral (
            select count(*) cnt
            from jsonb_array_elements(cm.communications) WITH ORDINALITY AS x(c, n)
            where coalesce((x.c -> 'stop_at')::int8, 0) < 1
              and x.n != (c.communication_idx + 1)
            ) x on c.member_id notnull
                 inner join call_center.cc_queue cq on cm.queue_id = cq.id
                 left join call_center.cc_team tm on tm.id = cq.team_id
                 left join call_center.cc_outbound_resource r on r.id = c.resource_id
                 left join directory.sip_gateway gw on gw.id = r.gateway_id
                 left join call_center.cc_agent ca on c.agent_id = ca.id
                 left join call_center.cc_queue_statistics cqs on cq.id = cqs.queue_id
                 left join directory.wbt_user u on u.id = ca.user_id
        where c.state = 'idle'
          and c.leaving_at isnull
        order by cq.priority desc, c.weight desc
            for update of c, cm, cq skip locked
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
            c.resource_updated_at::bigint as resource_updated_at,
            c.gateway_updated_at::bigint as gateway_updated_at,
            c.destination,
            c.variables ,
            c.member_name,
            a.member_call_id,
            a.agent_id,
            c.agent_updated_at,
            c.team_updated_at,
            a.list_communication_id,
            a.seq;
END;
$$;




--
-- Name: cc_trigger_list; Type: VIEW; Schema: call_center; Owner: -
--
drop VIEW if exists call_center.cc_trigger_list;
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
    t.updated_at
   FROM ((((call_center.cc_trigger t
     LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.schema_id)))
     LEFT JOIN flow.calendar_timezones tz ON ((tz.id = t.timezone_id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = t.created_by)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = t.updated_by)));


alter table storage.import_template add column if not exists created_at timestamp with time zone DEFAULT now() NOT NULL;
alter table storage.import_template add column if not exists created_by bigint;
alter table storage.import_template add column if not exists updated_at timestamp with time zone DEFAULT now() NOT NULL;
alter table storage.import_template add column if not exists updated_by bigint;



--
-- Name: import_template_acl; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.import_template_acl (
                                             id bigint NOT NULL,
                                             dc bigint NOT NULL,
                                             grantor bigint,
                                             subject bigint NOT NULL,
                                             access smallint DEFAULT 0 NOT NULL,
                                             object bigint NOT NULL
);


--
-- Name: import_template_acl_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.import_template_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_template_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.import_template_acl_id_seq OWNED BY storage.import_template_acl.id;



--
-- Name: import_template_view; Type: VIEW; Schema: storage; Owner: -
--
drop VIEW if exists storage.import_template_view;
CREATE VIEW storage.import_template_view AS
SELECT t.id,
       t.name,
       t.description,
       t.source_type,
       t.source_id,
       t.parameters,
       jsonb_build_object('id', s.id, 'name', s.name) AS source,
       t.domain_id,
       t.created_at,
       storage.get_lookup(c.id, (COALESCE(c.name, (c.username)::text))::character varying) AS created_by,
       t.updated_at,
       storage.get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS updated_by
FROM (((storage.import_template t
    LEFT JOIN directory.wbt_user c ON ((c.id = t.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = t.updated_by)))
    LEFT JOIN LATERAL ( SELECT q.id,
                               q.name
                        FROM call_center.cc_queue q
                        WHERE ((q.id = t.source_id) AND (q.domain_id = t.domain_id))
        LIMIT 1) s ON (true));



--
-- Name: import_template_acl id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl ALTER COLUMN id SET DEFAULT nextval('storage.import_template_acl_id_seq'::regclass);

--
-- Name: import_template_acl import_template_acl_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_pk PRIMARY KEY (id);



--
-- Name: import_template_acl_grantor_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX import_template_acl_grantor_idx ON storage.import_template_acl USING btree (grantor);


--
-- Name: import_template_acl_object_subject_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX import_template_acl_object_subject_udx ON storage.import_template_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: import_template_acl_subject_object_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX import_template_acl_subject_object_udx ON storage.import_template_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: import_template_id_domain_id_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX import_template_id_domain_id_uindex ON storage.import_template USING btree (id, domain_id);

--
-- Name: import_template import_template_set_rbac_acl; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER import_template_set_rbac_acl AFTER INSERT ON storage.import_template FOR EACH ROW EXECUTE FUNCTION storage.tg_obj_default_rbac('import_template');


--
-- Name: import_template_acl import_template_acl_domain_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: import_template_acl import_template_acl_grantor_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: import_template_acl import_template_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: import_template_acl import_template_acl_import_template_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_import_template_id_fk FOREIGN KEY (object) REFERENCES storage.import_template(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: import_template_acl import_template_acl_object_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_object_fk FOREIGN KEY (object, dc) REFERENCES storage.import_template(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: import_template_acl import_template_acl_subject_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;



--
-- Name: appointment_widget(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.appointment_widget(_uri character varying) RETURNS TABLE(profile jsonb, list jsonb)
    LANGUAGE sql ROWS 1
    AS $$
    with profile as (
        select
           (config['queue']->>'id')::int as queue_id,
           (config['communicationType']->>'id')::int as communication_type,
           (config->>'duration')::interval as duration,
           (config->>'days')::int as days,
           (config->>'availableAgents')::int as available_agents,
           string_to_array((b.metadata->>'allow_origin'), ',') as allow_origins,
           q.calendar_id,
           b.id,
           b.uri,
           b.dc as domain_id,
           c.timezone_id,
           tz.sys_name as timezone
        from chat.bot b
            inner join lateral (select (b.metadata->>'appointment')::jsonb as config) as cfx on true
            inner join call_center.cc_queue q on q.id = (config['queue']->>'id')::int
            inner join flow.calendar c on c.id = q.calendar_id
            inner join flow.calendar_timezones tz on tz.id = c.timezone_id
        where b.uri = _uri and b.enabled
        limit 1
    ), d as materialized (
        select  q.queue_id,
                q.duration,
                q.available_agents,
                x,
               (extract(isodow from x::timestamp)  ) - 1 as day,
               dy.*
        from profile  q ,
            flow.calendar_day_range(q.calendar_id, least(q.days, 7)) x
            left join lateral (
                select t.*, tz.sys_name, c.excepts
                from flow.calendar c
                    inner join flow.calendar_timezones tz on tz.id = c.timezone_id
                    inner join lateral unnest(c.accepts::flow.calendar_accept_time[]) t on true
                where c.id = q.calendar_id
                    and not t.disabled
                order by 1 asc
        ) y on y.day = (extract(isodow from x)  ) - 1
        left join lateral (
            select (x + (y.start_time_of_day || 'm')::interval)::timestamp as ss,
                case when date_bin(q.duration, (x + (y.end_time_of_day || 'm')::interval)::timestamp, x::timestamp) < (x + (y.end_time_of_day || 'm')::interval)::timestamp
                    then date_bin(q.duration, (x + (y.end_time_of_day || 'm')::interval)::timestamp, x::timestamp) - q.duration
                    else date_bin(q.duration, (x + (y.end_time_of_day || 'm')::interval)::timestamp, x::timestamp) - q.duration end as se
        ) dy on true
    )
    , min_max as materialized (
        select
            queue_id,
            x,
            duration,
            min(ss)  min_ss,
            max(se)  max_se
        from d
        group by 1, 2, 3
    )
    ,res as materialized (
        select
        mem.*
        from min_max
            left join lateral (
                select
                    date_bin(min_max.duration, coalesce(ready_at, created_at), coalesce(ready_at, created_at)::date)::timestamp d,
                    count(*) cnt
                from call_center.cc_member m
                where m.stop_at isnull
                    and m.queue_id = min_max.queue_id
                    and coalesce(ready_at, created_at) between min_max.min_ss and min_max.max_se
                group by 1
            ) mem on true
        where mem notnull
    )
    , list as (
        select
            d.*,
            res.*,
            xx,
            case when xx < now() or coalesce(res.cnt, 0) >= d.available_agents then true
                else false end as reserved
        from d
            left join generate_series(d.ss, d.se, d.duration) xx on true
            left join res on res.d = xx
        limit 10080
    )
    , ranges AS (
        select
            to_char(list.x::date,'YYYY-MM-DD')::text as date,
            jsonb_agg(jsonb_build_object('time', to_char(list.xx::time, 'HH24:MI'), 'reserved', list.reserved) order by list.x, list.xx) as times
        from list
        group by 1
    )
select
    row_to_json(p) as profile,
    jsonb_agg(row_to_json(r)) as list
from profile p
         left join lateral (
    select *
    from ranges
        ) r on true
group by p
    $$;


drop INDEX if exists call_center.cc_member_appointments_queue_id_ready;
CREATE INDEX cc_member_appointments_queue_id_ready
    ON call_center.cc_member USING
    btree (queue_id, COALESCE(ready_at, created_at))  where (stop_at isnull );