
--
-- Name: meetings; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA meetings;



--
-- Name: web_meetings; Type: TABLE; Schema: meetings; Owner: -
--

CREATE TABLE meetings.web_meetings (
                                     id text NOT NULL,
                                     domain_id bigint NOT NULL,
                                     title text NOT NULL,
                                     created_at bigint NOT NULL,
                                     expires_at bigint NOT NULL,
                                     variables jsonb,
                                     url text,
                                     call_id text,
                                     satisfaction text,
                                     bridged boolean DEFAULT false
);


--
-- Name: web_meetings web_meetings_pkey; Type: CONSTRAINT; Schema: meetings; Owner: -
--

ALTER TABLE ONLY meetings.web_meetings
  ADD CONSTRAINT web_meetings_pkey PRIMARY KEY (id);



drop VIEW storage.file_policies_view;
--
-- Name: file_policies_view; Type: VIEW; Schema: storage; Owner: -
--

CREATE VIEW storage.file_policies_view AS
SELECT p.id,
       p.domain_id,
       p.created_at,
       storage.get_lookup(c.id, (COALESCE(c.name, (c.username)::text))::character varying) AS created_by,
       p.updated_at,
       storage.get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS updated_by,
       p.enabled,
       p.name,
       COALESCE(p.description, ''::character varying) AS description,
       p.channels,
       p.mime_types,
       p.speed_download,
       p.speed_upload,
       p.max_upload_size,
       p.retention_days,
       p.encrypt,
       row_number() OVER (PARTITION BY p.domain_id ORDER BY p."position" DESC) AS "position"
FROM ((storage.file_policies p
  LEFT JOIN directory.wbt_user c ON ((c.id = p.created_by)))
  LEFT JOIN directory.wbt_user u ON ((u.id = p.updated_by)));




--
-- Name: calendar_check_timing(bigint, integer, character varying); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE OR REPLACE FUNCTION flow.calendar_check_timing(domain_id_ bigint, calendar_id_ integer, name_ character varying) RETURNS record
  LANGUAGE plpgsql IMMUTABLE
AS $$
declare
  res record;
begin
  select c.name,
         (
           select x.name
           from unnest(c.excepts) as x
           where not x.disabled is true
             and case
                   when x.repeat is true then
                     to_char((current_timestamp AT TIME ZONE ct.sys_name)::date, 'MM-DD') =
                     to_char((to_timestamp(x.date / 1000) at time zone ct.sys_name)::date, 'MM-DD')
                   else
                     (current_timestamp AT TIME ZONE ct.sys_name)::date =
                     (to_timestamp(x.date / 1000) at time zone ct.sys_name)::date
             end
             and not (x.working and (to_char(current_timestamp AT TIME ZONE ct.sys_name, 'SSSS') :: int / 60) between x.work_start and x.work_stop)
           limit 1
         )                     excepted,
         exists(
           select 1
           from unnest(c.accepts) as x
           where not x.disabled is true
             and x.day + 1 = extract(isodow from current_timestamp AT TIME ZONE ct.sys_name)::int
             and (to_char(current_timestamp AT TIME ZONE ct.sys_name, 'SSSS') :: int / 60) between x.start_time_of_day and x.end_time_of_day
         )                 accept,
         case
           when c.start_at > 0 and c.end_at > 0 then
             not current_date AT TIME ZONE ct.sys_name between (to_timestamp(c.start_at / 1000) at time zone ct.sys_name)::date and (to_timestamp(c.end_at / 1000) at time zone ct.sys_name)::date + interval '1d'
           else false end as expire
  into res
  from flow.calendar c
         inner join flow.calendar_timezones ct on c.timezone_id = ct.id
  where c.domain_id = domain_id_
    and (
    c.id = calendar_id_ or c.name = name_
    )
  limit 1;

  return res;
end;
$$;




--
-- Name: cc_attempt_end_reporting(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb, integer, integer, boolean, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, per_number_ boolean DEFAULT false, only_current_communication_ boolean DEFAULT false) RETURNS record
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
                b2o.*
         from call_center.cc_calls b
                left join call_center.cc_calls b2 on b2.id = call_bridged_id_
                left join lateral call_center.cc_call_get_owner_leg(b2) b2o on true
         where b.id = call_id_::uuid
       ) c
  where c.id = cc.id
  returning cc.transfer_from into transfer_from_;

  update call_center.cc_calls set
                                transfer_from =  case when id = transfer_from_ then transfer_to_ end,
                                transfer_to =  case when id = transfer_to_ then transfer_from_ end
  where id in (transfer_from_, transfer_to_);

end;
$$;



--
-- Name: cc_distribute_inbound_call_to_agent(character varying, character varying, jsonb, integer, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer, q_params jsonb DEFAULT NULL::jsonb) RETURNS record
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
  ELSIF _call.direction <> 'outbound' or _call.user_id notnull then
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
    call_center.cc_view_timestamp(_call.created_at)::int8,
    _call.parent_id::varchar
    );
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
    call_center.cc_view_timestamp(_call.created_at)::int8,
    _call.parent_id::varchar
    );

END;
$$;


--
-- Name: cc_get_agent_queues(integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_get_agent_queues(_domain_id integer, _user_id integer) RETURNS integer[]
  LANGUAGE sql STABLE
AS $$
select array_agg(distinct cq.id)
from call_center.cc_agent ca
       inner join call_center.cc_skill_in_agent csia
                  on csia.agent_id = ca.id
                    and csia.enabled
       inner join call_center.cc_queue_skill cqs on
  cqs.skill_id = csia.skill_id
    and cqs.enabled
    and csia.capacity between cqs.min_capacity and cqs.max_capacity
       inner join call_center.cc_queue cq
                  on cq.id = cqs.queue_id
where ca.user_id = _user_id
  and ca.domain_id = _domain_id
  and (cq.team_id is null or cq.team_id = ca.team_id);
$$;


drop materialized view call_center.cc_agent_today_pause_cause;
create materialized view call_center.cc_agent_today_pause_cause as
SELECT a.id,
       now()::date + age(now(), timezone(COALESCE(t.sys_name, 'UTC'::text), now())::timestamp with time zone) AS today,
       p.payload                                                                                              AS cause,
       p.d                                                                                                    AS duration
FROM call_center.cc_agent a
       LEFT JOIN flow.region r ON r.id = a.region_id
       LEFT JOIN flow.calendar_timezones t ON t.id = r.timezone_id
       LEFT JOIN LATERAL ( SELECT cc_agent_state_history.payload,
                                  sum(cc_agent_state_history.duration)
                                  FILTER (WHERE cc_agent_state_history.duration > '00:00:00'::interval) AS d
                           FROM call_center.cc_agent_state_history
                           WHERE cc_agent_state_history.joined_at > (now()::date + age(now(),
                                                                                       timezone(COALESCE(t.sys_name, 'UTC'::text), now())::timestamp with time zone))
                             AND cc_agent_state_history.agent_id = a.id
                             AND cc_agent_state_history.state::text = 'pause'::text
                             AND cc_agent_state_history.channel IS NULL
                           GROUP BY cc_agent_state_history.payload) p ON true
WHERE p.d IS NOT NULL;

create unique index cc_agent_today_pause_cause_agent_uidx
  on call_center.cc_agent_today_pause_cause (id, today, cause);


refresh materialized view call_center.cc_agent_today_pause_cause;


drop materialized view call_center.cc_agent_today_stats;
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
                                                                 WHEN (now()::date + '1 day'::interval -
                                                                       COALESCE(t.utc_offset, '00:00:00'::interval))::timestamp with time zone <
                                                                      now() THEN (now()::date + '1 day'::interval -
                                                                                  COALESCE(t.utc_offset, '00:00:00'::interval))::timestamp with time zone
                                                                 ELSE (now()::date - COALESCE(t.utc_offset, '00:00:00'::interval))::timestamp with time zone
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
             WHERE h.joined_at > (now()::date - '1 day'::interval)
               AND h.domain_id = agents.domain_id
               AND h.joined_at >= agents."from"
               AND h.joined_at <= agents."to"
               AND h.channel::text = 'call'::text
             GROUP BY h.agent_id),
     attempts AS MATERIALIZED (WITH rng(agent_id, c, s, e, b, ac) AS (SELECT h.agent_id,
                                                                             h.channel,
                                                                             h.offering_at,
                                                                             COALESCE(h.reporting_at, h.leaving_at) AS e,
                                                                             h.bridged_at                           AS v,
                                                                             CASE
                                                                               WHEN h.bridged_at IS NOT NULL THEN 1
                                                                               WHEN h.channel::text = 'task'::text AND h.reporting_at IS NOT NULL
                                                                                 THEN 1
                                                                               ELSE 0
                                                                               END                                AS ac
                                                                      FROM agents a_1
                                                                             JOIN call_center.cc_member_attempt_history h ON h.agent_id = a_1.id
                                                                      WHERE h.leaving_at > (now()::date - '2 days'::interval)
                                                                        AND h.leaving_at >= a_1."from"
                                                                        AND h.leaving_at <= a_1."to"
                                                                        AND (h.channel::text = ANY (ARRAY ['chat'::text, 'task'::text]))
                                                                        AND h.agent_id IS NOT NULL
                                                                        AND 1 = 1)
                               SELECT t.agent_id,
                                      t.c                                        AS channel,
                                      sum(t.delta)                               AS sht,
                                      sum(t.ac)                                  AS bridged_cnt,
                                      EXTRACT(epoch FROM avg(t.e - t.b))::bigint AS aht
                               FROM (SELECT rng.agent_id,
                                            rng.c,
                                            rng.s,
                                            rng.e,
                                            rng.b,
                                            rng.ac,
                                            GREATEST(rng.e - GREATEST(max(rng.e)
                                                                      OVER (PARTITION BY rng.agent_id, rng.c ORDER BY rng.s, rng.e ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                                                                      rng.s), '00:00:00'::interval) AS delta
                                     FROM rng) t
                               GROUP BY t.agent_id, t.c),
     calls AS (SELECT h.user_id,
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text)                                                                               AS all_inb,
                      count(*) FILTER (WHERE h.answered_at IS NOT NULL)                                                                                         AS handled,
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
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text AND h.bridged_at IS NULL AND
                                             NOT h.hide_missed IS TRUE AND
                                             pc.bridged_at IS NULL)                                                                                             AS missed,
                      count(h.parent_id) FILTER (WHERE h.bridged_at IS NULL AND NOT h.hide_missed IS TRUE AND
                                                       h.queue_id IS NOT NULL)                                                                                  AS queue_missed,
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text AND h.bridged_at IS NULL AND
                                             h.queue_id IS NOT NULL AND (h.cause::text = ANY
                                                                         (ARRAY ['NO_ANSWER'::character varying::text, 'USER_BUSY'::character varying::text]))) AS abandoned,
                      count(*) FILTER (WHERE (cq.type = ANY (ARRAY [3::smallint, 4::smallint, 5::smallint])) AND
                                             h.bridged_at IS NOT NULL)                                                                                          AS outbound_queue,
                      count(*) FILTER (WHERE h.parent_id IS NULL AND h.direction::text = 'outbound'::text AND
                                             h.queue_id IS NULL)                                                                                                AS manual_call,
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
              WHERE ar.call_created_at >=
                    (date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) AT TIME ZONE a_1.tz_name)
                AND ar.call_created_at <=
                    ((date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) + '1 mon'::interval -
                      '1 day 00:00:01'::interval) AT TIME ZONE a_1.tz_name)
              GROUP BY a_1.user_id)
SELECT a.id                                                                                                         AS agent_id,
       a.user_id,
       a.domain_id,
       COALESCE(c.missed, 0::bigint)                                                                                AS call_missed,
       COALESCE(c.queue_missed, 0::bigint)                                                                          AS call_queue_missed,
       COALESCE(c.abandoned, 0::bigint)                                                                             AS call_abandoned,
       COALESCE(c.inbound_bridged, 0::bigint)                                                                       AS call_inbound,
       COALESCE(c."inbound queue", 0::bigint)                                                                       AS call_inbound_queue,
       COALESCE(c.outbound_queue, 0::bigint)                                                                        AS call_dialer_queue,
       COALESCE(c.manual_call, 0::bigint)                                                                           AS call_manual,
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
                               0::numeric THEN
                            EXTRACT(epoch FROM stats.online - COALESCE(stats.lunch, '00:00:00'::interval)) -
                            (COALESCE(EXTRACT(epoch FROM c."Call initiation"), 0::numeric) +
                             COALESCE(EXTRACT(epoch FROM c."Talk time"), 0::numeric) +
                             COALESCE(EXTRACT(epoch FROM c."Post call"), 0::numeric) -
                             COALESCE(EXTRACT(epoch FROM eff.tpause), 0::numeric) +
                             EXTRACT(epoch FROM COALESCE(stats.study, '00:00:00'::interval)) +
                             EXTRACT(epoch FROM COALESCE(stats.conference, '00:00:00'::interval)))
                          ELSE 0::numeric
                          END, 0::numeric), 2),
                0::numeric)::integer                                                                                AS available,
       COALESCE(EXTRACT(epoch FROM c.vm)::bigint, 0::bigint)                                                        AS voice_mail,
       COALESCE(chc.aht, 0::bigint)                                                                                 AS chat_aht,
       COALESCE(cht.bridged_cnt, 0::bigint) + COALESCE(chc.bridged_cnt, 0::bigint) + COALESCE(c.handled, 0::bigint) -
       COALESCE(c.user_2user, 0::bigint)                                                                            AS task_accepts,
       COALESCE(EXTRACT(epoch FROM stats.online - COALESCE(stats.lunch, '00:00:00'::interval)),
                0::numeric)::bigint                                                                                 AS online,
       COALESCE(chc.bridged_cnt, 0::bigint)                                                                         AS chat_accepts,
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
       LEFT JOIN attempts chc ON chc.agent_id = a.id AND chc.channel::text = 'chat'::text
       LEFT JOIN attempts cht ON cht.agent_id = a.id AND cht.channel::text = 'task'::text
       LEFT JOIN rate ON rate.user_id = a.user_id;


create unique index cc_agent_today_stats_uidx
  on call_center.cc_agent_today_stats (agent_id);

create unique index cc_agent_today_stats_usr_uidx
  on call_center.cc_agent_today_stats (user_id);

refresh materialized view call_center.cc_agent_today_stats;



DROP VIEW call_center.cc_calls_history_list;
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
       call_center.cc_get_lookup(c.member_id, cm.name) AS member,
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
       (c.params ->> 'meeting_id'::text) AS meeting_id
FROM (((((((((((((call_center.cc_calls_history c
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
  LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by)))
  LEFT JOIN contacts.contact cc ON ((cc.id = c.contact_id)));


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
       q.tags,
       COALESCE(rg.resource_groups, '[]'::jsonb) AS resource_groups,
       COALESCE(rg.resources, '[]'::jsonb) AS resources
FROM ((((((((((((((call_center.cc_queue q
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
                      WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL) AND ((a.state)::text <> 'leaving'::text))) act ON (true))
  LEFT JOIN LATERAL ( SELECT jsonb_agg(DISTINCT call_center.cc_get_lookup(corg.id, corg.name)) FILTER (WHERE (corg.id IS NOT NULL)) AS resource_groups,
                             jsonb_agg(DISTINCT call_center.cc_get_lookup((cor.id)::bigint, cor.name)) FILTER (WHERE (cor.id IS NOT NULL)) AS resources
                      FROM (((call_center.cc_queue_resource cqr
                        JOIN call_center.cc_outbound_resource_group corg ON ((corg.id = cqr.resource_group_id)))
                        LEFT JOIN call_center.cc_outbound_resource_in_group corg_res ON ((corg_res.group_id = corg.id)))
                        LEFT JOIN call_center.cc_outbound_resource cor ON ((cor.id = corg_res.resource_id)))
                      WHERE (cqr.queue_id = q.id)) rg ON (true));


--
-- Name: cc_calls_history_meeting_id; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_meeting_id ON call_center.cc_calls_history USING btree (((params ->> 'meeting_id'::text))) WHERE (((params ->> 'meeting_id'::text) IS NOT NULL) AND (parent_id IS NULL));

