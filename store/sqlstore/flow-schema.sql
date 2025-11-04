--
-- PostgreSQL database dump
--

\restrict yy4caIRs9WnSXCJcHp5gRadVS77hm0sZOoPCaKSUJ32I9CFm5KqP4UI1XU60EaJ

-- Dumped from database version 15.14 (Debian 15.14-1.pgdg12+1)
-- Dumped by pg_dump version 15.14 (Debian 15.14-1.pgdg12+1)

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
	end_time_of_day smallint,
	special boolean
);


--
-- Name: calendar_except_date; Type: TYPE; Schema: flow; Owner: -
--

CREATE TYPE flow.calendar_except_date AS (
	disabled boolean,
	date bigint,
	name character varying,
	repeat boolean,
	work_start integer,
	work_stop integer,
	working boolean
);


--
-- Name: arr_type_to_jsonb(anyarray); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.arr_type_to_jsonb(anyarray) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $_$
select jsonb_agg(row_to_json(a))
    from unnest($1) a;
$_$;


--
-- Name: calendar_accepts_to_jsonb(flow.calendar_accept_time[]); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_accepts_to_jsonb(flow.calendar_accept_time[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $_$
select jsonb_agg(x.r)
from (select row_to_json(a) r
      from unnest($1) a
      where a.special isnull
         or a.special is false) x;
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
-- Name: calendar_day_range(integer, integer); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_day_range(calendar_id integer, days integer) RETURNS SETOF date
    LANGUAGE plpgsql IMMUTABLE
    AS $$
declare i int = 0;
    declare y int = 0;
    declare r record;
    declare d timestamp = null;
begin
        select c.excepts, c.accepts, tz.sys_name
        into r
        from  flow.calendar c
            inner join flow.calendar_timezones tz on tz.id = c.timezone_id
        where c.id = calendar_id
        limit 1
        ;

        while r notnull and i < days and y < 1000 loop
            d = (now() at time zone r.sys_name + (y || 'd')::interval)::timestamp;
            y = y + 1;

            if exists(select 1 from unnest(r.accepts) x
                where not x.disabled and x.day = (extract(isodow from d)  ) - 1)
               and not exists(
                    select 1
                       from unnest(r.excepts) as x
                       where not x.disabled is true
                         and case
                                 when x.repeat is true then
                                         to_char((d AT TIME ZONE r.sys_name)::date, 'MM-DD') =
                                         to_char((to_timestamp(x.date / 1000) at time zone r.sys_name)::date, 'MM-DD')
                                 else
                                         (d AT TIME ZONE r.sys_name)::date =
                                         (to_timestamp(x.date / 1000) at time zone r.sys_name)::date
                           end
                ) then
                i = i + 1;
                return next d::timestamp;
            end if;
        end loop;
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
-- Name: calendar_json_to_accepts(jsonb, jsonb); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_json_to_accepts(jsonb, jsonb) RETURNS flow.calendar_accept_time[]
    LANGUAGE sql IMMUTABLE
    AS $_$
select array(
               select row (disabled, wday, start_time_of_day, end_time_of_day, special)::flow.calendar_accept_time
               from (select (x -> 'disabled')::bool as         disabled,
                            (x -> 'day')::smallint             wday,
                            (x -> 'start_time_of_day')::smallint
                                                               start_time_of_day,
                            (x -> 'end_time_of_day')::smallint end_time_of_day,
                            (false)::bool                      special
                     from jsonb_array_elements($1) x
                     union all
                     select (s -> 'disabled')::bool as         disabled,
                            (s -> 'day')::smallint             wday,
                            (s -> 'start_time_of_day')::smallint
                                                               start_time_of_day,
                            (s -> 'end_time_of_day')::smallint end_time_of_day,
                            (true)::bool                       special
                     from jsonb_array_elements($2) as s) x
               order by x.wday, x.start_time_of_day
       )::flow.calendar_accept_time[]
$_$;


--
-- Name: calendar_json_to_excepts(jsonb); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_json_to_excepts(jsonb) RETURNS flow.calendar_except_date[]
    LANGUAGE sql IMMUTABLE
    AS $_$
select array(
       select row ((x -> 'disabled')::bool, (x -> 'date')::int8, (x ->> 'name')::varchar, (x -> 'repeat')::bool, (x-> 'work_start')::int4, (x-> 'work_stop')::int4, (x-> 'working')::bool)::flow.calendar_except_date
       from jsonb_array_elements($1) x
       order by x -> 'date'
   )::flow.calendar_except_date[]
$_$;


--
-- Name: calendar_specials_to_jsonb(flow.calendar_accept_time[]); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.calendar_specials_to_jsonb(flow.calendar_accept_time[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $_$
select jsonb_agg(x.r)
from (select row_to_json(a) r
      from unnest($1) a
      where a.special is true) x;
$_$;


--
-- Name: get_lookup(bigint, character varying); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.get_lookup(_id bigint, _name character varying) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
    if _id isnull then
        return null;
    else
        return json_build_object('id', _id, 'name', _name)::jsonb;
    end if;
END;
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


--
-- Name: tg_obj_default_rbac(); Type: FUNCTION; Schema: flow; Owner: -
--

CREATE FUNCTION flow.tg_obj_default_rbac() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $_$
BEGIN

    EXECUTE format(
'INSERT INTO %I.%I AS acl (dc, object, grantor, subject, access)
 SELECT $1, $2, rbac.grantor, rbac.subject, rbac.access
   FROM (
    -- NEW object OWNER access SUPER(255) mode (!)
    SELECT $3, $3, (255)::int2
     UNION ALL
    SELECT DISTINCT ON (rbac.subject)
      -- [WHO] grants MAX of WINDOW subset access level
        first_value(rbac.grantor) OVER sub
      -- [WHOM] role/user administrative unit
      , rbac.subject
      -- [GRANT] ALL of WINDOW subset access mode(s)
      , bit_or(rbac.access) OVER sub

      FROM directory.wbt_default_acl AS rbac
      JOIN directory.wbt_class AS oc ON (oc.dc, oc.name) = ($1, %L)
      -- EXISTS( OWNER membership WITH grantor role )
      -- JOIN directory.wbt_auth_member AS sup ON (sup.role_id, sup.member_id) = (rbac.grantor, $3)
     WHERE rbac.object = oc.id
       AND rbac.subject <> $3
        -- EXISTS( OWNER membership WITH grantor user/role )
       AND (rbac.grantor = $3 OR EXISTS(SELECT true
             FROM directory.wbt_auth_member sup
            WHERE sup.member_id = $3
              AND sup.role_id = rbac.grantor
           ))
    WINDOW sub AS (PARTITION BY rbac.subject ORDER BY rbac.access DESC)

   ) AS rbac(grantor, subject, access)',

--   ON CONFLICT (object, subject)
--   DO UPDATE SET
--     grantor = EXCLUDED.grantor,
--     access = EXCLUDED.access',

            tg_table_schema,
            tg_table_name||'_acl',
            tg_argv[0]::name -- objclass: directory.wbt_class.name
        )
    --      :srv,   :oid,   :rid
    USING NEW.domain_id, NEW.id, NEW.created_by;
    -- FOR EACH ROW
    RETURN NEW;

END
$_$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: region; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.region (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    name character varying NOT NULL,
    description character varying,
    timezone_id integer NOT NULL
);


--
-- Name: calendar_timezones; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.calendar_timezones (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    utc_offset interval NOT NULL,
    offset_id smallint NOT NULL,
    sys_name text
);


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
    created_by bigint,
    updated_at bigint NOT NULL,
    updated_by bigint,
    description character varying(200) DEFAULT ''::character varying NOT NULL,
    debug boolean DEFAULT false NOT NULL,
    state smallint,
    type character varying DEFAULT 'voice'::character varying NOT NULL,
    editor boolean DEFAULT false NOT NULL,
    tags character varying[],
    version integer DEFAULT 1 NOT NULL,
    note text
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
    name character varying NOT NULL,
    domain_id bigint NOT NULL,
    description character varying(200),
    timezone_id integer NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint,
    updated_at bigint NOT NULL,
    updated_by bigint,
    excepts flow.calendar_except_date[],
    accepts flow.calendar_accept_time[]
);


--
-- Name: calendar_timezone_offsets; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.calendar_timezone_offsets (
    id smallint NOT NULL,
    utc_offset interval,
    names text[]
);


--
-- Name: acr_chat_plan; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.acr_chat_plan (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    name character varying NOT NULL,
    schema_id integer NOT NULL,
    description text
);


--
-- Name: acr_chat_plan_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.acr_chat_plan_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: acr_chat_plan_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.acr_chat_plan_id_seq OWNED BY flow.acr_chat_plan.id;


--
-- Name: acr_chat_plan_list; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.acr_chat_plan_list AS
 SELECT c.id,
    c.enabled,
    c.name,
    flow.get_lookup(s.id, s.name) AS schema,
    c.description,
    c.domain_id
   FROM (flow.acr_chat_plan c
     LEFT JOIN flow.acr_routing_scheme s ON ((s.id = c.schema_id)));


--
-- Name: acr_routing_outbound_call; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.acr_routing_outbound_call (
    id bigint NOT NULL,
    domain_id bigint NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(200) DEFAULT ''::character varying NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint,
    updated_at bigint NOT NULL,
    updated_by bigint,
    pattern character varying NOT NULL,
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
-- Name: acr_routing_outbound_call_view; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.acr_routing_outbound_call_view AS
 SELECT tmp.id,
    tmp.domain_id,
    tmp.scheme_id AS schema_id,
    tmp.name,
    tmp.description,
    tmp.created_at,
    flow.get_lookup(c.id, (c.name)::character varying) AS created_by,
    flow.get_lookup(u.id, (u.name)::character varying) AS updated_by,
    tmp.pattern,
    tmp.disabled,
    flow.get_lookup(arst.id, arst.name) AS schema,
    row_number() OVER (PARTITION BY tmp.domain_id ORDER BY tmp.pos DESC) AS "position"
   FROM (((flow.acr_routing_outbound_call tmp
     JOIN flow.acr_routing_scheme arst ON ((tmp.scheme_id = arst.id)))
     LEFT JOIN directory.wbt_user c ON ((c.id = tmp.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = tmp.updated_by)));


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
-- Name: acr_routing_scheme_view; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.acr_routing_scheme_view AS
 SELECT s.id,
    s.domain_id,
    s.name,
    s.created_at,
    flow.get_lookup(c.id, (c.name)::character varying) AS created_by,
    s.updated_at,
    flow.get_lookup(u.id, (u.name)::character varying) AS updated_by,
    s.debug,
    s.scheme AS schema,
    s.payload,
    s.type,
    s.editor,
    s.tags
   FROM ((flow.acr_routing_scheme s
     LEFT JOIN directory.wbt_user c ON ((c.id = s.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = s.updated_by)));


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
    grantor bigint,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL,
    id bigint NOT NULL
);


--
-- Name: calendar_acl_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.calendar_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: calendar_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.calendar_acl_id_seq OWNED BY flow.calendar_acl.id;


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
-- Name: calendar_timezones_view; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.calendar_timezones_view AS
 SELECT t.id,
    t.name,
    (t.utc_offset)::text AS "offset"
   FROM flow.calendar_timezones t;


--
-- Name: calendar_view; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.calendar_view AS
 SELECT c.id,
    c.name,
    c.start_at,
    c.end_at,
    c.description,
    c.domain_id,
    flow.get_lookup((ct.id)::bigint, ct.name) AS timezone,
    c.created_at,
    flow.get_lookup(uc.id, (uc.name)::character varying) AS created_by,
    c.updated_at,
    flow.get_lookup(u.id, (u.name)::character varying) AS updated_by,
    flow.calendar_accepts_to_jsonb(c.accepts) AS accepts,
    flow.arr_type_to_jsonb(c.excepts) AS excepts,
    flow.calendar_specials_to_jsonb(c.accepts) AS specials
   FROM (((flow.calendar c
     LEFT JOIN flow.calendar_timezones ct ON ((c.timezone_id = ct.id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = c.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.updated_by)));


--
-- Name: region_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.region_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: region_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.region_id_seq OWNED BY flow.region.id;


--
-- Name: region_list; Type: VIEW; Schema: flow; Owner: -
--

CREATE VIEW flow.region_list AS
 SELECT r.id,
    r.name,
    r.description,
    flow.get_lookup((t.id)::bigint, t.name) AS timezone,
    r.timezone_id,
    r.domain_id
   FROM (flow.region r
     LEFT JOIN flow.calendar_timezones t ON ((t.id = r.timezone_id)));


--
-- Name: scheme_log; Type: TABLE; Schema: flow; Owner: -
--

CREATE TABLE flow.scheme_log (
    id bigint NOT NULL,
    schema_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    log jsonb NOT NULL,
    conn_id character varying(100) NOT NULL
);


--
-- Name: scheme_log_id_seq; Type: SEQUENCE; Schema: flow; Owner: -
--

CREATE SEQUENCE flow.scheme_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: scheme_log_id_seq; Type: SEQUENCE OWNED BY; Schema: flow; Owner: -
--

ALTER SEQUENCE flow.scheme_log_id_seq OWNED BY flow.scheme_log.id;


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

ALTER TABLE ONLY flow.scheme_version REPLICA IDENTITY FULL;


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
-- Name: acr_chat_plan id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_chat_plan ALTER COLUMN id SET DEFAULT nextval('flow.acr_chat_plan_id_seq'::regclass);


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
-- Name: calendar_acl id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_acl ALTER COLUMN id SET DEFAULT nextval('flow.calendar_acl_id_seq'::regclass);


--
-- Name: calendar_timezones id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_timezones ALTER COLUMN id SET DEFAULT nextval('flow.calendar_timezones_id_seq'::regclass);


--
-- Name: region id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.region ALTER COLUMN id SET DEFAULT nextval('flow.region_id_seq'::regclass);


--
-- Name: scheme_log id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_log ALTER COLUMN id SET DEFAULT nextval('flow.scheme_log_id_seq'::regclass);


--
-- Name: scheme_variable id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_variable ALTER COLUMN id SET DEFAULT nextval('flow.scheme_variables_id_seq'::regclass);


--
-- Name: web_hook id; Type: DEFAULT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.web_hook ALTER COLUMN id SET DEFAULT nextval('flow.web_hook_id_seq'::regclass);


--
-- Name: acr_chat_plan acr_chat_plan_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_chat_plan
    ADD CONSTRAINT acr_chat_plan_pk PRIMARY KEY (id);


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
-- Name: calendar_acl calendar_acl_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_acl
    ADD CONSTRAINT calendar_acl_pk PRIMARY KEY (id);


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
-- Name: calendar_timezones calendar_timezones_pk_2; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar_timezones
    ADD CONSTRAINT calendar_timezones_pk_2 UNIQUE (id);


--
-- Name: region region_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.region
    ADD CONSTRAINT region_pk PRIMARY KEY (id);


--
-- Name: scheme_log scheme_log_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_log
    ADD CONSTRAINT scheme_log_pk PRIMARY KEY (id);


--
-- Name: scheme_variable scheme_variables_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.scheme_variable
    ADD CONSTRAINT scheme_variables_pk PRIMARY KEY (id);


--
-- Name: web_hook web_hook_pk; Type: CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.web_hook
    ADD CONSTRAINT web_hook_pk PRIMARY KEY (id);


--
-- Name: acr_chat_plan_domain_id_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX acr_chat_plan_domain_id_name_uindex ON flow.acr_chat_plan USING btree (domain_id, name);


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

CREATE UNIQUE INDEX calendar_acl_object_subject_udx ON flow.calendar_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: calendar_acl_subject_object_udx; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_acl_subject_object_udx ON flow.calendar_acl USING btree (subject, object) INCLUDE (access);


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
-- Name: calendar_timezones_sys_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_timezones_sys_name_uindex ON flow.calendar_timezones USING btree (sys_name);


--
-- Name: calendar_timezones_utc_offset_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX calendar_timezones_utc_offset_index ON flow.calendar_timezones USING btree (id, utc_offset, name);


--
-- Name: calendar_updated_by_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX calendar_updated_by_index ON flow.calendar USING btree (updated_by);


--
-- Name: region_domain_id_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX region_domain_id_name_uindex ON flow.region USING btree (domain_id, name);


--
-- Name: scheme_log_conn_id_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX scheme_log_conn_id_uindex ON flow.scheme_log USING btree (conn_id);


--
-- Name: scheme_variables_domain_id_name_uindex; Type: INDEX; Schema: flow; Owner: -
--

CREATE UNIQUE INDEX scheme_variables_domain_id_name_uindex ON flow.scheme_variable USING btree (domain_id, name);


--
-- Name: scheme_version_scheme_id_index; Type: INDEX; Schema: flow; Owner: -
--

CREATE INDEX scheme_version_scheme_id_index ON flow.scheme_version USING btree (scheme_id);


--
-- Name: calendar calendar_set_rbac_acl; Type: TRIGGER; Schema: flow; Owner: -
--

CREATE TRIGGER calendar_set_rbac_acl AFTER INSERT ON flow.calendar FOR EACH ROW EXECUTE FUNCTION flow.tg_obj_default_rbac('calendar');


--
-- Name: acr_routing_scheme insert_flow_version; Type: TRIGGER; Schema: flow; Owner: -
--

CREATE TRIGGER insert_flow_version BEFORE UPDATE ON flow.acr_routing_scheme FOR EACH ROW WHEN ((old.scheme <> new.scheme)) EXECUTE FUNCTION flow.scheme_version_appeared();


--
-- Name: acr_chat_plan acr_chat_plan_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_chat_plan
    ADD CONSTRAINT acr_chat_plan_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id);


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
    ADD CONSTRAINT acr_routing_outbound_call_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: acr_routing_outbound_call acr_routing_outbound_call_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_outbound_call
    ADD CONSTRAINT acr_routing_outbound_call_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: acr_routing_scheme acr_routing_scheme_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: acr_routing_scheme acr_routing_scheme_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: acr_routing_scheme acr_routing_scheme_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.acr_routing_scheme
    ADD CONSTRAINT acr_routing_scheme_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON UPDATE SET NULL ON DELETE SET NULL;


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
    ADD CONSTRAINT calendar_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


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
    ADD CONSTRAINT calendar_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: calendar calendar_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.calendar
    ADD CONSTRAINT calendar_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: region region_calendar_timezones_id_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.region
    ADD CONSTRAINT region_calendar_timezones_id_fk FOREIGN KEY (timezone_id) REFERENCES flow.calendar_timezones(id);


--
-- Name: region region_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: flow; Owner: -
--

ALTER TABLE ONLY flow.region
    ADD CONSTRAINT region_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE RESTRICT ON DELETE RESTRICT;


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
-- PostgreSQL database dump complete
--

\unrestrict yy4caIRs9WnSXCJcHp5gRadVS77hm0sZOoPCaKSUJ32I9CFm5KqP4UI1XU60EaJ

