--
-- Name: import_template; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.import_template
(
    id          integer               NOT NULL,
    domain_id   bigint                NOT NULL,
    name        text                  NOT NULL,
    description text,
    source_type character varying(50) NOT NULL,
    source_id   bigint                NOT NULL,
    parameters  jsonb                 NOT NULL
);


--
-- Name: import_template_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.import_template_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_template_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.import_template_id_seq OWNED BY storage.import_template.id;


--
-- Name: import_template_view; Type: VIEW; Schema: storage; Owner: -
--

CREATE VIEW storage.import_template_view AS
SELECT t.id,
       t.name,
       t.description,
       t.source_type,
       t.source_id,
       t.parameters,
       jsonb_build_object('id', s.id, 'name', s.name) AS source,
       t.domain_id
FROM (storage.import_template t
    LEFT JOIN LATERAL ( SELECT q.id,
                               q.name
                        FROM call_center.cc_queue q
                        WHERE ((q.id = t.source_id) AND (q.domain_id = t.domain_id))
                        LIMIT 1) s ON (true));


--
-- Name: import_template id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template
    ALTER COLUMN id SET DEFAULT nextval('storage.import_template_id_seq'::regclass);

--
-- Name: import_template import_template_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template
    ADD CONSTRAINT import_template_pk PRIMARY KEY (id);


--
-- Name: file_transcript_file_id_profile_id_locale_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_transcript_file_id_profile_id_locale_index ON storage.file_transcript USING btree (file_id, profile_id, locale);



--
-- Name: cc_attempt_end_reporting(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb, integer, integer, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION call_center.cc_attempt_end_reporting;
CREATE FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying,
                                                     description_ character varying DEFAULT NULL::character varying,
                                                     expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone,
                                                     next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone,
                                                     sticky_agent_id_ integer DEFAULT NULL::integer,
                                                     variables_ jsonb DEFAULT NULL::jsonb,
                                                     max_attempts_ integer DEFAULT 0,
                                                     wait_between_retries_ integer DEFAULT 60,
                                                     exclude_dest boolean DEFAULT NULL::boolean,
                                                     _per_number boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
AS
$$
declare
    attempt        call_center.cc_member_attempt%rowtype;
    agent_timeout_ timestamptz;
    time_          int8 = extract(EPOCH from now()) * 1000;
    user_id_       int8 = null;
    domain_id_     int8;
    wrap_time_     int;
    other_cnt_     int;
    stop_cause_    varchar;
    agent_channel_ varchar;
begin

    if next_offering_at_ notnull and not attempt.result in ('success', 'cancel') and next_offering_at_ < now() then
        -- todo move to application
        raise exception 'bad parameter: next distribute at';
    end if;


    update call_center.cc_member_attempt
    set state        = 'leaving',
        reporting_at = now(),
        leaving_at   = case when leaving_at isnull then now() else leaving_at end,
        result       = status_,
        description  = description_
    where id = attempt_id_
      and state != 'leaving'
    returning * into attempt;

    if attempt.id isnull then
        return null;
--         raise exception  'not found %', attempt_id_;
    end if;

    if attempt.member_id notnull then
        update call_center.cc_member
        set last_hangup_at = time_,
            variables      = case
                                 when variables_ notnull then coalesce(variables::jsonb, '{}') || variables_
                                 else variables end,
            expire_at      = case when expire_at_ isnull then expire_at else expire_at_ end,
            agent_id       = case when sticky_agent_id_ isnull then agent_id else sticky_agent_id_ end,

            stop_at        = case
                                 when next_offering_at_ notnull or
                                      stop_at notnull or
                                      (not attempt.result in ('success', 'cancel') and
                                       case
                                           when _per_number is true then (attempt.waiting_other_numbers > 0 or
                                                                          (max_attempts_ > 0 and coalesce(
                                                                                                         (communications #>
                                                                                                          (format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int,
                                                                                                         0) + 1 <
                                                                                                 max_attempts_))
                                           else (max_attempts_ > 0 and (attempts + 1 < max_attempts_)) end
                                          )
                                     then stop_at
                                 else attempt.leaving_at end,
            stop_cause     = case
                                 when next_offering_at_ notnull or
                                      stop_at notnull or
                                      (not attempt.result in ('success', 'cancel') and
                                       case
                                           when _per_number is true then (attempt.waiting_other_numbers > 0 or
                                                                          (max_attempts_ > 0 and coalesce(
                                                                                                         (communications #>
                                                                                                          (format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int,
                                                                                                         0) + 1 <
                                                                                                 max_attempts_))
                                           else (max_attempts_ > 0 and (attempts + 1 < max_attempts_)) end
                                          )
                                     then stop_cause
                                 else attempt.result end,

            ready_at       = case
                                 when next_offering_at_ notnull then next_offering_at_
                                 else now() + (wait_between_retries_ || ' sec')::interval end,

            last_agent     = coalesce(attempt.agent_id, last_agent),
            communications = jsonb_set(communications, (array [attempt.communication_idx::int])::text[],
                                       communications -> (attempt.communication_idx::int) ||
                                       jsonb_build_object('last_activity_at', case
                                                                                  when next_offering_at_ notnull
                                                                                      then '0'::text::jsonb
                                                                                  else time_::text::jsonb end) ||
                                       jsonb_build_object('attempt_id', attempt_id_) ||
                                       jsonb_build_object('attempts', coalesce((communications #>
                                                                                (format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int,
                                                                               0) + 1) ||
                                       case
                                           when exclude_dest or
                                                (_per_number is true and coalesce((communications #>
                                                                                   (format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int,
                                                                                  0) + 1 >= max_attempts_)
                                               then jsonb_build_object('stop_at', time_)
                                           else '{}'::jsonb end
                ),
            attempts       = attempts + 1 --TODO
        where id = attempt.member_id
        returning stop_cause into stop_cause_;
    end if;

    if attempt.agent_id notnull then
        select a.user_id,
               a.domain_id,
               case when a.on_demand then null else coalesce(tm.wrap_up_time, 0) end,
               case
                   when attempt.channel = 'chat' then (select count(1)
                                                       from call_center.cc_member_attempt aa
                                                       where aa.agent_id = attempt.agent_id
                                                         and aa.id != attempt.id
                                                         and aa.state != 'leaving')
                   else 0 end as other
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
            set state          = 'wrap_time',
                joined_at      = now(),
                timeout        = case when wrap_time_ > 0 then now() + (wrap_time_ || ' sec')::interval end,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning timeout, channel into agent_timeout_, agent_channel_;
        else
            update call_center.cc_agent_channel c
            set state          = 'waiting',
                joined_at      = now(),
                timeout        = null,
                channel        = null,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id),
                queue_id       = null
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning timeout, channel into agent_timeout_, agent_channel_;
        end if;
    end if;

    return row (call_center.cc_view_timestamp(now()),
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


alter TABLE call_center.cc_email
    drop column body;
alter TABLE call_center.cc_email
    add column body text;



drop VIEW call_center.cc_email_profile_list;
--
-- Name: cc_email_profile_list; Type: VIEW; Schema: call_center; Owner: -
--
CREATE VIEW call_center.cc_email_profile_list AS
SELECT t.id,
       t.domain_id,
       call_center.cc_view_timestamp(t.created_at)                           AS created_at,
       call_center.cc_get_lookup(t.created_by, (cc.name)::character varying) AS created_by,
       call_center.cc_view_timestamp(t.updated_at)                           AS updated_at,
       call_center.cc_get_lookup(t.updated_by, (cu.name)::character varying) AS updated_by,
       t.name,
       t.host,
       t.login,
       t.mailbox,
       t.smtp_port,
       t.imap_port,
       call_center.cc_get_lookup((t.flow_id)::bigint, s.name)                AS schema,
       t.description,
       t.enabled,
       t.password
FROM (((call_center.cc_email_profile t
    LEFT JOIN directory.wbt_user cc ON ((cc.id = t.created_by)))
    LEFT JOIN directory.wbt_user cu ON ((cu.id = t.updated_by)))
    LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.flow_id)));


--
-- Name: cc_calls_history_mat_view_agent; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX if not exists cc_calls_history_mat_view_agent ON call_center.cc_calls_history USING btree (user_id, domain_id, created_at);

--
-- Name: cc_member_attempt_history_mat_view_agent; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX if not exists cc_member_attempt_history_mat_view_agent ON call_center.cc_member_attempt_history USING btree (agent_id, domain_id, joined_at, channel);



drop VIEW call_center.cc_calls_history_list;
--
-- Name: cc_calls_history_list; Type: VIEW; Schema: call_center; Owner: -
--

alter table storage.file_transcript
    alter column file_id drop not null;
alter table storage.file_transcript
    add column uuid character varying NOT NULL;
alter table storage.file_transcript
    add column domain_id int8;

alter TABLE storage.file_jobs
    add column error character varying;

CREATE VIEW call_center.cc_calls_history_list AS
SELECT c.id,
       c.app_id,
       'call'::character varying                                                                                 AS type,
       c.parent_id,
       c.transfer_from,
       CASE
           WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND ((c.id)::text <> (lega.bridged_id)::text))
               THEN lega.bridged_id
           ELSE c.transfer_to
           END                                                                                                   AS transfer_to,
       call_center.cc_get_lookup(u.id,
                                 (COALESCE(u.name, (u.username)::text))::character varying)                      AS "user",
       CASE
           WHEN (cq.type = ANY (ARRAY [4, 5])) THEN cag.extension
           ELSE u.extension
           END                                                                                                   AS extension,
       call_center.cc_get_lookup(gw.id, gw.name)                                                                 AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number',
                         COALESCE(c.from_number, ''::character varying), 'id',
                         COALESCE(c.from_id, ''::character varying), 'name',
                         COALESCE(c.from_name, ''::character varying))                                           AS "from",
       json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number',
                         COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying),
                         'name',
                         COALESCE(c.to_name, ''::character varying))                                             AS "to",
       c.payload                                                                                                 AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       c.stored_at,
       COALESCE(c.hangup_by, ''::character varying)                                                              AS hangup_by,
       c.cause,
       (date_part('epoch'::text, (c.hangup_at - c.created_at)))::bigint                                          AS duration,
       COALESCE(c.hold_sec, 0)                                                                                   AS hold_sec,
       COALESCE(
               CASE
                   WHEN (c.answered_at IS NOT NULL) THEN (date_part('epoch'::text, (c.answered_at - c.created_at)))::bigint
                   ELSE (date_part('epoch'::text, (c.hangup_at - c.created_at)))::bigint
                   END,
               (0)::bigint)                                                                                      AS wait_sec,
       CASE
           WHEN (c.answered_at IS NOT NULL) THEN (date_part('epoch'::text, (c.hangup_at - c.answered_at)))::bigint
           ELSE (0)::bigint
           END                                                                                                   AS bill_sec,
       c.sip_code,
       f.files,
       call_center.cc_get_lookup((cq.id)::bigint, cq.name)                                                       AS queue,
       call_center.cc_get_lookup((cm.id)::bigint, cm.name)                                                       AS member,
       call_center.cc_get_lookup(ct.id, ct.name)                                                                 AS team,
       call_center.cc_get_lookup((aa.id)::bigint,
                                 (COALESCE(cag.username, (cag.name)::name))::character varying)                  AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at                                                                                            AS queue_bridged_at,
       CASE
           WHEN (cma.bridged_at IS NOT NULL) THEN (date_part('epoch'::text, (cma.bridged_at - cma.joined_at)))::integer
           ELSE (date_part('epoch'::text, (cma.leaving_at - cma.joined_at)))::integer
           END                                                                                                   AS queue_wait_sec,
       (date_part('epoch'::text, (cma.leaving_at - cma.joined_at)))::integer                                     AS queue_duration_sec,
       cma.result,
       CASE
           WHEN (cma.reporting_at IS NOT NULL) THEN (date_part('epoch'::text, (cma.reporting_at - cma.leaving_at)))::integer
           ELSE 0
           END                                                                                                   AS reporting_sec,
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
       (EXISTS(SELECT 1
               FROM call_center.cc_calls_history hp
               WHERE ((c.parent_id IS NULL) AND ((hp.parent_id)::text = (c.id)::text))))                         AS has_children,
       (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text),
                 (''::character varying)::text))::character varying                                              AS agent_description,
       c.grantee_id,
       holds.res                                                                                                 AS hold,
       c.gateway_ids,
       c.user_ids,
       c.agent_ids,
       c.queue_ids,
       c.team_ids,
       (SELECT json_agg(row_to_json(annotations.*)) AS json_agg
        FROM (SELECT a.id,
                     a.call_id,
                     a.created_at,
                     call_center.cc_get_lookup(cc.id,
                                               (COALESCE(cc.name, (cc.username)::text))::character varying)        AS created_by,
                     a.updated_at,
                     call_center.cc_get_lookup(uc.id,
                                               (COALESCE(uc.name, (uc.username)::text))::character varying)        AS updated_by,
                     a.note,
                     a.start_sec,
                     a.end_sec
              FROM ((call_center.cc_calls_annotation a
                  LEFT JOIN directory.wbt_user cc ON ((cc.id = a.created_by)))
                  LEFT JOIN directory.wbt_user uc ON ((uc.id = a.updated_by)))
              WHERE ((a.call_id)::text = (c.id)::text)
              ORDER BY a.created_at DESC) annotations)                                                           AS annotations,
       c.amd_result,
       c.amd_duration,
       cq.type                                                                                                   AS queue_type,
       CASE
           WHEN (c.parent_id IS NOT NULL) THEN ''::text
           WHEN ((c.cause)::text = ANY
                 (ARRAY [('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text]))
               THEN 'not_answered'::text
           WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
           WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
               CASE
                   WHEN (((c.cause)::text = 'NORMAL_CLEARING'::text) AND
                         ((((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND
                           (c.user_id IS NOT NULL)) OR
                          (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND
                           (c.bridged_at IS NOT NULL)) OR
                          (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND
                           (cq.type = ANY (ARRAY [4, 5])) AND (c.bridged_at IS NOT NULL)))) THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END                                                                                                   AS hangup_disposition,
       c.blind_transfer,
       (SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at),
                                           'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error,
                                           'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
        FROM storage.file_jobs j
        WHERE (j.file_id = ANY (f.file_ids)))                                                                    AS files_job,
       transcripts.data                                                                                          AS transcripts
FROM ((((((((((((call_center.cc_calls_history c
    LEFT JOIN LATERAL ( SELECT array_agg(f_1.id)                                                         AS file_ids,
                               json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size,
                                                           'mime_type', f_1.mime_type, 'start_at',
                                                           ((c.params -> 'record_start'::text))::bigint, 'stop_at',
                                                           ((c.params -> 'record_stop'::text))::bigint)) AS files
                        FROM (SELECT f1.id,
                                     f1.size,
                                     f1.mime_type,
                                     f1.name
                              FROM storage.files f1
                              WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND
                                     ((f1.uuid)::text = (c.id)::text))
                              UNION ALL
                              SELECT f1.id,
                                     f1.size,
                                     f1.mime_type,
                                     f1.name
                              FROM storage.files f1
                              WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND
                                     ((f1.uuid)::text = (c.parent_id)::text))) f_1) f
                 ON (((c.answered_at IS NOT NULL) OR (c.bridged_at IS NOT NULL))))
    LEFT JOIN LATERAL ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
                        FROM (SELECT jsonb_array_elements(chh.hold) AS hi
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
    LEFT JOIN call_center.cc_calls_history lega
       ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))))
    LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id',
                                                          tr.file_id)) AS data
                        FROM storage.file_transcript tr
                        WHERE ((tr.uuid)::text = ((c.id)::character varying(50))::text)
                        GROUP BY (tr.uuid)::text) transcripts ON (true));





drop index if exists file_transcript_file_id_profile_id_locale_index;
--
-- Name: file_transcript_file_id_profile_id_locale_uindex; Type: INDEX; Schema: storage; Owner: -
--
drop INDEX if  exists call_center.file_transcript_file_id_profile_id_locale_uindex;
CREATE UNIQUE INDEX if not exists file_transcript_file_id_profile_id_locale_uindex ON storage.file_transcript USING btree (file_id, profile_id, locale);


drop INDEX if exists file_transcript_uuid_index;
--
-- Name: file_transcript_uuid_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_transcript_uuid_index ON storage.file_transcript USING btree (((uuid)::character varying(50)));

ALTER TABLE ONLY storage.file_transcript
    drop CONSTRAINT if exists file_transcript_files_id_fk;
ALTER TABLE ONLY storage.file_transcript
    ADD CONSTRAINT file_transcript_files_id_fk FOREIGN KEY (file_id) REFERENCES storage.files (id) ON UPDATE SET NULL ON DELETE SET NULL;



alter table call_center.cc_member_attempt_history
    add import_id varchar(30);
alter table call_center.cc_member
    add import_id varchar(30);
alter table call_center.cc_member_attempt
    add import_id varchar(30);



drop PROCEDURE call_center.cc_distribute;
CREATE PROCEDURE call_center.cc_distribute(INOUT cnt integer)
    LANGUAGE plpgsql
AS
$$
begin
    if NOT pg_try_advisory_xact_lock(132132117) then
        raise exception 'LOCK';
    end if;

    with dis as MATERIALIZED (select x.*, a.team_id
                              from call_center.cc_sys_distribute() x (agent_id int, queue_id int, bucket_id int,
                                                                      ins bool, id int8, resource_id int,
                                                                      resource_group_id int, comm_idx int)
                                       left join call_center.cc_agent a on a.id = x.agent_id)
       , ins as (
        insert into call_center.cc_member_attempt (channel, member_id, queue_id, resource_id, agent_id, bucket_id,
                                                   destination,
                                                   communication_idx, member_call_id, team_id, resource_group_id,
                                                   domain_id, import_id)
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
                   m.import_id
            from dis
                     inner join call_center.cc_queue q on q.id = dis.queue_id
                     inner join call_center.cc_member m on m.id = dis.id
                     inner join lateral jsonb_extract_path(m.communications, (dis.comm_idx)::text) x on true
            where dis.ins)
    update call_center.cc_member_attempt a
    set agent_id = t.agent_id,
        team_id  = t.team_id
    from (select dis.id, dis.agent_id, dis.team_id
          from dis

          where not dis.ins is true) t
    where t.id = a.id
      and a.agent_id isnull;

end;
$$;


alter table call_center.cc_calls_history
    add column talk_sec int not null default 0;



drop VIEW call_center.cc_calls_history_list;
--
-- Name: cc_calls_history_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_calls_history_list AS
SELECT c.id,
       c.app_id,
       'call'::character varying                                                                                 AS type,
       c.parent_id,
       c.transfer_from,
       CASE
           WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND ((c.id)::text <> (lega.bridged_id)::text))
               THEN lega.bridged_id
           ELSE c.transfer_to
           END                                                                                                   AS transfer_to,
       call_center.cc_get_lookup(u.id,
                                 (COALESCE(u.name, (u.username)::text))::character varying)                      AS "user",
       CASE
           WHEN (cq.type = ANY (ARRAY [4, 5])) THEN cag.extension
           ELSE u.extension
           END                                                                                                   AS extension,
       call_center.cc_get_lookup(gw.id, gw.name)                                                                 AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number',
                         COALESCE(c.from_number, ''::character varying), 'id',
                         COALESCE(c.from_id, ''::character varying), 'name',
                         COALESCE(c.from_name, ''::character varying))                                           AS "from",
       json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number',
                         COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying),
                         'name',
                         COALESCE(c.to_name, ''::character varying))                                             AS "to",
       c.payload                                                                                                 AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       c.stored_at,
       COALESCE(c.hangup_by, ''::character varying)                                                              AS hangup_by,
       c.cause,
       (date_part('epoch'::text, (c.hangup_at - c.created_at)))::bigint                                          AS duration,
       COALESCE(c.hold_sec, 0)                                                                                   AS hold_sec,
       COALESCE(
               CASE
                   WHEN (c.answered_at IS NOT NULL) THEN (date_part('epoch'::text, (c.answered_at - c.created_at)))::bigint
                   ELSE (date_part('epoch'::text, (c.hangup_at - c.created_at)))::bigint
                   END,
               (0)::bigint)                                                                                      AS wait_sec,
       CASE
           WHEN (c.answered_at IS NOT NULL) THEN (date_part('epoch'::text, (c.hangup_at - c.answered_at)))::bigint
           ELSE (0)::bigint
           END                                                                                                   AS bill_sec,
       c.sip_code,
       f.files,
       call_center.cc_get_lookup((cq.id)::bigint, cq.name)                                                       AS queue,
       call_center.cc_get_lookup((cm.id)::bigint, cm.name)                                                       AS member,
       call_center.cc_get_lookup(ct.id, ct.name)                                                                 AS team,
       call_center.cc_get_lookup((aa.id)::bigint,
                                 (COALESCE(cag.username, (cag.name)::name))::character varying)                  AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at                                                                                            AS queue_bridged_at,
       CASE
           WHEN (cma.bridged_at IS NOT NULL) THEN (date_part('epoch'::text, (cma.bridged_at - cma.joined_at)))::integer
           ELSE (date_part('epoch'::text, (cma.leaving_at - cma.joined_at)))::integer
           END                                                                                                   AS queue_wait_sec,
       (date_part('epoch'::text, (cma.leaving_at - cma.joined_at)))::integer                                     AS queue_duration_sec,
       cma.result,
       CASE
           WHEN (cma.reporting_at IS NOT NULL) THEN (date_part('epoch'::text, (cma.reporting_at - cma.leaving_at)))::integer
           ELSE 0
           END                                                                                                   AS reporting_sec,
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
       (EXISTS(SELECT 1
               FROM call_center.cc_calls_history hp
               WHERE ((c.parent_id IS NULL) AND ((hp.parent_id)::text = (c.id)::text))))                         AS has_children,
       (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text),
                 (''::character varying)::text))::character varying                                              AS agent_description,
       c.grantee_id,
       holds.res                                                                                                 AS hold,
       c.gateway_ids,
       c.user_ids,
       c.agent_ids,
       c.queue_ids,
       c.team_ids,
       (SELECT json_agg(row_to_json(annotations.*)) AS json_agg
        FROM (SELECT a.id,
                     a.call_id,
                     a.created_at,
                     call_center.cc_get_lookup(cc.id,
                                               (COALESCE(cc.name, (cc.username)::text))::character varying)        AS created_by,
                     a.updated_at,
                     call_center.cc_get_lookup(uc.id,
                                               (COALESCE(uc.name, (uc.username)::text))::character varying)        AS updated_by,
                     a.note,
                     a.start_sec,
                     a.end_sec
              FROM ((call_center.cc_calls_annotation a
                  LEFT JOIN directory.wbt_user cc ON ((cc.id = a.created_by)))
                  LEFT JOIN directory.wbt_user uc ON ((uc.id = a.updated_by)))
              WHERE ((a.call_id)::text = (c.id)::text)
              ORDER BY a.created_at DESC) annotations)                                                           AS annotations,
       c.amd_result,
       c.amd_duration,
       cq.type                                                                                                   AS queue_type,
       CASE
           WHEN (c.parent_id IS NOT NULL) THEN ''::text
           WHEN ((c.cause)::text = ANY
                 (ARRAY [('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text]))
               THEN 'not_answered'::text
           WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
           WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
               CASE
                   WHEN (((c.cause)::text = 'NORMAL_CLEARING'::text) AND
                         ((((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND
                           (c.user_id IS NOT NULL)) OR
                          (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND
                           (c.bridged_at IS NOT NULL)) OR
                          (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND
                           (cq.type = ANY (ARRAY [4, 5])) AND (c.bridged_at IS NOT NULL)))) THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END                                                                                                   AS hangup_disposition,
       c.blind_transfer,
       (SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at),
                                           'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error,
                                           'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
        FROM storage.file_jobs j
        WHERE (j.file_id = ANY (f.file_ids)))                                                                    AS files_job,
       transcripts.data                                                                                          AS transcripts,
       c.talk_sec
FROM ((((((((((((call_center.cc_calls_history c
    LEFT JOIN LATERAL ( SELECT array_agg(f_1.id)                                                         AS file_ids,
                               json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size,
                                                           'mime_type', f_1.mime_type, 'start_at',
                                                           ((c.params -> 'record_start'::text))::bigint, 'stop_at',
                                                           ((c.params -> 'record_stop'::text))::bigint)) AS files
                        FROM (SELECT f1.id,
                                     f1.size,
                                     f1.mime_type,
                                     f1.name
                              FROM storage.files f1
                              WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND
                                     ((f1.uuid)::text = (c.id)::text))
                              UNION ALL
                              SELECT f1.id,
                                     f1.size,
                                     f1.mime_type,
                                     f1.name
                              FROM storage.files f1
                              WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND
                                     ((f1.uuid)::text = (c.parent_id)::text))) f_1) f
                 ON (((c.answered_at IS NOT NULL) OR (c.bridged_at IS NOT NULL))))
    LEFT JOIN LATERAL ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
                        FROM (SELECT jsonb_array_elements(chh.hold) AS hi
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
    LEFT JOIN call_center.cc_calls_history lega
       ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))))
    LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id',
                                                          tr.file_id)) AS data
                        FROM storage.file_transcript tr
                        WHERE ((tr.uuid)::text = ((c.id)::character varying(50))::text)
                        GROUP BY (tr.uuid)::text) transcripts ON (true));


--
-- Name: cc_member_attempt_history_descript_s; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_descript_s ON call_center.cc_member_attempt_history USING btree (id, description) WHERE (description IS NOT NULL);




drop FUNCTION call_center.cc_attempt_abandoned;
CREATE FUNCTION call_center.cc_attempt_abandoned(attempt_id_ bigint, _max_count integer DEFAULT 0, _next_after integer DEFAULT 0, vars_ jsonb DEFAULT NULL::jsonb, _per_number boolean DEFAULT false, exclude_dest boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
attempt  call_center.cc_member_attempt%rowtype;
    member_stop_cause varchar;
begin
update call_center.cc_member_attempt
set leaving_at = now(),
    last_state_change = now(),
    result = case when offering_at isnull and resource_id notnull then 'failed' else 'abandoned' end,
            state = 'leaving'
where id = attempt_id_
    returning * into attempt;

if attempt.member_id notnull then
update call_center.cc_member
set last_hangup_at  = (extract(EPOCH from now() ) * 1000)::int8,
            last_agent      = coalesce(attempt.agent_id, last_agent),
            stop_at = case when (stop_cause notnull or
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (_max_count > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < _max_count)) else (_max_count > 0 and (attempts + 1 < _max_count)) end
                                 )  then stop_at else  attempt.leaving_at end,
            stop_cause = case when (stop_cause notnull or
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (_max_count > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < _max_count)) else (_max_count > 0 and (attempts + 1 < _max_count)) end
                                 ) then stop_cause else attempt.result end,
            ready_at = now() + (_next_after || ' sec')::interval,
            communications =  jsonb_set(communications, (array[attempt.communication_idx::int])::text[], communications->(attempt.communication_idx::int) ||
                jsonb_build_object('last_activity_at', (extract(epoch  from attempt.leaving_at) * 1000)::int8::text::jsonb) ||
                jsonb_build_object('attempt_id', attempt_id_) ||
                jsonb_build_object('attempts', coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                case when exclude_dest or (_per_number is true and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= _max_count) then jsonb_build_object('stop_at', (extract(EPOCH from now() ) * 1000)::int8) else '{}'::jsonb end
            ),
            variables = case when vars_ notnull then coalesce(variables::jsonb, '{}') || vars_ else variables end,
            attempts        = attempts + 1                     --TODO
        where id = attempt.member_id
        returning stop_cause into member_stop_cause;
end if;


return row(attempt.last_state_change::timestamptz, member_stop_cause::varchar, attempt.result::varchar);
end;
$$;

alter table call_center.cc_member_attempt add column talk_sec integer DEFAULT 0 NOT NULL;