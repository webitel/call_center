-- STORAGE

drop index if exists storage.file_transcript_file_id_profile_id_locale_uindex;

CREATE UNIQUE INDEX file_transcript_file_id_profile_id_locale_uindex
    ON storage.file_transcript USING btree (file_id, COALESCE(profile_id, 0), locale);

alter table storage.file_transcript alter column profile_id drop not null ;

-- FLOW

alter type flow.calendar_accept_time add attribute special boolean;


--
-- Name: calendar_accepts_to_jsonb(flow.calendar_accept_time[]); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE OR REPLACE FUNCTION flow.calendar_accepts_to_jsonb(flow.calendar_accept_time[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
AS $_$
select jsonb_agg(x.r)
from (select row_to_json(a) r
      from unnest($1) a
      where a.special isnull
         or a.special is false) x;
$_$;


--
-- Name: calendar_json_to_accepts(jsonb, jsonb); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE OR REPLACE FUNCTION flow.calendar_json_to_accepts(jsonb, jsonb) RETURNS flow.calendar_accept_time[]
    LANGUAGE sql IMMUTABLE
AS $_$
select array(
               select row (disabled, wday, start_time_of_day, end_time_of_day, special)::flow.calendar_accept_time
               from (select (x -> 'disabled')::bool as         disabled,
                            (x -> 'day')::smallint             wday,
                            (x -> 'start_time_of_day')::smallint
                                                               start_time_of_day,
                            (x -> 'end_time_of_day')::smallint end_time_of_day,
                            (false)::bool                      special
                     from jsonb_array_elements($1) x
                     union all
                     select (s -> 'disabled')::bool as         disabled,
                            (s -> 'day')::smallint             wday,
                            (s -> 'start_time_of_day')::smallint
                                                               start_time_of_day,
                            (s -> 'end_time_of_day')::smallint end_time_of_day,
                            (true)::bool                       special
                     from jsonb_array_elements($2) as s) x
               order by x.wday, x.start_time_of_day
           )::flow.calendar_accept_time[]
$_$;


--
-- Name: calendar_specials_to_jsonb(flow.calendar_accept_time[]); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE OR REPLACE FUNCTION flow.calendar_specials_to_jsonb(flow.calendar_accept_time[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
AS $_$
select jsonb_agg(x.r)
from (select row_to_json(a) r
      from unnest($1) a
      where a.special is true) x;
$_$;



drop VIEW flow.calendar_view;
--
-- Name: calendar_view; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.calendar_view AS
SELECT c.id,
       c.name,
       c.start_at,
       c.end_at,
       c.description,
       c.domain_id,
       flow.get_lookup((ct.id)::bigint, ct.name) AS timezone,
       c.created_at,
       flow.get_lookup(uc.id, (uc.name)::character varying) AS created_by,
       c.updated_at,
       flow.get_lookup(u.id, (u.name)::character varying) AS updated_by,
       flow.calendar_accepts_to_jsonb(c.accepts) AS accepts,
       flow.arr_type_to_jsonb(c.excepts) AS excepts,
       flow.calendar_specials_to_jsonb(c.accepts) AS specials
FROM (((flow.calendar c
    LEFT JOIN flow.calendar_timezones ct ON ((c.timezone_id = ct.id)))
    LEFT JOIN directory.wbt_user uc ON ((uc.id = c.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = c.updated_by)));


-- CC
alter table call_center.cc_member_attempt add column if not exists variables jsonb;
alter table call_center.cc_member_attempt_history add column if not exists variables jsonb;
alter table call_center.cc_member_attempt add column if not exists queue_type smallint;
alter table call_center.cc_email add column if not exists contact_ids bigint[];
alter table call_center.cc_email add column if not exists owner_id bigint;
--
-- Name: cc_attempt_waiting_agent(bigint, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_attempt_waiting_agent(attempt_id_ bigint, agent_hold_ integer) RETURNS record
    LANGUAGE plpgsql
AS $$
declare
    last_state_change_ timestamptz;
    channel_ varchar;
    agent_id_ int4;
    no_answers_ int4;
begin
    update call_center.cc_member_attempt  n
    set state = 'wait_agent',
        last_state_change = now(),
        agent_id = null ,
        team_id = null,
        agent_call_id = null
    from call_center.cc_member_attempt a
    where a.id = n.id and a.id = attempt_id_
    returning n.last_state_change, a.agent_id, n.channel into last_state_change_, agent_id_, channel_;

    if agent_id_ notnull then
        update call_center.cc_agent_channel c
        set state = 'waiting',
            joined_at = last_state_change_,
            timeout  = null,
            no_answers = 0,
            last_missed_at = now(),
            attempt_id = null,
            queue_id = null
        where c.agent_id = agent_id_ and c.channel = channel_
        returning no_answers into no_answers_;
    end if;

    return row(last_state_change_, no_answers_);
end;
$$;



--
-- Name: cc_call_active_numbers(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_call_active_numbers() RETURNS SETOF character varying
    LANGUAGE plpgsql
AS $$declare
    c call_center.cc_calls;
BEGIN

    for c in select *
             from call_center.cc_calls cc where cc.hangup_at isnull and not cc.direction isnull
                                            and ( (cc.gateway_id notnull and cc.direction = 'outbound') or (cc.gateway_id notnull and cc.direction = 'inbound') )
        loop
            if c.gateway_id notnull and c.direction = 'outbound' then
                return next c.to_number;
            elseif c.gateway_id notnull and c.direction = 'inbound' then
                return next c.from_number;
            end if;

        end loop;
END;
$$;


--
-- Name: cc_calls_rbac_queues(bigint, bigint, integer[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_calls_rbac_queues(_domain_id bigint, _user_id bigint, _groups integer[]) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
AS $$with x as (select a.user_id, a.id agent_id, a.supervisor, a.domain_id
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
             and a.aud
           union distinct
           select q.id
           from call_center.cc_queue q
           where q.domain_id = _domain_id
             and q.grantee_id = any (_groups)) t
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
                   case when q.type = 5 and q.sticky_agent then dis.agent_id end,
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

drop function call_center.cc_distribute_direct_member_to_queue;
--
-- Name: cc_distribute_direct_member_to_queue(character varying, bigint, integer, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint, seq integer, communication_idx integer, bucket_id bigint)
    LANGUAGE plpgsql
AS $$BEGIN
    return query with attempts as (
        insert into call_center.cc_member_attempt (state, queue_id, member_id, destination, communication_idx, node_id, agent_id, resource_id,
                                                   bucket_id, seq, team_id, domain_id, queue_params, queue_type)
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
                   call_center.cc_queue_params(q),
                   q.type
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
                        a.communication_idx::int communication_idx,
                        a.bucket_id
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
-- Name: cc_distribute_inbound_call_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
    _ignore_calendar bool;
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
           call_center.cc_queue_params(q),
           case when jsonb_typeof(q.payload->'ignore_calendar') = 'boolean' then (q.payload->'ignore_calendar')::bool else false end
    from call_center.cc_queue q
             inner join flow.calendar c on q.calendar_id = c.id
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


    if not _ignore_calendar and
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
        call_center.cc_view_timestamp(_call.created_at)::int8
        );

END;
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
           call_center.cc_queue_params(q),
           case when jsonb_typeof(q.payload->'ignore_calendar') = 'boolean' then (q.payload->'ignore_calendar')::bool else false end
    from call_center.cc_queue q
             inner join flow.calendar c on q.calendar_id = c.id
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

    if not _ignore_calendar and not exists(select accept
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
                                               destination, node_id, sticky_agent_id, list_communication_id, queue_params, queue_type)
    values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id::varchar,
            jsonb_build_object('destination', _con_name, 'name', _client_name, 'msg', _last_msg, 'chat', _con_type),
            _node_name, _sticky_agent_id, (select clc.id
                                           from call_center.cc_list_communications clc
                                           where (clc.list_id = dnc_list_id_ and clc.number = _conversation_id)), _qparams, 6) -- todo inbound chat queue
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



DROP FUNCTION call_center.cc_distribute_members_list;
--
-- Name: cc_distribute_members_list(integer, integer, smallint, boolean, smallint[], integer, integer, boolean, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_members_list(_queue_id integer, _bucket_id integer, strategy smallint, wait_between_retries_desc boolean DEFAULT false, l smallint[] DEFAULT '{}'::smallint[], lim integer DEFAULT 40, offs integer DEFAULT 0, sticky_agent boolean DEFAULT false, sticky_agent_sec integer DEFAULT 0, _agent_id integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STABLE
AS $_$begin return query
    select m.id::int8
    from call_center.cc_member m
    where m.queue_id = _queue_id
      and m.stop_at isnull
      and m.skill_id isnull
      and case when _bucket_id isnull then m.bucket_id isnull else m.bucket_id = _bucket_id end
      and (m.expire_at isnull or m.expire_at > now())
      and (m.ready_at isnull or m.ready_at < now())
      and (not sticky_agent or (m.agent_id isnull or m.agent_id = _agent_id))
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
-- Name: cc_distribute_task_to_agent(character varying, bigint, integer, jsonb, jsonb, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_distribute_task_to_agent(_node_name character varying, _domain_id bigint, _agent_id integer, _destination jsonb, variables_ jsonb, _qparams jsonb) RETURNS record
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


    insert into call_center.cc_member_attempt (channel, domain_id, state, team_id, member_call_id, destination, node_id,
                                               agent_id, queue_params, queue_type)
    values ('task', _domain_id, 'waiting', _team_id_, null, _destination,
            _node_name, _agent_id, _qparams, 7) -- todo task agent queue
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
-- Name: cc_offline_members_ids(bigint, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_offline_members_ids(_domain_id bigint, _agent_id integer, _lim integer) RETURNS SETOF bigint
    LANGUAGE plpgsql IMMUTABLE
AS $$begin
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
                                                                          request.strategy::int2, request.wait_between_retries_desc, request.l::int2[], _lim::int,
                                                                          0, request.sticky_agent::bool, request.sticky_agent_sec::int, _agent_id::int) x on true
        order by request.priority desc
        limit _lim;
end
$$;



DROP FUNCTION call_center.cc_set_active_members;
--
-- Name: cc_set_active_members(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer, communication_idx integer, timezone character varying, bucket_id bigint)
    LANGUAGE plpgsql
AS $$BEGIN
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
                   tz.sys_name::varchar as member_timezone,
                   c.bucket_id
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
            c.member_timezone,
            c.bucket_id
    ;
END;
$$;


DROP MATERIALIZED VIEW call_center.cc_agent_today_stats;
--
-- Name: cc_agent_today_stats; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

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
                                       WHEN (((((now())::date + '1 day'::interval) - t.utc_offset))::timestamp with time zone < now()) THEN ((((now())::date + '1 day'::interval) - t.utc_offset))::timestamp with time zone
                                       ELSE (((now())::date - t.utc_offset))::timestamp with time zone
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
    WHERE ((h.domain_id = agents.domain_id) AND (h.joined_at >= agents."from") AND (h.joined_at <= agents."to") AND ((h.channel)::text = 'call'::text))
    GROUP BY h.agent_id
), attempts AS (
    SELECT cma.agent_id,
           count(*) FILTER (WHERE ((cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = 'chat'::text))) AS chat_accepts,
           (avg(EXTRACT(epoch FROM (COALESCE(cma.reporting_at, cma.leaving_at) - cma.bridged_at))) FILTER (WHERE ((cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = 'chat'::text))))::bigint AS chat_aht,
           count(*) FILTER (WHERE ((cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = 'task'::text))) AS task_accepts
    FROM (agents
        JOIN call_center.cc_member_attempt_history cma ON ((cma.agent_id = agents.id)))
    WHERE ((cma.leaving_at >= agents."from") AND (cma.leaving_at <= agents."to") AND (cma.domain_id = agents.domain_id) AND (cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = ANY (ARRAY['chat'::text, 'task'::text])))
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
-- Name: cc_agent_today_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_uidx ON call_center.cc_agent_today_stats USING btree (agent_id);


--
-- Name: cc_agent_today_stats_usr_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_usr_uidx ON call_center.cc_agent_today_stats USING btree (user_id);

REFRESH MATERIALIZED VIEW call_center.cc_agent_today_stats;


alter table call_center.cc_calls_transcribe add column confidence numeric DEFAULT 0.0 NOT NULL;
alter table call_center.cc_calls_transcribe add column response jsonb;
alter table call_center.cc_calls_transcribe add column question character varying;


--
-- Name: cc_manual_queue_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_manual_queue_list AS
WITH manual_queue AS MATERIALIZED (
    SELECT q.domain_id,
           q.id,
           call_center.cc_get_lookup((q.id)::bigint, q.name) AS queue,
           q.priority,
           q.sticky_agent,
           q.team_id,
           COALESCE(((q.payload -> 'max_wait_time'::text))::integer, 0) AS max_wait_time,
           COALESCE(((q.payload -> 'sticky_agent_sec'::text))::integer, 0) AS sticky_agent_sec
    FROM call_center.cc_queue q
    WHERE (COALESCE(((q.payload -> 'manual_distribution'::text))::boolean, false) AND q.enabled)
    ORDER BY q.domain_id
), queues AS MATERIALIZED (
    SELECT DISTINCT q.domain_id,
                    q.queue,
                    qs.queue_id,
                    q.priority,
                    bq.priority AS bucket_pri,
                    q.max_wait_time,
                    q.sticky_agent_sec,
                    q.sticky_agent,
                    b.b AS bucket_id,
                    csia.agent_id,
                    a.user_id,
                    max(qs.lvl) AS lvl
    FROM (((((manual_queue q
        JOIN call_center.cc_queue_skill qs ON ((qs.queue_id = q.id)))
        JOIN call_center.cc_skill_in_agent csia ON ((csia.skill_id = qs.skill_id)))
        JOIN call_center.cc_agent a ON (((a.id = csia.agent_id) AND ((q.team_id IS NULL) OR (q.team_id = a.team_id)))))
        LEFT JOIN LATERAL unnest(qs.bucket_ids) b(b) ON (true))
        LEFT JOIN call_center.cc_bucket_in_queue bq ON (((bq.queue_id = q.id) AND (bq.bucket_id = b.b))))
    WHERE (qs.enabled AND csia.enabled AND (csia.capacity >= qs.min_capacity) AND (csia.capacity <= qs.max_capacity) AND (q.domain_id = a.domain_id) AND ((a.status)::text = 'online'::text))
    GROUP BY q.domain_id, q.queue, qs.queue_id, q.priority, bq.priority, q.max_wait_time, q.sticky_agent_sec, q.sticky_agent, b.b, csia.agent_id, a.user_id
), attempts AS MATERIALIZED (
    SELECT q.domain_id,
           q.queue,
           q.queue_id,
           q.priority,
           q.bucket_pri,
           q.max_wait_time,
           q.sticky_agent_sec,
           q.sticky_agent,
           q.bucket_id,
           q.agent_id,
           q.user_id,
           q.lvl,
           a.id AS attempt_id,
           a.joined_at,
           a.member_call_id AS session_id,
           (EXTRACT(epoch FROM (now() - a.joined_at)))::integer AS wait,
           a.destination AS communication,
           a.sticky_agent_id,
           a.channel,
           (((EXTRACT(epoch FROM (now() - a.joined_at)) / (q.max_wait_time)::numeric) * (100)::numeric))::integer AS deadline
    FROM (call_center.cc_member_attempt a
        JOIN queues q ON ((q.queue_id = a.queue_id)))
    WHERE ((a.domain_id = q.domain_id) AND (a.agent_id IS NULL) AND ((a.state)::text = 'wait_agent'::text) AND (a.queue_id = q.queue_id) AND (COALESCE(q.bucket_id, 0) = COALESCE(a.bucket_id, (0)::bigint)) AND ((a.sticky_agent_id IS NULL) OR (a.sticky_agent_id = q.agent_id) OR (a.joined_at < (now() - ((q.sticky_agent_sec || ' sec'::text))::interval))))
        FOR UPDATE OF a SKIP LOCKED
)
SELECT x.domain_id,
       array_agg(x.user_id) AS users,
       array_to_json(x.calls[1:10]) AS calls,
       array_to_json(x.chats[1:100]) AS chats
FROM ( SELECT a.domain_id,
              a.user_id,
              array_agg(jsonb_build_object('attempt_id', a.attempt_id, 'wait', a.wait, 'communication', a.communication, 'queue', a.queue, 'bucket', call_center.cc_get_lookup(b.id, ((b.name)::text)::character varying), 'deadline', a.deadline, 'session_id', a.session_id) ORDER BY a.lvl, a.priority DESC, a.bucket_pri DESC NULLS LAST, a.wait DESC) FILTER (WHERE ((a.channel)::text = 'call'::text)) AS calls,
              array_agg(jsonb_build_object('attempt_id', a.attempt_id, 'wait', a.wait, 'communication', a.communication, 'queue', a.queue, 'bucket', call_center.cc_get_lookup(b.id, ((b.name)::text)::character varying), 'deadline', a.deadline, 'session_id', a.session_id) ORDER BY a.lvl, a.priority DESC, a.bucket_pri DESC NULLS LAST, a.wait DESC) FILTER (WHERE ((a.channel)::text = 'chat'::text)) AS chats
       FROM (attempts a
           LEFT JOIN call_center.cc_bucket b ON ((b.id = a.bucket_id)))
       GROUP BY a.domain_id, a.user_id) x
GROUP BY x.domain_id, x.calls[1:10], x.chats[1:100];


DROP VIEW call_center.cc_queue_list;
--
-- Name: cc_queue_list; Type: VIEW; Schema: call_center; Owner: -
--

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
       CASE
           WHEN (q.type = ANY (ARRAY[1, 6])) THEN COALESCE(act.cnt_w, (0)::bigint)
           ELSE COALESCE(ss.member_waiting, (0)::bigint)
           END AS waiting,
       COALESCE(act.cnt, (0)::bigint) AS active,
       q.sticky_agent,
       q.processing,
       q.processing_sec,
       q.processing_renewal_sec,
       jsonb_build_object('enabled', q.processing, 'form_schema', call_center.cc_get_lookup(fs.id, fs.name), 'sec', q.processing_sec, 'renewal_sec', q.processing_renewal_sec) AS task_processing,
       call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
       q.team_id,
       q.tags
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
    LEFT JOIN LATERAL ( SELECT count(*) AS cnt,
                               count(*) FILTER (WHERE (a.agent_id IS NULL)) AS cnt_w
                        FROM call_center.cc_member_attempt a
                        WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL) AND ((a.state)::text <> 'leaving'::text))) act ON (true));

--
-- Name: cc_email_contact_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_contact_ids_index ON call_center.cc_email USING gin (contact_ids) WHERE (contact_ids IS NOT NULL);


--
-- Name: cc_email_owner_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_owner_id_index ON call_center.cc_email USING btree (owner_id);


--
-- Name: cc_member_attempt_history_mat_view_agent2; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_mat_view_agent2 ON call_center.cc_member_attempt_history USING btree (agent_id, domain_id, leaving_at) INCLUDE (reporting_at, bridged_at, leaving_at, channel) WHERE (((channel)::text = ANY (ARRAY['chat'::text, 'task'::text])) AND (bridged_at IS NOT NULL));


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
                                                                    END AND (NOT (x.working AND ((((to_char((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name), 'SSSS'::text))::integer / 60) >= x.work_start) AND (((to_char((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name), 'SSSS'::text))::integer / 60) <= x.work_stop)))))))))
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
       q.strict_circuit,
       q.op AS ins,
       q.min_wt
FROM (((queues q
    LEFT JOIN calend ON ((calend.queue_id = q.id)))
    LEFT JOIN resources r ON ((q.op AND (r.queue_id = q.id))))
    LEFT JOIN LATERAL ( SELECT count(*) AS usage
                        FROM call_center.cc_member_attempt a
                        WHERE ((a.queue_id = q.id) AND ((a.state)::text <> 'leaving'::text))) l ON ((q.lim > 0)))
WHERE ((q.type = 7) OR ((q.type = ANY (ARRAY[1, 6])) AND ((NOT q.ignore_calendar) OR calend.in_calendar)) OR ((q.type = 8) AND (GREATEST(((q.lim - COALESCE(l.usage, (0)::bigint)))::integer, 0) > 0)) OR ((q.type = 5) AND (NOT q.op)) OR (q.op AND (q.type = ANY (ARRAY[2, 3, 4, 5])) AND (r.* IS NOT NULL)))
ORDER BY q.domain_id, q.priority DESC, q.op;

alter table call_center.cc_calls_history
    DROP CONSTRAINT IF EXISTS cc_calls_history_cc_agent_id_fk;


alter table call_center.cc_calls_history
    DROP CONSTRAINT IF EXISTS cc_calls_history_cc_team_id_fk;

--
-- Name: cc_email cc_email_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email
    ADD CONSTRAINT cc_email_wbt_user_id_fk FOREIGN KEY (owner_id) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;



DROP FUNCTION call_center.cc_attempt_end_reporting;
--
-- Name: cc_attempt_end_reporting(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb, integer, integer, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, _per_number boolean DEFAULT false) RETURNS record
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


ALTER TABLE call_center.cc_calls
    SET (
        fillfactor='20', log_autovacuum_min_duration='0', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01'
        );

ALTER TABLE call_center.cc_member_attempt
    SET (
        fillfactor='20', log_autovacuum_min_duration='0', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01'
        );
ALTER TABLE call_center.cc_agent
    SET (
        fillfactor='20', log_autovacuum_min_duration='0', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01'
        );
ALTER TABLE call_center.cc_agent_channel
    SET (
        fillfactor='20', log_autovacuum_min_duration='0', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01'
        );
ALTER TABLE call_center.cc_queue_statistics
    SET (
        fillfactor='20', log_autovacuum_min_duration='0', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01'
        );

ALTER TABLE call_center.cc_member
    SET (
        fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_vacuum_cost_delay='20', autovacuum_enabled='1', autovacuum_analyze_threshold='2000'
        );


drop  materialized view call_center.cc_agent_today_stats;
create materialized view call_center.cc_agent_today_stats as
WITH agents AS MATERIALIZED (SELECT a_1.id,
                                    usr.id                                           AS user_id,
                                    CASE
                                        WHEN a_1.last_state_change < d."from" THEN d."from"
                                        WHEN a_1.last_state_change < d."to" THEN a_1.last_state_change
                                        ELSE a_1.last_state_change
                                        END                                          AS cur_state_change,
                                    a_1.status,
                                    a_1.status_payload,
                                    a_1.last_state_change,
                                    lasts.last_at,
                                    lasts.state                                      AS last_state,
                                    lasts.status_payload                             AS last_payload,
                                    COALESCE(top.top_at, a_1.last_state_change)      AS top_at,
                                    COALESCE(top.state, a_1.status)                  AS top_state,
                                    COALESCE(top.status_payload, a_1.status_payload) AS top_payload,
                                    d."from",
                                    d."to",
                                    usr.dc                                           AS domain_id,
                                    COALESCE(t.sys_name, 'UTC'::text)                AS tz_name
                             FROM call_center.cc_agent a_1
                                      RIGHT JOIN directory.wbt_user usr ON usr.id = a_1.user_id
                                      LEFT JOIN flow.region r ON r.id = a_1.region_id
                                      LEFT JOIN flow.calendar_timezones t ON t.id = r.timezone_id
                                      LEFT JOIN LATERAL ( SELECT now()   AS "to",
                                                                 CASE
                                                                     WHEN (now()::date + '1 day'::interval - coalesce(t.utc_offset, '0s'))::timestamp with time zone <
                                                                          now()
                                                                         THEN (now()::date + '1 day'::interval - coalesce(t.utc_offset, '0s'))::timestamp with time zone
                                                                     ELSE (now()::date - coalesce(t.utc_offset, '0s'))::timestamp with time zone
                                                                     END AS "from") d ON true
                                      LEFT JOIN LATERAL ( SELECT aa.state,
                                                                 d."from"   AS last_at,
                                                                 aa.payload AS status_payload
                                                          FROM call_center.cc_agent_state_history aa
                                                          WHERE aa.agent_id = a_1.id
                                                            AND aa.channel IS NULL
                                                            AND (aa.state::text = ANY
                                                                 (ARRAY ['pause'::character varying::text, 'online'::character varying::text, 'offline'::character varying::text]))
                                                            AND aa.joined_at < d."from"
                                                          ORDER BY aa.joined_at DESC
                                                          LIMIT 1) lasts ON a_1.last_state_change > d."from"
                                      LEFT JOIN LATERAL ( SELECT a2.state,
                                                                 d."to"     AS top_at,
                                                                 a2.payload AS status_payload
                                                          FROM call_center.cc_agent_state_history a2
                                                          WHERE a2.agent_id = a_1.id
                                                            AND a2.channel IS NULL
                                                            AND (a2.state::text = ANY
                                                                 (ARRAY ['pause'::character varying::text, 'online'::character varying::text, 'offline'::character varying::text]))
                                                            AND a2.joined_at > d."to"
                                                          ORDER BY a2.joined_at
                                                          LIMIT 1) top ON true),
     d AS MATERIALIZED (SELECT x.agent_id,
                               x.joined_at,
                               x.state,
                               x.payload
                        FROM (SELECT a_1.agent_id,
                                     a_1.joined_at,
                                     a_1.state,
                                     a_1.payload
                              FROM call_center.cc_agent_state_history a_1,
                                   agents
                              WHERE a_1.agent_id = agents.id
                                AND a_1.joined_at >= agents."from"
                                AND a_1.joined_at <= agents."to"
                                AND a_1.channel IS NULL
                                AND (a_1.state::text = ANY
                                     (ARRAY ['pause'::character varying::text, 'online'::character varying::text, 'offline'::character varying::text]))
                              UNION
                              SELECT agents.id,
                                     agents.cur_state_change,
                                     agents.status,
                                     agents.status_payload
                              FROM agents
                              WHERE 1 = 1) x
                        ORDER BY x.joined_at DESC),
     s AS MATERIALIZED (SELECT d.agent_id,
                               d.joined_at,
                               d.state,
                               d.payload,
                               COALESCE(lag(d.joined_at) OVER (PARTITION BY d.agent_id ORDER BY d.joined_at DESC),
                                        now()) - d.joined_at AS dur
                        FROM d
                        ORDER BY d.joined_at DESC),
     eff AS (SELECT h.agent_id,
                    sum(COALESCE(h.reporting_at, h.leaving_at) - h.bridged_at)
                    FILTER (WHERE h.bridged_at IS NOT NULL)                                                                          AS aht,
                    sum(h.reporting_at - h.leaving_at) FILTER (WHERE h.reporting_at IS NOT NULL AND
                                                                     (h.reporting_at - h.leaving_at) >
                                                                     '00:00:00'::interval)                                           AS processing,
                    sum(h.reporting_at - h.leaving_at - ((q.processing_sec || 's'::text)::interval))
                    FILTER (WHERE h.reporting_at IS NOT NULL AND q.processing AND (h.reporting_at - h.leaving_at) >
                                                                                  (((q.processing_sec + 1) || 's'::text)::interval)) AS tpause
             FROM agents
                      JOIN call_center.cc_member_attempt_history h ON h.agent_id = agents.id
                      LEFT JOIN call_center.cc_queue q ON q.id = h.queue_id
             WHERE h.domain_id = agents.domain_id
               AND h.joined_at >= agents."from"
               AND h.joined_at <= agents."to"
               AND h.channel::text = 'call'::text
             GROUP BY h.agent_id),
     attempts AS (SELECT cma.agent_id,
                         count(*)
                         FILTER (WHERE cma.bridged_at IS NOT NULL AND cma.channel::text = 'chat'::text)          AS chat_accepts,
                         avg(EXTRACT(epoch FROM COALESCE(cma.reporting_at, cma.leaving_at) - cma.bridged_at))
                         FILTER (WHERE cma.bridged_at IS NOT NULL AND cma.channel::text = 'chat'::text)::bigint  AS chat_aht,
                         count(*)
                         FILTER (WHERE cma.bridged_at IS NOT NULL AND cma.channel::text = 'task'::text)          AS task_accepts
                  FROM agents
                           JOIN call_center.cc_member_attempt_history cma ON cma.agent_id = agents.id
                  WHERE cma.leaving_at >= agents."from"
                    AND cma.leaving_at <= agents."to"
                    AND cma.domain_id = agents.domain_id
                    AND cma.bridged_at IS NOT NULL
                    AND (cma.channel::text = ANY (ARRAY ['chat'::text, 'task'::text]))
                  GROUP BY cma.agent_id),
     calls AS (SELECT h.user_id,
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text)                                                                               AS all_inb,
                      count(*) FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                          AS handled,
                      count(*)
                      FILTER (WHERE h.direction::text = 'inbound'::text AND h.bridged_at IS NOT NULL)                                                           AS inbound_bridged,
                      count(*)
                      FILTER (WHERE cq.type = 1 AND h.bridged_at IS NOT NULL AND h.parent_id IS NOT NULL)                                                       AS "inbound queue",
                      count(*)
                      FILTER (WHERE h.direction::text = 'inbound'::text AND h.queue_id IS NULL)                                                                 AS "direct inbound",
                      count(*)
                      FILTER (WHERE h.parent_id IS NOT NULL AND h.bridged_at IS NOT NULL AND h.queue_id IS NULL AND
                                    pc.user_id IS NOT NULL)                                                                                                     AS internal_inb,
                      count(*) FILTER (WHERE h.bridged_at IS NOT NULL AND h.queue_id IS NULL AND
                                             pc.user_id IS NOT NULL)                                                                                            AS user_2user,
                      count(*) FILTER (WHERE (h.direction::text = 'inbound'::text ) AND
                                             h.bridged_at IS NULL and not h.hide_missed is true
                          and  pc.bridged_at isnull )                                                                AS missed,
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text AND h.bridged_at IS NULL AND
                                             h.queue_id IS NOT NULL AND (h.cause::text = ANY
                                                                         (ARRAY ['NO_ANSWER'::character varying::text, 'USER_BUSY'::character varying::text]))) AS abandoned,
                      count(*)
                      FILTER (WHERE (cq.type = ANY (ARRAY [0::smallint, 3::smallint, 4::smallint, 5::smallint])) AND
                                    h.bridged_at IS NOT NULL)                                                                                                   AS outbound_queue,
                      count(*) FILTER (WHERE h.parent_id IS NULL AND h.direction::text = 'outbound'::text AND
                                             h.queue_id IS NULL)                                                                                                AS "direct outboud",
                      sum(h.hangup_at - h.created_at)
                      FILTER (WHERE h.direction::text = 'outbound'::text AND h.queue_id IS NULL)                                                                AS direct_out_dur,
                      avg(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL AND h.direction::text = 'inbound'::text AND
                                    h.parent_id IS NOT NULL)                                                                                                    AS "avg bill inbound",
                      avg(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL AND h.direction::text = 'outbound'::text)                                                          AS "avg bill outbound",
                      sum(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                                   AS "sum bill",
                      avg(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                                   AS avg_talk,
                      sum((h.hold_sec || ' sec'::text)::interval)                                                                                               AS "sum hold",
                      avg((h.hold_sec || ' sec'::text)::interval)
                      FILTER (WHERE h.hold_sec > 0)                                                                                                             AS avg_hold,
                      sum(COALESCE(h.answered_at, h.bridged_at, h.hangup_at) - h.created_at)                                                                    AS "Call initiation",
                      sum(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                                   AS "Talk time",
                      sum(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL AND h.queue_id IS NOT NULL)                                                                        AS queue_talk_sec,
                      sum(cc.reporting_at - cc.leaving_at)
                      FILTER (WHERE cc.reporting_at IS NOT NULL)                                                                                                AS "Post call",
                      sum(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL AND cc.description::text = 'Voice mail'::text)                                                     AS vm
               FROM agents
                        JOIN call_center.cc_calls_history h ON h.user_id = agents.user_id
                        LEFT JOIN call_center.cc_queue cq ON h.queue_id = cq.id
                        LEFT JOIN call_center.cc_member_attempt_history cc ON cc.agent_call_id::text = h.id::text
                        LEFT JOIN call_center.cc_calls_history pc
                                  ON pc.id = h.parent_id AND pc.created_at > (now()::date - '2 days'::interval)
               WHERE h.domain_id = agents.domain_id
                 AND h.created_at > (now()::date - '2 days'::interval)
                 AND h.created_at >= agents."from"
                 AND h.created_at <= agents."to"
               GROUP BY h.user_id),
     stats AS MATERIALIZED (SELECT s.agent_id,
                                   min(s.joined_at) FILTER (WHERE s.state::text = ANY
                                                                  (ARRAY ['online'::character varying::text, 'pause'::character varying::text])) AS login,
                                   max(s.joined_at) FILTER (WHERE s.state::text = 'offline'::text)                                               AS logout,
                                   sum(s.dur) FILTER (WHERE s.state::text = ANY
                                                            (ARRAY ['online'::character varying::text, 'pause'::character varying::text]))       AS online,
                                   sum(s.dur) FILTER (WHERE s.state::text = 'pause'::text)                                                       AS pause,
                                   sum(s.dur)
                                   FILTER (WHERE s.state::text = 'pause'::text AND s.payload::text = 'Навчання'::text)                           AS study,
                                   sum(s.dur)
                                   FILTER (WHERE s.state::text = 'pause'::text AND s.payload::text = 'Нарада'::text)                             AS conference,
                                   sum(s.dur)
                                   FILTER (WHERE s.state::text = 'pause'::text AND s.payload::text = 'Обід'::text)                               AS lunch,
                                   sum(s.dur) FILTER (WHERE s.state::text = 'pause'::text AND s.payload::text =
                                                                                              'Технічна перерва'::text)                          AS tech
                            FROM s
                                     LEFT JOIN agents ON agents.id = s.agent_id
                                     LEFT JOIN eff eff_1 ON eff_1.agent_id = s.agent_id
                                     LEFT JOIN calls ON calls.user_id = agents.user_id
                            GROUP BY s.agent_id),
     rate AS (SELECT a_1.user_id,
                     count(*)               AS count,
                     avg(ar.score_required) AS score_required_avg,
                     sum(ar.score_required) AS score_required_sum,
                     avg(ar.score_optional) AS score_optional_avg,
                     sum(ar.score_optional) AS score_optional_sum
              FROM agents a_1
                       JOIN call_center.cc_audit_rate ar ON ar.rated_user_id = a_1.user_id
              WHERE ar.created_at >=
                    (date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) AT TIME ZONE a_1.tz_name)
                AND ar.created_at <= ((date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) + '1 mon'::interval -
                                       '1 day 00:00:01'::interval) AT TIME ZONE a_1.tz_name)
              GROUP BY a_1.user_id)
SELECT a.id                                                                                                         AS agent_id,
       a.user_id,
       a.domain_id,
       COALESCE(c.missed, 0::bigint)                                                                                AS call_missed,
       COALESCE(c.abandoned, 0::bigint)                                                                             AS call_abandoned,
       COALESCE(c.inbound_bridged, 0::bigint)                                                                       AS call_inbound,
       COALESCE(c.handled, 0::bigint)                                                                               AS call_handled,
       COALESCE(EXTRACT(epoch FROM c.avg_talk)::bigint, 0::bigint)                                                  AS avg_talk_sec,
       COALESCE(EXTRACT(epoch FROM c.avg_hold)::bigint, 0::bigint)                                                  AS avg_hold_sec,
       COALESCE(EXTRACT(epoch FROM c."Talk time")::bigint, 0::bigint)                                               AS sum_talk_sec,
       COALESCE(EXTRACT(epoch FROM c.queue_talk_sec)::bigint, 0::bigint)                                            AS queue_talk_sec,
       LEAST(round(COALESCE(
                           CASE
                               WHEN stats.online > '00:00:00'::interval AND
                                    EXTRACT(epoch FROM stats.online - COALESCE(stats.lunch, '00:00:00'::interval)) > 0::numeric
                                   THEN (COALESCE(EXTRACT(epoch FROM c."Call initiation"), 0::numeric) +
                                         COALESCE(EXTRACT(epoch FROM c."Talk time"), 0::numeric) +
                                         COALESCE(EXTRACT(epoch FROM c."Post call"), 0::numeric) -
                                         COALESCE(EXTRACT(epoch FROM eff.tpause), 0::numeric) +
                                         EXTRACT(epoch FROM COALESCE(stats.study, '00:00:00'::interval)) +
                                         EXTRACT(epoch FROM COALESCE(stats.conference, '00:00:00'::interval))) /
                                        EXTRACT(epoch FROM stats.online - COALESCE(stats.lunch, '00:00:00'::interval)) *
                                        100::numeric
                               ELSE 0::numeric
                               END, 0::numeric), 2),
             100::numeric)                                                                                          AS occupancy,
       round(COALESCE(
                     CASE
                         WHEN stats.online > '00:00:00'::interval THEN
                                     EXTRACT(epoch FROM stats.online - COALESCE(stats.pause, '00:00:00'::interval)) /
                                     EXTRACT(epoch FROM stats.online) * 100::numeric
                         ELSE 0::numeric
                         END, 0::numeric),
             2)                                                                                                     AS utilization,
       GREATEST(round(COALESCE(
                              CASE
                                  WHEN stats.online > '00:00:00'::interval AND
                                       EXTRACT(epoch FROM stats.online - COALESCE(stats.lunch, '00:00:00'::interval)) >
                                       0::numeric THEN EXTRACT(epoch FROM stats.online -
                                                                          COALESCE(stats.lunch, '00:00:00'::interval)) -
                                                       (COALESCE(EXTRACT(epoch FROM c."Call initiation"), 0::numeric) +
                                                        COALESCE(EXTRACT(epoch FROM c."Talk time"), 0::numeric) +
                                                        COALESCE(EXTRACT(epoch FROM c."Post call"), 0::numeric) -
                                                        COALESCE(EXTRACT(epoch FROM eff.tpause), 0::numeric) +
                                                        EXTRACT(epoch FROM COALESCE(stats.study, '00:00:00'::interval)) +
                                                        EXTRACT(epoch FROM
                                                                COALESCE(stats.conference, '00:00:00'::interval)))
                                  ELSE 0::numeric
                                  END, 0::numeric), 2),
                0::numeric)::integer                                                                                AS available,
       COALESCE(EXTRACT(epoch FROM c.vm)::bigint, 0::bigint)                                                        AS voice_mail,
       COALESCE(ch.chat_aht, 0::bigint)                                                                             AS chat_aht,
       COALESCE(ch.task_accepts, 0::bigint) + COALESCE(ch.chat_accepts, 0::bigint) + COALESCE(c.handled, 0::bigint) -
       COALESCE(c.user_2user, 0::bigint)                                                                            AS task_accepts,
       COALESCE(EXTRACT(epoch FROM stats.online - COALESCE(stats.lunch, '00:00:00'::interval)),
                0::numeric)::bigint                                                                                 AS online,
       COALESCE(ch.chat_accepts, 0::bigint)                                                                         AS chat_accepts,
       COALESCE(rate.count, 0::bigint)                                                                              AS score_count,
       COALESCE(EXTRACT(epoch FROM eff.processing), 0::bigint::numeric)::integer                                    AS processing,
       COALESCE(rate.score_optional_avg, 0::numeric)                                                                AS score_optional_avg,
       COALESCE(rate.score_optional_sum, 0::bigint::numeric)                                                        AS score_optional_sum,
       COALESCE(rate.score_required_avg, 0::numeric)                                                                AS score_required_avg,
       COALESCE(rate.score_required_sum, 0::bigint::numeric)                                                        AS score_required_sum
FROM agents a
         LEFT JOIN call_center.cc_agent_with_user u ON u.id = a.id
         LEFT JOIN stats ON stats.agent_id = a.id
         LEFT JOIN eff ON eff.agent_id = a.id
         LEFT JOIN calls c ON c.user_id = a.user_id
         LEFT JOIN attempts ch ON ch.agent_id = a.id
         LEFT JOIN rate ON rate.user_id = a.user_id;
refresh materialized view call_center.cc_agent_today_stats;


create unique index cc_agent_today_stats_uidx
    on call_center.cc_agent_today_stats (agent_id);

create unique index cc_agent_today_stats_usr_uidx
    on call_center.cc_agent_today_stats (user_id);