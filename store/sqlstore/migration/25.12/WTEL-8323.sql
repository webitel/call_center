-- Name: cc_attempt_end_reporting; Type: FUNCTION; Schema: call_center; Owner: -
--

DROP FUNCTION IF EXISTS call_center.cc_attempt_end_reporting;

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
  member_tz_ text;
  scheduled_at_ timestamptz;
begin
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

  if next_offering_at_ notnull and not attempt.result in ('success', 'cancel', 'canceled_by_timeout') then
    select coalesce(tz.names[1], 'UTC')
    into member_tz_
    from call_center.cc_member m2
           left join flow.calendar_timezone_offsets tz on tz.id = m2.sys_offset_id
    where m2.id = attempt.member_id;

    scheduled_at_ := (next_offering_at_ at time zone 'UTC') at time zone coalesce(member_tz_, 'UTC');
    if scheduled_at_ < now() then
      -- todo move to application
      raise exception 'bad parameter: next distribute at';
    end if;
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

        -- WTEL-8323: next_offering_at_ is "naive" UTC - interpret as member's local time
        ready_at = case when next_offering_at_ notnull then (next_offering_at_ at time zone 'UTC') at time zone coalesce(tz.names[1], 'UTC')
                        else now() + (wait_between_retries_ || ' sec')::interval end,

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
-- Name: cc_attempt_schema_result; Type: FUNCTION; Schema: call_center; Owner: -
--

DROP FUNCTION IF EXISTS call_center.cc_attempt_schema_result;

CREATE OR REPLACE FUNCTION call_center.cc_attempt_schema_result(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, _per_number boolean DEFAULT false)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
declare
    attempt  call_center.cc_member_attempt%rowtype;
    stop_cause_ varchar;
    time_ int8 = extract(EPOCH  from now()) * 1000;
begin
    update call_center.cc_member_attempt
        set result = case when status_ notnull then status_ else result end,
            description = case when description_ notnull then description_ else description end,
            schema_processing = false
    where id = attempt_id_
    returning * into attempt;

    if attempt.member_id notnull then
        update call_center.cc_member m
        set last_hangup_at  = time_,
            variables = case when variables_ notnull then coalesce(m.variables::jsonb, '{}') || variables_ else m.variables end,
            expire_at = case when expire_at_ isnull then m.expire_at else expire_at_ end,
            agent_id = case when sticky_agent_id_ isnull then m.agent_id else sticky_agent_id_ end,

            stop_at = case when next_offering_at_ notnull or
                                m.stop_at notnull or
                                (not attempt.result in ('success', 'cancel', 'canceled_by_timeout') and
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                 )
                then m.stop_at else  attempt.leaving_at end,
            stop_cause = case when next_offering_at_ notnull or
                                m.stop_at notnull or
                                (not attempt.result in ('success', 'cancel', 'canceled_by_timeout') and
                                   case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                 )
                then m.stop_cause else  attempt.result end,

            -- WTEL-8323: next_offering_at_ is "naive" UTC - interpret as member's local time
            ready_at = case when next_offering_at_ notnull then (next_offering_at_ at time zone 'UTC') at time zone coalesce(tz.names[1], 'UTC')
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


    return row(attempt.last_state_change::timestamptz, stop_cause_::varchar, attempt.result::varchar);
end;
$function$
;
