--
-- PostgreSQL database dump
--

-- Dumped from database version 12.3 (Debian 12.3-1.pgdg100+1)
-- Dumped by pg_dump version 12.3 (Debian 12.3-1.pgdg100+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: flow; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA flow;


--
-- Name: calendar_accept_time; Type: TYPE; Schema: flow; Owner: -
--

CREATE TYPE flow.calendar_accept_time AS (
	disabled boolean,
	day smallint,
	start_time_of_day smallint,
	end_time_of_day smallint
);


--
-- Name: calendar_except_date; Type: TYPE; Schema: flow; Owner: -
--

CREATE TYPE flow.calendar_except_date AS (
	disabled boolean,
	date bigint,
	name character varying,
	repeat boolean
);


--
-- Name: calendar_accepts_to_jsonb(flow.calendar_accept_time[]); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_accepts_to_jsonb(flow.calendar_accept_time[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $_$
select jsonb_agg(x.r)
    from (
             select row_to_json(a) r
             from unnest($1) a
    ) x;
$_$;


--
-- Name: calendar_check_timing(bigint, integer, character varying); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_check_timing(domain_id_ bigint, calendar_id_ integer, name_ character varying) RETURNS record
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
                                 to_char((current_timestamp AT TIME ZONE ct.name)::date, 'MM-DD') =
                                 to_char((to_timestamp(x.date / 1000) at time zone ct.name)::date, 'MM-DD')
                         else
                                 (current_timestamp AT TIME ZONE ct.name)::date =
                                 (to_timestamp(x.date / 1000) at time zone ct.name)::date
                   end
               limit 1
           )                     excepted,
           exists(
                   select 1
                   from unnest(c.accepts) as x
                   where not x.disabled is true
                     and x.day + 1 = extract(isodow from current_timestamp AT TIME ZONE ct.name)::int
                     and (to_char(current_timestamp AT TIME ZONE ct.name, 'SSSS') :: int / 60) between x.start_time_of_day and x.end_time_of_day
               )                 accept,
           case
               when c.start_at > 0 and c.end_at > 0 then
                   not current_date AT TIME ZONE ct.name between (to_timestamp(c.start_at / 1000) at time zone ct.name)::date and (to_timestamp(c.end_at / 1000) at time zone ct.name)::date
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
-- Name: calendar_json_to_accepts(jsonb); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_json_to_accepts(jsonb) RETURNS flow.calendar_accept_time[]
    LANGUAGE sql IMMUTABLE
    AS $_$
select array(
       select row ((x -> 'disabled')::bool, (x -> 'day')::smallint, (x -> 'start_time_of_day')::smallint, (x -> 'end_time_of_day')::smallint)::flow.calendar_accept_time
       from jsonb_array_elements($1) x
       order by x -> 'day', x -> 'start_time_of_day'
   )::flow.calendar_accept_time[]
$_$;


--
-- Name: calendar_json_to_excepts(jsonb); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_json_to_excepts(jsonb) RETURNS flow.calendar_except_date[]
    LANGUAGE sql IMMUTABLE
    AS $_$
select array(
       select row ((x -> 'disabled')::bool, (x -> 'date')::int8, (x ->> 'name')::varchar, (x -> 'repeat')::bool)::flow.calendar_except_date
       from jsonb_array_elements($1) x
       order by x -> 'date'
   )::flow.calendar_except_date[]
$_$;


--
-- Name: set_rbac_rec(); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.set_rbac_rec() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
BEGIN
        execute 'insert into ' || (TG_ARGV[0])::text ||' (dc, object, grantor, subject, access)
        select t.dc, $1, t.grantor, t.subject, t.access
        from (
            select u.dc, u.id grantor, u.id subject, 255 as access
            from directory.wbt_user u
            where u.id = $2
            union all
            select rm.dc, rm.member_id, rm.role_id, 68
            from directory.wbt_auth_member rm
            where rm.member_id = $2
        ) t'
        using NEW.id, NEW.created_by;
        RETURN NEW;
    END;
$_$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: acr_routing_scheme; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.acr_routing_scheme (
    id bigint NOT NULL,
    domain_id bigint NOT NULL,
    name character varying(100) NOT NULL,
    scheme jsonb NOT NULL,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint NOT NULL,
    updated_at bigint NOT NULL,
    updated_by bigint NOT NULL,
    description character varying(200) DEFAULT ''::character varying NOT NULL,
    debug boolean DEFAULT false NOT NULL,
    state smallint,
    type character varying DEFAULT 'call'::character varying NOT NULL
);


--
-- Name: COLUMN acr_routing_scheme.state; Type: COMMENT; Schema: flow; Owner: -
--

COMMENT ON COLUMN flow.acr_routing_scheme.state IS 'draft / new / used';


--
-- Name: calendar; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.calendar (
    id integer NOT NULL,
    start_at bigint,
    end_at bigint,
    name character varying(20) NOT NULL,
    domain_id bigint NOT NULL,
    description character varying(200),
    timezone_id integer NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint NOT NULL,
    updated_at bigint NOT NULL,
    updated_by bigint NOT NULL,
    excepts flow.calendar_except_date[],
    accepts flow.calendar_accept_time[]
);


--
-- Name: acr_routing_outbound_call; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.acr_routing_outbound_call (
    id bigint NOT NULL,
    domain_id bigint NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(200) DEFAULT ''::character varying NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint NOT NULL,
    updated_at bigint NOT NULL,
    updated_by bigint NOT NULL,
    pattern character varying(50) NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    disabled boolean DEFAULT false,
    scheme_id bigint NOT NULL,
    pos integer NOT NULL
);


--
-- Name: acr_routing_outbound_call_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.acr_routing_outbound_call_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: acr_routing_outbound_call_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.acr_routing_outbound_call_id_seq OWNED BY flow.acr_routing_outbound_call.id;


--
-- Name: acr_routing_outbound_call_pos_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.acr_routing_outbound_call_pos_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: acr_routing_outbound_call_pos_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.acr_routing_outbound_call_pos_seq OWNED BY flow.acr_routing_outbound_call.pos;


--
-- Name: acr_routing_scheme_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.acr_routing_scheme_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: acr_routing_scheme_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.acr_routing_scheme_id_seq OWNED BY flow.acr_routing_scheme.id;


--
-- Name: acr_routing_variables; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.acr_routing_variables (
    id bigint NOT NULL,
    domain_id bigint NOT NULL,
    key character varying(20) NOT NULL,
    value character varying(100) DEFAULT ''::character varying NOT NULL
);


--
-- Name: acr_routing_variables_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.acr_routing_variables_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: acr_routing_variables_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.acr_routing_variables_id_seq OWNED BY flow.acr_routing_variables.id;


--
-- Name: calendar_acl; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.calendar_acl (
    dc bigint NOT NULL,
    object bigint NOT NULL,
    grantor bigint NOT NULL,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL
);


--
-- Name: calendar_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.calendar_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: calendar_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.calendar_id_seq OWNED BY flow.calendar.id;


--
-- Name: calendar_timezones; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.calendar_timezones (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    utc_offset interval NOT NULL,
    offset_id smallint NOT NULL
);


--
-- Name: calendar_intervals; Type: MATERIALIZED VIEW; Schema: flow; Owner: -
--

CREATE MATERIALIZED VIEW flow.calendar_intervals AS
 SELECT row_number() OVER (ORDER BY calendar_timezones.utc_offset) AS id,
    calendar_timezones.utc_offset
   FROM flow.calendar_timezones
  GROUP BY calendar_timezones.utc_offset
  ORDER BY calendar_timezones.utc_offset
  WITH NO DATA;


--
-- Name: calendar_timezone_offsets; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.calendar_timezone_offsets (
    id smallint NOT NULL,
    utc_offset interval,
    names text[]
);


--
-- Name: calendar_timezones_by_interval; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.calendar_timezones_by_interval (
    id bigint,
    utc_offset interval,
    names character varying[]
);


--
-- Name: calendar_timezones_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.calendar_timezones_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: calendar_timezones_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.calendar_timezones_id_seq OWNED BY flow.calendar_timezones.id;


--
-- Name: acr_routing_outbound_call id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call ALTER COLUMN id SET DEFAULT nextval('flow.acr_routing_outbound_call_id_seq'::regclass);


--
-- Name: acr_routing_outbound_call pos; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call ALTER COLUMN pos SET DEFAULT nextval('flow.acr_routing_outbound_call_pos_seq'::regclass);


--
-- Name: acr_routing_scheme id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_scheme ALTER COLUMN id SET DEFAULT nextval('flow.acr_routing_scheme_id_seq'::regclass);


--
-- Name: acr_routing_variables id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_variables ALTER COLUMN id SET DEFAULT nextval('flow.acr_routing_variables_id_seq'::regclass);


--
-- Name: calendar id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar ALTER COLUMN id SET DEFAULT nextval('flow.calendar_id_seq'::regclass);


--
-- Name: calendar_timezones id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_timezones ALTER COLUMN id SET DEFAULT nextval('flow.calendar_timezones_id_seq'::regclass);


--
-- Name: acr_routing_outbound_call acr_routing_outbound_call_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call
    ADD CONSTRAINT acr_routing_outbound_call_pk PRIMARY KEY (id);


--
-- Name: acr_routing_scheme acr_routing_scheme_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_pk PRIMARY KEY (id);


--
-- Name: acr_routing_variables acr_routing_variables_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_variables
    ADD CONSTRAINT acr_routing_variables_pk PRIMARY KEY (id);


--
-- Name: calendar calendar_pkey; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar
    ADD CONSTRAINT calendar_pkey PRIMARY KEY (id);


--
-- Name: calendar_timezones calendar_timezones_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_timezones
    ADD CONSTRAINT calendar_timezones_pk PRIMARY KEY (name);


--
-- Name: acr_routing_outbound_call_created_by_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX acr_routing_outbound_call_created_by_index ON flow.acr_routing_outbound_call USING btree (created_by);


--
-- Name: acr_routing_outbound_call_domain_id_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX acr_routing_outbound_call_domain_id_name_uindex ON flow.acr_routing_outbound_call USING btree (domain_id, name);


--
-- Name: acr_routing_outbound_call_pattern; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX acr_routing_outbound_call_pattern ON flow.acr_routing_outbound_call USING btree (domain_id, pos DESC, id, name, pattern, scheme_id) WHERE (NOT disabled);


--
-- Name: acr_routing_outbound_call_updated_by_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX acr_routing_outbound_call_updated_by_index ON flow.acr_routing_outbound_call USING btree (updated_by);


--
-- Name: acr_routing_scheme_created_by_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX acr_routing_scheme_created_by_index ON flow.acr_routing_scheme USING btree (created_by);


--
-- Name: acr_routing_scheme_domain_id_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX acr_routing_scheme_domain_id_name_uindex ON flow.acr_routing_scheme USING btree (domain_id, name);


--
-- Name: acr_routing_scheme_domain_id_udx; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX acr_routing_scheme_domain_id_udx ON flow.acr_routing_scheme USING btree (id, domain_id);


--
-- Name: acr_routing_scheme_updated_by_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX acr_routing_scheme_updated_by_index ON flow.acr_routing_scheme USING btree (updated_by);


--
-- Name: acr_routing_variables_domain_id_key_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX acr_routing_variables_domain_id_key_uindex ON flow.acr_routing_variables USING btree (domain_id, key);


--
-- Name: calendar_acl_grantor_idx; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX calendar_acl_grantor_idx ON flow.calendar_acl USING btree (grantor);


--
-- Name: calendar_acl_object_subject_udx; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_acl_object_subject_udx ON flow.calendar_acl USING btree (object, subject, access);


--
-- Name: calendar_acl_subject_object_udx; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_acl_subject_object_udx ON flow.calendar_acl USING btree (subject, object, access);


--
-- Name: calendar_created_by_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX calendar_created_by_index ON flow.calendar USING btree (created_by);


--
-- Name: calendar_domain_id_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_domain_id_name_uindex ON flow.calendar USING btree (domain_id, name);


--
-- Name: calendar_domain_udx; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_domain_udx ON flow.calendar USING btree (id, domain_id);


--
-- Name: calendar_timezone_offsets_id_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_timezone_offsets_id_uindex ON flow.calendar_timezone_offsets USING btree (id);


--
-- Name: calendar_timezones_id_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_timezones_id_uindex ON flow.calendar_timezones USING btree (id);


--
-- Name: calendar_timezones_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_timezones_name_uindex ON flow.calendar_timezones USING btree (name);


--
-- Name: calendar_timezones_utc_offset_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_timezones_utc_offset_index ON flow.calendar_timezones USING btree (id, utc_offset, name);


--
-- Name: calendar_updated_by_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX calendar_updated_by_index ON flow.calendar USING btree (updated_by);


--
-- Name: calendar calendar_set_rbac_acl; Type: TRIGGER; Schema: flow; Owner: -
--

CREATE TRIGGER calendar_set_rbac_acl AFTER INSERT ON flow.calendar FOR EACH ROW EXECUTE FUNCTION flow.set_rbac_rec('flow.calendar_acl');


--
-- Name: acr_routing_outbound_call acr_routing_outbound_call_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call
    ADD CONSTRAINT acr_routing_outbound_call_acr_routing_scheme_id_fk FOREIGN KEY (scheme_id) REFERENCES flow.acr_routing_scheme(id);


--
-- Name: acr_routing_outbound_call acr_routing_outbound_call_acr_routing_scheme_id_fk_2; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call
    ADD CONSTRAINT acr_routing_outbound_call_acr_routing_scheme_id_fk_2 FOREIGN KEY (scheme_id) REFERENCES flow.acr_routing_scheme(id);


--
-- Name: acr_routing_outbound_call acr_routing_outbound_call_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call
    ADD CONSTRAINT acr_routing_outbound_call_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: acr_routing_outbound_call acr_routing_outbound_call_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call
    ADD CONSTRAINT acr_routing_outbound_call_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: acr_routing_outbound_call acr_routing_outbound_call_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call
    ADD CONSTRAINT acr_routing_outbound_call_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


--
-- Name: acr_routing_scheme acr_routing_scheme_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: acr_routing_scheme acr_routing_scheme_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: acr_routing_scheme acr_routing_scheme_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


--
-- Name: acr_routing_variables acr_routing_variables_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_variables
    ADD CONSTRAINT acr_routing_variables_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: calendar_acl calendar_acl_domain_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_acl
    ADD CONSTRAINT calendar_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: calendar_acl calendar_acl_grantor_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_acl
    ADD CONSTRAINT calendar_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


--
-- Name: calendar_acl calendar_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_acl
    ADD CONSTRAINT calendar_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: calendar_acl calendar_acl_object_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_acl
    ADD CONSTRAINT calendar_acl_object_fk FOREIGN KEY (object, dc) REFERENCES flow.calendar(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: calendar_acl calendar_acl_subject_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_acl
    ADD CONSTRAINT calendar_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: calendar calendar_calendar_timezones_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar
    ADD CONSTRAINT calendar_calendar_timezones_id_fk FOREIGN KEY (timezone_id) REFERENCES flow.calendar_timezones(id);


--
-- Name: calendar calendar_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar
    ADD CONSTRAINT calendar_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: calendar calendar_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar
    ADD CONSTRAINT calendar_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: calendar calendar_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar
    ADD CONSTRAINT calendar_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


--
-- PostgreSQL database dump complete
--

