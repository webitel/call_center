
--
-- Name: cc_preset_query; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_preset_query (
                                             id integer NOT NULL,
                                             name character varying NOT NULL,
                                             user_id bigint NOT NULL,
                                             created_at timestamp with time zone DEFAULT now() NOT NULL,
                                             preset jsonb NOT NULL,
                                             description character varying,
                                             section character varying NOT NULL,
                                             domain_id bigint NOT NULL,
                                             updated_at timestamp with time zone NOT NULL
);


--
-- Name: cc_preset_query_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_preset_query_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_preset_query_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_preset_query_id_seq OWNED BY call_center.cc_preset_query.id;


--
-- Name: cc_preset_query_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_preset_query_list AS
SELECT p.id,
       p.name,
       p.description,
       p.created_at,
       p.updated_at,
       p.section,
       p.preset,
       p.domain_id,
       p.user_id
FROM call_center.cc_preset_query p;



--
-- Name: cc_preset_query id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_preset_query ALTER COLUMN id SET DEFAULT nextval('call_center.cc_preset_query_id_seq'::regclass);


--
-- Name: cc_preset_query cc_preset_query_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_preset_query
    ADD CONSTRAINT cc_preset_query_pk PRIMARY KEY (id);




--
-- Name: cc_preset_query_user_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_preset_query_user_id_name_uindex ON call_center.cc_preset_query USING btree (user_id, name);


--
-- Name: cc_preset_query cc_preset_query_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_preset_query
    ADD CONSTRAINT cc_preset_query_wbt_user_id_fk FOREIGN KEY (user_id) REFERENCES directory.wbt_user(id) ON DELETE CASCADE;



--
-- Name: cc_audit_form; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_audit_form (
                                           id integer NOT NULL,
                                           domain_id bigint NOT NULL,
                                           name character varying NOT NULL,
                                           description character varying,
                                           enabled boolean DEFAULT false NOT NULL,
                                           created_by bigint,
                                           created_at timestamp with time zone DEFAULT now() NOT NULL,
                                           updated_by bigint NOT NULL,
                                           updated_at timestamp with time zone DEFAULT now(),
                                           questions jsonb,
                                           team_ids integer[],
                                           archive boolean DEFAULT false NOT NULL,
                                           editable boolean DEFAULT true NOT NULL
);


--
-- Name: cc_audit_form_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_audit_form_acl (
                                               id bigint NOT NULL,
                                               dc bigint NOT NULL,
                                               grantor bigint,
                                               object integer NOT NULL,
                                               subject bigint NOT NULL,
                                               access smallint DEFAULT 0 NOT NULL
);


--
-- Name: cc_audit_form_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_audit_form_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_audit_form_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_audit_form_acl_id_seq OWNED BY call_center.cc_audit_form_acl.id;


--
-- Name: cc_audit_form_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_audit_form_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_audit_form_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_audit_form_id_seq OWNED BY call_center.cc_audit_form.id;


--
-- Name: cc_audit_form_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_audit_form_view AS
SELECT i.id,
       i.name,
       i.description,
       i.domain_id,
       i.created_at,
       call_center.cc_get_lookup(uc.id, (uc.name)::character varying) AS created_by,
       i.updated_at,
       call_center.cc_get_lookup(u.id, (u.name)::character varying) AS updated_by,
       ( SELECT jsonb_agg(call_center.cc_get_lookup(aud.id, (aud.name)::character varying)) AS jsonb_agg
         FROM call_center.cc_team aud
         WHERE (aud.id = ANY (i.team_ids))) AS teams,
       i.enabled,
       i.questions,
       i.team_ids,
       i.editable,
       i.archive
FROM ((call_center.cc_audit_form i
    LEFT JOIN directory.wbt_user uc ON ((uc.id = i.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = i.updated_by)));



--
-- Name: cc_audit_form id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form ALTER COLUMN id SET DEFAULT nextval('call_center.cc_audit_form_id_seq'::regclass);


--
-- Name: cc_audit_form_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_audit_form_acl_id_seq'::regclass);




--
-- Name: cc_audit_form_acl cc_audit_form_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl
    ADD CONSTRAINT cc_audit_form_acl_pk PRIMARY KEY (id);


--
-- Name: cc_audit_form cc_audit_form_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form
    ADD CONSTRAINT cc_audit_form_pk PRIMARY KEY (id);


--
-- Name: cc_audit_form_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_audit_form_acl_grantor_idx ON call_center.cc_audit_form_acl USING btree (grantor);


--
-- Name: cc_audit_form_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_audit_form_acl_object_subject_udx ON call_center.cc_audit_form_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_audit_form_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_audit_form_acl_subject_object_udx ON call_center.cc_audit_form_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_audit_form_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_audit_form_domain_id_name_uindex ON call_center.cc_audit_form USING btree (domain_id, name);


--
-- Name: cc_audit_form_id_domain_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_audit_form_id_domain_id_uindex ON call_center.cc_audit_form USING btree (id, domain_id);




--
-- Name: cc_audit_form cc_audit_form_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_audit_form_set_rbac_acl AFTER INSERT ON call_center.cc_audit_form FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_audit_form_acl');



--
-- Name: cc_audit_form_acl cc_audit_form_acl_cc_audit_form_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl
    ADD CONSTRAINT cc_audit_form_acl_cc_audit_form_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_audit_form(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_audit_form_acl cc_audit_form_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl
    ADD CONSTRAINT cc_audit_form_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_audit_form_acl cc_audit_form_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl
    ADD CONSTRAINT cc_audit_form_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_audit_form_acl cc_audit_form_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl
    ADD CONSTRAINT cc_audit_form_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_audit_form_acl cc_audit_form_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl
    ADD CONSTRAINT cc_audit_form_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_audit_form(id, domain_id) ON DELETE CASCADE;


--
-- Name: cc_audit_form_acl cc_audit_form_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl
    ADD CONSTRAINT cc_audit_form_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_audit_form cc_audit_form_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form
    ADD CONSTRAINT cc_audit_form_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_audit_form cc_audit_form_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form
    ADD CONSTRAINT cc_audit_form_wbt_user_id_fk FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_audit_form cc_audit_form_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form
    ADD CONSTRAINT cc_audit_form_wbt_user_id_fk_2 FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;



CREATE TABLE call_center.cc_audit_rate (
                                           id bigint NOT NULL,
                                           domain_id bigint NOT NULL,
                                           form_id integer NOT NULL,
                                           created_at timestamp with time zone NOT NULL,
                                           created_by bigint,
                                           updated_at timestamp with time zone NOT NULL,
                                           updated_by bigint,
                                           answers jsonb,
                                           score_required numeric DEFAULT 0 NOT NULL,
                                           score_optional numeric DEFAULT 0 NOT NULL,
                                           comment text,
                                           call_id character varying,
                                           rated_user_id bigint NOT NULL
);



--
-- Name: cc_audit_rate_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_audit_rate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

--
-- Name: cc_audit_rate_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_audit_rate_id_seq OWNED BY call_center.cc_audit_rate.id;



--
-- Name: cc_audit_rate cc_audit_rate_cc_audit_form_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate
    ADD CONSTRAINT cc_audit_rate_cc_audit_form_id_fk FOREIGN KEY (form_id) REFERENCES call_center.cc_audit_form(id) ON DELETE CASCADE;

--
-- Name: cc_audit_rate_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_audit_rate_view AS
SELECT r.id,
       r.domain_id,
       r.form_id,
       r.created_at,
       call_center.cc_get_lookup(uc.id, COALESCE((uc.name)::character varying, (uc.username)::character varying)) AS created_by,
       r.updated_at,
       call_center.cc_get_lookup(u.id, COALESCE((u.name)::character varying, (u.username)::character varying)) AS updated_by,
       call_center.cc_get_lookup(ur.id, (ur.name)::character varying) AS rated_user,
       call_center.cc_get_lookup((f.id)::bigint, f.name) AS form,
       r.answers,
       r.score_required,
       r.score_optional,
       r.comment,
       r.call_id,
       f.questions,
       r.rated_user_id
FROM ((((call_center.cc_audit_rate r
    LEFT JOIN call_center.cc_audit_form f ON ((f.id = r.form_id)))
    LEFT JOIN directory.wbt_user ur ON ((ur.id = r.rated_user_id)))
    LEFT JOIN directory.wbt_user uc ON ((uc.id = r.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = r.updated_by)));


--
-- Name: cc_audit_rate id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate ALTER COLUMN id SET DEFAULT nextval('call_center.cc_audit_rate_id_seq'::regclass);

--
-- Name: cc_audit_rate cc_audit_rate_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate
    ADD CONSTRAINT cc_audit_rate_pk PRIMARY KEY (id);

--
-- Name: cc_audit_rate_call_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_audit_rate_call_id_uindex ON call_center.cc_audit_rate USING btree (call_id) WHERE (call_id IS NOT NULL);



--
-- Name: cc_audit_rate_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_audit_rate_created_by_index ON call_center.cc_audit_rate USING btree (created_by DESC);


--
-- Name: cc_audit_rate_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_audit_rate_domain_id_index ON call_center.cc_audit_rate USING btree (domain_id);


--
-- Name: cc_audit_rate_form_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_audit_rate_form_id_index ON call_center.cc_audit_rate USING btree (form_id);


--
-- Name: cc_audit_rate_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_audit_rate_updated_by_index ON call_center.cc_audit_rate USING btree (updated_by);



--
-- Name: cc_audit_rate cc_audit_rate_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate
    ADD CONSTRAINT cc_audit_rate_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_audit_rate cc_audit_rate_wbt_domain_dc_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate
    ADD CONSTRAINT cc_audit_rate_wbt_domain_dc_fk_2 FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_audit_rate cc_audit_rate_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate
    ADD CONSTRAINT cc_audit_rate_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_audit_rate cc_audit_rate_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate
    ADD CONSTRAINT cc_audit_rate_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;





drop FUNCTION if exists call_center.cc_attempt_schema_result;
--
-- Name: cc_attempt_schema_result(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb, integer, integer, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_schema_result(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, _per_number boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
AS $$
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
                                (not attempt.result in ('success', 'cancel') and
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                    )
                               then m.stop_at else  attempt.leaving_at end,
            stop_cause = case when next_offering_at_ notnull or
                                   m.stop_at notnull or
                                   (not attempt.result in ('success', 'cancel') and
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
$$;



drop function if exists call_center.cc_attempt_timeout;
--
-- Name: cc_attempt_timeout(bigint, character varying, integer, integer, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_timeout(attempt_id_ bigint, agent_status_ character varying, agent_hold_sec_ integer, max_attempts_ integer DEFAULT 0, per_number_ boolean DEFAULT false, do_leaving_ boolean DEFAULT false) RETURNS timestamp with time zone
    LANGUAGE plpgsql
AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
begin
    update call_center.cc_member_attempt
    set reporting_at = now(),
        result = 'timeout',
        state = 'leaving',
        schema_processing = do_leaving_
    where id = attempt_id_
    returning * into attempt;

    if not do_leaving_  is true then
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
    end if;

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



--
-- Name: cc_wrap_over_dial(numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_wrap_over_dial(over numeric DEFAULT 1, current numeric DEFAULT 0, target numeric DEFAULT 5, maximum numeric DEFAULT 7) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
AS $$
declare dx numeric;
begin
    if current >= maximum then
        return 1;
    end if;

    dx = target - current;
    if dx = 0 then
        return over;
    elseif dx > 0 then
        return over + ( (over * (dx * (10))) / 100 );
    else
        return over + ( -(over * ((maximum - dx))) / 100 );
    end if;
end;
$$;


alter table call_center.cc_member_attempt add column if not exists schema_processing boolean DEFAULT false;



drop FUNCTION if exists call_center.cc_attempt_flip_next_resource;
--
-- Name: cc_attempt_flip_next_resource(bigint, integer[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_flip_next_resource(attempt_id_ bigint, skip_resources integer[]) RETURNS record
    LANGUAGE plpgsql
AS $$
declare destination_ varchar;
        type_id_ int4;
        queue_id_ int4;
        cur_res_id_ int4;

        resource_id_ int4;
        resource_updated_at_ int8;
        gateway_updated_at_ int8;
        allow_call_ bool;
begin
    select a.destination->>'destination', (a.destination->'type'->>'id')::int, a.queue_id, a.resource_id
    from call_center.cc_member_attempt a
    where a.id = attempt_id_
    into destination_, type_id_, queue_id_, cur_res_id_;

    with r as (
        select r.id,
               r.updated_at                                 as resource_updated_at,
               call_center.cc_view_timestamp(gw.updated_at) as gateway_updated_at,
               r."limit" - coalesce(used.cnt, 0) > 0 as allow_call
        from call_center.cc_queue_resource qr
                 inner join call_center.cc_outbound_resource_group rq on rq.id = qr.resource_group_id
                 inner join call_center.cc_outbound_resource_in_group rig on rig.group_id = rq.id
                 inner join call_center.cc_outbound_resource r on r.id = rig.resource_id
                 inner join directory.sip_gateway gw on gw.id = r.gateway_id
                 LEFT JOIN LATERAL ( SELECT count(*) AS cnt
                                     FROM (SELECT 1 AS cnt
                                           FROM call_center.cc_member_attempt c_1
                                           WHERE c_1.resource_id = r.id
                                             AND (c_1.state::text <> ALL
                                                  (ARRAY ['leaving'::character varying::text, 'processing'::character varying::text]))) c) used on true
        where qr.queue_id = queue_id_
          and rq.communication_id = type_id_
          and (array_length(coalesce(r.patterns::text[], '{}'), 1) isnull or exists(select 1 from unnest(r.patterns::text[]) pts
                                                                                    where destination_ similar to regexp_replace(regexp_replace(pts, 'x|X', '_', 'gi'), '\+', '\+', 'gi')))
          and r.enabled
          and not r.id = any(call_center.cc_array_merge(array[cur_res_id_::int], skip_resources))
        order by r."limit" - coalesce(used.cnt, 0) > 0 desc nulls last, rig.priority desc
        limit 1
    )
    update call_center.cc_member_attempt a
    set resource_id = r.id
    from r
    where a.id = attempt_id_
    returning r.id, r.resource_updated_at, r.gateway_updated_at, r.allow_call
        into resource_id_, resource_updated_at_, gateway_updated_at_, allow_call_;

    return row(resource_id_, resource_updated_at_, gateway_updated_at_, allow_call_);
end
$$;



drop FUNCTION if exists call_center.cc_attempt_flip_next_resource;
--
-- Name: cc_attempt_flip_next_resource(bigint, integer[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_flip_next_resource(attempt_id_ bigint, skip_resources integer[]) RETURNS record
    LANGUAGE plpgsql
AS $$
declare destination_ varchar;
        type_id_ int4;
        queue_id_ int4;
        cur_res_id_ int4;

        resource_id_ int4;
        resource_updated_at_ int8;
        gateway_updated_at_ int8;
        allow_call_ bool;
        call_id_ varchar;
begin
    select a.destination->>'destination', (a.destination->'type'->>'id')::int, a.queue_id, a.resource_id
    from call_center.cc_member_attempt a
    where a.id = attempt_id_
    into destination_, type_id_, queue_id_, cur_res_id_;

    with r as (
        select r.id,
               r.updated_at                                 as resource_updated_at,
               call_center.cc_view_timestamp(gw.updated_at) as gateway_updated_at,
               r."limit" - coalesce(used.cnt, 0) > 0 as allow_call
        from call_center.cc_queue_resource qr
                 inner join call_center.cc_outbound_resource_group rq on rq.id = qr.resource_group_id
                 inner join call_center.cc_outbound_resource_in_group rig on rig.group_id = rq.id
                 inner join call_center.cc_outbound_resource r on r.id = rig.resource_id
                 inner join directory.sip_gateway gw on gw.id = r.gateway_id
                 LEFT JOIN LATERAL ( SELECT count(*) AS cnt
                                     FROM (SELECT 1 AS cnt
                                           FROM call_center.cc_member_attempt c_1
                                           WHERE c_1.resource_id = r.id
                                             AND (c_1.state::text <> ALL
                                                  (ARRAY ['leaving'::character varying::text, 'processing'::character varying::text]))) c) used on true
        where qr.queue_id = queue_id_
          and rq.communication_id = type_id_
          and (array_length(coalesce(r.patterns::text[], '{}'), 1) isnull or exists(select 1 from unnest(r.patterns::text[]) pts
                                                                                    where destination_ similar to regexp_replace(regexp_replace(pts, 'x|X', '_', 'gi'), '\+', '\+', 'gi')))
          and r.enabled
          and not r.id = any(call_center.cc_array_merge(array[cur_res_id_::int], skip_resources))
        order by r."limit" - coalesce(used.cnt, 0) > 0 desc nulls last, rig.priority desc
        limit 1
    )
    update call_center.cc_member_attempt a
    set resource_id = r.id,
        member_call_id = uuid_generate_v4()
    from r
    where a.id = attempt_id_
    returning r.id, r.resource_updated_at, r.gateway_updated_at, r.allow_call, a.member_call_id
        into resource_id_, resource_updated_at_, gateway_updated_at_, allow_call_, call_id_;

    return row(resource_id_, resource_updated_at_, gateway_updated_at_, allow_call_, call_id_);
end
$$;



drop VIEW if exists call_center.cc_member_view_attempt_history;
--
-- Name: cc_member_view_attempt_history; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_member_view_attempt_history AS
SELECT t.id,
       t.joined_at,
       t.offering_at,
       t.bridged_at,
       t.reporting_at,
       t.leaving_at,
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
       t.seq AS attempts,
       c.amd_result
FROM ((((((((call_center.cc_member_attempt_history t
    LEFT JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
    LEFT JOIN call_center.cc_member cm ON ((t.member_id = cm.id)))
    LEFT JOIN call_center.cc_agent a ON ((t.agent_id = a.id)))
    LEFT JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (u.dc = a.domain_id))))
    LEFT JOIN call_center.cc_outbound_resource r ON ((r.id = t.resource_id)))
    LEFT JOIN call_center.cc_bucket cb ON ((cb.id = t.bucket_id)))
    LEFT JOIN call_center.cc_list l ON ((l.id = t.list_communication_id)))
    LEFT JOIN call_center.cc_calls_history c ON (((c.domain_id = t.domain_id) AND ((c.id)::text = (t.member_call_id)::text))));





drop VIEW if exists call_center.cc_calls_history_list;
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
       COALESCE(c.amd_result, c.amd_ai_result) AS amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       c.amd_ai_positive,
       cq.type AS queue_type,
       CASE
           WHEN (c.parent_id IS NOT NULL) THEN ''::text
           WHEN ((c.cause)::text = ANY (ARRAY[('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text])) THEN 'not_answered'::text
           WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
           WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
               CASE
                   WHEN (((c.cause)::text = 'NORMAL_CLEARING'::text) AND ((((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND (c.user_id IS NOT NULL)) OR (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (c.bridged_at IS NOT NULL)) OR (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (cq.type = ANY (ARRAY[4, 5])) AND (c.bridged_at IS NOT NULL)))) THEN 'agent_dropped'::text
                   WHEN ((c.bridged_at IS NULL) AND ((c.hangup_by)::text = 'B'::text)) THEN 'ended'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END AS hangup_disposition,
       c.blind_transfer,
       ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error, 'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
         FROM storage.file_jobs j
         WHERE (j.file_id = ANY (f.file_ids))) AS files_job,
       transcripts.data AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
       ar.id AS rate_id,
       call_center.cc_get_lookup(aru.id, COALESCE((aru.name)::character varying, (aru.username)::character varying)) AS rated_user,
       call_center.cc_get_lookup(arub.id, COALESCE((arub.name)::character varying, (arub.username)::character varying)) AS rated_by,
       ar.score_optional,
       ar.score_required
FROM ((((((((((((((((call_center.cc_calls_history c
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
    LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
    LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))))
    LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id, 'file', call_center.cc_get_lookup(ff.id, ff.name))) AS data
                        FROM (storage.file_transcript tr
                            LEFT JOIN storage.files ff ON ((ff.id = tr.file_id)))
                        WHERE ((tr.uuid)::text = ((c.id)::character varying(50))::text)
                        GROUP BY (tr.uuid)::text) transcripts ON (true))
    LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
    LEFT JOIN directory.wbt_user aru ON ((aru.id = ar.rated_user_id)))
    LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by)));



update call_center.cc_queue_events e
set enabled = false
from (
         select *, row_number() over (partition by queue_id, event) rn
         from call_center.cc_queue_events
         where enabled
     ) t
where t.rn > 1 and t.id = e.id;

create unique index cc_queue_events_queue_id_event_uindex
    on call_center.cc_queue_events (queue_id, event) where enabled;




drop VIEW if exists call_center.cc_calls_history_list;
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
       COALESCE(c.amd_result, c.amd_ai_result) AS amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       c.amd_ai_positive,
       cq.type AS queue_type,
       CASE
           WHEN (c.parent_id IS NOT NULL) THEN ''::text
           WHEN ((c.cause)::text = ANY (ARRAY[('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text])) THEN 'not_answered'::text
           WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
           WHEN ((c.hangup_by)::text = 'F'::text) THEN 'ended'::text
           WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
               CASE
                   WHEN (((c.cause)::text = 'NORMAL_CLEARING'::text) AND ((((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND (c.user_id IS NOT NULL)) OR (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (c.bridged_at IS NOT NULL)) OR (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (cq.type = ANY (ARRAY[4, 5])) AND (c.bridged_at IS NOT NULL)))) THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END AS hangup_disposition,
       c.blind_transfer,
       ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error, 'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
         FROM storage.file_jobs j
         WHERE (j.file_id = ANY (f.file_ids))) AS files_job,
       transcripts.data AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
       ar.id AS rate_id,
       call_center.cc_get_lookup(aru.id, COALESCE((aru.name)::character varying, (aru.username)::character varying)) AS rated_user,
       call_center.cc_get_lookup(arub.id, COALESCE((arub.name)::character varying, (arub.username)::character varying)) AS rated_by,
       ar.score_optional,
       ar.score_required
FROM ((((((((((((((((call_center.cc_calls_history c
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
    LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
    LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))))
    LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id, 'file', call_center.cc_get_lookup(ff.id, ff.name))) AS data
                        FROM (storage.file_transcript tr
                            LEFT JOIN storage.files ff ON ((ff.id = tr.file_id)))
                        WHERE ((tr.uuid)::text = ((c.id)::character varying(50))::text)
                        GROUP BY (tr.uuid)::text) transcripts ON (true))
    LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
    LEFT JOIN directory.wbt_user aru ON ((aru.id = ar.rated_user_id)))
    LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by)));



drop VIEW if exists call_center.cc_member_view_attempt;
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



--
-- Name: cc_calls_history_gateway_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX concurrently cc_calls_history_gateway_id_index ON call_center.cc_calls_history USING btree (gateway_id) WHERE (gateway_id IS NOT NULL);




drop VIEW if exists call_center.cc_calls_history_list;

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
       COALESCE(c.amd_result, c.amd_ai_result) AS amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       c.amd_ai_positive,
       cq.type AS queue_type,
       CASE
           WHEN (c.parent_id IS NOT NULL) THEN ''::text
           WHEN ((c.cause)::text = ANY (ARRAY[('USER_BUSY'::character varying)::text, ('NO_ANSWER'::character varying)::text])) THEN 'not_answered'::text
           WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
           WHEN ((c.hangup_by)::text = 'F'::text) THEN 'ended'::text
           WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
               CASE
                   WHEN ((((c.cause)::text = 'NORMAL_CLEARING'::text) AND (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND (c.user_id IS NOT NULL))) OR (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (c.bridged_at IS NOT NULL)) OR (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (cq.type = ANY (ARRAY[4, 5, 1])) AND (c.bridged_at IS NOT NULL))) THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END AS hangup_disposition,
       c.blind_transfer,
       ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error, 'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
         FROM storage.file_jobs j
         WHERE (j.file_id = ANY (f.file_ids))) AS files_job,
       transcripts.data AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
       ar.id AS rate_id,
       call_center.cc_get_lookup(aru.id, COALESCE((aru.name)::character varying, (aru.username)::character varying)) AS rated_user,
       call_center.cc_get_lookup(arub.id, COALESCE((arub.name)::character varying, (arub.username)::character varying)) AS rated_by,
       ar.score_optional,
       ar.score_required
FROM ((((((((((((((((call_center.cc_calls_history c
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
    LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
    LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))))
    LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id, 'file', call_center.cc_get_lookup(ff.id, ff.name))) AS data
                        FROM (storage.file_transcript tr
                            LEFT JOIN storage.files ff ON ((ff.id = tr.file_id)))
                        WHERE ((tr.uuid)::text = ((c.id)::character varying(50))::text)
                        GROUP BY (tr.uuid)::text) transcripts ON (true))
    LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
    LEFT JOIN directory.wbt_user aru ON ((aru.id = ar.rated_user_id)))
    LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by)));





drop VIEW if exists call_center.cc_skill_in_agent_view;
--
-- Name: cc_skill_in_agent_view; Type: VIEW; Schema: call_center; Owner: -
--
CREATE VIEW call_center.cc_skill_in_agent_view AS
SELECT sa.id,
       call_center.cc_get_lookup(c.id, (c.name)::character varying) AS created_by,
       sa.created_at,
       call_center.cc_get_lookup(u.id, (u.name)::character varying) AS updated_by,
       sa.updated_at,
       call_center.cc_get_lookup((cs.id)::bigint, cs.name) AS skill,
       call_center.cc_get_lookup((ca.id)::bigint, (COALESCE(uu.name, (uu.username)::text))::character varying) AS agent,
       call_center.cc_get_lookup(t.id, t.name) AS team,
       sa.capacity,
       sa.enabled,
       ca.domain_id,
       sa.skill_id,
       cs.name AS skill_name,
       sa.agent_id,
       COALESCE(u.name, (u.username)::text) AS agent_name
FROM ((((((call_center.cc_skill_in_agent sa
    LEFT JOIN call_center.cc_agent ca ON ((sa.agent_id = ca.id)))
    LEFT JOIN call_center.cc_team t ON ((t.id = ca.team_id)))
    LEFT JOIN directory.wbt_user uu ON ((uu.id = ca.user_id)))
    LEFT JOIN call_center.cc_skill cs ON ((sa.skill_id = cs.id)))
    LEFT JOIN directory.wbt_user c ON ((c.id = sa.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = sa.updated_by)));


drop VIEW if exists call_center.cc_skill_view;
--
-- Name: cc_skill_view; Type: VIEW; Schema: call_center; Owner: -
--
CREATE VIEW call_center.cc_skill_view AS
SELECT c.id,
       c.name,
       c.description,
       c.domain_id,
       ( SELECT count(DISTINCT sa.agent_id) AS count
         FROM call_center.cc_skill_in_agent sa
         WHERE ((sa.skill_id = c.id) AND sa.enabled)) AS agents
FROM call_center.cc_skill c;




drop FUNCTION if exists call_center.cc_calls_rbac_users_from_group;

CREATE FUNCTION call_center.rbac_users_from_group(_class_name varchar, _domain_id bigint, _access smallint, _groups integer[]) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
AS $$
select array_agg(distinct am.member_id::int)
from directory.wbt_class c
         inner join directory.wbt_default_acl a on a.object = c.id
         join directory.wbt_auth_member am on am.role_id = a.grantor
where c.name = _class_name
  and c.dc = _domain_id
  and a.access&_access = _access and a.subject = any(_groups)
$$;




/* 3467  */
drop materialized view if exists call_center.cc_distribute_stats;
drop view if exists  call_center.cc_member_view_attempt_history;
drop view if exists  call_center.cc_calls_history_list;
drop materialized view if exists  call_center.cc_agent_today_stats;

drop  view if exists call_center.cc_call_active_list ;
drop procedure if exists call_center.cc_call_set_bridged;

ALTER TABLE call_center.cc_calls_history ALTER COLUMN id type uuid USING id::uuid;
ALTER TABLE call_center.cc_calls_history ALTER COLUMN parent_id type uuid USING parent_id::uuid;
ALTER TABLE call_center.cc_calls_history ALTER COLUMN bridged_id type uuid USING bridged_id::uuid;
ALTER TABLE call_center.cc_calls_history ALTER COLUMN transfer_from type uuid USING transfer_from::uuid;
ALTER TABLE call_center.cc_calls_history ALTER COLUMN transfer_to type uuid USING transfer_to::uuid;

ALTER TABLE call_center.cc_calls ALTER COLUMN id type uuid USING id::uuid;
ALTER TABLE call_center.cc_calls ALTER COLUMN parent_id type uuid USING parent_id::uuid;
ALTER TABLE call_center.cc_calls ALTER COLUMN bridged_id type uuid USING bridged_id::uuid;
ALTER TABLE call_center.cc_calls ALTER COLUMN transfer_from type uuid USING transfer_from::uuid;
ALTER TABLE call_center.cc_calls ALTER COLUMN transfer_to type uuid USING transfer_to::uuid;


create materialized view call_center.cc_distribute_stats as
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
       s.over_dial,
       s.abandoned_rate,
       s.hit_rate,
       s.agents,
       s.aggent_ids
FROM call_center.cc_queue q
         LEFT JOIN LATERAL ( SELECT CASE
                                        WHEN ((q.payload -> 'amd'::text) -> 'allow_not_sure'::text)::boolean IS TRUE
                                            THEN ARRAY ['HUMAN'::text, 'NOTSURE'::text]
                                        ELSE ARRAY ['HUMAN'::text]
                                        END AS arr) amd ON true
         JOIN LATERAL ( SELECT att.queue_id,
                               att.bucket_id,
                               min(att.joined_at)                                                                     AS start_stat,
                               max(att.joined_at)                                                                     AS stop_stat,
                               count(*)                                                                               AS call_attempts,
                               COALESCE(avg(date_part('epoch'::text,
                                                      COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))
                                        FILTER (WHERE att.bridged_at IS NOT NULL),
                                        0::double precision)                                                          AS avg_handle,
                               COALESCE(avg(DISTINCT round(date_part('epoch'::text,
                                                                     COALESCE(att.reporting_at, att.leaving_at) -
                                                                     att.offering_at))::real)
                                        FILTER (WHERE att.bridged_at IS NOT NULL),
                                        0::double precision)                                                          AS med_handle,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL),
                                        0::double precision)                                                          AS avg_member_answer,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL AND ch.bridged_at IS NULL),
                                        0::double precision)                                                          AS avg_member_answer_not_bridged,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL AND ch.bridged_at IS NOT NULL),
                                        0::double precision)                                                          AS avg_member_answer_bridged,
                               COALESCE(max(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL),
                                        0::double precision)                                                          AS max_member_answer,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)                   AS connected_calls,
                               count(*) FILTER (WHERE att.bridged_at IS NOT NULL)                                     AS bridged_calls,
                               count(*)
                               FILTER (WHERE ch.answered_at IS NOT NULL AND att.bridged_at IS NULL AND amd_res.human) AS abandoned_calls,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)::double precision /
                               count(*)::double precision                                                             AS connection_rate,
                               CASE
                                   WHEN (count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)::double precision /
                                         count(*)::double precision) > 0::double precision THEN 1::double precision /
                                                                                                (count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)::double precision /
                                                                                                 count(*)::double precision)
                                   ELSE (count(*) / GREATEST(count(DISTINCT att.agent_id), 1::bigint) - 1)::double precision
                                   END                                                                                AS over_dial,
                               COALESCE((count(*)
                                         FILTER (WHERE ch.answered_at IS NOT NULL AND att.bridged_at IS NULL AND amd_res.human)::double precision -
                                         COALESCE((q.payload -> 'abandon_rate_adjustment'::text)::integer,
                                                  0)::double precision) /
                                        NULLIF(count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human),
                                               0)::double precision * 100::double precision,
                                        0::double precision)                                                          AS abandoned_rate,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)::double precision /
                               count(*)::double precision                                                             AS hit_rate,
                               count(DISTINCT att.agent_id)                                                           AS agents,
                               array_agg(DISTINCT att.agent_id)
                               FILTER (WHERE att.agent_id IS NOT NULL)                                                AS aggent_ids
                        FROM call_center.cc_member_attempt_history att
                                 LEFT JOIN call_center.cc_calls_history ch
                                           ON ch.domain_id = att.domain_id AND ch.id::uuid = att.member_call_id::uuid
                                 LEFT JOIN LATERAL ( SELECT ch.amd_result IS NULL AND ch.amd_ai_positive IS NULL OR
                                                            (ch.amd_result::text = ANY (amd.arr)) OR
                                                            ch.amd_ai_positive IS TRUE AS human) amd_res ON true
                        WHERE att.channel::text = 'call'::text
                          AND att.joined_at > (now() - ((COALESCE((q.payload -> 'statistic_time'::text)::integer, 60) ||
                                                         ' min'::text)::interval))
                          AND att.queue_id = q.id
                          AND att.domain_id = q.domain_id
                        GROUP BY att.queue_id, att.bucket_id) s ON s.queue_id IS NOT NULL
WHERE q.type = 5
  AND q.enabled;

create unique index cc_distribute_stats_uidx
    on call_center.cc_distribute_stats (queue_id, bucket_id);

refresh materialized view call_center.cc_distribute_stats;


create view call_center.cc_member_view_attempt_history
            (id, joined_at, offering_at, bridged_at, reporting_at, leaving_at, channel, queue, member, member_call_id,
             variables, agent, agent_call_id, position, resource, bucket, list, display, destination, result, domain_id,
             queue_id, bucket_id, member_id, agent_id, attempts, amd_result)
as
SELECT t.id,
       t.joined_at,
       t.offering_at,
       t.bridged_at,
       t.reporting_at,
       t.leaving_at,
       t.channel,
       call_center.cc_get_lookup(t.queue_id::bigint, cq.name)                                               AS queue,
       call_center.cc_get_lookup(t.member_id, cm.name)                                                      AS member,
       t.member_call_id,
       COALESCE(cm.variables, '{}'::jsonb)                                                                  AS variables,
       call_center.cc_get_lookup(t.agent_id::bigint, COALESCE(u.name, u.username::text)::character varying) AS agent,
       t.agent_call_id,
       t.weight                                                                                             AS "position",
       call_center.cc_get_lookup(t.resource_id::bigint, r.name)                                             AS resource,
       call_center.cc_get_lookup(t.bucket_id, cb.name::character varying)                                   AS bucket,
       call_center.cc_get_lookup(t.list_communication_id, l.name)                                           AS list,
       COALESCE(t.display, ''::character varying)                                                           AS display,
       t.destination,
       t.result,
       t.domain_id,
       t.queue_id,
       t.bucket_id,
       t.member_id,
       t.agent_id,
       t.seq                                                                                                AS attempts,
       c.amd_result
FROM call_center.cc_member_attempt_history t
         LEFT JOIN call_center.cc_queue cq ON t.queue_id = cq.id
         LEFT JOIN call_center.cc_member cm ON t.member_id = cm.id
         LEFT JOIN call_center.cc_agent a ON t.agent_id = a.id
         LEFT JOIN directory.wbt_user u ON u.id = a.user_id AND u.dc = a.domain_id
         LEFT JOIN call_center.cc_outbound_resource r ON r.id = t.resource_id
         LEFT JOIN call_center.cc_bucket cb ON cb.id = t.bucket_id
         LEFT JOIN call_center.cc_list l ON l.id = t.list_communication_id
         LEFT JOIN call_center.cc_calls_history c ON c.domain_id = t.domain_id AND c.id::text = t.member_call_id::text;


create or replace view call_center.cc_calls_history_list
as
SELECT c.id,
       c.app_id,
       'call'::character varying                                                                                    AS type,
       c.parent_id,
       c.transfer_from,
       CASE
           WHEN c.parent_id IS NOT NULL AND c.transfer_to IS NULL AND c.id::text <> lega.bridged_id::text
               THEN lega.bridged_id
           ELSE c.transfer_to
           END                                                                                                      AS transfer_to,
       call_center.cc_get_lookup(u.id,
                                 COALESCE(u.name, u.username::text)::character varying)                             AS "user",
       CASE
           WHEN cq.type = ANY (ARRAY [4, 5]) THEN cag.extension
           ELSE u.extension
           END                                                                                                      AS extension,
       call_center.cc_get_lookup(gw.id, gw.name)                                                                    AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number',
                         COALESCE(c.from_number, ''::character varying), 'id',
                         COALESCE(c.from_id, ''::character varying), 'name',
                         COALESCE(c.from_name, ''::character varying))                                              AS "from",
       json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number',
                         COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying),
                         'name',
                         COALESCE(c.to_name, ''::character varying))                                                AS "to",
       c.payload                                                                                                    AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       c.stored_at,
       COALESCE(c.hangup_by, ''::character varying)                                                                 AS hangup_by,
       c.cause,
       date_part('epoch'::text, c.hangup_at - c.created_at)::bigint                                                 AS duration,
       COALESCE(c.hold_sec, 0)                                                                                      AS hold_sec,
       COALESCE(
               CASE
                   WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.answered_at - c.created_at)::bigint
                   ELSE date_part('epoch'::text, c.hangup_at - c.created_at)::bigint
                   END,
               0::bigint)                                                                                           AS wait_sec,
       CASE
           WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.hangup_at - c.answered_at)::bigint
           ELSE 0::bigint
           END                                                                                                      AS bill_sec,
       c.sip_code,
       f.files,
       call_center.cc_get_lookup(cq.id::bigint, cq.name)                                                            AS queue,
       call_center.cc_get_lookup(cm.id::bigint, cm.name)                                                            AS member,
       call_center.cc_get_lookup(ct.id, ct.name)                                                                    AS team,
       call_center.cc_get_lookup(aa.id::bigint,
                                 COALESCE(cag.username, cag.name::name)::character varying)                         AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at                                                                                               AS queue_bridged_at,
       CASE
           WHEN cma.bridged_at IS NOT NULL THEN date_part('epoch'::text, cma.bridged_at - cma.joined_at)::integer
           ELSE date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer
           END                                                                                                      AS queue_wait_sec,
       date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer                                            AS queue_duration_sec,
       cma.result,
       CASE
           WHEN cma.reporting_at IS NOT NULL THEN date_part('epoch'::text, cma.reporting_at - cma.leaving_at)::integer
           ELSE 0
           END                                                                                                      AS reporting_sec,
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
               WHERE c.parent_id IS NULL
                 AND hp.parent_id::uuid = c.id::uuid))                                                              AS has_children,
       COALESCE(regexp_replace(cma.description::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text),
                ''::character varying::text)::character varying                                                     AS agent_description,
       c.grantee_id,
       holds.res                                                                                                    AS hold,
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
                                               COALESCE(cc.name, cc.username::text)::character varying)        AS created_by,
                     a.updated_at,
                     call_center.cc_get_lookup(uc.id,
                                               COALESCE(uc.name, uc.username::text)::character varying)        AS updated_by,
                     a.note,
                     a.start_sec,
                     a.end_sec
              FROM call_center.cc_calls_annotation a
                       LEFT JOIN directory.wbt_user cc ON cc.id = a.created_by
                       LEFT JOIN directory.wbt_user uc ON uc.id = a.updated_by
              WHERE a.call_id::text = c.id::text
              ORDER BY a.created_at DESC) annotations)                                                              AS annotations,
       COALESCE(c.amd_result, c.amd_ai_result)                                                                      AS amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       c.amd_ai_positive,
       cq.type                                                                                                      AS queue_type,
       CASE
           WHEN c.parent_id IS NOT NULL THEN ''::text
           WHEN c.cause::text = ANY (ARRAY ['USER_BUSY'::character varying::text, 'NO_ANSWER'::character varying::text])
               THEN 'not_answered'::text
           WHEN c.cause::text = 'ORIGINATOR_CANCEL'::text OR c.cause::text = 'LOSE_RACE'::text AND cq.type = 4
               THEN 'cancelled'::text
           WHEN c.hangup_by::text = 'F'::text THEN 'ended'::text
           WHEN c.cause::text = 'NORMAL_CLEARING'::text THEN
               CASE
                   WHEN c.cause::text = 'NORMAL_CLEARING'::text AND c.direction::text = 'outbound'::text AND
                        c.hangup_by::text = 'A'::text AND c.user_id IS NOT NULL OR
                        c.direction::text = 'inbound'::text AND c.hangup_by::text = 'B'::text AND
                        c.bridged_at IS NOT NULL OR
                        c.direction::text = 'outbound'::text AND c.hangup_by::text = 'B'::text AND
                        (cq.type = ANY (ARRAY [4, 5, 1])) AND c.bridged_at IS NOT NULL THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END                                                                                                      AS hangup_disposition,
       c.blind_transfer,
       (SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at),
                                           'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error,
                                           'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
        FROM storage.file_jobs j
        WHERE j.file_id = ANY (f.file_ids))                                                                         AS files_job,
       transcripts.data                                                                                             AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, au.name::character varying)                                                 AS grantee,
       ar.id                                                                                                        AS rate_id,
       call_center.cc_get_lookup(aru.id, COALESCE(aru.name::character varying,
                                                  aru.username::character varying))                                 AS rated_user,
       call_center.cc_get_lookup(arub.id, COALESCE(arub.name::character varying,
                                                   arub.username::character varying))                               AS rated_by,
       ar.score_optional,
       ar.score_required
FROM call_center.cc_calls_history c
         LEFT JOIN LATERAL ( SELECT array_agg(f_1.id)                                                       AS file_ids,
                                    json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size,
                                                                'mime_type', f_1.mime_type, 'start_at',
                                                                (c.params -> 'record_start'::text)::bigint, 'stop_at',
                                                                (c.params -> 'record_stop'::text)::bigint)) AS files
                             FROM (SELECT f1.id,
                                          f1.size,
                                          f1.mime_type,
                                          f1.name
                                   FROM storage.files f1
                                   WHERE f1.domain_id = c.domain_id
                                     AND NOT f1.removed IS TRUE
                                     AND f1.uuid::text = c.id::text
                                   UNION ALL
                                   SELECT f1.id,
                                          f1.size,
                                          f1.mime_type,
                                          f1.name
                                   FROM storage.files f1
                                   WHERE f1.domain_id = c.domain_id
                                     AND NOT f1.removed IS TRUE
                                     AND f1.uuid::text = c.parent_id::text) f_1) f
                   ON c.answered_at IS NOT NULL OR c.bridged_at IS NOT NULL
         LEFT JOIN LATERAL ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
                             FROM (SELECT jsonb_array_elements(chh.hold) AS hi
                                   FROM call_center.cc_calls_history chh
                                   WHERE chh.parent_id::uuid = c.id::uuid
                                     AND chh.hold IS NOT NULL
                                   UNION
                                   SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
                             WHERE x.hi IS NOT NULL) holds ON c.parent_id IS NULL
         LEFT JOIN call_center.cc_queue cq ON c.queue_id = cq.id
         LEFT JOIN call_center.cc_team ct ON c.team_id = ct.id
         LEFT JOIN call_center.cc_member cm ON c.member_id = cm.id
         LEFT JOIN call_center.cc_member_attempt_history cma ON cma.id = c.attempt_id
         LEFT JOIN call_center.cc_agent aa ON cma.agent_id = aa.id
         LEFT JOIN directory.wbt_user cag ON cag.id = aa.user_id
         LEFT JOIN directory.wbt_user u ON u.id = c.user_id
         LEFT JOIN directory.sip_gateway gw ON gw.id = c.gateway_id
         LEFT JOIN directory.wbt_auth au ON au.id = c.grantee_id
         LEFT JOIN call_center.cc_calls_history lega ON c.parent_id IS NOT NULL AND lega.id::uuid = c.parent_id::uuid
         LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id,
                                                               'file',
                                                               call_center.cc_get_lookup(ff.id, ff.name))) AS data
                             FROM storage.file_transcript tr
                                      LEFT JOIN storage.files ff ON ff.id = tr.file_id
                             WHERE tr.uuid::text = c.id::text
                             GROUP BY (tr.uuid::text)) transcripts ON true
         LEFT JOIN call_center.cc_audit_rate ar ON ar.call_id::text = c.id::text
         LEFT JOIN directory.wbt_user aru ON aru.id = ar.rated_user_id
         LEFT JOIN directory.wbt_user arub ON arub.id = ar.created_by;



create materialized view call_center.cc_agent_today_stats as
WITH agents AS MATERIALIZED (SELECT a_1.id,
                                    a_1.user_id,
                                    CASE
                                        WHEN a_1.last_state_change < d."from"::timestamp with time zone
                                            THEN d."from"::timestamp with time zone
                                        WHEN a_1.last_state_change < d."to" THEN a_1.last_state_change
                                        ELSE a_1.last_state_change
                                        END                                          AS cur_state_change,
                                    a_1.status,
                                    a_1.status_payload,
                                    a_1.last_state_change,
                                    lasts.last_at::timestamp with time zone          AS last_at,
                                    lasts.state                                      AS last_state,
                                    lasts.status_payload                             AS last_payload,
                                    COALESCE(top.top_at, a_1.last_state_change)      AS top_at,
                                    COALESCE(top.state, a_1.status)                  AS top_state,
                                    COALESCE(top.status_payload, a_1.status_payload) AS top_payload,
                                    d."from",
                                    d."to",
                                    a_1.domain_id,
                                    COALESCE(t.sys_name, 'UTC'::text)                AS tz_name
                             FROM call_center.cc_agent a_1
                                      LEFT JOIN flow.region r ON r.id = a_1.region_id
                                      LEFT JOIN flow.calendar_timezones t ON t.id = r.timezone_id
                                      LEFT JOIN LATERAL ( SELECT now()                                                                                           AS "to",
                                                                 now()::date + age(now(),
                                                                                   timezone(COALESCE(t.sys_name, 'UTC'::text), now())::timestamp with time zone) AS "from") d
                                                ON true
                                      LEFT JOIN LATERAL ( SELECT aa.state,
                                                                 d."from"   AS last_at,
                                                                 aa.payload AS status_payload
                                                          FROM call_center.cc_agent_state_history aa
                                                          WHERE aa.agent_id = a_1.id
                                                            AND aa.channel IS NULL
                                                            AND (aa.state::text = ANY
                                                                 (ARRAY ['pause'::character varying::text, 'online'::character varying::text, 'offline'::character varying::text]))
                                                            AND aa.joined_at < d."from"::timestamp with time zone
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
                    sum(h.reporting_at - h.leaving_at - ((q.processing_sec || 's'::text)::interval))
                    FILTER (WHERE h.reporting_at IS NOT NULL AND q.processing AND (h.reporting_at - h.leaving_at) >
                                                                                  (((q.processing_sec + 1) || 's'::text)::interval)) AS tpause
             FROM agents
                      JOIN call_center.cc_member_attempt_history h ON h.agent_id = agents.id
                      LEFT JOIN call_center.cc_queue q ON q.id = h.queue_id
             WHERE h.domain_id = agents.domain_id
               AND h.joined_at >= agents."from"::timestamp with time zone
               AND h.joined_at <= agents."to"
               AND h.channel::text = 'call'::text
             GROUP BY h.agent_id),
     chats AS (SELECT cma.agent_id,
                      count(*) FILTER (WHERE cma.bridged_at IS NOT NULL) AS chat_accepts,
                      avg(EXTRACT(epoch FROM COALESCE(cma.reporting_at, cma.leaving_at) - cma.bridged_at))
                      FILTER (WHERE cma.bridged_at IS NOT NULL)::bigint  AS chat_aht
               FROM agents
                        JOIN call_center.cc_member_attempt_history cma ON cma.agent_id = agents.id
               WHERE cma.joined_at >= agents."from"::timestamp with time zone
                 AND cma.joined_at <= agents."to"
                 AND cma.domain_id = agents.domain_id
                 AND cma.bridged_at IS NOT NULL
                 AND cma.channel::text = 'chat'::text
               GROUP BY cma.agent_id),
     calls AS (SELECT h.user_id,
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text)                                                                               AS all_inb,
                      count(*) FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                          AS handled,
                      count(*)
                      FILTER (WHERE h.direction::text = 'inbound'::text AND h.bridged_at IS NOT NULL)                                                           AS inbound_bridged,
                      count(*)
                      FILTER (WHERE cq.type = 1 AND h.bridged_at IS NOT NULL AND h.parent_id IS NOT NULL)                                                       AS "inbound queue",
                      count(*)
                      FILTER (WHERE h.direction::text = 'inbound'::text AND h.queue_id IS NULL)                                                                 AS "direct inbound",
                      count(*)
                      FILTER (WHERE h.parent_id IS NOT NULL AND h.bridged_at IS NOT NULL AND h.queue_id IS NULL AND
                                    pc.user_id IS NOT NULL)                                                                                                     AS internal_inb,
                      count(*) FILTER (WHERE (h.direction::text = 'inbound'::text OR cq.type = 3) AND
                                             h.bridged_at IS NULL)                                                                                              AS missed,
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text AND h.bridged_at IS NULL AND
                                             h.queue_id IS NOT NULL AND (h.cause::text = ANY
                                                                         (ARRAY ['NO_ANSWER'::character varying::text, 'USER_BUSY'::character varying::text]))) AS abandoned,
                      count(*)
                      FILTER (WHERE (cq.type = ANY (ARRAY [0::smallint, 3::smallint, 4::smallint, 5::smallint])) AND
                                    h.bridged_at IS NOT NULL)                                                                                                   AS outbound_queue,
                      count(*) FILTER (WHERE h.parent_id IS NULL AND h.direction::text = 'outbound'::text AND
                                             h.queue_id IS NULL)                                                                                                AS "direct outboud",
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
                      sum(cc.reporting_at - cc.leaving_at)
                      FILTER (WHERE cc.reporting_at IS NOT NULL)                                                                                                AS "Post call"
               FROM agents
                        JOIN call_center.cc_calls_history h ON h.user_id = agents.user_id
                        LEFT JOIN call_center.cc_queue cq ON h.queue_id = cq.id
                        LEFT JOIN call_center.cc_member_attempt_history cc ON cc.agent_call_id::text = h.id::text
                        LEFT JOIN call_center.cc_calls_history pc ON pc.id::uuid = h.parent_id::uuid
               WHERE h.domain_id = agents.domain_id
                 AND h.created_at >= agents."from"::timestamp with time zone
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
              WHERE ar.created_at >=
                    (date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) AT TIME ZONE a_1.tz_name)
                AND ar.created_at <= ((date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) + '1 mon'::interval -
                                       '1 day 00:00:01'::interval) AT TIME ZONE a_1.tz_name)
              GROUP BY a_1.user_id)
SELECT a.id                                                        AS agent_id,
       a.domain_id,
       COALESCE(c.missed, 0::bigint)                               AS call_missed,
       COALESCE(c.abandoned, 0::bigint)                            AS call_abandoned,
       COALESCE(c.inbound_bridged, 0::bigint)                      AS call_inbound,
       COALESCE(c.handled, 0::bigint)                              AS call_handled,
       COALESCE(EXTRACT(epoch FROM c.avg_talk)::bigint, 0::bigint) AS avg_talk_sec,
       COALESCE(EXTRACT(epoch FROM c.avg_hold)::bigint, 0::bigint) AS avg_hold_sec,
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
                               END, 0::numeric), 2), 100::numeric) AS occupancy,
       round(COALESCE(
                     CASE
                         WHEN stats.online > '00:00:00'::interval THEN
                                     EXTRACT(epoch FROM stats.online - COALESCE(stats.pause, '00:00:00'::interval)) /
                                     EXTRACT(epoch FROM stats.online) * 100::numeric
                         ELSE 0::numeric
                         END, 0::numeric), 2)                      AS utilization,
       COALESCE(ch.chat_aht, 0::bigint)                            AS chat_aht,
       COALESCE(ch.chat_accepts, 0::bigint)                        AS chat_accepts,
       COALESCE(rate.count, 0::bigint)                             AS score_count,
       COALESCE(rate.score_optional_avg, 0::numeric)               AS score_optional_avg,
       COALESCE(rate.score_optional_sum, 0::bigint::numeric)       AS score_optional_sum,
       COALESCE(rate.score_required_avg, 0::numeric)               AS score_required_avg,
       COALESCE(rate.score_required_sum, 0::bigint::numeric)       AS score_required_sum
FROM agents a
         LEFT JOIN call_center.cc_agent_with_user u ON u.id = a.id
         LEFT JOIN stats ON stats.agent_id = a.id
         LEFT JOIN eff ON eff.agent_id = a.id
         LEFT JOIN calls c ON c.user_id = a.user_id
         LEFT JOIN chats ch ON ch.agent_id = a.id
         LEFT JOIN rate ON rate.user_id = a.user_id;


create unique index cc_agent_today_stats_uidx
    on call_center.cc_agent_today_stats (agent_id);

refresh materialized view call_center.cc_agent_today_stats;


create view call_center.cc_call_active_list
as
SELECT c.id,
       c.app_id,
       c.state,
       c."timestamp",
       'call'::character varying                                                              AS type,
       c.parent_id,
       call_center.cc_get_lookup(u.id, COALESCE(u.name, u.username::text)::character varying) AS "user",
       u.extension,
       call_center.cc_get_lookup(gw.id, gw.name)                                              AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number',
                         COALESCE(c.from_number, ''::character varying), 'id',
                         COALESCE(c.from_id, ''::character varying), 'name',
                         COALESCE(c.from_name, ''::character varying))                        AS "from",
       CASE
           WHEN c.to_number::text <> ''::text THEN json_build_object('type', COALESCE(c.to_type, ''::character varying),
                                                                     'number',
                                                                     COALESCE(c.to_number, ''::character varying), 'id',
                                                                     COALESCE(c.to_id, ''::character varying), 'name',
                                                                     COALESCE(c.to_name, ''::character varying))
           ELSE NULL::json
           END                                                                                AS "to",
       CASE
           WHEN c.payload IS NULL THEN '{}'::jsonb
           ELSE c.payload
           END                                                                                AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       date_part('epoch'::text, now() - c.created_at)::bigint                                 AS duration,
       COALESCE(c.hold_sec, 0)                                                                AS hold_sec,
       COALESCE(
               CASE
                   WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.answered_at - c.created_at)::bigint
                   ELSE date_part('epoch'::text, now() - c.created_at)::bigint
                   END, 0::bigint)                                                            AS wait_sec,
       CASE
           WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, now() - c.answered_at)::bigint
           ELSE 0::bigint
           END                                                                                AS bill_sec,
       call_center.cc_get_lookup(cq.id::bigint, cq.name)                                      AS queue,
       call_center.cc_get_lookup(cm.id::bigint, cm.name)                                      AS member,
       call_center.cc_get_lookup(ct.id, ct.name)                                              AS team,
       ca."user"                                                                              AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at                                                                         AS queue_bridged_at,
       CASE
           WHEN cma.bridged_at IS NOT NULL THEN date_part('epoch'::text, cma.bridged_at - cma.joined_at)::integer
           ELSE date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer
           END                                                                                AS queue_wait_sec,
       date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer                      AS queue_duration_sec,
       cma.result,
       CASE
           WHEN cma.reporting_at IS NOT NULL THEN date_part('epoch'::text, cma.reporting_at - now())::integer
           ELSE 0
           END                                                                                AS reporting_sec,
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
       cma.display,
       (SELECT jsonb_agg(sag."user") AS jsonb_agg
        FROM call_center.cc_agent_with_user sag
        WHERE sag.id = ANY (aa.supervisor_ids))                                               AS supervisor,
       aa.supervisor_ids,
       c.grantee_id,
       c.hold,
       c.blind_transfer
FROM call_center.cc_calls c
         LEFT JOIN call_center.cc_queue cq ON c.queue_id = cq.id
         LEFT JOIN call_center.cc_team ct ON c.team_id = ct.id
         LEFT JOIN call_center.cc_member cm ON c.member_id = cm.id
         LEFT JOIN call_center.cc_member_attempt cma ON cma.id = c.attempt_id
         LEFT JOIN call_center.cc_agent_with_user ca ON cma.agent_id = ca.id
         LEFT JOIN call_center.cc_agent aa ON aa.user_id = c.user_id
         LEFT JOIN directory.wbt_user u ON u.id = c.user_id
         LEFT JOIN directory.sip_gateway gw ON gw.id = c.gateway_id
WHERE c.hangup_at IS NULL
  AND c.direction IS NOT NULL;


create procedure call_center.cc_call_set_bridged(IN call_id_ uuid, IN state_ character varying, IN timestamp_ timestamp with time zone, IN app_id_ character varying, IN domain_id_ bigint, IN call_bridged_id_ uuid)
    language plpgsql
as
$$
declare
    transfer_to_ uuid;
    transfer_from_ uuid;
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



create or replace function call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer) returns record
    language plpgsql
as
$$
declare
    _domain_id int8;
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;

    _call record;
    _attempt record;

    _a_status varchar;
    _a_channel varchar;
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
    ELSIF _call.direction <> 'outbound' then
        _number = _call.from_number;
    else
        _number = _call.destination;
    end if;

    select
        a.team_id,
        t.updated_at,
        a.status,
        cac.channel,
        a.domain_id,
        (a.updated_at - extract(epoch from u.updated_at))::int8,
        exists (select 1 from call_center.cc_calls c where c.user_id = a.user_id and c.queue_id isnull and c.hangup_at isnull ) busy_ext
    from call_center.cc_agent a
             inner join call_center.cc_team t on t.id = a.team_id
             inner join call_center.cc_agent_channel cac on a.id = cac.agent_id
             inner join directory.wbt_user u on u.id = a.user_id
    where a.id = _agent_id -- check attempt
      and length(coalesce(u.extension, '')) > 0
        for update
    into _team_id_,
        _team_updated_at,
        _a_status,
        _a_channel,
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

    if not _a_channel isnull  then
        raise exception 'agent is busy';
    end if;

    if _busy_ext then
        raise exception 'agent has external call';
    end if;


    insert into call_center.cc_member_attempt (domain_id, state, team_id, member_call_id, destination, node_id, agent_id, parent_id)
    values (_domain_id, 'waiting', _team_id_, _call_id, jsonb_build_object('destination', _number),
            _node_name, _agent_id, _call.attempt_id)
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
        call_center.cc_view_timestamp(_call.created_at)::int8
        );
END;
$$;


create or replace function call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) returns record
    language plpgsql
as
$$
declare
    _timezone_id             int4;
    _discard_abandoned_after int4;
    _weight                  int4;
    dnc_list_id_
                             int4;
    _domain_id               int8;
    _calendar_id             int4;
    _queue_updated_at        int8;
    _team_updated_at         int8;
    _team_id_                int;
    _list_comm_id            int8;
    _enabled                 bool;
    _q_type                  smallint;
    _sticky                  bool;
    _call                    record;
    _attempt                 record;
    _number                  varchar;
    _max_waiting_size        int;
    _grantee_id              int8;
BEGIN
    select c.timezone_id,
           (payload ->> 'discard_abandoned_after')::int discard_abandoned_after,
           c.domain_id,
           q.dnc_list_id,
           q.calendar_id,
           q.updated_at,
           ct.updated_at,
           q.team_id,
           q.enabled,
           q.type,
           q.sticky_agent,
           (payload ->> 'max_waiting_size')::int        max_size,
           q.grantee_id
    from call_center.cc_queue q
             inner join flow.calendar c on q.calendar_id = c.id
             left join call_center.cc_team ct on q.team_id = ct.id
    where q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _grantee_id;

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
    else
        _number = _call.destination;
    end if;

--   raise  exception '%', _number;


    if
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
                        and a.status = 'online'
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
                                               parent_id)
    values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id,
            jsonb_build_object('destination', _number),
            _node_name, _sticky_agent_id, null, _call.attempt_id)
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


vacuum analyze call_center.cc_calls_history;
vacuum full call_center.cc_calls;




drop view call_center.cc_calls_history_list;
create view call_center.cc_calls_history_list
as
SELECT c.id,
       c.app_id,
       'call'::character varying                                                                                    AS type,
       c.parent_id,
       c.transfer_from,
       CASE
           WHEN c.parent_id IS NOT NULL AND c.transfer_to IS NULL AND c.id::text <> lega.bridged_id::text
               THEN lega.bridged_id
           ELSE c.transfer_to
           END                                                                                                      AS transfer_to,
       call_center.cc_get_lookup(u.id,
                                 COALESCE(u.name, u.username::text)::character varying)                             AS "user",
       CASE
           WHEN cq.type = ANY (ARRAY [4, 5]) THEN cag.extension
           ELSE u.extension
           END                                                                                                      AS extension,
       call_center.cc_get_lookup(gw.id, gw.name)                                                                    AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number',
                         COALESCE(c.from_number, ''::character varying), 'id',
                         COALESCE(c.from_id, ''::character varying), 'name',
                         COALESCE(c.from_name, ''::character varying))                                              AS "from",
       json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number',
                         COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying),
                         'name',
                         COALESCE(c.to_name, ''::character varying))                                                AS "to",
       c.payload                                                                                                    AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       c.stored_at,
       COALESCE(c.hangup_by, ''::character varying)                                                                 AS hangup_by,
       c.cause,
       date_part('epoch'::text, c.hangup_at - c.created_at)::bigint                                                 AS duration,
       COALESCE(c.hold_sec, 0)                                                                                      AS hold_sec,
       COALESCE(
               CASE
                   WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.answered_at - c.created_at)::bigint
                   ELSE date_part('epoch'::text, c.hangup_at - c.created_at)::bigint
                   END,
               0::bigint)                                                                                           AS wait_sec,
       CASE
           WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.hangup_at - c.answered_at)::bigint
           ELSE 0::bigint
           END                                                                                                      AS bill_sec,
       c.sip_code,
       f.files,
       call_center.cc_get_lookup(cq.id::bigint, cq.name)                                                            AS queue,
       call_center.cc_get_lookup(cm.id::bigint, cm.name)                                                            AS member,
       call_center.cc_get_lookup(ct.id, ct.name)                                                                    AS team,
       call_center.cc_get_lookup(aa.id::bigint,
                                 COALESCE(cag.username, cag.name::name)::character varying)                         AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at                                                                                               AS queue_bridged_at,
       CASE
           WHEN cma.bridged_at IS NOT NULL THEN date_part('epoch'::text, cma.bridged_at - cma.joined_at)::integer
           ELSE date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer
           END                                                                                                      AS queue_wait_sec,
       date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer                                            AS queue_duration_sec,
       cma.result,
       CASE
           WHEN cma.reporting_at IS NOT NULL THEN date_part('epoch'::text, cma.reporting_at - cma.leaving_at)::integer
           ELSE 0
           END                                                                                                      AS reporting_sec,
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
               WHERE c.parent_id IS NULL
                 AND hp.parent_id = c.id))                                                                          AS has_children,
       COALESCE(regexp_replace(cma.description::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text),
                ''::character varying::text)::character varying                                                     AS agent_description,
       c.grantee_id,
       (SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
        FROM (SELECT jsonb_array_elements(chh.hold) AS hi
              FROM call_center.cc_calls_history chh
              WHERE chh.parent_id = c.id
                AND chh.hold IS NOT NULL
              UNION
              SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
        WHERE x.hi IS NOT NULL)                                                                                     AS hold,
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
                                               COALESCE(cc.name, cc.username::text)::character varying)        AS created_by,
                     a.updated_at,
                     call_center.cc_get_lookup(uc.id,
                                               COALESCE(uc.name, uc.username::text)::character varying)        AS updated_by,
                     a.note,
                     a.start_sec,
                     a.end_sec
              FROM call_center.cc_calls_annotation a
                       LEFT JOIN directory.wbt_user cc ON cc.id = a.created_by
                       LEFT JOIN directory.wbt_user uc ON uc.id = a.updated_by
              WHERE a.call_id::text = c.id::text
              ORDER BY a.created_at DESC) annotations)                                                              AS annotations,
       COALESCE(c.amd_result, c.amd_ai_result)                                                                      AS amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       c.amd_ai_positive,
       cq.type                                                                                                      AS queue_type,
       CASE
           WHEN c.parent_id IS NOT NULL THEN ''::text
           WHEN c.cause::text = ANY (ARRAY ['USER_BUSY'::character varying::text, 'NO_ANSWER'::character varying::text])
               THEN 'not_answered'::text
           WHEN c.cause::text = 'ORIGINATOR_CANCEL'::text OR c.cause::text = 'LOSE_RACE'::text AND cq.type = 4
               THEN 'cancelled'::text
           WHEN c.hangup_by::text = 'F'::text THEN 'ended'::text
           WHEN c.cause::text = 'NORMAL_CLEARING'::text THEN
               CASE
                   WHEN c.cause::text = 'NORMAL_CLEARING'::text AND c.direction::text = 'outbound'::text AND
                        c.hangup_by::text = 'A'::text AND c.user_id IS NOT NULL OR
                        c.direction::text = 'inbound'::text AND c.hangup_by::text = 'B'::text AND
                        c.bridged_at IS NOT NULL OR
                        c.direction::text = 'outbound'::text AND c.hangup_by::text = 'B'::text AND
                        (cq.type = ANY (ARRAY [4, 5, 1])) AND c.bridged_at IS NOT NULL THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END                                                                                                      AS hangup_disposition,
       c.blind_transfer,
       (SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at),
                                           'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error,
                                           'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
        FROM storage.file_jobs j
        WHERE j.file_id = ANY (f.file_ids))                                                                         AS files_job,
       (SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id, 'file',
                                          call_center.cc_get_lookup(ff.id, ff.name))) AS data
        FROM storage.file_transcript tr
                 LEFT JOIN storage.files ff ON ff.id = tr.file_id
        WHERE tr.uuid::text = c.id::text
        GROUP BY (tr.uuid::text))                                                                                   AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, au.name::character varying)                                                 AS grantee,
       ar.id                                                                                                        AS rate_id,
       call_center.cc_get_lookup(aru.id, COALESCE(aru.name::character varying,
                                                  aru.username::character varying))                                 AS rated_user,
       call_center.cc_get_lookup(arub.id, COALESCE(arub.name::character varying,
                                                   arub.username::character varying))                               AS rated_by,
       ar.score_optional,
       ar.score_required,
       (exists(select 1
               from call_center.cc_calls_history cr
               where cr.id = c.bridged_id::uuid and c.bridged_id notnull  and coalesce(cr.user_id, c.user_id) notnull )) as  allow_evaluation
FROM call_center.cc_calls_history c
         LEFT JOIN LATERAL ( SELECT array_agg(f_1.id)                                                       AS file_ids,
                                    json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size,
                                                                'mime_type', f_1.mime_type, 'start_at',
                                                                (c.params -> 'record_start'::text)::bigint, 'stop_at',
                                                                (c.params -> 'record_stop'::text)::bigint)) AS files
                             FROM (SELECT f1.id,
                                          f1.size,
                                          f1.mime_type,
                                          f1.name
                                   FROM storage.files f1
                                   WHERE f1.domain_id = c.domain_id
                                     AND NOT f1.removed IS TRUE
                                     AND f1.uuid::text = c.id::text
                                   UNION ALL
                                   SELECT f1.id,
                                          f1.size,
                                          f1.mime_type,
                                          f1.name
                                   FROM storage.files f1
                                   WHERE f1.domain_id = c.domain_id
                                     AND NOT f1.removed IS TRUE
                                     AND f1.uuid::text = c.parent_id::text) f_1) f
                   ON c.answered_at IS NOT NULL OR c.bridged_at IS NOT NULL
         LEFT JOIN call_center.cc_queue cq ON c.queue_id = cq.id
         LEFT JOIN call_center.cc_team ct ON c.team_id = ct.id
         LEFT JOIN call_center.cc_member cm ON c.member_id = cm.id
         LEFT JOIN call_center.cc_member_attempt_history cma ON cma.id = c.attempt_id
         LEFT JOIN call_center.cc_agent aa ON cma.agent_id = aa.id
         LEFT JOIN directory.wbt_user cag ON cag.id = aa.user_id
         LEFT JOIN directory.wbt_user u ON u.id = c.user_id
         LEFT JOIN directory.sip_gateway gw ON gw.id = c.gateway_id
         LEFT JOIN directory.wbt_auth au ON au.id = c.grantee_id
         LEFT JOIN call_center.cc_calls_history lega ON c.parent_id IS NOT NULL AND lega.id = c.parent_id
         LEFT JOIN call_center.cc_audit_rate ar ON ar.call_id::text = c.id::text
         LEFT JOIN directory.wbt_user aru ON aru.id = ar.rated_user_id
         LEFT JOIN directory.wbt_user arub ON arub.id = ar.created_by;




drop function if exists call_center.cc_calls_history_drop_partition;
--
-- Name: cc_calls_history_drop_partition(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_calls_history_drop_partition() RETURNS void
    LANGUAGE plpgsql
AS $$
declare
    r record;
    sql varchar;
begin
    for r in (SELECT table_name
              FROM information_schema.tables
              WHERE table_schema = 'call_center'
                and table_name ilike 'cc_calls_history_%')
        loop
            sql = format('drop table call_center.%s', r.table_name);
            execute sql;
--             raise notice '%', sql;
        end loop;

end;
$$;



drop function if exists call_center.cc_calls_history_populate_partition;

--
-- Name: cc_calls_history_populate_partition(date, date); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_calls_history_populate_partition(from_date date, to_date date) RETURNS void
    LANGUAGE plpgsql
AS $$
declare
    r record;
    sql varchar;
begin
    for r in (select x::date::text x1, (x::date + interval '1month')::date x2,
                     replace(x::date::text, '-', '_') || '_' || replace((x::date + interval '1month')::date::text, '-', '_') as suff_name
              from generate_series(from_date, to_date, interval '1 month') x
              where not exists(SELECT table_name
                               FROM information_schema.tables
                               WHERE table_schema = 'call_center'
                                 and table_name = 'cc_calls_history_' || replace(x::date::text, '-', '_') || '_' || replace((x::date + interval '1month')::date::text, '-', '_') ))
        loop
            sql = format('create table call_center.cc_calls_history_%s
partition of call_center.cc_calls_history
for values from (%s) to (%s)', r.suff_name,
                         quote_literal(r.x1),
                         quote_literal(r.x2)
                );
            execute sql;
            raise notice '%', sql;
        end loop;

end;
$$;






drop view if exists call_center.cc_calls_history_list;

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
                 WHERE ((cr.id = c.bridged_id) AND (c.bridged_id IS NOT NULL) AND (COALESCE(cr.user_id, c.user_id) IS NOT NULL)))) AS allow_evaluation
FROM ((((((((((((((call_center.cc_calls_history c
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
    LEFT JOIN directory.wbt_user aru ON ((aru.id = ar.rated_user_id)))
    LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by)));





drop view if exists call_center.cc_member_view_attempt_history;
--
-- Name: cc_member_view_attempt_history; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_member_view_attempt_history AS
SELECT t.id,
       t.joined_at,
       t.offering_at,
       t.bridged_at,
       t.reporting_at,
       t.leaving_at,
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
       t.seq AS attempts,
       c.amd_result
FROM ((((((((call_center.cc_member_attempt_history t
    LEFT JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
    LEFT JOIN call_center.cc_member cm ON ((t.member_id = cm.id)))
    LEFT JOIN call_center.cc_agent a ON ((t.agent_id = a.id)))
    LEFT JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (u.dc = a.domain_id))))
    LEFT JOIN call_center.cc_outbound_resource r ON ((r.id = t.resource_id)))
    LEFT JOIN call_center.cc_bucket cb ON ((cb.id = t.bucket_id)))
    LEFT JOIN call_center.cc_list l ON ((l.id = t.list_communication_id)))
    LEFT JOIN call_center.cc_calls_history c ON (((c.domain_id = t.domain_id) AND (c.id = (t.member_call_id)::uuid))));
