
CREATE OR REPLACE FUNCTION call_center.cc_trigger_ins_upd() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    if NEW.type <> 'cron' then
        return NEW;
    end if;

    if call_center.cc_cron_valid(NEW.expression) is not true then
        raise exception 'invalid expression %', NEW.expression using errcode ='20808';
    end if;

    if old.enabled != new.enabled or old.expression != new.expression or old.timezone_id != new.timezone_id then
        select
            call_center.cc_cron_next_after_now(new.expression, (now() at time zone tz.sys_name)::timestamp, (now() at time zone tz.sys_name)::timestamp)
        into new.schedule_at
        from flow.calendar_timezones tz
        where tz.id = NEW.timezone_id;
    end if;

    RETURN NEW;
END;
$$;


--
-- Name: cc_scheduler_jobs(); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE OR REPLACE PROCEDURE call_center.cc_scheduler_jobs()
    LANGUAGE plpgsql
AS $$
begin

    if NOT pg_try_advisory_xact_lock(132132118) then
        raise exception 'LOCKED cc_scheduler_jobs';
    end if;

    with del as (
        delete from call_center.cc_trigger_job
            where stopped_at notnull
            returning id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
    )
    insert into call_center.cc_trigger_job_log (id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id)
    select id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
    from del
    ;

    with u as (
        update call_center.cc_trigger t2
            set schedule_at = (t.new_schedule_at)::timestamp
            from (select t.id,
                         jsonb_build_object('variables', t.variables,
                                            'schema_id', t.schema_id,
                                            'timeout', t.timeout_sec
                             ) as                                      params,
                         call_center.cc_cron_next_after_now(t.expression, (t.schedule_at)::timestamp, (now() at time zone tz.sys_name)::timestamp) new_schedule_at,
                         t.domain_id,
                         (t.schedule_at)::timestamp as old_schedule_at,
                         (now() at time zone tz.sys_name)::timestamp - (t.schedule_at)::timestamp < interval '5m' valid
                  from call_center.cc_trigger t
                           inner join flow.calendar_timezones tz on tz.id = t.timezone_id
                  where t.enabled
                    and t.type = 'cron'
                    and (t.schedule_at)::timestamp <= (now() at time zone tz.sys_name)::timestamp
                    and not exists(select 1 from call_center.cc_trigger_job tj where tj.trigger_id = t.id and tj.state = 0)
                      for update of t skip locked) t
            where t2.id = t.id
            returning t.*
    )
    insert
    into call_center.cc_trigger_job(trigger_id, parameters, domain_id)
    select id, params, domain_id
    from u
    where u.valid;
end;
$$;


CREATE or replace FUNCTION call_center.cc_trigger_ins_upd() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    if NEW.type <> 'cron' then
        return NEW;
    end if;

    if call_center.cc_cron_valid(NEW.expression) is not true then
        raise exception 'invalid expression %', NEW.expression using errcode ='20808';
    end if;

    if old.enabled != new.enabled or old.expression != new.expression or old.timezone_id != new.timezone_id then
        select
            call_center.cc_cron_next_after_now(new.expression, (now() at time zone tz.sys_name)::timestamp, (now() at time zone tz.sys_name)::timestamp)
        into new.schedule_at
        from flow.calendar_timezones tz
        where tz.id = NEW.timezone_id;
    end if;

    RETURN NEW;
END;
$$;

--
-- Name: files_domain_id_channel_mime_type_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX if not exists files_domain_id_channel_mime_type_index ON storage.files USING gin (domain_id, channel, mime_type gin_trgm_ops);


drop index if exists storage.file_transcript_uuid_index;
--
-- Name: file_transcript_uuid_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_transcript_uuid_index ON storage.file_transcript USING btree (uuid);


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
       p.description,
       p.channels,
       p.mime_types,
       p.speed_download,
       p.speed_upload,
       p.max_upload_size,
       p.retention_days,
       row_number() OVER (PARTITION BY p.domain_id ORDER BY p."position" DESC) AS "position"
FROM ((storage.file_policies p
    LEFT JOIN directory.wbt_user c ON ((c.id = p.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = p.updated_by)));

ALTER TABLE ONLY flow.scheme_version REPLICA IDENTITY FULL;


drop FUNCTION call_center.cc_attempt_end_reporting;
--
-- Name: cc_attempt_end_reporting(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb, integer, integer, boolean, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, per_number_ boolean DEFAULT false, only_current_communication_ boolean DEFAULT false) RETURNS record
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
                                only_current_communication_ or
                                (not attempt.result in ('success', 'cancel') and
                                 case when per_number_ is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                    )
                               then m.stop_at else  attempt.leaving_at end,
            stop_cause = case when next_offering_at_ notnull or
                                   m.stop_at notnull or
                                   only_current_communication_ or
                                   (not attempt.result in ('success', 'cancel') and
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
-- Name: cc_attempt_transferred_from(bigint, bigint, integer, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_attempt_transferred_from(attempt_id_ bigint, to_attempt_id_ bigint, to_agent_id_ integer, agent_sess_id_ character varying) RETURNS record
    LANGUAGE plpgsql
AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
    user_id_ int8 = null;
    domain_id_ int8;
    wrap_time_ int;
    agent_timeout_ timestamptz;
begin

    update call_center.cc_member_attempt
    set transferred_agent_id = agent_id,
        agent_id = to_agent_id_,
        agent_call_id = agent_sess_id_
    where id = attempt_id_
    returning * into attempt;

    insert into call_center.cc_member_attempt_transferred (from_id, to_id, from_agent_id, to_agent_id)
    values (to_attempt_id_, attempt_id_, attempt.transferred_agent_id, attempt.agent_id);

    if attempt.transferred_agent_id notnull then
        select a.user_id, a.domain_id, case when a.on_demand then null else coalesce(tm.wrap_up_time, 0) end
        into user_id_, domain_id_, wrap_time_
        from call_center.cc_agent a
                 left join call_center.cc_team tm on tm.id = attempt.team_id
        where a.id = attempt.transferred_agent_id;

        if wrap_time_ > 0 or wrap_time_ isnull then
            update call_center.cc_agent_channel c
            set state = 'wrap_time',
                joined_at = now(),
                timeout = case when wrap_time_ > 0 then now() + (wrap_time_ || ' sec')::interval end,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.transferred_agent_id, attempt.channel)
            returning timeout into agent_timeout_;
        else
            update call_center.cc_agent_channel c
            set state = 'waiting',
                joined_at = now(),
                timeout = null,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id),
                queue_id = null
            where (c.agent_id, c.channel) = (attempt.transferred_agent_id, attempt.channel)
            returning timeout into agent_timeout_;
        end if;
    end if;


    return row(attempt.last_state_change::timestamptz);
end;
$$;

alter table call_center.cc_calls add column if not exists did text;



--
-- Name: cc_call_set_bridged(uuid, character varying, timestamp with time zone, character varying, bigint, uuid); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE or replace PROCEDURE call_center.cc_call_set_bridged(IN call_id_ uuid, IN state_ character varying, IN timestamp_ timestamp with time zone, IN app_id_ character varying, IN domain_id_ bigint, IN call_bridged_id_ uuid)
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
                         else to_id end
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
-- Name: cc_calls_set_timing(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE  or replace FUNCTION call_center.cc_calls_set_timing() RETURNS trigger
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

    RETURN new;
END
$$;


alter table call_center.cc_audit_rate alter column rated_user_id drop not null ;



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
       (EXISTS ( SELECT 1
                 FROM call_center.cc_calls_history lega
                 WHERE ((lega.id = c.parent_id) AND (lega.bridged_id IS NOT NULL)))) AS parent_bridged,
       ( SELECT jsonb_agg(call_center.cc_get_lookup(ash.id, ash.name)) AS jsonb_agg
         FROM flow.acr_routing_scheme ash
         WHERE (ash.id = ANY (c.schema_ids))) AS schemas,
       c.schema_ids,
       c.hangup_phrase,
       c.blind_transfers
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


drop MATERIALIZED VIEW call_center.cc_distribute_stats;
--
-- Name: cc_distribute_stats; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_distribute_stats AS
SELECT s.queue_id,
       s.bucket_id,
       s.start_stat,
       s.stop_stat,
       s.call_attempts,
       s.avg_handle,
       s.med_handle,
       s.avg_member_answer,
       s.avg_member_answer_not_bridged,
       s.avg_member_answer_bridged,
       s.max_member_answer,
       s.connected_calls,
       s.bridged_calls,
       s.abandoned_calls,
       s.connection_rate,
       (call_center.cc_wrap_over_dial((s.over_dial)::numeric, (s.abandoned_rate)::numeric, COALESCE(((q.payload -> 'target_abandoned_rate'::text))::numeric, COALESCE(((q.payload -> 'max_abandoned_rate'::text))::numeric, 3.0)), COALESCE(((q.payload -> 'max_abandoned_rate'::text))::numeric, 3.0), COALESCE(((q.payload -> 'load_factor'::text))::numeric, 10.0)))::double precision AS over_dial,
       GREATEST(s.abandoned_rate, (0)::double precision) AS abandoned_rate,
       s.hit_rate,
       s.agents,
       s.aggent_ids
FROM (((call_center.cc_queue q
    LEFT JOIN LATERAL ( SELECT
                            CASE
                                WHEN ((jsonb_typeof(s_1.value) = 'boolean'::text) AND (s_1.value)::boolean) THEN true
                                ELSE false
                                END AS amd_cancel_not_human
                        FROM call_center.system_settings s_1
                        WHERE ((s_1.domain_id = q.domain_id) AND ((s_1.name)::text = 'amd_cancel_not_human'::text))) sys ON (true))
    LEFT JOIN LATERAL ( SELECT
                            CASE
                                WHEN sys.amd_cancel_not_human THEN tmp.v
                                ELSE (tmp.v || 'CANCEL'::text)
                                END AS arr
                        FROM ( SELECT
                                   CASE
                                       WHEN ((((q.payload -> 'amd'::text) -> 'allow_not_sure'::text))::boolean IS TRUE) THEN ARRAY['HUMAN'::text, 'NOTSURE'::text]
                                       ELSE ARRAY['HUMAN'::text]
                                       END AS v) tmp) amd ON (true))
    JOIN LATERAL ( SELECT att.queue_id,
                          att.bucket_id,
                          min(att.joined_at) AS start_stat,
                          max(att.joined_at) AS stop_stat,
                          count(*) AS call_attempts,
                          COALESCE(avg(date_part('epoch'::text, (COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))) FILTER (WHERE (att.bridged_at IS NOT NULL)), (0)::double precision) AS avg_handle,
                          COALESCE(avg(DISTINCT (round(date_part('epoch'::text, (COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))))::real) FILTER (WHERE (att.bridged_at IS NOT NULL)), (0)::double precision) AS med_handle,
                          COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE (ch.answered_at IS NOT NULL)), (0)::double precision) AS avg_member_answer,
                          COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (ch.bridged_at IS NULL))), (0)::double precision) AS avg_member_answer_not_bridged,
                          COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (ch.bridged_at IS NOT NULL))), (0)::double precision) AS avg_member_answer_bridged,
                          COALESCE(max(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE (ch.answered_at IS NOT NULL)), (0)::double precision) AS max_member_answer,
                          count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)) AS connected_calls,
                          count(*) FILTER (WHERE (att.bridged_at IS NOT NULL)) AS bridged_calls,
                          count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (att.bridged_at IS NULL) AND amd_res.human)) AS abandoned_calls,
                          ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) AS connection_rate,
                          CASE
                              WHEN (((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) > (0)::double precision) THEN ((1)::double precision / ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision))
                              ELSE (((count(*) / GREATEST(count(DISTINCT att.agent_id), (1)::bigint)) - 1))::double precision
                              END AS over_dial,
                          COALESCE(((((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (att.bridged_at IS NULL) AND amd_res.human)))::double precision - (COALESCE(((q.payload -> 'abandon_rate_adjustment'::text))::integer, 0))::double precision) / (NULLIF(count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)), 0))::double precision) * (100)::double precision), (0)::double precision) AS abandoned_rate,
                          ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) AS hit_rate,
                          count(DISTINCT att.agent_id) AS agents,
                          array_agg(DISTINCT att.agent_id) FILTER (WHERE (att.agent_id IS NOT NULL)) AS aggent_ids
                   FROM ((call_center.cc_member_attempt_history att
                       LEFT JOIN call_center.cc_calls_history ch ON (((ch.domain_id = att.domain_id) AND (ch.id = (att.member_call_id)::uuid) AND (ch.created_at > ((now())::date - '1 day'::interval)))))
                       LEFT JOIN LATERAL ( SELECT (((ch.amd_result IS NULL) AND (ch.amd_ai_positive IS NULL)) OR ((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_ai_positive IS TRUE)) AS human) amd_res ON (true))
                   WHERE (((att.channel)::text = 'call'::text) AND (att.joined_at > (now() - ((COALESCE(((q.payload -> 'statistic_time'::text))::integer, 60) || ' min'::text))::interval)) AND (att.queue_id = q.id) AND (att.domain_id = q.domain_id))
                   GROUP BY att.queue_id, att.bucket_id) s ON ((s.queue_id IS NOT NULL)))
WHERE ((q.type = 5) AND q.enabled)
WITH NO DATA;


--
-- Name: cc_distribute_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_distribute_stats_uidx ON call_center.cc_distribute_stats USING btree (queue_id, bucket_id);

refresh materialized view call_center.cc_distribute_stats;

--
-- Name: cc_member_reset_by_queue; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX if not exists cc_member_reset_by_queue ON call_center.cc_member USING btree (domain_id, queue_id) INCLUDE (id) WHERE ((stop_at IS NOT NULL) AND ((stop_cause)::text <> ALL ('{success,expired,cancel,terminate,no_communications}'::text[])));


drop VIEW call_center.cc_distribute_stage_1;

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
        JOIN LATERAL unnest(c.accepts) a(disabled, day, start_time_of_day, end_time_of_day, special) ON (true))
        JOIN flow.calendar_timezone_offsets o1 ON ((((a.day + 1) = (date_part('isodow'::text, timezone(o1.names[1], now())))::integer) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) >= a.start_time_of_day) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) <= a.end_time_of_day))))
    WHERE ((NOT (a.disabled IS TRUE)) AND (NOT (EXISTS ( SELECT 1
                                                         FROM unnest(c.excepts) x(disabled, date, name, repeat, work_start, work_stop, working)
                                                         WHERE ((NOT (x.disabled IS TRUE)) AND
                                                                CASE
                                                                    WHEN (x.repeat IS TRUE) THEN (to_char((((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name))::date)::timestamp with time zone, 'MM-DD'::text) = to_char((((to_timestamp(((x.date / 1000))::double precision) AT TIME ZONE tz.sys_name))::date)::timestamp with time zone, 'MM-DD'::text))
                                                                    ELSE (((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name))::date = ((to_timestamp(((x.date / 1000))::double precision) AT TIME ZONE tz.sys_name))::date)
                                                                    END AND (NOT (x.working AND (((to_char((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name), 'SSSS'::text))::integer / 60) >= x.work_start) AND (((to_char((CURRENT_TIMESTAMP AT TIME ZONE tz.sys_name), 'SSSS'::text))::integer / 60) <= x.work_stop))))))))
    GROUP BY c.id, queues.id, queues.recall_calendar, tz.offset_id
), resources AS MATERIALIZED (
    SELECT l_1.queue_id,
           array_agg(ROW(cor.communication_id, (cor.id)::bigint, ((l_1.l & (l2.x)::integer[]))::smallint[], (cor.resource_group_id)::integer)::call_center.cc_sys_distribute_type ORDER BY (random())) AS types,
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