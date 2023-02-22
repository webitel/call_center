

create unique index cc_distribute_stats_uidx on call_center.cc_distribute_stats using btree(queue_id, bucket_id nulls last );
create unique index cc_inbound_stats_uidx on call_center.cc_inbound_stats using btree(queue_id, bucket_id nulls last );
drop index if exists call_center.cc_agent_today_pause_cause_agent_idx;
create unique index cc_agent_today_pause_cause_agent_uidx
    on call_center.cc_agent_today_pause_cause (id, today, cause);
create unique index cc_agent_today_stats_uidx
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

CREATE INDEX cc_member_queue_id_created_at ON call_center.cc_member USING btree (queue_id, created_at DESC);

