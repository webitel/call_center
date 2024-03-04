alter type flow.calendar_except_date add attribute work_start int ;
alter type flow.calendar_except_date add attribute work_stop int ;
alter type flow.calendar_except_date add attribute working bool;


alter table flow.acr_routing_scheme add column if not exists version integer DEFAULT 1 NOT NULL;
alter table flow.acr_routing_scheme add column if not exists note text;


--
-- Name: scheme_variable; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.scheme_variable (
                                      id integer NOT NULL,
                                      domain_id bigint NOT NULL,
                                      value jsonb,
                                      name character varying NOT NULL,
                                      encrypt boolean DEFAULT false NOT NULL
);


--
-- Name: scheme_variables_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.scheme_variables_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scheme_variables_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.scheme_variables_id_seq OWNED BY flow.scheme_variable.id;


--
-- Name: scheme_version_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.scheme_version_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scheme_version; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.scheme_version (
                                     id integer DEFAULT nextval('flow.scheme_version_id_seq'::regclass) NOT NULL,
                                     created_by integer NOT NULL,
                                     scheme_id bigint NOT NULL,
                                     scheme jsonb NOT NULL,
                                     version integer NOT NULL,
                                     note text,
                                     payload jsonb NOT NULL,
                                     created_at bigint NOT NULL
);


drop table if exists flow.web_hook;


--
-- Name: web_hook; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.web_hook (
                               name character varying NOT NULL,
                               domain_id bigint NOT NULL,
                               description character varying,
                               origin character varying[],
                               schema_id integer NOT NULL,
                               enabled boolean DEFAULT true NOT NULL,
                               "authorization" character varying,
                               created_at timestamp with time zone DEFAULT now() NOT NULL,
                               updated_at timestamp with time zone DEFAULT now() NOT NULL,
                               created_by bigint,
                               updated_by bigint,
                               id integer NOT NULL,
                               key character varying NOT NULL
);


--
-- Name: web_hook_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.web_hook_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: web_hook_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.web_hook_id_seq OWNED BY flow.web_hook.id;


--
-- Name: web_hook_list; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.web_hook_list AS
SELECT h.id,
       h.key,
       h.name,
       h.description,
       h.origin,
       h.enabled,
       h."authorization",
       flow.get_lookup(s.id, s.name) AS schema,
       flow.get_lookup(c.id, (c.name)::character varying) AS created_by,
       flow.get_lookup(u.id, (u.name)::character varying) AS updated_by,
       h.created_at,
       h.updated_at,
       h.schema_id,
       h.domain_id
FROM (((flow.web_hook h
    LEFT JOIN flow.acr_routing_scheme s ON ((s.id = h.schema_id)))
    LEFT JOIN directory.wbt_user c ON ((c.id = h.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = h.updated_by)));


--
-- Name: scheme_variable id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_variable ALTER COLUMN id SET DEFAULT nextval('flow.scheme_variables_id_seq'::regclass);


--
-- Name: web_hook id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.web_hook ALTER COLUMN id SET DEFAULT nextval('flow.web_hook_id_seq'::regclass);


--
-- Name: scheme_variable scheme_variables_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_variable
    ADD CONSTRAINT scheme_variables_pk PRIMARY KEY (id);



--
-- Name: scheme_variables_domain_id_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX scheme_variables_domain_id_name_uindex ON flow.scheme_variable USING btree (domain_id, name);


--
-- Name: scheme_version_scheme_id_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX scheme_version_scheme_id_index ON flow.scheme_version USING btree (scheme_id);


--
-- Name: acr_routing_scheme insert_flow_version; Type: TRIGGER; Schema: flow; Owner: -
--

CREATE TRIGGER insert_flow_version BEFORE UPDATE ON flow.acr_routing_scheme FOR EACH ROW WHEN ((old.scheme <> new.scheme)) EXECUTE FUNCTION flow.scheme_version_appeared();



--
-- Name: scheme_variable scheme_variables_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_variable
    ADD CONSTRAINT scheme_variables_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: scheme_version scheme_version_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_version
    ADD CONSTRAINT scheme_version_acr_routing_scheme_id_fk FOREIGN KEY (scheme_id) REFERENCES flow.acr_routing_scheme(id) ON DELETE CASCADE;


--
-- Name: scheme_version scheme_version_wbt_auth_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_version
    ADD CONSTRAINT scheme_version_wbt_auth_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_auth(id) ON DELETE CASCADE;


--
-- Name: web_hook web_hook_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.web_hook
    ADD CONSTRAINT web_hook_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id) ON DELETE RESTRICT;


--
-- Name: web_hook web_hook_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.web_hook
    ADD CONSTRAINT web_hook_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;




--
-- Name: calendar_json_to_excepts(jsonb); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE or replace FUNCTION flow.calendar_json_to_excepts(jsonb) RETURNS flow.calendar_except_date[]
    LANGUAGE sql IMMUTABLE
AS $_$
select array(
               select row ((x -> 'disabled')::bool, (x -> 'date')::int8, (x ->> 'name')::varchar, (x -> 'repeat')::bool, (x-> 'work_start')::int4, (x-> 'work_stop')::int4, (x-> 'working')::bool)::flow.calendar_except_date
               from jsonb_array_elements($1) x
               order by x -> 'date'
           )::flow.calendar_except_date[]
$_$;

--
-- Name: calendar_check_timing(bigint, integer, character varying); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE or replace FUNCTION flow.calendar_check_timing(domain_id_ bigint, calendar_id_ integer, name_ character varying) RETURNS record
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
                   not current_date AT TIME ZONE ct.sys_name between (to_timestamp(c.start_at / 1000) at time zone ct.sys_name)::date and (to_timestamp(c.end_at / 1000) at time zone ct.sys_name)::date
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
-- Name: scheme_version_appeared(); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.scheme_version_appeared() RETURNS trigger
    LANGUAGE plpgsql
AS $$
begin

    delete from  flow.scheme_version
    where id in (select id
                 from (
                          select id, row_number() over (order by  created_at desc) r
                          from flow.scheme_version
                          where scheme_version.scheme_id = new.id
                          order by  created_at desc
                      ) t
                 where r >= (
                     select value::int from call_center.system_settings where domain_id = new.domain_id and name = 'scheme_version_limit'
                 ));

    insert into flow.scheme_version(created_at, created_by, scheme_id, scheme, version, note, payload) VALUES (old.updated_at, old.updated_by, old.id, old.scheme, old.version, new.note, old.payload);
    new.version = old.version +1;
    return new;
end;
$$;






drop function call_center.cc_set_active_members(node character varying);

create or replace function call_center.cc_set_active_members(node character varying)
    returns TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer, communication_idx integer)
    language plpgsql
as
$$
BEGIN
    return query update call_center.cc_member_attempt a
        set state = case when c.member_id isnull then 'leaving' else
            case when c.queue_type in (3, 4) then 'offering' else 'waiting' end
            end
            ,node_id = node
            ,last_state_change = now()
            ,list_communication_id = lc.id
            ,seq = coalesce(c.attempts, -1) + 1
            ,waiting_other_numbers = coalesce(c.waiting_other_numbers, 0)
            ,result = case when c.member_id isnull then 'cancel' else a.result end
            ,leaving_at = case when c.member_id isnull then now() end
        from (
            select c.id,
                   cq.updated_at                                            as queue_updated_at,
                   r.updated_at::bigint as resource_updated_at,
                   call_center.cc_view_timestamp(gw.updated_at at time zone 'utc')::bigint             as gateway_updated_at,
                   c.destination                                            as destination,
                   cm.variables                                             as variables,
                   cm.name                                                  as member_name,
                   c.state                                                  as state,
                   cqs.member_count                                         as queue_cnt,
                   0                                                        as queue_active_cnt,
                   cqs.member_waiting                                       as queue_waiting_cnt,
                   (ca.updated_at - extract(epoch from u.updated_at))::int8 as agent_updated_at,
                   tm.updated_at                                            as team_updated_at,
                   cq.dnc_list_id,
                   cm.attempts,
                   x.cnt                                                    as waiting_other_numbers,
                   cq.type                                                  as queue_type,
                   cm.id as member_id
            from call_center.cc_member_attempt c
                     left join call_center.cc_member cm on c.member_id = cm.id
                     left join lateral (
                select count(*) cnt
                from jsonb_array_elements(cm.communications) WITH ORDINALITY AS x(c, n)
                where coalesce((x.c -> 'stop_at')::int8, 0) < 1
                  and x.n != (c.communication_idx + 1)
                ) x on c.member_id notnull
                     inner join call_center.cc_queue cq on c.queue_id = cq.id
                     left join call_center.cc_team tm on tm.id = cq.team_id
                     left join call_center.cc_outbound_resource r on r.id = c.resource_id
                     left join directory.sip_gateway gw on gw.id = r.gateway_id
                     left join call_center.cc_agent ca on c.agent_id = ca.id
                     left join call_center.cc_queue_statistics cqs on cq.id = cqs.queue_id
                     left join directory.wbt_user u on u.id = ca.user_id
            where c.state = 'idle'
              and c.leaving_at isnull
            order by cq.priority desc, c.weight desc
                for update of c, cq skip locked
        ) c
            left join call_center.cc_list_communications lc on lc.list_id = c.dnc_list_id and
                                                               lc.number = c.destination ->> 'destination'
        where a.id = c.id --and node = 'call_center-igor'
        returning
            a.id::bigint as id,
            a.member_id::bigint as member_id,
            a.result as result,
            a.queue_id::int as qeueue_id,
            c.queue_updated_at::bigint as queue_updated_at,
            c.queue_cnt::int,
            c.queue_active_cnt::int,
            c.queue_waiting_cnt::int,
            a.resource_id::int as resource_id,
            greatest(c.resource_updated_at::bigint, c.gateway_updated_at::bigint) as resource_updated_at,
            greatest(c.resource_updated_at::bigint, c.gateway_updated_at::bigint) as gateway_updated_at,
            c.destination,
            coalesce(c.variables, '{}') ,
            coalesce(c.member_name, ''),
            a.member_call_id,
            a.agent_id,
            c.agent_updated_at,
            c.team_updated_at,
            a.list_communication_id,
            a.seq,
            a.communication_idx;
END;
$$;




create or replace function call_center.cc_set_agent_channel_change_status() returns trigger
    language plpgsql
as
$$
BEGIN
    -- FIXME
    if TG_OP = 'INSERT' then
        return new;
    end if;
    if new.online != old.online and new.state = 'waiting' then
        new.joined_at := now();
        if new.online then
            return new;
        end if;
    end if;

    --
    if new.state = 'waiting' then
        new.lose_attempt = 0;
        new.queue_id := null;
        new.attempt_id := null;
    end if;

    --fixme error when agent set offline/pause in active call
    if new.joined_at - old.joined_at = interval '0' then
        return new;
    end if;

    new.channel_changed_at = now();

    insert into call_center.cc_agent_state_history (agent_id, joined_at, state, channel, duration, queue_id, attempt_id)
    values (old.agent_id, old.joined_at, old.state, old.channel, new.joined_at - old.joined_at, old.queue_id, old.attempt_id);

    RETURN new;
END;
$$;




--
-- Name: cc_array_to_string(text[], text); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_array_to_string(text[], text) RETURNS text
    LANGUAGE sql IMMUTABLE
AS $_$SELECT array_to_string($1, $2)$_$;



drop PROCEDURE call_center.cc_distribute;
--
-- Name: cc_distribute(boolean); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean)
    LANGUAGE plpgsql
AS $$
begin
    if NOT pg_try_advisory_xact_lock(132132117) then
        raise exception 'LOCK';
    end if;

    with dis as MATERIALIZED (
        select x.*, a.team_id
        from call_center.cc_sys_distribute(disable_omnichannel) x (agent_id int, queue_id int, bucket_id int, ins bool, id int8, resource_id int,
                                                                   resource_group_id int, comm_idx int)
                 left join call_center.cc_agent a on a.id= x.agent_id
    )
       , ins as (
        insert into call_center.cc_member_attempt (channel, member_id, queue_id, resource_id, agent_id, bucket_id, destination,
                                                   communication_idx, member_call_id, team_id, resource_group_id, domain_id, import_id, sticky_agent_id)
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
                   m.import_id,
                   case when q.type = 5 and q.sticky_agent then dis.agent_id end
            from dis
                     inner join call_center.cc_queue q on q.id = dis.queue_id
                     inner join call_center.cc_member m on m.id = dis.id
                     inner join lateral jsonb_extract_path(m.communications, (dis.comm_idx)::text) x on true
            where dis.ins
    )
    update call_center.cc_member_attempt a
    set agent_id = t.agent_id,
        team_id = t.team_id
    from (
             select dis.id, dis.agent_id, dis.team_id
             from dis
                      inner join call_center.cc_agent a on a.id = dis.agent_id
                      left join call_center.cc_queue q on q.id = dis.queue_id
             where not dis.ins is true
               and (q.type is null or q.type in (6, 7) or not exists(select 1 from call_center.cc_calls cc where cc.user_id = a.user_id and cc.hangup_at isnull ))
         ) t
    where t.id = a.id
      and a.agent_id isnull;

end;
$$;

--
-- Name: cc_set_agent_channel_change_status(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_set_agent_channel_change_status() RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    -- FIXME
    if TG_OP = 'INSERT' then
        return new;
    end if;
    if new.online != old.online and new.state = 'waiting' then
        new.joined_at := now();
        if new.online then
            return new;
        end if;
    end if;

    --
    if new.state = 'waiting' then
        new.lose_attempt = 0;
        new.queue_id := null;
        new.attempt_id := null;
    end if;

    --fixme error when agent set offline/pause in active call
    if new.joined_at - old.joined_at = interval '0' then
        return new;
    end if;

    new.channel_changed_at = now();

    insert into call_center.cc_agent_state_history (agent_id, joined_at, state, channel, duration, queue_id, attempt_id)
    values (old.agent_id, old.joined_at, old.state, old.channel, new.joined_at - old.joined_at, old.queue_id, old.attempt_id);

    RETURN new;
END;
$$;

alter table call_center.cc_agent add column if not exists task_count smallint DEFAULT 1 NOT NULL;


drop VIEW call_center.cc_agent_list;
CREATE VIEW call_center.cc_agent_list AS
SELECT a.domain_id,
       a.id,
       (COALESCE(((ct.name)::character varying)::name, (ct.username COLLATE "default")))::character varying AS name,
       a.status,
       a.description,
       ((date_part('epoch'::text, a.last_state_change) * (1000)::double precision))::bigint AS last_status_change,
       (date_part('epoch'::text, (now() - a.last_state_change)))::bigint AS status_duration,
       a.progressive_count,
       ch.x AS channel,
       (json_build_object('id', ct.id, 'name', COALESCE(((ct.name)::character varying)::name, ct.username)))::jsonb AS "user",
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
       a.task_count
FROM (((((call_center.cc_agent a
    LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
    LEFT JOIN storage.media_files g ON ((g.id = a.greeting_media_id)))
    LEFT JOIN call_center.cc_team t ON ((t.id = a.team_id)))
    LEFT JOIN flow.region r ON ((r.id = a.region_id)))
    LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint)) AS x
                        FROM call_center.cc_agent_channel c
                        WHERE (c.agent_id = a.id)) ch ON (true));

alter table call_center.cc_email_profile add column token jsonb;

drop VIEW call_center.cc_email_profile_list;
CREATE VIEW call_center.cc_email_profile_list AS
SELECT t.id,
       t.domain_id,
       call_center.cc_view_timestamp(t.created_at) AS created_at,
       call_center.cc_get_lookup(t.created_by, (cc.name)::character varying) AS created_by,
       call_center.cc_view_timestamp(t.updated_at) AS updated_at,
       call_center.cc_get_lookup(t.updated_by, (cu.name)::character varying) AS updated_by,
       call_center.cc_view_timestamp(t.last_activity_at) AS activity_at,
       t.name,
       t.imap_host,
       t.smtp_host,
       t.login,
       t.mailbox,
       t.smtp_port,
       t.imap_port,
       t.fetch_err AS fetch_error,
       t.fetch_interval,
       t.state,
       call_center.cc_get_lookup((t.flow_id)::bigint, s.name) AS schema,
       t.description,
       t.enabled,
       t.password,
       t.listen,
       (((t.token ->> 'expiry'::text) IS NOT NULL) AND ((t.token ->> 'access_token'::text) IS NOT NULL)) AS logged
FROM (((call_center.cc_email_profile t
    LEFT JOIN directory.wbt_user cc ON ((cc.id = t.created_by)))
    LEFT JOIN directory.wbt_user cu ON ((cu.id = t.updated_by)))
    LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.flow_id)));





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
                 WHERE ((c.parent_id IS NULL) AND (hp.parent_id = c.id)))) AS has_children,
       (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), (''::character varying)::text))::character varying AS agent_description,
       c.grantee_id,
       ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
         FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                FROM call_center.cc_calls_history chh
                WHERE ((chh.parent_id = c.id) AND (chh.hold IS NOT NULL))
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
           WHEN (((c.cause)::text = 'ORIGINATOR_CANCEL'::text) OR (((c.cause)::text = 'LOSE_RACE'::text) AND (cq.type = 4))) THEN 'cancelled'::text
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
         WHERE (j.file_id = ANY (f.file_ids))) AS files_job,
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
       (EXISTS ( SELECT 1
                 FROM call_center.cc_calls_history cr
                 WHERE ((cr.id = c.bridged_id) AND (c.bridged_id IS NOT NULL) AND (c.blind_transfer IS NULL) AND (cr.blind_transfer IS NULL) AND (c.transfer_to IS NULL) AND (cr.transfer_to IS NULL) AND (c.transfer_from IS NULL) AND (cr.transfer_from IS NULL) AND (COALESCE(cr.user_id, c.user_id) IS NOT NULL)))) AS allow_evaluation,
       cma.form_fields,
       c.bridged_id,
       call_center.cc_get_lookup(cc.id, (cc.common_name)::character varying) AS contact,
       c.contact_id,
       c.search_number,
       c.hide_missed,
       c.redial_id,
       (lega.bridged_id IS NOT NULL) AS parent_bridged
FROM (((((((((((((((call_center.cc_calls_history c
    LEFT JOIN LATERAL ( SELECT array_agg(f_1.id) AS file_ids,
                               json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at', ((c.params -> 'record_start'::text))::bigint, 'stop_at', ((c.params -> 'record_stop'::text))::bigint)) AS files
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
                               WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) f ON (((c.answered_at IS NOT NULL) OR (c.bridged_at IS NOT NULL))))
    LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
    LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
    LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
    LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
    LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
    LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
    LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
    LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
    LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
    LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND (lega.id = c.parent_id))))
    LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
    LEFT JOIN directory.wbt_user aru ON (((ar.* IS NOT NULL) AND (aru.id = ar.rated_user_id))))
    LEFT JOIN directory.wbt_user arub ON (((ar.* IS NOT NULL) AND (arub.id = ar.created_by))))
    LEFT JOIN contacts.contact cc ON ((cc.id = c.contact_id)));



--
-- Name: cc_team_events; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_team_events (
                                            id integer NOT NULL,
                                            team_id integer NOT NULL,
                                            event character varying NOT NULL,
                                            schema_id integer NOT NULL,
                                            enabled boolean DEFAULT false NOT NULL,
                                            updated_at timestamp with time zone DEFAULT now() NOT NULL,
                                            updated_by bigint NOT NULL
);


--
-- Name: cc_team_events_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_team_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_team_events_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_team_events_id_seq OWNED BY call_center.cc_team_events.id;


--
-- Name: cc_team_events_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_team_events_list AS
SELECT qe.id,
       call_center.cc_get_lookup((qe.schema_id)::bigint, s.name) AS schema,
       qe.event,
       qe.enabled,
       qe.team_id,
       qe.schema_id
FROM (call_center.cc_team_events qe
    LEFT JOIN flow.acr_routing_scheme s ON ((s.id = qe.schema_id)));



drop VIEW if exists call_center.cc_user_status_view;
--
-- Name: cc_user_status_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_user_status_view AS
SELECT u.dc AS domain_id,
       u.id,
       COALESCE(u.name, (u.username)::text) AS name,
       COALESCE(pr.status, '{}'::name[]) AS presence,
       COALESCE(a.status, ''::character varying) AS status,
       COALESCE(u.extension, ''::name) AS extension,
       row_number() OVER (PARTITION BY u.dc ORDER BY
           CASE
               WHEN ((a.status)::text = 'online'::text) THEN 0
               WHEN ((a.status)::text = 'pause'::text) THEN 1
               WHEN ((a.status)::text = 'offline'::text) THEN 2
               ELSE 3
               END, pr.status, COALESCE(u.name, (u.username)::text)) AS "position"
FROM ((directory.wbt_user u
    LEFT JOIN call_center.cc_agent a ON ((a.user_id = u.id)))
    LEFT JOIN LATERAL ( SELECT array_agg(status.open) AS array_agg
                        FROM ( SELECT 'dnd'::name AS "?column?"
                               FROM directory.wbt_user_status stt
                               WHERE ((stt.user_id = u.id) AND stt.dnd)
                               UNION ALL
                               ( SELECT stt.status
                                 FROM directory.wbt_user_presence stt
                                 WHERE ((stt.user_id = u.id) AND (stt.status IS NOT NULL) AND (stt.open > 0))
                                 ORDER BY stt.prior, stt.status)) status(open)) pr(status) ON (true));

--
-- Name: cc_team_events id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_events ALTER COLUMN id SET DEFAULT nextval('call_center.cc_team_events_id_seq'::regclass);

--
-- Name: cc_team_events cc_team_events_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_events
    ADD CONSTRAINT cc_team_events_pk PRIMARY KEY (id);

--
-- Name: cc_team_events_team_id_schema_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_events_team_id_schema_id_uindex ON call_center.cc_team_events USING btree (team_id, schema_id);




--
-- Name: cc_team_events cc_team_events_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_events
    ADD CONSTRAINT cc_team_events_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id);


--
-- Name: cc_team_events cc_team_events_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_events
    ADD CONSTRAINT cc_team_events_cc_team_id_fk FOREIGN KEY (team_id) REFERENCES call_center.cc_team(id) ON DELETE CASCADE;


--
-- Name: cc_team_events cc_team_events_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_events
    ADD CONSTRAINT cc_team_events_wbt_user_id_fk FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;

