alter table storage.files add column malware jsonb;
alter table storage.files add column updated_by bigint;
alter table storage.files add column custom_properties jsonb;

DROP VIEW storage.files_list;
--
-- Name: files_list; Type: VIEW; Schema: storage; Owner: -
--

CREATE VIEW storage.files_list AS
SELECT f.id,
       f.name,
       f.view_name,
       f.size,
       f.mime_type,
       f.uuid,
       f.uuid AS reference_id,
       storage.get_lookup(p.id, (p.name)::character varying) AS profile,
       f.uploaded_at,
       storage.get_lookup(u.id, COALESCE((u.username)::character varying, (u.name)::character varying)) AS uploaded_by,
       f.sha256sum,
       f.channel,
       f.thumbnail,
       f.retention_until,
       f.domain_id,
       f.profile_id,
       f.created_at,
       f.properties,
       f.instance,
       f.uploaded_by AS uploaded_by_id,
       f.removed
FROM ((storage.files f
  LEFT JOIN storage.file_backend_profiles p ON ((f.id = f.profile_id)))
  LEFT JOIN directory.wbt_user u ON ((u.id = f.uploaded_by)));


--
-- Name: files_malware_found_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_malware_found_index ON storage.files USING btree (domain_id) WHERE ((malware -> 'found'::text))::boolean;


--
-- Name: cc_agent_screen_control_tg(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_agent_screen_control_tg() RETURNS trigger
  LANGUAGE plpgsql
AS $$
declare team_sc bool = false;
BEGIN

  if TG_OP = 'INSERT' OR new.screen_control IS DISTINCT FROM old.screen_control then
    select screen_control
    into team_sc
    from call_center.cc_team t
    where t.id = new.team_id;

    if TG_OP = 'INSERT' and team_sc then
      new.screen_control = team_sc;
    end if;

    if team_sc and not new.screen_control then
      RAISE EXCEPTION 'The screen_control option is enabled at the team level for this agent. This setting has priority and cannot be overridden at the agent level.'               --'Changing agent''s screen_control is not allowed.'
        USING
          DETAIL = 'The screen_control option is enabled at the team level for this agent. This setting has priority and cannot be overridden at the agent level.',
          HINT = 'To change this setting, disable the screen_control option in the team settings or move the agent to another team.',
          ERRCODE = '09000';
    end if;
  end if;

  RETURN new;
END;
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

        ready_at = case when next_offering_at_ notnull then next_offering_at_ at time zone tz.names[1]
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


alter table call_center.cc_member_attempt
  add column available_prolongation_quant smallint DEFAULT 0;

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

--
-- Name: cc_user_has_grant(bigint, bigint, text); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_user_has_grant(_domain_id bigint, _user_id bigint, _grant_permision text) RETURNS boolean
  LANGUAGE sql IMMUTABLE
AS $$
select exists (
  select
    1
  from directory.users u
  where u.dc = _domain_id
    and u.id = _user_id
    and _grant_permision = any(string_to_array(u.grants, ','))
  limit 1
)
$$;



DROP VIEW call_center.cc_agent_list;
--
-- Name: cc_agent_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_agent_list AS
SELECT a.domain_id,
       a.id,
       (COALESCE(ct.name, ((ct.username)::text COLLATE "default")))::character varying AS name,
       a.status,
       a.description,
       ((date_part('epoch'::text, a.last_state_change) * (1000)::double precision))::bigint AS last_status_change,
       (date_part('epoch'::text, (now() - a.last_state_change)))::bigint AS status_duration,
       a.progressive_count,
       ch.x AS channel,
       (json_build_object('id', ct.id, 'name', COALESCE(ct.name, (ct.username)::text)))::jsonb AS "user",
       call_center.cc_get_lookup((a.greeting_media_id)::bigint, g.name) AS greeting_media,
       a.allow_channels,
       a.chat_count,
       ( SELECT jsonb_agg(sag."user") AS jsonb_agg
         FROM call_center.cc_agent_with_user sag
         WHERE (sag.id = ANY (a.supervisor_ids))) AS supervisor,
       ( SELECT jsonb_agg(call_center.cc_get_lookup(aud.id, (COALESCE(aud.name, (aud.username)::text))::character varying)) AS jsonb_agg
         FROM directory.wbt_user aud
         WHERE (aud.id = ANY (a.auditor_ids))) AS auditor,
       call_center.cc_get_lookup(t.id, t.name) AS team,
       call_center.cc_get_lookup((r.id)::bigint, r.name) AS region,
       a.supervisor AS is_supervisor,
       ( SELECT jsonb_agg(call_center.cc_get_lookup((sa.skill_id)::bigint, cs.name)) AS jsonb_agg
         FROM (call_center.cc_skill_in_agent sa
           JOIN call_center.cc_skill cs ON ((sa.skill_id = cs.id)))
         WHERE (sa.agent_id = a.id)) AS skills,
       a.team_id,
       a.region_id,
       a.supervisor_ids,
       a.auditor_ids,
       a.user_id,
       ct.extension,
       a.task_count,
       a.screen_control,
       (t.screen_control IS FALSE) AS allow_set_screen_control,
       row_number() OVER (PARTITION BY a.domain_id ORDER BY
         CASE
           WHEN ((a.status)::text = 'online'::text) THEN 0
           WHEN ((a.status)::text = 'pause'::text) THEN 1
           WHEN ((a.status)::text = 'offline'::text) THEN 2
           ELSE 3
           END, COALESCE(ct.name, (ct.username)::text)) AS "position",
       COALESCE(( SELECT array_agg(status.open) AS array_agg
                  FROM ( SELECT 'dnd'::name AS "?column?"
                         FROM directory.wbt_user_status stt
                         WHERE ((stt.user_id = a.user_id) AND stt.dnd)
                         UNION ALL
                         ( SELECT stt.status
                           FROM directory.wbt_user_presence stt
                           WHERE ((stt.user_id = a.user_id) AND (stt.status IS NOT NULL) AND (stt.open > 0))
                           ORDER BY stt.prior, stt.status)) status(open)), '{}'::name[]) AS user_presence_status
FROM (((((call_center.cc_agent a
  LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
  LEFT JOIN storage.media_files g ON ((g.id = a.greeting_media_id)))
  LEFT JOIN call_center.cc_team t ON ((t.id = a.team_id)))
  LEFT JOIN flow.region r ON ((r.id = a.region_id)))
  LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint)) AS x
                      FROM call_center.cc_agent_channel c
                      WHERE (c.agent_id = a.id)) ch ON (true));



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
                                              WHEN ((f_1.channel)::text = 'call'::text) THEN ((c.params -> 'record_start'::text))::bigint
                                              ELSE ((f_1.custom_properties ->> 'start_time'::text))::bigint
                                              END, 'stop_at',
                                            CASE
                                              WHEN ((f_1.channel)::text = 'call'::text) THEN ((c.params -> 'record_stop'::text))::bigint
                                              ELSE ((f_1.custom_properties ->> 'end_time'::text))::bigint
                                              END, 'start_record', f_1.sr, 'channel', f_1.channel)) AS files
         FROM ( SELECT f1.id,
                       f1.size,
                       f1.mime_type,
                       COALESCE(f1.view_name, f1.name) AS name,
                       f1.channel,
                       f1.custom_properties,
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
                       NULL::text AS sr
                FROM storage.files f1
                WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND (c.parent_id IS NOT NULL) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) AS files,
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
         LIMIT 20) AS forms
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
       COALESCE(rg.resource_groups, '{}'::character varying[]) AS resource_groups,
       COALESCE(rg.resources, '{}'::character varying[]) AS resources
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
  LEFT JOIN LATERAL ( SELECT array_agg(DISTINCT corg.name) FILTER (WHERE (corg.name IS NOT NULL)) AS resource_groups,
                             array_agg(DISTINCT cor.name) FILTER (WHERE (cor.name IS NOT NULL)) AS resources
                      FROM (((call_center.cc_queue_resource cqr
                        JOIN call_center.cc_outbound_resource_group corg ON ((corg.id = cqr.resource_group_id)))
                        LEFT JOIN call_center.cc_outbound_resource_in_group corg_res ON ((corg_res.group_id = corg.id)))
                        LEFT JOIN call_center.cc_outbound_resource cor ON ((cor.id = corg_res.resource_id)))
                      WHERE (cqr.queue_id = q.id)) rg ON (true));


DROP VIEW call_center.cc_quick_reply_list;
--
-- Name: cc_quick_reply_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_quick_reply_list AS
SELECT a.domain_id,
       a.id,
       a.text,
       ( SELECT jsonb_agg(call_center.cc_get_lookup((q.id)::bigint, q.name)) AS jsonb_agg
         FROM call_center.cc_queue q
         WHERE (q.id = ANY (a.queues))) AS queues,
       a.queues AS queue_ids,
       a.teams AS team_ids,
       ( SELECT jsonb_agg(call_center.cc_get_lookup(t.id, t.name)) AS jsonb_agg
         FROM call_center.cc_team t
         WHERE (t.id = ANY (a.teams))) AS teams,
       a.name,
       a.created_at,
       call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
       a.updated_at,
       call_center.cc_get_lookup(uu.id, (COALESCE(uu.name, (uu.username)::text))::character varying) AS updated_by,
       row_number() OVER (PARTITION BY a.domain_id ORDER BY
         CASE
           WHEN (COALESCE(array_length(a.queues, 1), 0) > 0) THEN 1
           WHEN (COALESCE(array_length(a.teams, 1), 0) > 0) THEN 2
           ELSE 3
           END) AS sort_priority
FROM ((call_center.cc_quick_reply a
  LEFT JOIN directory.wbt_user uc ON ((uc.id = a.created_by)))
  LEFT JOIN directory.wbt_user uu ON ((uu.id = a.updated_by)));


drop function if exists call_center.cc_get_agent_queues;
--
-- Name: cc_get_agent_queues(integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_get_agent_queues(_domain_id integer, _user_id integer) RETURNS integer[]
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


--
-- Name: idx_cc_agent_domain_user; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX idx_cc_agent_domain_user ON call_center.cc_agent USING btree (domain_id, user_id) INCLUDE (team_id, id);


--
-- Name: idx_cc_skill_in_agent_enabled; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX idx_cc_skill_in_agent_enabled ON call_center.cc_skill_in_agent USING btree (agent_id, enabled);

