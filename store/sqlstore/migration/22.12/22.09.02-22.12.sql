

create unique index if not exists cc_distribute_stats_uidx on call_center.cc_distribute_stats using btree(queue_id, bucket_id nulls last );
create unique index if not exists cc_inbound_stats_uidx on call_center.cc_inbound_stats using btree(queue_id, bucket_id nulls last );
drop index if exists call_center.cc_agent_today_pause_cause_agent_idx;
create unique index if not exists cc_agent_today_pause_cause_agent_uidx
    on call_center.cc_agent_today_pause_cause (id, today, cause);
create unique index if not exists cc_agent_today_stats_uidx
    on call_center.cc_agent_today_stats (agent_id);



create or replace function call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) returns record
    language plpgsql
as
$$
declare
    _timezone_id             int4;
    _discard_abandoned_after int4;
    _weight                  int4;
    dnc_list_id_
                             int4;
    _domain_id               int8;
    _calendar_id             int4;
    _queue_updated_at        int8;
    _team_updated_at         int8;
    _team_id_                int;
    _list_comm_id            int8;
    _enabled                 bool;
    _q_type                  smallint;
    _sticky                  bool;
    _call                    record;
    _attempt                 record;
    _number                  varchar;
    _max_waiting_size        int;
    _grantee_id              int8;
BEGIN
    select c.timezone_id,
           (payload ->> 'discard_abandoned_after')::int discard_abandoned_after,
           c.domain_id,
           q.dnc_list_id,
           q.calendar_id,
           q.updated_at,
           ct.updated_at,
           q.team_id,
           q.enabled,
           q.type,
           q.sticky_agent,
           (payload ->> 'max_waiting_size')::int        max_size,
           q.grantee_id
    from call_center.cc_queue q
             inner join flow.calendar c on q.calendar_id = c.id
             left join call_center.cc_team ct on q.team_id = ct.id
    where q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _grantee_id;

    if
        not _q_type = 1 then
        raise exception 'queue not inbound';
    end if;

    if
        not _enabled = true then
        raise exception 'queue disabled';
    end if;

    select *
    from call_center.cc_calls c
    where c.id = _call_id
--   for update
    into _call;

    if
            _call.domain_id != _domain_id then
        raise exception 'the queue on another domain';
    end if;

    if
            _call.id isnull or _call.direction isnull then
        raise exception 'not found call';
    ELSIF
                _call.direction <> 'outbound' or _call.user_id notnull then
        _number = _call.from_number;
    else
        _number = _call.destination;
    end if;

--   raise  exception '%', _number;


    if
        not exists(select accept
                   from flow.calendar_check_timing(_domain_id, _calendar_id, null)
                            as x (name varchar, excepted varchar, accept bool, expire bool)
                   where accept
                     and excepted is null
                     and not expire)
    then
        raise exception 'number % calendar not working [%]', _number, _calendar_id;
    end if;


    if
            _max_waiting_size > 0 then
        if (select count(*)
            from call_center.cc_member_attempt aa
            where aa.queue_id = _queue_id
              and aa.bridged_at isnull
              and aa.leaving_at isnull
              and (bucket_id_ isnull or aa.bucket_id = bucket_id_)) >= _max_waiting_size then
            raise exception using
                errcode = 'MAXWS',
                message = 'Queue maximum waiting size';
        end if;
    end if;

    if
        dnc_list_id_ notnull then
        select clc.id
        into _list_comm_id
        from call_center.cc_list_communications clc
        where (clc.list_id = dnc_list_id_
            and clc.number = _number)
        limit 1;
    end if;

    if
        _list_comm_id notnull then
        raise exception 'number % banned', _number;
    end if;

    if
            _discard_abandoned_after > 0 then
        select case
                   when log.result = 'abandoned' then
                           extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
                   else coalesce(_priority, 0)
                   end
        from call_center.cc_member_attempt_history log
        where log.leaving_at >= (now() - (_discard_abandoned_after || ' sec')::interval)
          and log.queue_id = _queue_id
          and log.destination ->> 'destination' = _number
        order by log.leaving_at desc
        limit 1
        into _weight;
    end if;

    if
            _sticky_agent_id notnull and _sticky then
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

    insert into call_center.cc_member_attempt (domain_id, state, queue_id, team_id, member_id, bucket_id, weight,
                                               member_call_id, destination, node_id, sticky_agent_id,
                                               list_communication_id,
                                               parent_id)
    values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id,
            jsonb_build_object('destination', _number),
            _node_name, _sticky_agent_id, null, _call.attempt_id)
    returning * into _attempt;

    update call_center.cc_calls
    set queue_id   = _attempt.queue_id,
        team_id    = _team_id_,
        attempt_id = _attempt.id,
        payload    = case when jsonb_typeof(variables_::jsonb) = 'object' then variables_ else coalesce(payload, '{}') end, --coalesce(variables_, '{}'),
        grantee_id = _grantee_id
    where id = _call_id
    returning * into _call;

    if
            _call.id isnull or _call.direction isnull then
        raise exception 'not found call';
    end if;

    return row (
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
        case
            when (_call.direction <> 'outbound'
                and _call.to_name:: varchar <> ''
                and _call.to_name:: varchar notnull)
                then _call.from_name::varchar
            else _call.to_name::varchar end,
        call_center.cc_view_timestamp(_call.answered_at)::int8,
        call_center.cc_view_timestamp(_call.bridged_at)::int8,
        call_center.cc_view_timestamp(_call.created_at)::int8
        );

END;
$$;

create or replace function call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer) returns record
    language plpgsql
as
$$
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
        payload    = case when jsonb_typeof(variables_::jsonb) = 'object' then variables_ else coalesce(payload, '{}') end
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


create or replace function call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint)
    returns TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint, seq integer)
    language plpgsql
as
$$
declare
    _weight      int4;
    _destination jsonb;
BEGIN

    return query with attempts as (
        insert into call_center.cc_member_attempt (state, queue_id, member_id, destination, communication_idx, node_id, agent_id, resource_id,
                                                   bucket_id, seq, team_id, domain_id)
            select 1,
                   m.queue_id,
                   m.id,
                   m.communications -> (_communication_id::int2),
                   (_communication_id::int2),
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


--
-- Name: cc_distribute_direct_member_to_queue(character varying, bigint, integer, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint, seq integer)
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



--
-- Name: cc_set_active_members(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer)
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
-- Name: cc_member_queue_id_created_at; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX if not exists cc_member_queue_id_created_at ON call_center.cc_member USING btree (queue_id, created_at DESC);



-- 02
create or replace  function call_center.cc_calls_rbac_users_from_group(_domain_id int8, _access smallint, _groups int[]) returns int[]
as
$$
select array_agg(distinct am.member_id::int)
from directory.wbt_class c
         inner join directory.wbt_default_acl a on a.object = c.id
         join directory.wbt_auth_member am on am.role_id = a.grantor
where c.name = 'calls'
  and c.dc = _domain_id
  and a.access&_access = _access and a.subject = any(_groups)
$$ language sql immutable ;

create or replace function call_center.cc_calls_rbac_users(_domain_id int8, _user_id int8) returns int[]
as
$$
with x as materialized (
    select a.user_id, a.id agent_id, a.supervisor, a.domain_id
    from directory.wbt_user u
             inner join call_center.cc_agent a on a.user_id = u.id
    where u.id = _user_id
      and u.dc = _domain_id
)
select array_agg(distinct a.user_id::int) users
from x
         left join lateral (
    select a.user_id, a.auditor_ids && array [x.user_id] aud
    from call_center.cc_agent a
    where a.domain_id = x.domain_id
      and (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and a.supervisor) or
           a.auditor_ids && array [x.user_id])

    union
    distinct

    select a.user_id, a.auditor_ids && array [x.user_id] aud
    from call_center.cc_team t
             inner join call_center.cc_agent a on a.team_id = t.id
    where t.admin_ids && array [x.agent_id]
      and x.domain_id = t.domain_id
    ) a on true
$$ language sql immutable ;


create or replace  function call_center.cc_calls_rbac_queues(_domain_id int8, _user_id int8, _groups int[]) returns int[]
as
$$
with x as (select a.user_id, a.id agent_id, a.supervisor, a.domain_id
           from directory.wbt_user u
                    inner join call_center.cc_agent a on a.user_id = u.id and a.domain_id = u.dc
           where u.id = _user_id
             and u.dc = _domain_id)
select array_agg(distinct t.queue_id)
from (select qs.queue_id::int as queue_id
      from x
               left join lateral (
          select a.id, a.auditor_ids && array [x.user_id] aud
          from call_center.cc_agent a
          where (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and a.supervisor))
          union
          distinct
          select a.id, a.auditor_ids && array [x.user_id] aud
          from call_center.cc_team t
                   inner join call_center.cc_agent a on a.team_id = t.id
          where t.admin_ids && array [x.agent_id]
          ) a on true
               inner join call_center.cc_skill_in_agent sa on sa.agent_id = a.id
               inner join call_center.cc_queue_skill qs
                          on qs.skill_id = sa.skill_id and sa.capacity between qs.min_capacity and qs.max_capacity
      where sa.enabled
        and qs.enabled
      union distinct
      select q.id
      from call_center.cc_queue q
      where q.domain_id = _domain_id
        and q.grantee_id = any (_groups)) t
$$ language sql immutable ;;


create index concurrently  if not exists cc_calls_history_grantee_id_index
    on call_center.cc_calls_history
        using btree(grantee_id asc nulls last );


refresh materialized view call_center.cc_inbound_stats;
refresh materialized view call_center.cc_distribute_stats;
refresh materialized view call_center.cc_agent_today_stats;
refresh materialized view call_center.cc_agent_today_pause_cause;




-- TODO NEW

--
-- Name: appointment_widget(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.appointment_widget(_uri character varying) RETURNS TABLE(profile jsonb, list jsonb)
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
            q.timezone,
            x,
            (extract(isodow from x::timestamp)  ) - 1 as day,
            dy.*,
            min(dy.ss::time) over () mins,
            max(dy.se::time) over () maxe
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
        case when xx < now() at time zone d.timezone or coalesce(res.cnt, 0) >= d.available_agents or xx < d.ss or xx > d.se then true
             else false end as reserved
    from d
             left join generate_series((d.x || ' ' || d.mins)::timestamp, (d.x || ' ' || d.maxe)::timestamp, d.duration) xx on true
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





--
-- Name: cc_attempt_abandoned(bigint, integer, integer, jsonb, boolean, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_attempt_abandoned(attempt_id_ bigint, _max_count integer DEFAULT 0, _next_after integer DEFAULT 0, vars_ jsonb DEFAULT NULL::jsonb, _per_number boolean DEFAULT false, exclude_dest boolean DEFAULT false, redial boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
AS $$
declare
    attempt  call_center.cc_member_attempt%rowtype;
    member_stop_cause varchar;
begin
    update call_center.cc_member_attempt
    set leaving_at = now(),
        last_state_change = now(),
        result = case when offering_at isnull and resource_id notnull then 'failed' else 'abandoned' end,
        state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    if attempt.member_id notnull then
        update call_center.cc_member
        set last_hangup_at  = (extract(EPOCH from now() ) * 1000)::int8,
            last_agent      = coalesce(attempt.agent_id, last_agent),
            stop_at = case when (stop_cause notnull or
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (_max_count > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < _max_count)) else (_max_count > 0 and (attempts + 1 < _max_count)) end
                )  then stop_at else  attempt.leaving_at end,
            stop_cause = case when (stop_cause notnull or
                                    case when _per_number is true then (attempt.waiting_other_numbers > 0 or (_max_count > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < _max_count)) else (_max_count > 0 and (attempts + 1 < _max_count)) end
                ) then stop_cause else attempt.result end,
            ready_at = now() + (_next_after || ' sec')::interval,
            communications =  jsonb_set(communications, (array[attempt.communication_idx::int])::text[], communications->(attempt.communication_idx::int) ||
                                                                                                         jsonb_build_object('last_activity_at', (case when redial is true then 0 else extract(epoch  from attempt.leaving_at) * 1000 end )::int8::text::jsonb) ||
                                                                                                         jsonb_build_object('attempt_id', attempt_id_) ||
                                                                                                         jsonb_build_object('attempts', coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                                                                                                         case when exclude_dest or (_per_number is true and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= _max_count) then jsonb_build_object('stop_at', (extract(EPOCH from now() ) * 1000)::int8) else '{}'::jsonb end
                ),
            variables = case when vars_ notnull then coalesce(variables::jsonb, '{}') || vars_ else variables end,
            attempts        = attempts + 1                     --TODO
        where id = attempt.member_id
        returning stop_cause into member_stop_cause;
    end if;


    return row(attempt.last_state_change::timestamptz, member_stop_cause::varchar, attempt.result::varchar);
end;
$$;





--
-- Name: cc_calls_rbac_queues(bigint, bigint, integer[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_calls_rbac_queues(_domain_id bigint, _user_id bigint, _groups integer[]) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
AS $$
with x as (select a.user_id, a.id agent_id, a.supervisor, a.domain_id
           from directory.wbt_user u
                    inner join call_center.cc_agent a on a.user_id = u.id and a.domain_id = u.dc
           where u.id = _user_id
             and u.dc = _domain_id)
select array_agg(distinct t.queue_id)
from (select qs.queue_id::int as queue_id
      from x
               left join lateral (
          select a.id, a.auditor_ids && array [x.user_id] aud
          from call_center.cc_agent a
          where (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and a.supervisor))
          union
          distinct
          select a.id, a.auditor_ids && array [x.user_id] aud
          from call_center.cc_team t
                   inner join call_center.cc_agent a on a.team_id = t.id
          where t.admin_ids && array [x.agent_id]
          ) a on true
               inner join call_center.cc_skill_in_agent sa on sa.agent_id = a.id
               inner join call_center.cc_queue_skill qs
                          on qs.skill_id = sa.skill_id and sa.capacity between qs.min_capacity and qs.max_capacity
      where sa.enabled
        and qs.enabled
      union distinct
      select q.id
      from call_center.cc_queue q
      where q.domain_id = _domain_id
        and q.grantee_id = any (_groups)) t
$$;


--
-- Name: cc_calls_rbac_users(bigint, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_calls_rbac_users(_domain_id bigint, _user_id bigint) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
AS $$
with x as materialized (
    select a.user_id, a.id agent_id, a.supervisor, a.domain_id
    from directory.wbt_user u
             inner join call_center.cc_agent a on a.user_id = u.id
    where u.id = _user_id
      and u.dc = _domain_id
)
select array_agg(distinct a.user_id::int) users
from x
         left join lateral (
    select a.user_id, a.auditor_ids && array [x.user_id] aud
    from call_center.cc_agent a
    where a.domain_id = x.domain_id
      and (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and a.supervisor) or
           a.auditor_ids && array [x.user_id])

    union
    distinct

    select a.user_id, a.auditor_ids && array [x.user_id] aud
    from call_center.cc_team t
             inner join call_center.cc_agent a on a.team_id = t.id
    where t.admin_ids && array [x.agent_id]
      and x.domain_id = t.domain_id
    ) a on true
$$;


--
-- Name: cc_calls_rbac_users_from_group(bigint, smallint, integer[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_calls_rbac_users_from_group(_domain_id bigint, _access smallint, _groups integer[]) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
AS $$
select array_agg(distinct am.member_id::int)
from directory.wbt_class c
         inner join directory.wbt_default_acl a on a.object = c.id
         join directory.wbt_auth_member am on am.role_id = a.grantor
where c.name = 'calls'
  and c.dc = _domain_id
  and a.access&_access = _access and a.subject = any(_groups)
$$;


alter TABLE call_center.cc_email_profile add column params jsonb;
alter TABLE call_center.cc_email_profile add column auth_type character varying DEFAULT 'plain'::character varying NOT NULL;
alter TABLE call_center.cc_email_profile add column listen boolean DEFAULT false NOT NULL;



drop VIEW call_center.cc_email_profile_list;
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
       t.password,
       t.listen
FROM (((call_center.cc_email_profile t
    LEFT JOIN directory.wbt_user cc ON ((cc.id = t.created_by)))
    LEFT JOIN directory.wbt_user cu ON ((cu.id = t.updated_by)))
    LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.flow_id)));


--
-- Name: cc_calls_history_grantee_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX if not exists cc_calls_history_grantee_id_index ON call_center.cc_calls_history USING btree (grantee_id);


--
-- Name: cc_calls_history_queue_id_dom; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX if not exists cc_calls_history_queue_id_dom ON call_center.cc_calls_history USING btree (domain_id, created_at, user_id, queue_id);


ALTER TABLE ONLY call_center.cc_member
    drop CONSTRAINT if exists cc_member_cc_agent_id_fk;

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE SET NULL ON DELETE SET NULL;



alter table storage.upload_file_jobs add column view_name character varying;
alter table storage.files add column view_name character varying;