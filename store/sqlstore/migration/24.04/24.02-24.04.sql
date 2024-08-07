alter table storage.upload_file_jobs add column if not exists sha256sum character varying;
alter table storage.files add column if not exists sha256sum character varying;

alter table call_center.cc_calls add column if not exists schema_ids integer[];
alter table call_center.cc_calls_history add column if not exists schema_ids integer[];

alter table call_center.cc_calls add column if not exists contact_id bigint;
alter table call_center.cc_calls_history add column if not exists contact_id bigint;

alter table call_center.cc_member_attempt add column if not exists queue_params jsonb;
alter table call_center.cc_member_attempt add column if not exists variables jsonb;
alter table call_center.cc_member_attempt_history add column if not exists variables jsonb;


alter table call_center.cc_calls add column if not exists heartbeat timestamp with time zone;
alter table call_center.cc_calls add column if not exists hangup_phrase character varying;
alter table call_center.cc_calls_history add column if not exists hangup_phrase character varying;
alter table call_center.cc_calls add column if not exists blind_transfers jsonb;
alter table call_center.cc_calls_history add column if not exists blind_transfers jsonb;

--
-- Name: cc_distribute(boolean); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE or replace PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean)
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
                                                   communication_idx, member_call_id, team_id, resource_group_id, domain_id, import_id, sticky_agent_id, queue_params)
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
                   case when q.type = 5 and q.sticky_agent then dis.agent_id end,
                   call_center.cc_queue_params(q)
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
-- Name: cc_distribute_direct_member_to_queue(character varying, bigint, integer, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint, seq integer, communication_idx integer)
    LANGUAGE plpgsql
AS $$BEGIN
    return query with attempts as (
        insert into call_center.cc_member_attempt (state, queue_id, member_id, destination, communication_idx, node_id, agent_id, resource_id,
                                                   bucket_id, seq, team_id, domain_id, queue_params)
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
                   q.domain_id,
                   call_center.cc_queue_params(q)
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
              and not exists(select 1 from call_center.cc_member_attempt ma  where ma.member_id = _member_id )
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
        a.seq::int seq,
        a.communication_idx::int communication_idx
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
-- Name: cc_distribute_inbound_call_to_agent(character varying, character varying, jsonb, integer, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer, q_params jsonb DEFAULT NULL::jsonb) RETURNS record
    LANGUAGE plpgsql
AS $$declare
    _domain_id int8;
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;

    _call record;
    _attempt record;

    _a_status varchar;
    _a_state varchar;
    _number varchar;
    _busy_ext bool;
BEGIN

select *
from call_center.cc_calls c
where c.id = _call_id::uuid
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
    cac.state,
    a.domain_id,
    (a.updated_at - extract(epoch from u.updated_at))::int8,
        exists (select 1 from call_center.cc_calls c where c.user_id = a.user_id and c.queue_id isnull and c.hangup_at isnull ) busy_ext
from call_center.cc_agent a
         inner join call_center.cc_team t on t.id = a.team_id
         inner join call_center.cc_agent_channel cac on a.id = cac.agent_id and cac.channel = 'call'
         inner join directory.wbt_user u on u.id = a.user_id
where a.id = _agent_id -- check attempt
      and length(coalesce(u.extension, '')) > 0
        for update
                                       into _team_id_,
                                       _team_updated_at,
                                       _a_status,
                                       _a_state,
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

    if _a_state != 'waiting'  then
        raise exception 'agent is busy';
end if;

    if _busy_ext then
        raise exception 'agent has external call';
end if;


insert into call_center.cc_member_attempt (domain_id, state, team_id, member_call_id, destination, node_id, agent_id, parent_id, queue_params)
values (_domain_id, 'waiting', _team_id_, _call_id, jsonb_build_object('destination', _number),
        _node_name, _agent_id, _call.attempt_id, q_params)
    returning * into _attempt;

update call_center.cc_calls
set team_id = _team_id_,
    attempt_id = _attempt.id,
    payload    = case when jsonb_typeof(variables_::jsonb) = 'object' then variables_ else coalesce(payload, '{}') end
    where id = _call_id::uuid
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


--
-- Name: cc_distribute_inbound_call_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
    LANGUAGE plpgsql
AS $$declare
    _timezone_id             int4;
    _discard_abandoned_after int4;
    _weight                  int4;
    dnc_list_id_ int4;
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
    _name                  varchar;
    _max_waiting_size        int;
    _grantee_id              int8;
    _qparams jsonb;
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
        q.grantee_id,
       call_center.cc_queue_params(q)
from call_center.cc_queue q
         inner join flow.calendar c on q.calendar_id = c.id
         left join call_center.cc_team ct on q.team_id = ct.id
where q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _grantee_id, _qparams;

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
where c.id = _call_id::uuid
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
_name = _call.from_name;
else
        _number = _call.destination;
end if;

--   raise  exception '%', _name;


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
                                           parent_id, queue_params)
values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id,
        jsonb_build_object('destination', _number, 'name', coalesce(_name, _number)),
        _node_name, _sticky_agent_id, null, _call.attempt_id, _qparams)
    returning * into _attempt;

update call_center.cc_calls
set queue_id   = _attempt.queue_id,
    team_id    = _team_id_,
    attempt_id = _attempt.id,
    payload    = case when jsonb_typeof(variables_::jsonb) = 'object' then variables_ else coalesce(payload, '{}') end, --coalesce(variables_, '{}'),
        grantee_id = _grantee_id
    where id = _call_id::uuid
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


--
-- Name: cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
    _max_waiting_size int;
    _qparams jsonb;
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
       (payload->>'max_waiting_size')::int max_size,
        call_center.cc_queue_params(q)
from call_center.cc_queue q
         inner join flow.calendar c on q.calendar_id = c.id
         left join call_center.cc_team ct on q.team_id = ct.id
where  q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _qparams;

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

insert into call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_id, bucket_id, weight, member_call_id,
                                           destination, node_id, sticky_agent_id, list_communication_id, queue_params)
values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id::varchar,
        jsonb_build_object('destination', _con_name, 'name', _client_name, 'msg', _last_msg, 'chat', _con_type),
        _node_name, _sticky_agent_id, (select clc.id
                                       from call_center.cc_list_communications clc
                                       where (clc.list_id = dnc_list_id_ and clc.number = _conversation_id)), _qparams)
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
-- Name: cc_distribute_task_to_agent(character varying, bigint, integer, jsonb, jsonb, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_task_to_agent(_node_name character varying, _domain_id bigint, _agent_id integer, _destination jsonb, variables_ jsonb, _qparams jsonb) RETURNS record
    LANGUAGE plpgsql
AS $$declare
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;

    _attempt record;

    _a_status varchar;
    _a_state varchar;
    _busy_ext bool;
BEGIN

select
    a.team_id,
    t.updated_at,
    a.status,
    cac.state,
    (a.updated_at - extract(epoch from u.updated_at))::int8,
        exists (select 1 from call_center.cc_calls c where c.user_id = a.user_id and c.queue_id isnull and c.hangup_at isnull ) busy_ext
from call_center.cc_agent a
         inner join call_center.cc_team t on t.id = a.team_id
         inner join call_center.cc_agent_channel cac on a.id = cac.agent_id and cac.channel = 'task'
         inner join directory.wbt_user u on u.id = a.user_id
where a.id = _agent_id -- check attempt
      and a.domain_id = _domain_id
        for update
                                       into _team_id_,
                                       _team_updated_at,
                                       _a_status,
                                       _a_state,
                                       _agent_updated_at,
                                       _busy_ext
;

if _team_id_ isnull then
        raise exception 'not found agent';
end if;


insert into call_center.cc_member_attempt (channel, domain_id, state, team_id, member_call_id, destination, node_id, agent_id, queue_params)
values ('task', _domain_id, 'waiting', _team_id_, null, _destination,
        _node_name, _agent_id, _qparams)
    returning * into _attempt;

return row(
        _attempt.id::int8,
        _attempt.destination::jsonb,
        variables_::jsonb,
        _team_id_::int,
        _team_updated_at::int8,
        _agent_updated_at::int8
    );
END;
$$;

--
-- Name: cc_queue_params(call_center.cc_queue); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_queue_params(q call_center.cc_queue) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
AS $$
select jsonb_build_object('has_reporting', q.processing)
           || jsonb_build_object('has_form', q.processing and q.form_schema_id notnull)
           || jsonb_build_object('processing_sec', q.processing_sec)
           || jsonb_build_object('processing_renewal_sec', q.processing_renewal_sec)
           || jsonb_build_object('queue_name', q.name) as queue_params;
$$;



--
-- Name: cc_team_event_changed_tg(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_team_event_changed_tg() RETURNS trigger
    LANGUAGE plpgsql
AS $$BEGIN
    IF (TG_OP = 'DELETE') THEN
update call_center.cc_team
set updated_at = (extract(epoch from now()) * 1000)::int8
where id = old.team_id;

return old;
else
update call_center.cc_team
set updated_at = (extract(epoch from new.updated_at) * 1000)::int8,
            updated_by = new.updated_by
where id = new.team_id;

return new;
end if;
END;
$$;



--
-- Name: cc_team_trigger; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_team_trigger (
                                             id integer NOT NULL,
                                             team_id integer NOT NULL,
                                             name character varying NOT NULL,
                                             description character varying,
                                             enabled boolean DEFAULT false NOT NULL,
                                             schema_id integer NOT NULL,
                                             created_at timestamp with time zone DEFAULT now() NOT NULL,
                                             created_by bigint,
                                             updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                             updated_by bigint
);


--
-- Name: cc_team_trigger_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_team_trigger_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_team_trigger_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_team_trigger_id_seq OWNED BY call_center.cc_team_trigger.id;


--
-- Name: cc_team_trigger_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_team_trigger_list AS
SELECT qt.id,
       call_center.cc_get_lookup((qt.schema_id)::bigint, s.name) AS schema,
       qt.name,
       qt.description,
       qt.enabled,
       call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
       qt.created_at,
       call_center.cc_get_lookup(uu.id, (COALESCE(uu.name, (uu.username)::text))::character varying) AS updated_by,
       qt.team_id,
       qt.schema_id
FROM (((call_center.cc_team_trigger qt
    LEFT JOIN flow.acr_routing_scheme s ON ((s.id = qt.schema_id)))
    LEFT JOIN directory.wbt_user uc ON ((uc.id = qt.created_by)))
    LEFT JOIN directory.wbt_user uu ON ((uu.id = qt.updated_by)));

--
-- Name: cc_team_trigger id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_trigger ALTER COLUMN id SET DEFAULT nextval('call_center.cc_team_trigger_id_seq'::regclass);

--
-- Name: cc_team_trigger cc_team_trigger_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_trigger
    ADD CONSTRAINT cc_team_trigger_pkey PRIMARY KEY (id);

--
-- Name: cc_team_trigger_schema_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_trigger_schema_id_index ON call_center.cc_team_trigger USING btree (schema_id);


--
-- Name: cc_team_events cc_team_events_changed; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_team_events_changed AFTER INSERT OR DELETE OR UPDATE ON call_center.cc_team_events FOR EACH ROW EXECUTE FUNCTION call_center.cc_team_event_changed_tg();


--
-- Name: cc_team_trigger cc_team_trigger_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_trigger
    ADD CONSTRAINT cc_team_trigger_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id) ON DELETE CASCADE;


--
-- Name: cc_team_trigger cc_team_trigger_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_trigger
    ADD CONSTRAINT cc_team_trigger_cc_team_id_fk FOREIGN KEY (team_id) REFERENCES call_center.cc_team(id) ON DELETE CASCADE;


update call_center.cc_agent
set task_count = greatest(task_count, 1),
    chat_count = greatest(chat_count, 1),
    progressive_count = greatest(progressive_count, 1);




--
-- Name: cc_distribute_inbound_call_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
    LANGUAGE plpgsql
    AS $$declare
_timezone_id             int4;
_discard_abandoned_after int4;
_weight                  int4;
dnc_list_id_ int4;
    _domain_id               int8;
    _calendar_id             int4;
    _queue_updated_at        int8;
    _team_updated_at         int8;
    _team_id_                int;
    _list_comm_id            int8;
    _enabled                 bool;
    _q_type                  smallint;
    _sticky                  bool;
    _sticky_ignore_status                  bool;
    _call                    record;
    _attempt                 record;
    _number                  varchar;
    _name                  varchar;
    _max_waiting_size        int;
    _grantee_id              int8;
    _qparams jsonb;
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
        case when jsonb_typeof(payload->'sticky_ignore_status') = 'boolean'
                 then (payload->'sticky_ignore_status')::bool else false end sticky_ignore_status,
       q.grantee_id,
       call_center.cc_queue_params(q)
from call_center.cc_queue q
         inner join flow.calendar c on q.calendar_id = c.id
         left join call_center.cc_team ct on q.team_id = ct.id
where q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _sticky_ignore_status, _grantee_id, _qparams;

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
where c.id = _call_id::uuid
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
_name = _call.from_name;
else
        _number = _call.destination;
end if;

--   raise  exception '%', _name;


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

insert into call_center.cc_member_attempt (domain_id, state, queue_id, team_id, member_id, bucket_id, weight,
                                           member_call_id, destination, node_id, sticky_agent_id,
                                           list_communication_id,
                                           parent_id, queue_params)
values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id,
        jsonb_build_object('destination', _number, 'name', coalesce(_name, _number)),
        _node_name, _sticky_agent_id, null, _call.attempt_id, _qparams)
    returning * into _attempt;

update call_center.cc_calls
set queue_id   = _attempt.queue_id,
    team_id    = _team_id_,
    attempt_id = _attempt.id,
    payload    = case when jsonb_typeof(variables_::jsonb) = 'object' then variables_ else coalesce(payload, '{}') end, --coalesce(variables_, '{}'),
    grantee_id = _grantee_id
where id = _call_id::uuid
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



--
-- Name: cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
       (payload->>'max_waiting_size')::int max_size,
        case when jsonb_typeof(payload->'sticky_ignore_status') = 'boolean'
                 then (payload->'sticky_ignore_status')::bool else false end sticky_ignore_status,
       call_center.cc_queue_params(q)
from call_center.cc_queue q
         inner join flow.calendar c on q.calendar_id = c.id
         left join call_center.cc_team ct on q.team_id = ct.id
where  q.id = _queue_id
  into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
      _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _sticky_ignore_status, _qparams;

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
                                           destination, node_id, sticky_agent_id, list_communication_id, queue_params)
values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id::varchar,
        jsonb_build_object('destination', _con_name, 'name', _client_name, 'msg', _last_msg, 'chat', _con_type),
        _node_name, _sticky_agent_id, (select clc.id
                                       from call_center.cc_list_communications clc
                                       where (clc.list_id = dnc_list_id_ and clc.number = _conversation_id)), _qparams)
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

drop table if exists call_center.cc_agent_attempt;



drop VIEW call_center.cc_calls_history_list;
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
           WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND (c.id <> call_center.cc_bridged_id(c.parent_id))) THEN call_center.cc_bridged_id(c.parent_id)
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
       ( SELECT json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at', ((c.params -> 'record_start'::text))::bigint, 'stop_at', ((c.params -> 'record_stop'::text))::bigint)) AS files
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
                WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) AS files,
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
                 WHERE ((c.parent_id IS NULL) AND (hp.parent_id = c.id) AND (hp.created_at > (c.created_at)::date)))) AS has_children,
       (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), (''::character varying)::text))::character varying AS agent_description,
       c.grantee_id,
       ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
         FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                FROM call_center.cc_calls_history chh
                WHERE ((chh.parent_id = c.id) AND (chh.created_at > (c.created_at)::date) AND (chh.hold IS NOT NULL))
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
           WHEN (((c.cause)::text = 'ORIGINATOR_CANCEL'::text) OR (((c.cause)::text = 'NORMAL_UNSPECIFIED'::text) AND (c.amd_ai_result IS NOT NULL)) OR (((c.cause)::text = 'LOSE_RACE'::text) AND (cq.type = 4))) THEN 'cancelled'::text
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
         WHERE (j.file_id IN ( SELECT f_1.id
                               FROM ( SELECT f1.id
                                      FROM storage.files f1
                                      WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.id)::text))
                                      UNION
                                      SELECT f1.id
                                      FROM storage.files f1
                                      WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1))) AS files_job,
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
       c.search_number,
       c.hide_missed,
       c.redial_id,
       exists(select 1 from call_center.cc_calls_history lega where lega.id = c.parent_id and lega.bridged_id notnull ) AS parent_bridged,
       ( SELECT jsonb_agg(call_center.cc_get_lookup(ash.id, ash.name)) AS jsonb_agg
         FROM flow.acr_routing_scheme ash
         WHERE (ash.id = ANY (c.schema_ids))) AS schemas,
       c.schema_ids,
       c.hangup_phrase,
       c.blind_transfers
FROM ((((((((((((((call_center.cc_calls_history c
    LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
    LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
    LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
    LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
    LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
    LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
    LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
    LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
    LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
    LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
    LEFT JOIN directory.wbt_user aru ON ((aru.id = ar.rated_user_id)))
    LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by))))
    LEFT JOIN contacts.contact cc ON ((cc.id = c.contact_id)));



drop view call_center.cc_list_communications_view;
alter table call_center.cc_list_communications
    alter column number type varchar(256) using number::varchar(256);

create view call_center.cc_list_communications_view(id, number, description, list_id, domain_id, expire_at) as
SELECT i.id,
       i.number,
       i.description,
       i.list_id,
       cl.domain_id,
       i.expire_at
FROM call_center.cc_list_communications i
         LEFT JOIN call_center.cc_list cl ON cl.id = i.list_id;



--
-- Name: cc_team_trigger_team_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_trigger_team_id_name_uindex ON call_center.cc_team_trigger USING btree (team_id, name);


--
-- Name: cc_team_trigger_team_id_schema_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_trigger_team_id_schema_id_uindex ON call_center.cc_team_trigger USING btree (team_id, schema_id);



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