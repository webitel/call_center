--new tables

create table storage.file_jobs
(
    id         bigserial
        primary key,
    file_id    bigint                                 not null,
    state      smallint                 default 0     not null,
    created_at timestamp with time zone default now() not null,
    updated_at timestamp with time zone default now() not null,
    action     varchar(15)                            not null,
    log        jsonb,
    config     jsonb
);

create unique index file_jobs_file_id_uindex
    on storage.file_jobs (file_id);

create table storage.cognitive_profile_services
(
    id          serial
        constraint stt_profiles_pk
            primary key,
    domain_id   bigint                                                                            not null,
    provider    varchar(15)                                                                       not null,
    properties  jsonb                                                                             not null,
    created_at  timestamp with time zone default now()                                            not null,
    updated_at  timestamp with time zone default now()                                            not null,
    created_by  bigint,
    updated_by  bigint,
    enabled     boolean                  default true                                             not null,
    name        varchar(50)                                                                       not null,
    description varchar                  default ''::character varying,
    service     varchar(10)                                                                       not null,
    "default"   boolean                  default false                                            not null
);

alter table storage.cognitive_profile_services
    owner to opensips;

create unique index cognitive_profile_services_domain_udx
    on storage.cognitive_profile_services (id asc, domain_id desc);


create table storage.cognitive_profile_services_acl
(
    id      bigserial
        constraint cognitive_profile_services_acl_pk
            primary key,
    dc      bigint             not null
        constraint file_cognitive_profile_services_acl_domain_fk
            references directory.wbt_domain
            on delete cascade,
    grantor bigint
        constraint file_cognitive_profile_services_acl_grantor_id_fk
            references directory.wbt_auth
            on delete set null,
    subject bigint             not null,
    access  smallint default 0 not null,
    object  bigint             not null,
    constraint file_cognitive_profile_services_acl_subject_fk
        foreign key (subject, dc) references directory.wbt_auth (id, dc)
            on delete cascade,
    constraint file_cognitive_profile_services_acl_grantor_fk
        foreign key (grantor, dc) references directory.wbt_auth (id, dc)
            deferrable initially deferred,
    constraint file_cognitive_profile_services_acl_object_fk
        foreign key (object, dc) references storage.cognitive_profile_services (id, domain_id)
            on delete cascade
            deferrable initially deferred
);



create table storage.file_transcript
(
    id         bigserial
        constraint file_transcript_pk
            primary key,
    file_id    bigint                                                     not null
        constraint file_transcript_files_id_fk
            references storage.files
            on update cascade on delete cascade,
    transcript text                                                       not null,
    log        jsonb,
    created_at timestamp with time zone default now()                     not null,
    profile_id integer                                                    not null
        constraint file_transcript_cognitive_profile_services_id_fk
            references storage.cognitive_profile_services
            on update set null on delete set null,
    locale     varchar                  default 'none'::character varying not null,
    phrases    jsonb,
    channels   jsonb
);


--4b127db7
drop view storage.media_files_view;

alter table storage.media_files
alter column mime_type type varchar(120) using mime_type::varchar(120);

create view storage.media_files_view
            (id, name, created_at, created_by, updated_at, updated_by, mime_type, size, properties, domain_id) as
SELECT f.id,
       f.name,
       f.created_at,
       storage.get_lookup(c.id, c.name::character varying) AS created_by,
       f.updated_at,
       storage.get_lookup(u.id, u.name::character varying) AS updated_by,
       f.mime_type,
       f.size,
       f.properties,
       f.domain_id
FROM storage.media_files f
         LEFT JOIN directory.wbt_user c ON f.created_by = c.id
         LEFT JOIN directory.wbt_user u ON f.updated_by = u.id;



--52f71b33
--
-- Name: cc_outbound_resource_display_changed(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_outbound_resource_display_changed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
update call_center.cc_outbound_resource r
set updated_at = (extract(epoch from now()) * 1000)::int8
where r.id = coalesce(NEW.resource_id, OLD.resource_id);

RETURN NEW;
END;
$$;

alter table call_center.cc_queue add column if not exists form_schema_id integer;


--
-- Name: cc_outbound_resource_display cc_outbound_resource_display_changed_iud; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE  TRIGGER cc_outbound_resource_display_changed_iud AFTER INSERT OR DELETE OR UPDATE ON call_center.cc_outbound_resource_display FOR EACH ROW EXECUTE FUNCTION call_center.cc_outbound_resource_display_changed();


--
-- Name: cc_queue cc_queue_acr_routing_scheme_id_fk_4; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE  ONLY call_center.cc_queue
    ADD CONSTRAINT  cc_queue_acr_routing_scheme_id_fk_4 FOREIGN KEY (form_schema_id) REFERENCES flow.acr_routing_scheme(id);




--d746048d WTEL-2594
ALTER TABLE flow.acr_routing_scheme
drop  CONSTRAINT if exists  acr_routing_scheme_wbt_domain_dc_fk;
ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT  acr_routing_scheme_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: acr_routing_scheme acr_routing_scheme_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--
ALTER TABLE ONLY flow.acr_routing_scheme
drop CONSTRAINT if exists acr_routing_scheme_wbt_user_id_fk;
ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON UPDATE SET NULL ON DELETE SET NULL;

ALTER TABLE ONLY flow.acr_routing_scheme
drop CONSTRAINT if exists acr_routing_scheme_wbt_user_id_fk_2;
ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON UPDATE SET NULL ON DELETE SET NULL;



--41da6ba5


drop PROCEDURE call_center.cc_attempt_distribute_cancel;
CREATE PROCEDURE call_center.cc_attempt_distribute_cancel(IN attempt_id_ bigint, IN description_ character varying, IN next_distribute_sec_ integer, IN stop_ boolean, IN vars_ jsonb)
    LANGUAGE plpgsql
    AS $$
declare
attempt  call_center.cc_member_attempt%rowtype;
begin
update call_center.cc_member_attempt
set leaving_at = now(),
    description = description_,
    last_state_change = now(),
    result = 'cancel', --TODO
    state = 'leaving'
where id = attempt_id_
    returning * into attempt;

update call_center.cc_member
set last_hangup_at  = (extract(EPOCH from now() ) * 1000)::int8,
        last_agent      = coalesce(attempt.agent_id, last_agent),
        variables = case when vars_ notnull  then coalesce(variables, '{}'::jsonb) || vars_ else variables end,
        ready_at = case when next_distribute_sec_ > 0 then now() + (next_distribute_sec_::text || ' sec')::interval else now() end,
        stop_at = case when stop_ is true and stop_at isnull then attempt.leaving_at else stop_at end,
        stop_cause = case when stop_ is true and stop_cause isnull then attempt.result else stop_cause end
    where id = attempt.member_id;

end;
$$;



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
    stop_cause_ varchar;
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
    description = description_
where id = attempt_id_ and state != 'leaving'
    returning * into attempt;

if attempt.id isnull then
        return null;
--         raise exception  'not found %', attempt_id_;
end if;

    if attempt.member_id notnull then
update call_center.cc_member
set last_hangup_at  = time_,
    variables = case when variables_ notnull then coalesce(variables::jsonb, '{}') || variables_ else variables end,
    expire_at = case when expire_at_ isnull then expire_at else expire_at_ end,
    agent_id = case when sticky_agent_id_ isnull then agent_id else sticky_agent_id_ end,

    stop_at = case when next_offering_at_ notnull or
              stop_at notnull or
                                (not attempt.result in ('success', 'cancel') and
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (attempts + 1 < max_attempts_)) end
                                 )
                then stop_at else  attempt.leaving_at end,
            stop_cause = case when next_offering_at_ notnull or
                                stop_at notnull or
                                (not attempt.result in ('success', 'cancel') and
                                   case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (attempts + 1 < max_attempts_)) end
                                 )
                then stop_cause else  attempt.result end,

            ready_at = case when next_offering_at_ notnull then next_offering_at_
                else now() + (wait_between_retries_ || ' sec')::interval end,

            last_agent      = coalesce(attempt.agent_id, last_agent),
            communications =  jsonb_set(communications, (array[attempt.communication_idx::int])::text[], communications->(attempt.communication_idx::int) ||
                jsonb_build_object('last_activity_at', case when next_offering_at_ notnull then '0'::text::jsonb else time_::text::jsonb end) ||
                jsonb_build_object('attempt_id', attempt_id_) ||
                jsonb_build_object('attempts', coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                case when exclude_dest or
                          (_per_number is true and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= max_attempts_) then jsonb_build_object('stop_at', time_) else '{}'::jsonb end
            ),
            attempts        = attempts + 1                     --TODO
        where id = attempt.member_id
        returning stop_cause into stop_cause_;
end if;

    if attempt.agent_id notnull then
select a.user_id, a.domain_id, case when a.on_demand then null else coalesce(tm.wrap_up_time, 0) end
into user_id_, domain_id_, wrap_time_
from call_center.cc_agent a
         left join call_center.cc_team tm on tm.id = attempt.team_id
where a.id = attempt.agent_id;

if wrap_time_ > 0 or wrap_time_ isnull then
update call_center.cc_agent_channel c
set state = 'wrap_time',
    joined_at = now(),
    timeout = case when wrap_time_ > 0 then now() + (wrap_time_ || ' sec')::interval end,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
    returning timeout into agent_timeout_;
else
update call_center.cc_agent_channel c
set state = 'waiting',
    joined_at = now(),
    timeout = null,
    channel = null,
    last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id),
    queue_id = null
where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
    returning timeout into agent_timeout_;
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
           stop_cause_
    );
end;
$$;

drop PROCEDURE call_center.cc_call_set_bridged;
CREATE PROCEDURE call_center.cc_call_set_bridged(IN call_id_ character varying, IN state_ character varying, IN timestamp_ timestamp with time zone, IN app_id_ character varying, IN domain_id_ bigint, IN call_bridged_id_ character varying)
    LANGUAGE plpgsql
    AS $$
declare
transfer_to_ varchar;
        transfer_from_ varchar;
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
                      left join call_center.cc_calls b2 on b2.id = call_id_
                      left join lateral call_center.cc_call_get_owner_leg(b2) b2o on true
             where b.id = call_bridged_id_
         ) c
where c.id = cc.id
    returning c.transfer_to into transfer_to_;


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
             where b.id = call_id_
         ) c
    where c.id = cc.id
    returning cc.transfer_from into transfer_from_;

update call_center.cc_calls set
                                transfer_from =  case when id = transfer_from_ then transfer_to_ end,
                                transfer_to =  case when id = transfer_to_ then transfer_from_ end
where id in (transfer_from_, transfer_to_);

end;
$$;



alter TABLE call_center.cc_member_attempt add column form_fields jsonb;
alter TABLE call_center.cc_member_attempt add column form_view jsonb;
alter TABLE call_center.cc_member_attempt_history add column  form_fields jsonb;


drop VIEW call_center.cc_queue_list;
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
    COALESCE(ss.member_waiting, (0)::bigint) AS waiting,
    COALESCE(act.cnt, (0)::bigint) AS active,
    q.sticky_agent,
    q.processing,
    q.processing_sec,
    q.processing_renewal_sec
   FROM ((((((((((((call_center.cc_queue q
     JOIN flow.calendar c ON ((q.calendar_id = c.id)))
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
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL) AND ((a.state)::text <> 'leaving'::text))) act ON (true));

drop INDEX if exists call_center.cc_agent_state_history_dev_g;
CREATE INDEX cc_agent_state_history_dev_g ON call_center.cc_agent_state_history USING btree (joined_at DESC, agent_id) INCLUDE (state) WHERE ((channel IS NULL) AND ((state)::text = ANY (ARRAY[('pause'::character varying)::text, ('online'::character varying)::text, ('offline'::character varying)::text])));




drop VIEW call_center.cc_agent_in_queue_view;
CREATE OR REPLACE VIEW call_center.cc_agent_in_queue_view AS
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
       jsonb_build_object('online', COALESCE(array_length(a.agent_on_ids, 1), 0), 'pause', COALESCE(array_length(a.agent_p_ids, 1), 0), 'offline', COALESCE(array_length(a.agent_off_ids, 1), 0), 'free', COALESCE(array_length(a.free, 1), 0), 'total', COALESCE(array_length(a.total, 1), 0)) AS agents
FROM (( SELECT call_center.cc_get_lookup((q_1.id)::bigint, q_1.name) AS queue,
               q_1.priority,
               q_1.type,
               q_1.strategy,
               q_1.enabled,
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
    a_1.id AS agent_id
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
                                     array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND (ac.channel IS NULL) AND ((ac.state)::text = 'waiting'::text))) AS free,
                                     array_agg(DISTINCT a_1.id) AS total
                             FROM (((call_center.cc_agent a_1
                                 JOIN call_center.cc_agent_channel ac ON ((ac.agent_id = a_1.id)))
                                 JOIN call_center.cc_queue_skill qs ON (((qs.queue_id = q.queue_id) AND qs.enabled)))
                                 JOIN call_center.cc_skill_in_agent sia ON (((sia.agent_id = a_1.id) AND sia.enabled)))
                             WHERE ((a_1.domain_id = q.domain_id) AND ((q.team_id IS NULL) OR (a_1.team_id = q.team_id)) AND (qs.skill_id = sia.skill_id) AND (sia.capacity >= qs.min_capacity) AND (sia.capacity <= qs.max_capacity))
                             GROUP BY ROLLUP(q.queue_id)) a ON (true));


drop VIEW call_center.cc_distribute_stage_1;
CREATE VIEW call_center.cc_distribute_stage_1 AS
WITH queues AS MATERIALIZED (
SELECT q_1.domain_id,
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
            array_agg(ROW((m.bucket_id)::integer, (m.member_waiting)::integer, m.op)::call_center.cc_sys_distribute_bucket ORDER BY cbiq.priority DESC NULLS LAST, cbiq.ratio DESC NULLS LAST, m.bucket_id) AS buckets,
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
          WHERE ((m.member_waiting > 0) AND q_1.enabled AND (q_1.type > 0) AND (m.pos = 1) AND ((cbiq.bucket_id IS NULL) OR (NOT cbiq.disabled)))
          GROUP BY q_1.domain_id, q_1.id, q_1.calendar_id, q_1.type, m.op
         LIMIT 1024
        ), calend AS MATERIALIZED (
         SELECT c.id AS calendar_id,
            queues.id AS queue_id,
                CASE
                    WHEN (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) THEN ((array_agg(DISTINCT o1.id))::integer[] + (tz.offset_id)::integer)
                    ELSE (array_agg(DISTINCT o1.id))::integer[]
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
    q.strict_circuit
   FROM (((queues q
     LEFT JOIN calend ON ((calend.queue_id = q.id)))
     LEFT JOIN resources r ON ((q.op AND (r.queue_id = q.id))))
     LEFT JOIN LATERAL ( SELECT count(*) AS usage
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND ((a.state)::text <> 'leaving'::text))) l ON ((q.lim > 0)))
  WHERE ((q.type = ANY (ARRAY[1, 6, 7, 8])) OR ((q.type = 5) AND (NOT q.op)) OR (q.op AND (q.type = ANY (ARRAY[2, 3, 4, 5])) AND (r.* IS NOT NULL)));




--
-- Name: cc_queue_report_general _RETURN; Type: RULE; Schema: call_center; Owner: -
--
drop VIEW call_center.cc_queue_report_general;
CREATE VIEW call_center.cc_queue_report_general AS
SELECT call_center.cc_get_lookup((q.id)::bigint, q.name) AS queue,
       call_center.cc_get_lookup(ct.id, ct.name) AS team,
       ( SELECT sum(s.member_waiting) AS sum
    FROM call_center.cc_queue_statistics s
    WHERE (s.queue_id = q.id)) AS waiting,
    ( SELECT count(*) AS count
    FROM call_center.cc_member_attempt a
    WHERE (a.queue_id = q.id)) AS processed,
    count(*) AS cnt,
    count(*) FILTER (WHERE (t.offering_at IS NOT NULL)) AS calls,
    count(*) FILTER (WHERE ((t.result)::text = 'abandoned'::text)) AS abandoned,
    date_part('epoch'::text, sum((t.leaving_at - t.bridged_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS bill_sec,
    date_part('epoch'::text, avg((t.leaving_at - t.reporting_at)) FILTER (WHERE (t.reporting_at IS NOT NULL))) AS avg_wrap_sec,
    date_part('epoch'::text, avg((t.bridged_at - t.offering_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_awt_sec,
    date_part('epoch'::text, max((t.bridged_at - t.offering_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS max_awt_sec,
    date_part('epoch'::text, avg((t.bridged_at - t.joined_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_asa_sec,
    date_part('epoch'::text, avg((GREATEST(t.leaving_at, t.reporting_at) - t.bridged_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_aht_sec,
    q.id AS queue_id,
    q.team_id
    FROM ((call_center.cc_member_attempt_history t
    JOIN call_center.cc_queue q ON ((q.id = t.queue_id)))
    LEFT JOIN call_center.cc_team ct ON ((q.team_id = ct.id)))
    GROUP BY q.id, ct.id;


--7296ce3a WTEL-2617; WTEL-2609; WTEL-2442
alter TABLE call_center.cc_team add column if not exists invite_chat_timeout smallint DEFAULT 30 NOT NULL;


drop VIEW call_center.cc_calls_history_list;
CREATE VIEW call_center.cc_calls_history_list AS
SELECT c.id,
       c.app_id,
       'call'::character varying AS type,
    c.parent_id,
    c.transfer_from,
        CASE
            WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND ((c.id)::text <> (lega.bridged_id)::text)) THEN lega.bridged_id
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
    f.files,
    call_center.cc_get_lookup((cq.id)::bigint, cq.name) AS queue,
    call_center.cc_get_lookup((cm.id)::bigint, cm.name) AS member,
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
          WHERE ((c.parent_id IS NULL) AND ((hp.parent_id)::text = (c.id)::text)))) AS has_children,
    (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), (''::character varying)::text))::character varying AS agent_description,
    c.grantee_id,
    holds.res AS hold,
    c.gateway_ids,
    c.user_ids,
    c.agent_ids,
    c.queue_ids,
    c.team_ids,
    ( SELECT json_agg(row_to_json(annotations.*)) AS json_agg
           FROM ( SELECT a.id,
                    a.call_id,
                    a.created_at,
                    call_center.cc_get_lookup(cc.id, (COALESCE(cc.name, (cc.username)::text))::character varying) AS created_by,
                    a.updated_at,
                    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS updated_by,
                    a.note,
                    a.start_sec,
                    a.end_sec
                   FROM ((call_center.cc_calls_annotation a
                     LEFT JOIN directory.wbt_user cc ON ((cc.id = a.created_by)))
                     LEFT JOIN directory.wbt_user uc ON ((uc.id = a.updated_by)))
                  WHERE ((a.call_id)::text = (c.id)::text)
                  ORDER BY a.created_at DESC) annotations) AS annotations,
    c.amd_result,
    c.amd_duration,
        CASE
            WHEN (c.parent_id IS NOT NULL) THEN ''::text
            WHEN ((c.cause)::text = ANY (ARRAY[('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text])) THEN 'not_answered'::text
            WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
            WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
            CASE
                WHEN (((c.cause)::text = 'NORMAL_CLEARING'::text) AND ((((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND (c.user_id IS NOT NULL)) OR (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (c.bridged_at IS NOT NULL)) OR (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (cq.type = ANY (ARRAY[4, 5])) AND (c.bridged_at IS NOT NULL)))) THEN 'agent_dropped'::text
                ELSE 'client_dropped'::text
END
ELSE 'error'::text
END AS hangup_disposition,
    c.blind_transfer,
    ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id)) AS jsonb_agg
           FROM storage.file_jobs j
          WHERE (j.file_id = ANY (f.file_ids))) AS files_job
   FROM (((((((((((call_center.cc_calls_history c
     LEFT JOIN LATERAL ( SELECT array_agg(f_1.id) AS file_ids,
            json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at', ((c.params -> 'record_start'::text))::bigint, 'stop_at', ((c.params -> 'record_stop'::text))::bigint, 'transcripts', transcripts.data)) AS files
           FROM (( SELECT f1.id,
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
                  WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1
             LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale)) AS data
                   FROM storage.file_transcript tr
                  WHERE (tr.file_id = f_1.id)
                  GROUP BY tr.file_id) transcripts ON (true))) f ON (((c.answered_at IS NOT NULL) OR (c.bridged_at IS NOT NULL))))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
           FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                   FROM call_center.cc_calls_history chh
                  WHERE (((chh.parent_id)::text = (c.id)::text) AND (chh.hold IS NOT NULL))
                UNION
                 SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
          WHERE (x.hi IS NOT NULL)) holds ON ((c.parent_id IS NULL)))
     LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
     LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
     LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
     LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
     LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
     LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
     LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))));



drop VIEW call_center.cc_queue_list;
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
    COALESCE(ss.member_waiting, (0)::bigint) AS waiting,
    COALESCE(act.cnt, (0)::bigint) AS active,
    q.sticky_agent,
    q.processing,
    q.processing_sec,
    q.processing_renewal_sec,
    jsonb_build_object('enabled', q.processing, 'form_schema', call_center.cc_get_lookup(fs.id, fs.name), 'sec', q.processing_sec, 'renewal_sec', q.processing_renewal_sec) AS task_processing
   FROM ((((((((((((call_center.cc_queue q
     JOIN flow.calendar c ON ((q.calendar_id = c.id)))
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
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL) AND ((a.state)::text <> 'leaving'::text))) act ON (true));



drop VIEW call_center.cc_team_list;
CREATE VIEW call_center.cc_team_list AS
SELECT t.id,
       t.name,
       t.description,
       t.strategy,
       t.max_no_answer,
       t.wrap_up_time,
       t.no_answer_delay_time,
       t.call_timeout,
       t.updated_at,
       ( SELECT jsonb_agg(adm."user") AS jsonb_agg
         FROM call_center.cc_agent_with_user adm
         WHERE (adm.id = ANY (t.admin_ids))) AS admin,
       t.domain_id,
       t.admin_ids,
       t.invite_chat_timeout
FROM call_center.cc_team t;


--8361cc38

drop MATERIALIZED VIEW if exists call_center.cc_agent_today_stats;
CREATE MATERIALIZED VIEW call_center.cc_agent_today_stats AS
 WITH agents AS MATERIALIZED (
         SELECT a_1.id,
            a_1.user_id,
                CASE
                    WHEN (a_1.last_state_change < (d."from")::timestamp with time zone) THEN (d."from")::timestamp with time zone
                    WHEN (a_1.last_state_change < d."to") THEN a_1.last_state_change
                    ELSE a_1.last_state_change
                END AS cur_state_change,
            a_1.status,
            a_1.status_payload,
            a_1.last_state_change,
            (lasts.last_at)::timestamp with time zone AS last_at,
            lasts.state AS last_state,
            lasts.status_payload AS last_payload,
            COALESCE(top.top_at, a_1.last_state_change) AS top_at,
            COALESCE(top.state, a_1.status) AS top_state,
            COALESCE(top.status_payload, a_1.status_payload) AS top_payload,
            d."from",
            d."to",
            a_1.domain_id
           FROM (((((call_center.cc_agent a_1
             LEFT JOIN flow.region r ON ((r.id = a_1.region_id)))
             LEFT JOIN flow.calendar_timezones t ON ((t.id = r.timezone_id)))
             LEFT JOIN LATERAL ( SELECT now() AS "to",
                    ((now())::date + age(now(), (timezone(COALESCE(t.sys_name, 'UTC'::text), now()))::timestamp with time zone)) AS "from") d ON (true))
             LEFT JOIN LATERAL ( SELECT aa.state,
                    d."from" AS last_at,
                    aa.payload AS status_payload
                   FROM call_center.cc_agent_state_history aa
                  WHERE ((aa.agent_id = a_1.id) AND (aa.channel IS NULL) AND ((aa.state)::text = ANY (ARRAY[('pause'::character varying)::text, ('online'::character varying)::text, ('offline'::character varying)::text])) AND (aa.joined_at < (d."from")::timestamp with time zone))
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
            sum(((h.reporting_at - h.leaving_at) - ((q.processing_sec || 's'::text))::interval)) FILTER (WHERE ((h.reporting_at IS NOT NULL) AND q.processing AND ((h.reporting_at - h.leaving_at) > (((q.processing_sec + 1) || 's'::text))::interval))) AS tpause
           FROM ((agents
             JOIN call_center.cc_member_attempt_history h ON ((h.agent_id = agents.id)))
             LEFT JOIN call_center.cc_queue q ON ((q.id = h.queue_id)))
          WHERE ((h.domain_id = agents.domain_id) AND (h.joined_at >= (agents."from")::timestamp with time zone) AND (h.joined_at <= agents."to") AND ((h.channel)::text = 'call'::text))
          GROUP BY h.agent_id
        ), chats AS (
         SELECT cma.agent_id,
            count(*) FILTER (WHERE (cma.bridged_at IS NOT NULL)) AS chat_accepts,
            (avg(EXTRACT(epoch FROM (COALESCE(cma.reporting_at, cma.leaving_at) - cma.bridged_at))) FILTER (WHERE (cma.bridged_at IS NOT NULL)))::bigint AS chat_aht
           FROM (agents
             JOIN call_center.cc_member_attempt_history cma ON ((cma.agent_id = agents.id)))
          WHERE ((cma.joined_at >= (agents."from")::timestamp with time zone) AND (cma.joined_at <= agents."to") AND (cma.domain_id = agents.domain_id) AND (cma.bridged_at IS NOT NULL) AND ((cma.channel)::text = 'chat'::text))
          GROUP BY cma.agent_id
        ), calls AS (
         SELECT h.user_id,
            count(*) FILTER (WHERE ((h.direction)::text = 'inbound'::text)) AS all_inb,
            count(*) FILTER (WHERE (h.bridged_at IS NOT NULL)) AS handled,
            count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.bridged_at IS NOT NULL))) AS inbound_bridged,
            count(*) FILTER (WHERE ((cq.type = 1) AND (h.bridged_at IS NOT NULL) AND (h.parent_id IS NOT NULL))) AS "inbound queue",
            count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.queue_id IS NULL))) AS "direct inbound",
            count(*) FILTER (WHERE ((h.parent_id IS NOT NULL) AND (h.bridged_at IS NOT NULL) AND (h.queue_id IS NULL) AND (pc.user_id IS NOT NULL))) AS internal_inb,
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
            sum((cc.reporting_at - cc.leaving_at)) FILTER (WHERE (cc.reporting_at IS NOT NULL)) AS "Post call"
           FROM ((((agents
             JOIN call_center.cc_calls_history h ON ((h.user_id = agents.user_id)))
             LEFT JOIN call_center.cc_queue cq ON ((h.queue_id = cq.id)))
             LEFT JOIN call_center.cc_member_attempt_history cc ON (((cc.agent_call_id)::text = (h.id)::text)))
             LEFT JOIN call_center.cc_calls_history pc ON (((pc.id)::text = (h.parent_id)::text)))
          WHERE ((h.domain_id = agents.domain_id) AND (h.created_at >= (agents."from")::timestamp with time zone) AND (h.created_at <= agents."to"))
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
        )
SELECT a.id AS agent_id,
       a.domain_id,
       COALESCE(c.missed, (0)::bigint) AS call_missed,
       COALESCE(c.abandoned, (0)::bigint) AS call_abandoned,
       COALESCE(c.inbound_bridged, (0)::bigint) AS call_inbound,
       COALESCE(c.handled, (0)::bigint) AS call_handled,
       COALESCE((EXTRACT(epoch FROM c.avg_talk))::bigint, (0)::bigint) AS avg_talk_sec,
       COALESCE((EXTRACT(epoch FROM c.avg_hold))::bigint, (0)::bigint) AS avg_hold_sec,
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
       COALESCE(ch.chat_aht, (0)::bigint) AS chat_aht,
       COALESCE(ch.chat_accepts, (0)::bigint) AS chat_accepts
FROM (((((agents a
    LEFT JOIN call_center.cc_agent_with_user u ON ((u.id = a.id)))
    LEFT JOIN stats ON ((stats.agent_id = a.id)))
    LEFT JOIN eff ON ((eff.agent_id = a.id)))
    LEFT JOIN calls c ON ((c.user_id = a.user_id)))
    LEFT JOIN chats ch ON ((ch.agent_id = a.id)))
    WITH NO DATA;
refresh materialized view call_center.cc_agent_today_stats;


drop VIEW call_center.cc_calls_history_list;
CREATE VIEW call_center.cc_calls_history_list AS
SELECT c.id,
       c.app_id,
       'call'::character varying AS type,
    c.parent_id,
    c.transfer_from,
        CASE
            WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND ((c.id)::text <> (lega.bridged_id)::text)) THEN lega.bridged_id
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
    f.files,
    call_center.cc_get_lookup((cq.id)::bigint, cq.name) AS queue,
    call_center.cc_get_lookup((cm.id)::bigint, cm.name) AS member,
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
          WHERE ((c.parent_id IS NULL) AND ((hp.parent_id)::text = (c.id)::text)))) AS has_children,
    (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), (''::character varying)::text))::character varying AS agent_description,
    c.grantee_id,
    holds.res AS hold,
    c.gateway_ids,
    c.user_ids,
    c.agent_ids,
    c.queue_ids,
    c.team_ids,
    ( SELECT json_agg(row_to_json(annotations.*)) AS json_agg
           FROM ( SELECT a.id,
                    a.call_id,
                    a.created_at,
                    call_center.cc_get_lookup(cc.id, (COALESCE(cc.name, (cc.username)::text))::character varying) AS created_by,
                    a.updated_at,
                    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS updated_by,
                    a.note,
                    a.start_sec,
                    a.end_sec
                   FROM ((call_center.cc_calls_annotation a
                     LEFT JOIN directory.wbt_user cc ON ((cc.id = a.created_by)))
                     LEFT JOIN directory.wbt_user uc ON ((uc.id = a.updated_by)))
                  WHERE ((a.call_id)::text = (c.id)::text)
                  ORDER BY a.created_at DESC) annotations) AS annotations,
    c.amd_result,
    c.amd_duration,
    cq.type AS queue_type,
        CASE
            WHEN (c.parent_id IS NOT NULL) THEN ''::text
            WHEN ((c.cause)::text = ANY (ARRAY[('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text])) THEN 'not_answered'::text
            WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
            WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
            CASE
                WHEN (((c.cause)::text = 'NORMAL_CLEARING'::text) AND ((((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND (c.user_id IS NOT NULL)) OR (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (c.bridged_at IS NOT NULL)) OR (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (cq.type = ANY (ARRAY[4, 5])) AND (c.bridged_at IS NOT NULL)))) THEN 'agent_dropped'::text
                ELSE 'client_dropped'::text
END
ELSE 'error'::text
END AS hangup_disposition,
    c.blind_transfer,
    ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id)) AS jsonb_agg
           FROM storage.file_jobs j
          WHERE (j.file_id = ANY (f.file_ids))) AS files_job
   FROM (((((((((((call_center.cc_calls_history c
     LEFT JOIN LATERAL ( SELECT array_agg(f_1.id) AS file_ids,
            json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at', ((c.params -> 'record_start'::text))::bigint, 'stop_at', ((c.params -> 'record_stop'::text))::bigint, 'transcripts', transcripts.data)) AS files
           FROM (( SELECT f1.id,
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
                  WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1
             LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale)) AS data
                   FROM storage.file_transcript tr
                  WHERE (tr.file_id = f_1.id)
                  GROUP BY tr.file_id) transcripts ON (true))) f ON (((c.answered_at IS NOT NULL) OR (c.bridged_at IS NOT NULL))))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
           FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                   FROM call_center.cc_calls_history chh
                  WHERE (((chh.parent_id)::text = (c.id)::text) AND (chh.hold IS NOT NULL))
                UNION
                 SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
          WHERE (x.hi IS NOT NULL)) holds ON ((c.parent_id IS NULL)))
     LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
     LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
     LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
     LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
     LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
     LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
     LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))));


alter table flow.acr_routing_scheme alter column created_by drop not null ;
alter table flow.acr_routing_scheme alter column updated_by drop not null ;


--38d225b7

drop table if exists storage.remove_file_jobs;

--
-- Name: cognitive_profile_services_set_def(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.cognitive_profile_services_set_def() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if new.default is distinct from old."default" or new.service is distinct from old."service"  then
update storage.cognitive_profile_services c
set  "default" = false
where c.domain_id = new.domain_id and c.id != new.id and c.service = new.service;
end if;
return new;
end;
$$;





create trigger cognitive_profile_services_set_def_tg
    before insert or update
                         on storage.cognitive_profile_services
                         for each row
                         when (new."default")
                         execute procedure storage.cognitive_profile_services_set_def();

create trigger cognitive_profile_services_set_rbac_acl
    after insert
    on storage.cognitive_profile_services
    for each row
    execute procedure storage.tg_obj_default_rbac('cognitive_profile_services');



create index cognitive_profile_services_acl_grantor_idx
    on storage.cognitive_profile_services_acl (grantor);

create unique index cognitive_profile_services_acl_id_uindex
    on storage.cognitive_profile_services_acl (id);

create unique index cognitive_profile_services_acl_object_subject_udx
    on storage.cognitive_profile_services_acl (object, subject) include (access);

create unique index cognitive_profile_services_acl_subject_object_udx
    on storage.cognitive_profile_services_acl (subject, object) include (access);


create index file_transcript_profile_id_index
    on storage.file_transcript (profile_id);

create unique index file_transcript_file_id_profile_id_locale_uindex
    on storage.file_transcript (file_id, profile_id, locale);

create index file_transcript_fts_idx
    on storage.file_transcript using gin (setweight(to_tsvector('english'::regconfig, transcript), 'A'::"char"));

create index file_transcript_fts_ru_idx
    on storage.file_transcript using gin (setweight(to_tsvector('russian'::regconfig, transcript), 'A'::"char"));




--
-- Name: cognitive_profile_services_view; Type: VIEW; Schema: storage; Owner: -
--

CREATE VIEW storage.cognitive_profile_services_view AS
SELECT p.id,
       p.domain_id,
       p.provider,
       p.properties,
       p.created_at,
       storage.get_lookup(c.id, (COALESCE(c.name, (c.username)::text))::character varying) AS created_by,
       p.updated_at,
       storage.get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS updated_by,
       p.enabled,
       p.name,
       p.description,
       p.service,
       p."default"
FROM ((storage.cognitive_profile_services p
    LEFT JOIN directory.wbt_user c ON ((c.id = p.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = p.updated_by)));




--
-- Name: cc_queue_report_general _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_queue_report_general AS
SELECT call_center.cc_get_lookup((q.id)::bigint, q.name) AS queue,
       call_center.cc_get_lookup(ct.id, ct.name) AS team,
       ( SELECT sum(s.member_waiting) AS sum
FROM call_center.cc_queue_statistics s
WHERE (s.queue_id = q.id)) AS waiting,
    ( SELECT count(*) AS count
FROM call_center.cc_member_attempt a
WHERE (a.queue_id = q.id)) AS processed,
    count(*) AS cnt,
    count(*) FILTER (WHERE (t.offering_at IS NOT NULL)) AS calls,
    count(*) FILTER (WHERE ((t.result)::text = 'abandoned'::text)) AS abandoned,
    date_part('epoch'::text, sum((t.leaving_at - t.bridged_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS bill_sec,
    date_part('epoch'::text, avg((t.leaving_at - t.reporting_at)) FILTER (WHERE (t.reporting_at IS NOT NULL))) AS avg_wrap_sec,
    date_part('epoch'::text, avg((t.bridged_at - t.offering_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_awt_sec,
    date_part('epoch'::text, max((t.bridged_at - t.offering_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS max_awt_sec,
    date_part('epoch'::text, avg((t.bridged_at - t.joined_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_asa_sec,
    date_part('epoch'::text, avg((GREATEST(t.leaving_at, t.reporting_at) - t.bridged_at)) FILTER (WHERE (t.bridged_at IS NOT NULL))) AS avg_aht_sec,
    q.id AS queue_id,
    q.team_id
FROM ((call_center.cc_member_attempt_history t
    JOIN call_center.cc_queue q ON ((q.id = t.queue_id)))
    LEFT JOIN call_center.cc_team ct ON ((q.team_id = ct.id)))
GROUP BY q.id, ct.id;

