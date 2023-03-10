drop function call_center.cc_attempt_timeout;
create  function call_center.cc_attempt_timeout(attempt_id_ bigint, agent_status_ character varying, agent_hold_sec_ integer,
                                                max_attempts_ integer DEFAULT 0, per_number_ boolean DEFAULT false) returns timestamp with time zone
    language plpgsql
as
$$
declare
    attempt call_center.cc_member_attempt%rowtype;
begin
    update call_center.cc_member_attempt
    set reporting_at = now(),
        result = 'timeout',
        state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    update call_center.cc_member
    set last_hangup_at  = extract(EPOCH from now())::int8 * 1000,
        last_agent      = coalesce(attempt.agent_id, last_agent),


        stop_at = case when stop_at notnull or
                            (not attempt.result in ('success', 'cancel') and
                             case when per_number_ is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (attempts + 1 < max_attempts_)) end
                                )
                           then stop_at else  attempt.leaving_at end,
        stop_cause = case when stop_at notnull or
                               (not attempt.result in ('success', 'cancel') and
                                case when per_number_ is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (attempts + 1 < max_attempts_)) end
                                   )
                              then stop_cause else  attempt.result end,

        ready_at = now() + (coalesce(q._next_after, 0) || ' sec')::interval,

        communications =  jsonb_set(communications, (array[attempt.communication_idx::int])::text[], communications->(attempt.communication_idx::int) ||
                                                                                                     jsonb_build_object('last_activity_at', (extract(epoch  from attempt.leaving_at) * 1000)::int8::text::jsonb) ||
                                                                                                     jsonb_build_object('attempt_id', attempt_id_) ||
                                                                                                     jsonb_build_object('attempts', coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                                                                                                     case when (per_number_ is true and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= max_attempts_) then jsonb_build_object('stop_at', (extract(EPOCH from now() ) * 1000)::int8) else '{}'::jsonb end
            ),
        attempts        = attempts + 1
    from (
             -- fixme
             select coalesce(cast((q.payload->>'max_attempts') as int), 0) as _max_count, coalesce(cast((q.payload->>'wait_between_retries') as int), 0) as _next_after
             from call_center.cc_queue q
             where q.id = attempt.queue_id
         ) q
    where id = attempt.member_id;

    if attempt.agent_id notnull then
        update call_center.cc_agent_channel c
        set state = agent_status_,
            joined_at = now(),
            channel = case when c.channel = any('{chat,task}') and (select count(1)
                                                                    from call_center.cc_member_attempt aa
                                                                    where aa.agent_id = attempt.agent_id and aa.id != attempt.id and aa.state != 'leaving') > 0
                               then c.channel else null end,
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where c.agent_id = attempt.agent_id;

    end if;

    return now();
end;
$$;