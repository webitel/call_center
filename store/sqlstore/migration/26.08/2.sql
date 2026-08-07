create or replace function "call_center"."cc_agent_has_queue_skill"(p_agent_id int8, p_queue_id int8, p_domain_id int8, p_ignore_status boolean default false)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from "call_center"."cc_agent" a
    where a."id" = p_agent_id
      and a."domain_id" = p_domain_id
      and (a."status" = 'online' or p_ignore_status is true)
      and exists (
        select 1
        from "call_center"."cc_skill_in_agent" sa
        inner join "call_center"."cc_queue_skill" qs on qs."skill_id" = sa."skill_id" and qs."queue_id" = p_queue_id
        left join "call_center"."cc_online_skills" sp on sp."id" = a."status_id" and a."status" = 'online'
        left join "call_center"."cc_skills_in_online_skill" spp on spp."online_skill_id" = a."status_id" and spp."skill_id" = sa."skill_id" and a."status" = 'online'
        where sa."agent_id" = a."id"
          and sa."enabled"
          and sa."capacity" between qs."min_capacity" and qs."max_capacity"
          and (
            a."status_id" is null or a."status" <> 'online' or spp."skill_id" is not null or sp."is_system" is true
          )
      )
  );
$$;

CREATE FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
    _member_jsonb jsonb;
    _last_msg_channel_type varchar;
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
         lst.channel_type,
         c.type
  from chat.channel c
           left join chat.client cli on cli.id = c.user_id
           left join lateral (
               	select
					coalesce(m.text, m.file_name, 'empty') message,
					ch.type as channel_type
                from chat.message m
                left join chat.channel ch on ch.id = m.channel_id
                where m.conversation_id = _conversation_id::uuid
                order by m.created_at desc
                limit 1
           ) lst on true
  where c.closed_at isnull
        and c.conversation_id = _conversation_id::uuid
    and not c.internal
  into _con_name, _con_created, _inviter_channel_id, _inviter_user_id, _client_name, _last_msg, _last_msg_channel_type, _con_type;

  if coalesce(_inviter_channel_id, '') = '' or coalesce(_inviter_user_id, '') = '' isnull then
      raise exception using
            errcode='VALID',
            message='Bad request inviter_channel_id or user_id';
  end if;

  _member_jsonb := null;

  if _last_msg_channel_type is null then
      _member_jsonb := jsonb_build_object('type', 'bot');
  elseif _last_msg_channel_type = 'webitel' then
      _member_jsonb := jsonb_build_object('type', 'agent');
  else
      _member_jsonb := jsonb_build_object('type', 'contacts');
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

  if _sticky_agent_id is not null and _sticky then
    if not call_center.cc_agent_has_queue_skill(_sticky_agent_id, _queue_id, _domain_id, _sticky_ignore_status) then
      _sticky_agent_id = null;
    end if;
  else _sticky_agent_id = null;
  end if;


  insert into call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_id, bucket_id, weight, member_call_id,
                                             destination, node_id, sticky_agent_id, list_communication_id, queue_params, queue_type)
  values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id::varchar,
          jsonb_build_object('destination', _con_name, 'name', _client_name, 'msg', _last_msg, 'chat', _con_type) ||
		  case when _member_jsonb notnull then jsonb_build_object('member', _member_jsonb) else '{}'::jsonb end,
              _node_name, _sticky_agent_id, (select clc.id
                            from call_center.cc_list_communications clc
                            where (clc.list_id = dnc_list_id_ and clc.number = _con_name)), _qparams, 6)
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


CREATE OR REPLACE FUNCTION call_center.cc_distribute_inbound_call_to_queue(
	_node_name character varying,
	_queue_id bigint,
	_call_id character varying,
	variables_ jsonb,
	bucket_id_ integer,
	_priority integer DEFAULT 0,
	_sticky_agent_id integer DEFAULT NULL::integer)
    RETURNS record
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
declare
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
    _ignore_calendar bool;
BEGIN
select c.timezone_id,
       (payload ->> 'discard_abandoned_after')::int discard_abandoned_after,
        q.domain_id,
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
        call_center.cc_queue_params(q),
        case when jsonb_typeof(q.payload->'ignore_calendar') = 'boolean' then (q.payload->'ignore_calendar')::bool else false end
from call_center.cc_queue q
         left join flow.calendar c on q.calendar_id = c.id
         left join call_center.cc_team ct on q.team_id = ct.id
where q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _sticky_ignore_status, _grantee_id, _qparams, _ignore_calendar;

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

    if not _calendar_id isnull  and not _ignore_calendar and
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

if _sticky_agent_id is not null and _sticky then
  if not call_center.cc_agent_has_queue_skill(_sticky_agent_id::int8, _queue_id, _domain_id, _sticky_ignore_status)
    then _sticky_agent_id = null;
  end if;
else _sticky_agent_id = null;
end if;


insert into call_center.cc_member_attempt (domain_id, state, queue_id, team_id, member_id, bucket_id, weight,
                                           member_call_id, destination, node_id, sticky_agent_id,
                                           list_communication_id,
                                           parent_id, queue_params, queue_type)
values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id,
        jsonb_build_object('destination', _number, 'name', coalesce(_name, _number)),
        _node_name, _sticky_agent_id, null, _call.attempt_id, _qparams, 1) -- todo inbound queue
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
        call_center.cc_view_timestamp(_call.created_at)::int8,
        _call.parent_id::varchar
    );

END;
$BODY$;
