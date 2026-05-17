
--
-- Name: cc_agent_init_channel(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_agent_init_channel() RETURNS trigger
  LANGUAGE plpgsql
AS $$
BEGIN
  insert into call_center.cc_agent_channel (agent_id, channel, state)
  select new.id, c, 'waiting'
  from unnest('{chat,call,task,out_call,im}'::text[]) c;
  RETURN NEW;
END;
$$;

--
-- Name: cc_attempt_missed_agent(bigint, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_attempt_missed_agent(attempt_id_ bigint, agent_hold_ integer) RETURNS record
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
    set state = 'missed',
        joined_at = last_state_change_,
        timeout  = now() + (agent_hold_::varchar || ' sec')::interval,
        no_answers = (no_answers + 1),
        attempt_id = attempt_id_,
        last_missed_at = now()
    where c.agent_id = agent_id_ and c.channel = channel_
    returning no_answers into no_answers_;
  end if;

  return row(last_state_change_, no_answers_);
end;
$$;



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
        attempt_id         = attempt.id,
        last_bucket_id   = coalesce(attempt.bucket_id, last_bucket_id)
    where (ch.agent_id, ch.channel) = (attempt.agent_id, attempt.channel);
  end if;

  return row (attempt.last_state_change::timestamptz);
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
        return next c.destination;
      elseif c.gateway_id notnull and c.direction = 'inbound' then
        return next c.from_number;
      end if;

    end loop;
END;
$$;

alter table call_center.cc_calls add column progress_at timestamp with time zone;
alter table call_center.cc_calls_history add column progress_at timestamp with time zone;



--
-- Name: cc_call_set_bridged(uuid, character varying, timestamp with time zone, character varying, bigint, uuid, character varying); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE OR REPLACE PROCEDURE call_center.cc_call_set_bridged(IN call_id_ uuid, IN state_ character varying, IN timestamp_ timestamp with time zone, IN app_id_ character varying, IN domain_id_ bigint, IN call_bridged_id_ uuid, IN _to_name character varying)
  LANGUAGE plpgsql
AS $$
declare
  transfer_to_ uuid;
  transfer_from_ uuid;
  transfer_from_name_ varchar;
  transfer_from_number_ varchar;
  contact_id_ int8;
begin

  update call_center.cc_calls cc
  set bridged_id = c.bridged_id,
      state      = state_,
      timestamp  = timestamp_,
      to_number  = case
                     when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound' and cc.gateway_id isnull )
                       then c.number_
                     else to_number end,
      to_name    = case
                     when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound' and cc.gateway_id isnull )
                       then c.name_
                     else to_name end,
      to_type    = case
                     when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound' and cc.gateway_id isnull )
                       then c.type_
                     else to_type end,
      to_id      = case
                     when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound'  and cc.gateway_id isnull )
                       then c.id_
                     else to_id end,
      from_name = case when cc.gateway_id notnull then coalesce(_to_name, from_name) else from_name end
  from (
         select b.id,
                b.bridged_id as transfer_to,
                b2.id parent_id,
                b2.id bridged_id,
                b2o.*
         from call_center.cc_calls b
                left join call_center.cc_calls b2 on b2.id = call_id_::uuid
                left join lateral call_center.cc_call_get_owner_leg(b2) b2o on true
         where b.id = call_bridged_id_
       ) c
  where c.id = cc.id
  returning c.transfer_to, cc.from_name, cc.from_number
    into transfer_to_, transfer_from_name_, transfer_from_number_;

  update call_center.cc_calls cc
  set bridged_id    = c.bridged_id,
      state         = state_,
      timestamp     = timestamp_,
      parent_id     = case
                        when c.is_leg_a is true and cc.parent_id notnull and cc.parent_id != c.bridged_id then c.bridged_id
                        else cc.parent_id end,
      transfer_from = case
                        when cc.parent_id notnull and cc.parent_id != c.bridged_id then cc.parent_id
                        else cc.transfer_from end,
      transfer_to = transfer_to_,


      from_number = case
                      when transfer_from_number_ notnull and direction = 'inbound' and transfer_to_ notnull and cc.parent_id notnull and cc.parent_id != c.bridged_id
                        then transfer_from_number_
                      else from_number end,
      from_name = case
                    when transfer_from_name_ notnull and direction = 'inbound' and transfer_to_ notnull and cc.parent_id notnull and cc.parent_id != c.bridged_id
                      then transfer_from_name_
                    else from_name end,
      to_number     = case
                        when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                          then c.number_
                        else to_number end,
      to_name       = case
                        when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                          then c.name_
                        else to_name end,
      to_type       = case
                        when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                          then c.type_
                        else to_type end,
      to_id         = case
                        when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                          then c.id_
                        else to_id end
  from (
         select b.id,
                b2.id parent_id,
                b2.id bridged_id,
                b.parent_id isnull as is_leg_a,
                b2.contact_id,
                b2o.*
         from call_center.cc_calls b
                left join call_center.cc_calls b2 on b2.id = call_bridged_id_
                left join lateral call_center.cc_call_get_owner_leg(b2) b2o on true
         where b.id = call_id_::uuid
       ) c
  where c.id = cc.id
  returning cc.transfer_from, c.contact_id into transfer_from_, contact_id_;

  update call_center.cc_calls set
                                transfer_from =  case when id = transfer_from_ then transfer_to_ end,
                                transfer_to =  case when id = transfer_to_ then transfer_from_ end,
                                contact_id = case when id = transfer_to_ and contact_id isnull then (select cc.contact_id from call_center.cc_calls cc where cc.id = transfer_to_) else cc_calls.contact_id end
  where id in (transfer_from_, transfer_to_);

end;
$$;


--
-- Name: cc_calls_set_timing(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_calls_set_timing() RETURNS trigger
  LANGUAGE plpgsql
AS $$
BEGIN
  if new.state = old.state then
    return new;
  end if;

  if new.state = 'active' then
    if new.answered_at isnull then
      new.answered_at = new.timestamp;

      if new.direction = 'inbound' and new.parent_id notnull and new.bridged_at isnull then
        new.bridged_at = new.answered_at;
      end if;

    else if old.state = 'hold' then
      new.hold_sec =  coalesce(old.hold_sec, 0) + extract ('epoch' from new.timestamp - old.timestamp)::double precision;
      if new.hold isnull then
        new.hold = '[]';
      end if;

      new.hold = new.hold || jsonb_build_object(
        'start', (extract(epoch from old.timestamp)::double precision * 1000)::int8,
        'finish', (extract(epoch from new.timestamp)::double precision * 1000)::int8,
        'sec', extract ('epoch' from new.timestamp - old.timestamp)::int8
                             );


      --             if new.parent_id notnull then
--                 update cc_calls set hold_sec  = hold_sec + new.hold_sec  where id = new.parent_id;
--             end if;
    end if;

    end if;
  else if (new.state = 'progress') then
    new.progress_at = coalesce(new.progress_at, new.timestamp);
  else if (new.state = 'bridge') then
    new.bridged_at = coalesce(new.bridged_at, new.timestamp);
  else if new.state = 'hangup' then
    new.hangup_at = new.timestamp;
    -- TODO
    if old.state = 'hold' then
      new.hold_sec =  coalesce(old.hold_sec, 0) + extract ('epoch' from new.timestamp - old.timestamp)::double precision;
      if new.hold isnull then
        new.hold = '[]';
      end if;

      new.hold = new.hold || jsonb_build_object(
        'start', (extract(epoch from old.timestamp)::double precision * 1000)::int8,
        'finish', (extract(epoch from new.timestamp)::double precision * 1000)::int8,
        'sec', extract ('epoch' from new.timestamp - old.timestamp)::int8
                             );


      --             if new.parent_id notnull then
--                 update cc_calls set hold_sec  = hold_sec + new.hold_sec  where id = new.parent_id;
--             end if;
    end if;
  end if;
  end if;
  end if;
  end if;

  RETURN new;
END
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
    _member_jsonb := jsonb_build_object('type', 'self');
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



--
-- Name: cc_distribute_inbound_im_to_queue(character varying, bigint, character varying, jsonb, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_inbound_im_to_queue(_node_name character varying, _queue_id bigint, _thread_id character varying, destination_ jsonb, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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

  if not _q_type = 9 then
    raise exception 'queue type not inbound IM';
  end if;

  if not _enabled = true then
    raise exception 'queue disabled';
  end if;

  if not _calendar_id isnull  and (not _ignore_calendar and not exists(select accept
                                                                       from flow.calendar_check_timing(_domain_id, _calendar_id, null)
                                                                              as x (name varchar, excepted varchar, accept bool, expire bool)
                                                                       where accept and excepted is null and not expire)) then
    raise exception 'thread [%] calendar not working [%] [%]', _thread_id, _calendar_id, _queue_id;
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


  if  _discard_abandoned_after > 0 then
    select
      case when log.result = 'abandoned' then
             extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
           else coalesce(_priority, 0) end
    from call_center.cc_member_attempt_history log
    where log.leaving_at >= (now() -  (_discard_abandoned_after || ' sec')::interval)
      and log.queue_id = _queue_id
      and log.destination->>'destination' = destination_->>'destination'
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
  values (_domain_id, 'im', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _thread_id::varchar,
          destination_,
          _node_name, _sticky_agent_id, (select clc.id
                                         from call_center.cc_list_communications clc
                                         where (clc.list_id = dnc_list_id_ and clc.number = destination_->>'destination')), _qparams, 6)
  returning * into _attempt;


  return row(
    _attempt.id::int8,
    _attempt.queue_id::int,
    _queue_updated_at::int8,
    _attempt.destination::jsonb,
    coalesce((variables_::jsonb), '{}'::jsonb),
    (destination_->>'destination')::varchar,
    _team_updated_at::int8,

    _thread_id::varchar,
    call_center.cc_view_timestamp(now())::int8,
    _attempt.list_communication_id::int8
    );
END;
$$;



--
-- Name: cc_distribute_outbound_call(character varying, character varying, jsonb, bigint, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_distribute_outbound_call(_node_name character varying, _call_id character varying, variables_ jsonb, _user_id bigint DEFAULT NULL::integer, q_params jsonb DEFAULT NULL::jsonb) RETURNS record
  LANGUAGE plpgsql
AS $$declare
  _domain_id int8;
  _team_updated_at int8;
  _agent_updated_at int8;
  _team_id_ int;
  _agent_id int;

  _call record;
  _attempt record;

  _number varchar;
BEGIN

  select *
  from call_center.cc_calls c
  where c.id = _call_id::uuid
--   for update
  into _call;

  if _call.id isnull or _call.direction isnull then
    raise exception 'not found call';
  elseif _call.direction <> 'outbound' then
    _number = _call.from_number;
  else
    _number = _call.destination;
  end if;


  select
    a.id,
    a.team_id,
    t.updated_at,
    a.domain_id,
    (a.updated_at - extract(epoch from u.updated_at))::int8
  from call_center.cc_agent a
         inner join call_center.cc_team t on t.id = a.team_id
         inner join directory.wbt_user u on u.id = a.user_id
  where a.user_id = _user_id -- check attempt
    and length(coalesce(u.extension, '')) > 0
    for update
  into _agent_id,
    _team_id_,
    _team_updated_at,
    _domain_id,
    _agent_updated_at
  ;

  if _call.domain_id != _domain_id then
    raise exception 'the queue on another domain';
  end if;

  if _team_id_ isnull then
    raise exception 'not found agent';
  end if;


  insert into call_center.cc_member_attempt (channel, domain_id, state, team_id, member_call_id, destination, node_id, agent_id, parent_id, queue_params)
  values ('out_call', _domain_id, 'active', _team_id_, _call_id, jsonb_build_object('destination', _number),
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
    call_center.cc_view_timestamp(_call.created_at)::int8,
    _agent_id
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
-- Name: cc_queue_params(call_center.cc_queue); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_queue_params(q call_center.cc_queue) RETURNS jsonb
  LANGUAGE sql IMMUTABLE
AS $$
select jsonb_build_object('has_reporting', q.processing)
         || jsonb_build_object('has_form', q.processing and q.form_schema_id notnull)
         || jsonb_build_object('processing_sec', q.processing_sec)
         || jsonb_build_object('processing_renewal_sec', q.processing_renewal_sec)
         || jsonb_build_object('queue_name', q.name)
         || jsonb_build_object('has_prolongation', q.prolongation_enabled)
         || jsonb_build_object('remaining_prolongations', q.prolongation_repeats_number)
         || jsonb_build_object('prolongation_sec', q.prolongation_time_sec)
         || jsonb_build_object('is_timeout_retry', q.prolongation_is_timeout_retry)
         as queue_params;
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

alter table call_center.cc_calls_annotation add column file_id bigint;



--
-- Name: cc_call_active_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_call_active_list AS
SELECT c.id,
       c.app_id,
       c.state,
       c."timestamp",
       'call'::character varying AS type,
       c.parent_id,
       call_center.cc_get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS "user",
       u.extension,
       call_center.cc_get_lookup(gw.id, gw.name) AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number', COALESCE(c.from_number, ''::character varying), 'id', COALESCE(c.from_id, ''::character varying), 'name', COALESCE(c.from_name, ''::character varying)) AS "from",
       CASE
         WHEN ((c.to_number)::text <> ''::text) THEN json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number', COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying), 'name', COALESCE(c.to_name, ''::character varying))
         ELSE NULL::json
         END AS "to",
       CASE
         WHEN (c.payload IS NULL) THEN '{}'::jsonb
         ELSE c.payload
         END AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       (date_part('epoch'::text, (now() - c.created_at)))::bigint AS duration,
       COALESCE(c.hold_sec, 0) AS hold_sec,
       COALESCE(
         CASE
           WHEN (c.answered_at IS NOT NULL) THEN (date_part('epoch'::text, (c.answered_at - c.created_at)))::bigint
           ELSE (date_part('epoch'::text, (now() - c.created_at)))::bigint
           END, (0)::bigint) AS wait_sec,
       CASE
         WHEN (c.answered_at IS NOT NULL) THEN (date_part('epoch'::text, (now() - c.answered_at)))::bigint
         ELSE (0)::bigint
         END AS bill_sec,
       call_center.cc_get_lookup((cq.id)::bigint, cq.name) AS queue,
       call_center.cc_get_lookup((cm.id)::bigint, cm.name) AS member,
       call_center.cc_get_lookup(ct.id, ct.name) AS team,
       ca."user" AS agent,
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
         WHEN (cma.reporting_at IS NOT NULL) THEN (date_part('epoch'::text, (cma.reporting_at - now())))::integer
         ELSE 0
         END AS reporting_sec,
       cma.agent_id,
       aa.team_id,
       c.user_id,
       c.queue_id,
       c.member_id,
       c.attempt_id,
       c.domain_id,
       c.gateway_id,
       c.from_number,
       c.to_number,
       cma.display,
       ( SELECT jsonb_agg(sag."user") AS jsonb_agg
         FROM call_center.cc_agent_with_user sag
         WHERE (sag.id = ANY (aa.supervisor_ids))) AS supervisor,
       aa.supervisor_ids,
       c.grantee_id,
       c.hold,
       c.blind_transfer,
       c.bridged_id
FROM ((((((((call_center.cc_calls c
  LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
  LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
  LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
  LEFT JOIN call_center.cc_member_attempt cma ON ((cma.id = c.attempt_id)))
  LEFT JOIN call_center.cc_agent_with_user ca ON ((cma.agent_id = ca.id)))
  LEFT JOIN call_center.cc_agent aa ON ((aa.user_id = c.user_id)))
  LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
  LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
WHERE ((c.hangup_at IS NULL) AND (c.direction IS NOT NULL));



--
-- Name: cc_calls_history_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_calls_history_list AS
SELECT c.id,
       c.app_id,
       'call'::character varying AS type,
       c.parent_id,
       c.transfer_from,
       CASE
         WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND (c.id <> call_center.cc_bridged_id(c.parent_id))) THEN call_center.cc_bridged_id(c.parent_id)
         ELSE c.transfer_to
         END AS transfer_to,
       COALESCE(call_center.cc_get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying), call_center.cc_get_lookup(cag.id, (COALESCE(cag.name, (cag.username)::text))::character varying), NULL::jsonb) AS "user",
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
       ( SELECT json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at',
                                            CASE
                                              WHEN (((f_1.channel)::text = 'call'::text) AND (NOT ((f_1.mime_type)::text ~~ 'image%'::text))) THEN COALESCE(((f_1.custom_properties ->> 'start_time'::text))::bigint, ((c.params -> 'record_start'::text))::bigint, call_center.cc_view_timestamp(c.answered_at))
                                              ELSE COALESCE(((f_1.custom_properties ->> 'start_time'::text))::bigint, f_1.created_at)
                                              END, 'stop_at',
                                            CASE
                                              WHEN (((f_1.channel)::text = 'call'::text) AND (NOT ((f_1.mime_type)::text ~~ 'image%'::text))) THEN COALESCE(((f_1.custom_properties ->> 'end_time'::text))::bigint, ((c.params -> 'record_stop'::text))::bigint, call_center.cc_view_timestamp(c.hangup_at))
                                              ELSE ((f_1.custom_properties ->> 'end_time'::text))::bigint
                                              END, 'start_record', f_1.sr, 'channel', f_1.channel)) AS files
         FROM ( SELECT f1.id,
                       f1.size,
                       f1.mime_type,
                       COALESCE(f1.view_name, f1.name) AS name,
                       f1.channel,
                       f1.custom_properties,
                       f1.created_at,
                       CASE
                         WHEN (((c.direction)::text = 'outbound'::text) AND (c.user_id IS NOT NULL) AND ((c.queue_id IS NULL) OR (cq.type = 2))) THEN 'operator'::text
                         ELSE 'client'::text
                         END AS sr
                FROM storage.files f1
                WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.id)::text))
                UNION ALL
                SELECT f1.id,
                       f1.size,
                       f1.mime_type,
                       COALESCE(f1.view_name, f1.name) AS name,
                       f1.channel,
                       f1.custom_properties,
                       f1.created_at,
                       NULL::text AS sr
                FROM storage.files f1
                WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND (c.parent_id IS NOT NULL) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) AS files,
       call_center.cc_get_lookup((cq.id)::bigint, cq.name) AS queue,
       call_center.cc_get_lookup(c.member_id, COALESCE(cm.name, ((cma.destination ->> 'name'::text))::character varying)) AS member,
       call_center.cc_get_lookup(ct.id, ct.name) AS team,
       call_center.cc_get_lookup((aa.id)::bigint, (COALESCE(cag.name, (cag.username)::text))::character varying) AS agent,
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
                 WHERE (((c.parent_id IS NULL) OR (c.blind_transfer IS NOT NULL)) AND (hp.parent_id = c.id) AND (hp.created_at > (c.created_at)::date)))) AS has_children,
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
                       a.end_sec,
                       a.file_id
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
       ((EXISTS ( SELECT 1
                  WHERE ((c.answered_at IS NOT NULL) AND (cq.type = 2)))) OR (EXISTS ( SELECT 1
                                                                                       FROM call_center.cc_calls_history cr
                                                                                       WHERE ((cr.id = c.bridged_id) AND (c.bridged_id IS NOT NULL) AND (c.blind_transfer IS NULL) AND (cr.blind_transfer IS NULL) AND (c.transfer_to IS NULL) AND (cr.transfer_to IS NULL) AND (c.transfer_from IS NULL) AND (cr.transfer_from IS NULL) AND (COALESCE(cr.user_id, c.user_id) IS NOT NULL))))) AS allow_evaluation,
       cma.form_fields,
       c.bridged_id,
       call_center.cc_get_lookup(cc.id, (cc.common_name)::character varying) AS contact,
       c.contact_id,
       c.search_number,
       c.hide_missed,
       c.redial_id,
       ((c.parent_id IS NOT NULL) AND (EXISTS ( SELECT 1
                                                FROM call_center.cc_calls_history lega
                                                WHERE ((lega.id = c.parent_id) AND (lega.domain_id = c.domain_id) AND (lega.bridged_at IS NOT NULL))))) AS parent_bridged,
       ( SELECT jsonb_agg(call_center.cc_get_lookup(ash.id, ash.name)) AS jsonb_agg
         FROM flow.acr_routing_scheme ash
         WHERE (ash.id = ANY (c.schema_ids))) AS schemas,
       c.schema_ids,
       c.hangup_phrase,
       c.blind_transfers,
       c.destination_name,
       c.attempt_ids,
       ( SELECT jsonb_agg(json_build_object('id', p.id, 'agent', u_1."user", 'form_fields', p.form_fields, 'reporting_at', call_center.cc_view_timestamp(p.reporting_at))) AS jsonb_agg
         FROM (call_center.cc_member_attempt_history p
           LEFT JOIN call_center.cc_agent_with_user u_1 ON ((u_1.id = p.agent_id)))
         WHERE ((p.id IN ( SELECT DISTINCT x.x
                           FROM unnest((c.attempt_ids || c.attempt_id)) x(x))) AND (p.reporting_at IS NOT NULL))
         LIMIT 20) AS forms,
       ( SELECT co.id
         FROM chat.conversation co
         WHERE ((co.props ->> 'wbt_meeting_id'::text) = (c.params ->> 'meeting_id'::text))
         LIMIT 1) AS conversation_id,
       (c.params ->> 'meeting_id'::text) AS meeting_id,
       row_to_json(ms.*) AS quality_metrics
FROM ((((((((((((((call_center.cc_calls_history c
  LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
  LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
  LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
  LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
  LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
  LEFT JOIN call_center.cc_team ct ON ((aa.team_id = ct.id)))
  LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
  LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
  LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
  LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
  LEFT JOIN directory.wbt_user aru ON ((aru.id = ar.rated_user_id)))
  LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by)))
  LEFT JOIN contacts.contact cc ON ((cc.id = c.contact_id)))
  LEFT JOIN call_center.cc_calls_media_stats ms ON ((ms.sip_id = (c.params ->> 'sip_id'::text))));




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
              array_agg(jsonb_build_object('attempt_id', a.attempt_id, 'wait', a.wait, 'communication', a.communication, 'queue', a.queue, 'bucket', call_center.cc_get_lookup(b.id, ((b.name)::text)::character varying), 'deadline', a.deadline, 'session_id', a.session_id) ORDER BY a.lvl, a.priority DESC, a.bucket_pri DESC NULLS LAST, a.wait DESC) FILTER (WHERE ((a.channel)::text = ANY (ARRAY['chat'::text, 'im'::text]))) AS chats
       FROM (attempts a
         LEFT JOIN call_center.cc_bucket b ON ((b.id = a.bucket_id)))
       GROUP BY a.domain_id, a.user_id) x
GROUP BY x.domain_id, x.calls[1:10], x.chats[1:100];


drop view call_center.cc_agent_in_queue_view;
--
-- Name: cc_agent_in_queue_view _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_agent_in_queue_view AS
WITH users_with_calls AS (
  SELECT DISTINCT c.user_id
  FROM call_center.cc_calls c
  WHERE ((c.user_id IS NOT NULL) AND (((c.hangup_at IS NULL) AND (NOT (EXISTS ( SELECT 1
                                                                                FROM call_center.cc_calls cc
                                                                                WHERE ((cc.parent_id = c.id) AND (cc.hangup_at IS NOT NULL)))))) OR ((c.hangup_at IS NOT NULL) AND (c.attempt_id IS NOT NULL) AND (EXISTS ( SELECT 1
                                                                                                                                                                                                                            FROM call_center.cc_agent_channel ch
                                                                                                                                                                                                                            WHERE ((ch.agent_id = c.agent_id) AND ((ch.channel)::text = ANY ((ARRAY['call'::character varying, 'out_call'::character varying])::text[])) AND ((ch.state)::text = 'processing'::text)))))))
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
                            WHEN (q.min_online_agents > 0) THEN GREATEST(((COALESCE(array_length(a.agent_p_ids, 1), 0) + COALESCE(array_length(a.agent_on_ids, 1), 0)) - q.min_online_agents), 0)
                            ELSE NULL::integer
                            END, 'busy', COALESCE(array_length(a.agent_b_ids, 1), 0)) AS agents,
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
                                      array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND ((ac.state)::text = 'waiting'::text) AND ((ac_call.user_id IS NULL) OR ((ac.channel)::text = ANY (ARRAY['chat'::text, 'task'::text]))))) AS free,
                                      array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND (ac_call.user_id IS NOT NULL))) AS agent_b_ids,
                                      array_agg(DISTINCT a_1.id) AS total
                      FROM ((((call_center.cc_agent a_1
                        JOIN call_center.cc_agent_channel ac ON (((ac.agent_id = a_1.id) AND ((ac.channel)::text = q.chan_name))))
                        LEFT JOIN users_with_calls ac_call ON ((ac_call.user_id = a_1.user_id)))
                        JOIN call_center.cc_queue_skill qs ON (((qs.queue_id = q.queue_id) AND qs.enabled)))
                        JOIN call_center.cc_skill_in_agent sia ON (((sia.agent_id = a_1.id) AND sia.enabled)))
                      WHERE ((a_1.domain_id = q.domain_id) AND ((q.team_id IS NULL) OR (a_1.team_id = q.team_id)) AND (qs.skill_id = sia.skill_id) AND (sia.capacity >= qs.min_capacity) AND (sia.capacity <= qs.max_capacity))
                      GROUP BY ROLLUP(q.queue_id)) a ON (true));



drop view call_center.cc_distribute_stage_1;
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
    JOIN LATERAL unnest(c.accepts) a(disabled, day, start_time_of_day, end_time_of_day, special) ON (true))
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


--
-- Name: cc_member_attempt_history_mat_view_chat_task; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX if not exists cc_member_attempt_history_mat_view_chat_task ON call_center.cc_member_attempt_history
  USING btree (agent_id, leaving_at) WHERE ((channel)::text = ANY (ARRAY['chat'::text, 'task'::text]));


drop index call_center.idx_cc_agent_domain_user;
--
-- Name: idx_cc_agent_domain_user; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX idx_cc_agent_domain_user ON call_center.cc_agent USING btree (domain_id, user_id) INCLUDE (team_id, id);



DROP MATERIALIZED VIEW call_center.cc_agent_today_pause_cause;
--
-- Name: cc_agent_today_pause_cause; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_agent_today_pause_cause AS
SELECT a.id,
       ((now())::date + age(now(), (timezone(COALESCE(t.sys_name, 'UTC'::text), now()))::timestamp with time zone)) AS today,
       p.payload AS cause,
       p.d AS duration
FROM (((call_center.cc_agent a
  LEFT JOIN flow.region r ON ((r.id = a.region_id)))
  LEFT JOIN flow.calendar_timezones t ON ((t.id = r.timezone_id)))
  LEFT JOIN LATERAL ( SELECT cc_agent_state_history.payload,
                             sum(cc_agent_state_history.duration) FILTER (WHERE (cc_agent_state_history.duration > '00:00:00'::interval)) AS d
                      FROM call_center.cc_agent_state_history
                      WHERE ((cc_agent_state_history.joined_at > ((now())::date + age(now(), (timezone(COALESCE(t.sys_name, 'UTC'::text), now()))::timestamp with time zone))) AND (cc_agent_state_history.agent_id = a.id) AND ((cc_agent_state_history.state)::text = 'pause'::text) AND (cc_agent_state_history.channel IS NULL))
                      GROUP BY cc_agent_state_history.payload) p ON (true))
WHERE (p.d IS NOT NULL)
WITH NO DATA;

create unique index cc_agent_today_stats_uidx
  on call_center.cc_agent_today_stats (agent_id);

create unique index cc_agent_today_stats_usr_uidx
  on call_center.cc_agent_today_stats (user_id);

refresh materialized view call_center.cc_agent_today_pause_cause;


ALTER TABLE call_center.cc_member_attempt SET (
  fillfactor = 70,
  autovacuum_vacuum_cost_delay = 0,
  autovacuum_vacuum_cost_limit = 1000,
  autovacuum_vacuum_scale_factor = 0.01
  );
ALTER TABLE call_center.cc_calls SET (
  fillfactor = 70,
  autovacuum_vacuum_cost_delay = 0,
  autovacuum_vacuum_cost_limit = 1000,
  autovacuum_vacuum_scale_factor = 0.01
  );

ALTER TABLE call_center.cc_member
  reset (fillfactor, log_autovacuum_min_duration, autovacuum_vacuum_scale_factor, autovacuum_analyze_scale_factor,
         autovacuum_vacuum_cost_delay, autovacuum_enabled, autovacuum_analyze_threshold);
show autovacuum_vacuum_scale_factor;


ALTER TABLE call_center.cc_member SET (
  autovacuum_vacuum_cost_delay = 0,
  autovacuum_vacuum_cost_limit = 1000,
  autovacuum_vacuum_scale_factor = 0.01
  );
ALTER TABLE call_center.cc_member SET (fillfactor = 70);
