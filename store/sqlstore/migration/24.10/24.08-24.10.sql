alter table storage.files add column channel character varying;
alter table storage.files add column thumbnail jsonb;
alter table storage.files add column retention_until timestamp with time zone;
alter table storage.files add column uploaded_by bigint;
alter table storage.files add column uploaded_at timestamp with time zone GENERATED ALWAYS AS (to_timestamp((((created_at)::numeric / (1000)::numeric))::double precision)) STORED;



--
-- Name: file_policies; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.file_policies (
                                       id integer NOT NULL,
                                       domain_id bigint NOT NULL,
                                       created_at timestamp with time zone DEFAULT now() NOT NULL,
                                       created_by bigint,
                                       updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                       updated_by bigint,
                                       name character varying DEFAULT ''::character varying NOT NULL,
                                       enabled boolean DEFAULT true NOT NULL,
                                       mime_types character varying[],
                                       speed_download integer DEFAULT 0 NOT NULL,
                                       speed_upload integer DEFAULT 0 NOT NULL,
                                       description character varying,
                                       channels character varying[],
                                       retention_days integer DEFAULT 0 NOT NULL,
                                       max_upload_size bigint DEFAULT 0 NOT NULL,
                                       "position" integer NOT NULL
);


--
-- Name: file_policies_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.file_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.file_policies_id_seq OWNED BY storage.file_policies.id;


--
-- Name: file_policies_position_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.file_policies_position_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_policies_position_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.file_policies_position_seq OWNED BY storage.file_policies."position";


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
       row_number() OVER (PARTITION BY p.domain_id ORDER BY p."position" DESC) AS "position"
FROM ((storage.file_policies p
    LEFT JOIN directory.wbt_user c ON ((c.id = p.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = p.updated_by)));



drop view if exists storage.files_list;
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
       f.instance
FROM ((storage.files f
    LEFT JOIN storage.file_backend_profiles p ON ((f.id = f.profile_id)))
    LEFT JOIN directory.wbt_user u ON ((u.id = f.uploaded_by)));

alter table storage.upload_file_jobs add column channel character varying;

--
-- Name: file_policies id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_policies ALTER COLUMN id SET DEFAULT nextval('storage.file_policies_id_seq'::regclass);


--
-- Name: file_policies position; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_policies ALTER COLUMN "position" SET DEFAULT nextval('storage.file_policies_position_seq'::regclass);

--
-- Name: file_policies file_policies_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_policies
    ADD CONSTRAINT file_policies_pkey PRIMARY KEY (id);


--
-- Name: file_policies_created_by_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_policies_created_by_index ON storage.file_policies USING btree (created_by);


--
-- Name: file_policies_domain_id_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_policies_domain_id_index ON storage.file_policies USING btree (domain_id);


--
-- Name: file_policies_id_domain_id_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX file_policies_id_domain_id_uindex ON storage.file_policies USING btree (id, domain_id);


--
-- Name: file_policies_updated_by_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_policies_updated_by_index ON storage.file_policies USING btree (updated_by);

--
-- Name: files_domain_id_uploaded_at_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_domain_id_uploaded_at_index ON storage.files USING btree (domain_id, uploaded_at DESC);


--
-- Name: files_retention_until_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_retention_until_index ON storage.files USING btree (retention_until) WHERE (retention_until IS NOT NULL);


--
-- Name: files_uploaded_by_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_uploaded_by_index ON storage.files USING btree (uploaded_by);

--
-- Name: file_policies file_policies_set_rbac_acl; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER file_policies_set_rbac_acl AFTER INSERT ON storage.file_policies FOR EACH ROW EXECUTE FUNCTION storage.tg_obj_default_rbac('file_policies');


--
-- Name: file_policies file_policies_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_policies
    ADD CONSTRAINT file_policies_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: file_policies file_policies_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_policies
    ADD CONSTRAINT file_policies_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: file_policies file_policies_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_policies
    ADD CONSTRAINT file_policies_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;

--
-- Name: files files_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.files
    ADD CONSTRAINT files_wbt_user_id_fk FOREIGN KEY (uploaded_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;




--
-- Name: cc_distribute_inbound_call_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
        call_center.cc_view_timestamp(_call.created_at)::int8
        );

END;
$$;



--
-- Name: cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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


alter table call_center.cc_queue alter column calendar_id drop not null ;

alter table call_center.cc_skill add column created_at timestamptz;
alter table call_center.cc_skill add column created_by int8;
alter table call_center.cc_skill add column updated_at timestamptz;
alter table call_center.cc_skill add column updated_by int8;

alter table call_center.cc_team add column forecast_calculation_id int8;
alter table call_center.cc_audit_rate add column call_created_at timestamp with time zone;



drop MATERIALIZED VIEW call_center.cc_agent_today_stats;
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
                                       WHEN (((((now())::date + '1 day'::interval) - COALESCE(t.utc_offset, '00:00:00'::interval)))::timestamp with time zone < now()) THEN ((((now())::date + '1 day'::interval) - COALESCE(t.utc_offset, '00:00:00'::interval)))::timestamp with time zone
                                       ELSE (((now())::date - COALESCE(t.utc_offset, '00:00:00'::interval)))::timestamp with time zone
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
           count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.bridged_at IS NULL) AND (NOT (h.hide_missed IS TRUE)) AND (pc.bridged_at IS NULL))) AS missed,
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


create unique index cc_agent_today_stats_uidx
    on call_center.cc_agent_today_stats (agent_id);

create unique index cc_agent_today_stats_usr_uidx
    on call_center.cc_agent_today_stats (user_id);


alter table call_center.cc_email add column cid jsonb;


--
-- Name: cc_skill_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_skill_acl (
                                          id bigint NOT NULL,
                                          dc bigint NOT NULL,
                                          grantor bigint,
                                          object integer NOT NULL,
                                          subject bigint NOT NULL,
                                          access smallint DEFAULT 0 NOT NULL
);


--
-- Name: cc_skill_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_skill_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_skill_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_skill_acl_id_seq OWNED BY call_center.cc_skill_acl.id;


drop VIEW call_center.cc_skill_view;
--
-- Name: cc_skill_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_skill_view AS
SELECT s.id,
       s.created_at,
       call_center.cc_get_lookup(c.id, (COALESCE(c.name, (c.username)::text))::character varying) AS created_by,
       s.updated_at,
       call_center.cc_get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS updated_by,
       s.name,
       s.description,
       s.domain_id,
       agents.active_agents,
       agents.total_agents
FROM (((call_center.cc_skill s
    LEFT JOIN directory.wbt_user c ON ((c.id = s.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = s.updated_by)))
    LEFT JOIN LATERAL ( SELECT count(DISTINCT sa.agent_id) FILTER (WHERE sa.enabled) AS active_agents,
                               count(DISTINCT sa.agent_id) AS total_agents
                        FROM call_center.cc_skill_in_agent sa
                        WHERE (sa.skill_id = s.id)) agents ON (true));


drop VIEW call_center.cc_team_list;
--
-- Name: cc_team_list; Type: VIEW; Schema: call_center; Owner: -
--

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
       t.invite_chat_timeout,
       t.task_accept_timeout,
       call_center.cc_get_lookup((fc.id)::bigint, (fc.name)::character varying) AS forecast_calculation
FROM (call_center.cc_team t
    LEFT JOIN wfm.forecast_calculation fc ON ((fc.id = t.forecast_calculation_id)));
;


--
-- Name: cc_skill_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_skill_acl_id_seq'::regclass);

--
-- Name: cc_skill_acl cc_skill_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl
    ADD CONSTRAINT cc_skill_acl_pk PRIMARY KEY (id);


--
-- Name: cc_audit_rate_call_created_at; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_audit_rate_call_created_at ON call_center.cc_audit_rate USING btree (call_created_at);



--
-- Name: cc_skill_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_acl_grantor_idx ON call_center.cc_skill_acl USING btree (grantor);


--
-- Name: cc_skill_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_skill_acl_object_subject_udx ON call_center.cc_skill_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_skill_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_skill_acl_subject_object_udx ON call_center.cc_skill_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_skill_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_created_by_index ON call_center.cc_skill USING btree (created_by);

--
-- Name: cc_skill_domain_id_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_skill_domain_id_udx ON call_center.cc_skill USING btree (id, domain_id);

--
-- Name: cc_skill_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_updated_by_index ON call_center.cc_skill USING btree (updated_by);



drop VIEW call_center.cc_distribute_stage_1;
--
-- Name: cc_distribute_stage_1 _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_distribute_stage_1 AS
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
WHERE ((q.type = 7) OR ((q.type = ANY (ARRAY[1, 6])) AND ((NOT q.ignore_calendar) OR calend.in_calendar OR (calend.in_calendar IS NULL))) OR ((q.type = 8) AND (GREATEST(((q.lim - COALESCE(l.usage, (0)::bigint)))::integer, 0) > 0)) OR ((q.type = 5) AND (NOT q.op)) OR (q.op AND (q.type = ANY (ARRAY[2, 3, 4, 5])) AND (r.* IS NOT NULL)))
ORDER BY q.domain_id, q.priority DESC, q.op;


drop VIEW call_center.cc_queue_report_general;


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

--
-- Name: cc_skill cc_skill_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_skill_set_rbac_acl AFTER INSERT ON call_center.cc_skill FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_skill');


ALTER TABLE ONLY call_center.cc_calls_history
    drop CONSTRAINT if exists cc_calls_history_cc_team_id_fk ;



--
-- Name: cc_skill_acl cc_skill_acl_cc_skill_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl
    ADD CONSTRAINT cc_skill_acl_cc_skill_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_skill(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_skill_acl cc_skill_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl
    ADD CONSTRAINT cc_skill_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_skill_acl cc_skill_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl
    ADD CONSTRAINT cc_skill_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_skill_acl cc_skill_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl
    ADD CONSTRAINT cc_skill_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_skill_acl cc_skill_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl
    ADD CONSTRAINT cc_skill_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_skill(id, domain_id) ON DELETE CASCADE;


--
-- Name: cc_skill_acl cc_skill_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl
    ADD CONSTRAINT cc_skill_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_skill cc_skill_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill
    ADD CONSTRAINT cc_skill_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_skill cc_skill_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill
    ADD CONSTRAINT cc_skill_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


drop VIEW call_center.cc_call_active_list;
drop view call_center.cc_member_view_attempt;

alter table call_center.cc_member_attempt
    alter column result type varchar(200) using result::varchar(200);


--
-- Name: cc_call_active_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_call_active_list AS
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
       c.agent_id,
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
-- Name: cc_member_view_attempt; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_member_view_attempt AS
SELECT t.id,
       t.state,
       call_center.cc_view_timestamp(t.last_state_change) AS last_state_change,
       call_center.cc_view_timestamp(t.joined_at) AS joined_at,
       call_center.cc_view_timestamp(t.offering_at) AS offering_at,
       call_center.cc_view_timestamp(t.bridged_at) AS bridged_at,
       call_center.cc_view_timestamp(t.reporting_at) AS reporting_at,
       call_center.cc_view_timestamp(t.leaving_at) AS leaving_at,
       call_center.cc_view_timestamp(t.timeout) AS timeout,
       t.channel,
       call_center.cc_get_lookup((t.queue_id)::bigint, cq.name) AS queue,
       call_center.cc_get_lookup(t.member_id, cm.name) AS member,
       t.member_call_id,
       COALESCE(cm.variables, '{}'::jsonb) AS variables,
       call_center.cc_get_lookup((t.agent_id)::bigint, (COALESCE(u.name, (u.username)::text))::character varying) AS agent,
       t.agent_call_id,
       t.weight AS "position",
       call_center.cc_get_lookup((t.resource_id)::bigint, r.name) AS resource,
       call_center.cc_get_lookup(t.bucket_id, (cb.name)::character varying) AS bucket,
       call_center.cc_get_lookup(t.list_communication_id, l.name) AS list,
       COALESCE(t.display, ''::character varying) AS display,
       t.destination,
       t.result,
       t.domain_id,
       t.queue_id,
       t.bucket_id,
       t.member_id,
       t.agent_id,
       t.joined_at AS joined_at_timestamp,
       t.seq AS attempts
FROM (((((((call_center.cc_member_attempt t
    LEFT JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
    LEFT JOIN call_center.cc_member cm ON ((t.member_id = cm.id)))
    LEFT JOIN call_center.cc_agent a ON ((t.agent_id = a.id)))
    LEFT JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (u.dc = a.domain_id))))
    LEFT JOIN call_center.cc_outbound_resource r ON ((r.id = t.resource_id)))
    LEFT JOIN call_center.cc_bucket cb ON ((cb.id = t.bucket_id)))
    LEFT JOIN call_center.cc_list l ON ((l.id = t.list_communication_id)));



refresh materialized view call_center.cc_agent_today_stats;