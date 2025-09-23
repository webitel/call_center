
alter table if exists call_center.cc_agent 
	add column status_comment text;
--
-- Name: cc_queue; Type: TABLE; Schema: call_center; Owner: -
--

alter table if exists call_center.cc_queue
add column prolongation_enabled bool default false,
    add column prolongation_repeats_number smallint default 0,
    add column prolongation_time_sec smallint default 0,
    add column prolongation_is_timeout_retry bool default true;

--
-- Name: cc_queue_params(call_center.cc_queue); Type: FUNCTION; Schema: call_center; Owner: -
--

create or replace function call_center.cc_queue_params(q call_center.cc_queue) returns jsonb
    language sql immutable
    as $$
    select jsonb_build_object('has_reporting', q.processing)
    || jsonb_build_object('has_form', q.processing and q.form_schema_id notnull)
    || jsonb_build_object('processing_sec', q.processing_sec)
    || jsonb_build_object('processing_renewal_sec', q.processing_renewal_sec)
    || jsonb_build_object('queue_name', q.name)
    || jsonb_build_object('has_prolongation', q.prolongation_enabled)
    || jsonb_build_object('remaining_prolongations', q.prolongation_repeats_number)
    || jsonb_build_object('prolongation_sec', q.prolongation_time_sec)
    as queue_params;
$$;


--
-- Name: cc_attempt_schema_result(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb, integer, integer, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

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


    return row(attempt.last_state_change::timestamptz, stop_cause_::varchar, attempt.result::varchar);
end;
$function$
;

-- call_center.cc_agent_list source

CREATE OR REPLACE VIEW call_center.cc_agent_list
AS SELECT a.domain_id,
    a.id,
    COALESCE(ct.name, ct.username COLLATE "default")::character varying AS name,
    a.status,
    a.description,
    (date_part('epoch'::text, a.last_state_change) * 1000::double precision)::bigint AS last_status_change,
    date_part('epoch'::text, now() - a.last_state_change)::bigint AS status_duration,
    a.progressive_count,
    ch.x AS channel,
    json_build_object('id', ct.id, 'name', COALESCE(ct.name, ct.username))::jsonb AS "user",
    call_center.cc_get_lookup(a.greeting_media_id::bigint, g.name) AS greeting_media,
    a.allow_channels,
    a.chat_count,
    ( SELECT jsonb_agg(sag."user") AS jsonb_agg
           FROM call_center.cc_agent_with_user sag
          WHERE sag.id = ANY (a.supervisor_ids)) AS supervisor,
    ( SELECT jsonb_agg(call_center.cc_get_lookup(aud.id, COALESCE(aud.name, aud.username::text)::character varying)) AS jsonb_agg
           FROM directory.wbt_user aud
          WHERE aud.id = ANY (a.auditor_ids)) AS auditor,
    call_center.cc_get_lookup(t.id, t.name) AS team,
    call_center.cc_get_lookup(r.id::bigint, r.name) AS region,
    a.supervisor AS is_supervisor,
    ( SELECT jsonb_agg(call_center.cc_get_lookup(sa.skill_id::bigint, cs.name)) AS jsonb_agg
           FROM call_center.cc_skill_in_agent sa
             JOIN call_center.cc_skill cs ON sa.skill_id = cs.id
          WHERE sa.agent_id = a.id) AS skills,
    a.team_id,
    a.region_id,
    a.supervisor_ids,
    a.auditor_ids,
    a.user_id,
    ct.extension,
    a.task_count,
    a.screen_control,
    t.screen_control IS FALSE AS allow_set_screen_control
   FROM call_center.cc_agent a
     LEFT JOIN directory.wbt_user ct ON ct.id = a.user_id
     LEFT JOIN storage.media_files g ON g.id = a.greeting_media_id
     LEFT JOIN call_center.cc_team t ON t.id = a.team_id
     LEFT JOIN flow.region r ON r.id = a.region_id
     LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', (date_part('epoch'::text, c.joined_at) * 1000::double precision)::bigint)) AS x
           FROM call_center.cc_agent_channel c
          WHERE c.agent_id = a.id) ch ON true;