--
-- PostgreSQL database dump
--

-- Dumped from database version 15.7 (Debian 15.7-1.pgdg120+1)
-- Dumped by pg_dump version 15.7 (Debian 15.7-1.pgdg120+1)

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
-- Name: storage; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA storage;


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


--
-- Name: file_decrement_profile_size(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.file_decrement_profile_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  update storage.file_backend_profiles p
      SET data_size = data_size - f.sum_size,
        data_count = data_count - f.count_files
      from (
             select
               profile_id,
               sum(size) * 0.000001 as sum_size,
               count(*) as count_files
             from tg_data
             group by profile_id
           ) as f
      where p.id = f.profile_id;
  RETURN NULL;
END;
$$;


--
-- Name: file_increment_profile_size(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.file_increment_profile_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  update storage.file_backend_profiles p
      SET data_size = data_size + f.sum_size,
      data_count = data_count + f.count_files
      from (
             select
               profile_id,
               sum(size) * 0.000001 as sum_size,
               count(*) as count_files
             from tg_data
             group by profile_id
           ) as f
      where p.id = f.profile_id;
  RETURN NULL;
END;
$$;


--
-- Name: file_statistics_trigger_deleted(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.file_statistics_trigger_deleted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    insert into storage.files_statistics (domain_id, profile_id, mime_type, count, size, not_exists_count)
    select s.domain_id, s.profile_id, s.mime_type, s.cnt, s.size, not_exists_count
    from (
        select f.domain_id, f.profile_id, f.mime_type, count(*) cnt, sum(f.size) size,
               count(*) filter ( where f.not_exists is true ) not_exists_count
        from deleted f
        group by f.domain_id, f.profile_id, f.mime_type
    ) s
    on conflict (domain_id, coalesce(profile_id, 0), mime_type)
            do update
            set count = storage.files_statistics.count - EXCLUDED.count,
                size = storage.files_statistics.size - EXCLUDED.size,
                not_exists_count = storage.files_statistics.not_exists_count - EXCLUDED.not_exists_count;

    RETURN NULL;
END
$$;


--
-- Name: file_statistics_trigger_inserted(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.file_statistics_trigger_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    insert into storage.files_statistics (domain_id, profile_id, mime_type, count, size, not_exists_count)
    select s.domain_id, s.profile_id, s.mime_type, s.cnt, s.size, not_exists_count
    from (
        select f.domain_id, f.profile_id, f.mime_type, count(*) cnt, sum(f.size) size,
               count(*) filter ( where f.not_exists is true ) not_exists_count
        from inserted f
        group by f.domain_id, f.profile_id, f.mime_type
    ) s
    on conflict (domain_id, coalesce(profile_id, 0), mime_type)
            do update
            set count   = EXCLUDED.count + storage.files_statistics.count,
                size = EXCLUDED.size + storage.files_statistics.size,
                not_exists_count = EXCLUDED.not_exists_count + storage.files_statistics.not_exists_count;
    RETURN NULL;
END
$$;


--
-- Name: file_trigger_decrement_profile_size(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.file_trigger_decrement_profile_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  update storage.file_backend_profiles p
      SET data_size = data_size - f.sum_size,
        data_count = data_count - f.count_files
      from (
             select
               profile_id,
               sum(size) * 0.000001 as sum_size,
               count(*) as count_files
             from deleted
             group by profile_id
           ) as f
      where p.id = f.profile_id;
  RETURN NULL;
END;
$$;


--
-- Name: file_trigger_increment_profile_size(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.file_trigger_increment_profile_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  update storage.file_backend_profiles p
      SET data_size = data_size + f.sum_size,
      data_count = data_count + f.count_files
      from (
             select
               profile_id,
               sum(size) * 0.000001 as sum_size,
               count(*) as count_files
             from inserted
             group by profile_id
           ) as f
      where p.id = f.profile_id;
  RETURN NULL;
END;
$$;


--
-- Name: get_lookup(bigint, character varying); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.get_lookup(_id bigint, _name character varying) RETURNS jsonb
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
-- Name: tg_obj_default_rbac(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.tg_obj_default_rbac() RETURNS trigger
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
-- Name: media_files; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.media_files (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    size bigint NOT NULL,
    mime_type character varying(120),
    properties jsonb,
    instance character varying(50),
    created_at bigint,
    updated_at bigint,
    domain_id bigint NOT NULL,
    created_by bigint,
    updated_by bigint
);


--
-- Name: file_jobs; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.file_jobs (
    id bigint NOT NULL,
    file_id bigint NOT NULL,
    state smallint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    action character varying(15) NOT NULL,
    log jsonb,
    config jsonb,
    error character varying
);


--
-- Name: file_transcript; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.file_transcript (
    id bigint NOT NULL,
    file_id bigint,
    transcript text NOT NULL,
    log jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    profile_id integer NOT NULL,
    locale character varying DEFAULT 'none'::character varying NOT NULL,
    phrases jsonb,
    channels jsonb,
    uuid character varying NOT NULL,
    domain_id bigint
);


--
-- Name: files; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.files (
    id bigint NOT NULL,
    name character varying NOT NULL,
    size bigint NOT NULL,
    mime_type character varying,
    properties jsonb NOT NULL,
    instance character varying(50) NOT NULL,
    uuid character varying NOT NULL,
    profile_id integer,
    created_at bigint,
    removed boolean,
    not_exists boolean,
    domain_id bigint NOT NULL,
    view_name character varying,
    sha256sum character varying
);


--
-- Name: cognitive_profile_services; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.cognitive_profile_services (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    provider character varying(15) NOT NULL,
    properties jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_by bigint,
    enabled boolean DEFAULT true NOT NULL,
    name character varying(50) NOT NULL,
    description character varying DEFAULT ''::character varying,
    service character varying(10) NOT NULL,
    "default" boolean DEFAULT false NOT NULL
);


--
-- Name: cognitive_profile_services_acl; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.cognitive_profile_services_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL,
    object bigint NOT NULL
);


--
-- Name: cognitive_profile_services_acl_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.cognitive_profile_services_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cognitive_profile_services_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.cognitive_profile_services_acl_id_seq OWNED BY storage.cognitive_profile_services_acl.id;


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
-- Name: cognitive_profiles_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.cognitive_profiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cognitive_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.cognitive_profiles_id_seq OWNED BY storage.cognitive_profile_services.id;


--
-- Name: file_backend_profiles; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.file_backend_profiles (
    id bigint NOT NULL,
    name character varying(100) NOT NULL,
    expire_day integer DEFAULT 0 NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    disabled boolean,
    max_size_mb integer DEFAULT 0 NOT NULL,
    properties jsonb NOT NULL,
    created_at bigint NOT NULL,
    updated_at bigint NOT NULL,
    data_size double precision DEFAULT 0 NOT NULL,
    data_count bigint DEFAULT 0 NOT NULL,
    created_by bigint,
    updated_by bigint,
    domain_id bigint,
    description character varying DEFAULT ''::character varying,
    type character varying(10) NOT NULL
);


--
-- Name: file_backend_profiles_acl; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.file_backend_profiles_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL,
    object bigint NOT NULL
);


--
-- Name: file_backend_profiles_acl_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.file_backend_profiles_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_backend_profiles_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.file_backend_profiles_acl_id_seq OWNED BY storage.file_backend_profiles_acl.id;


--
-- Name: file_backend_profiles_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.file_backend_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_backend_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.file_backend_profiles_id_seq OWNED BY storage.file_backend_profiles.id;


--
-- Name: files_statistics; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.files_statistics (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    profile_id integer,
    mime_type character varying NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    size bigint DEFAULT 0 NOT NULL,
    not_exists_count integer DEFAULT 0 NOT NULL
);


--
-- Name: file_backend_profiles_view; Type: VIEW; Schema: storage; Owner: -
--

CREATE VIEW storage.file_backend_profiles_view AS
 SELECT p.id,
    storage.get_lookup(c.id, (c.name)::character varying) AS created_by,
    p.created_at,
    storage.get_lookup(u.id, (u.name)::character varying) AS updated_by,
    p.updated_at,
    p.name,
    p.description,
    p.expire_day AS expire_days,
    p.priority,
    p.disabled,
    p.max_size_mb AS max_size,
    p.properties,
    p.type,
    COALESCE(s.size, (0)::numeric) AS data_size,
    COALESCE(s.cnt, (0)::numeric) AS data_count,
    p.domain_id
   FROM (((storage.file_backend_profiles p
     LEFT JOIN LATERAL ( SELECT sum(s_1.size) AS size,
            sum(s_1.count) AS cnt
           FROM storage.files_statistics s_1
          WHERE (s_1.profile_id = p.id)) s ON (true))
     LEFT JOIN directory.wbt_user c ON ((c.id = p.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = p.updated_by)));


--
-- Name: file_jobs_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.file_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.file_jobs_id_seq OWNED BY storage.file_jobs.id;


--
-- Name: file_transcript_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.file_transcript_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_transcript_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.file_transcript_id_seq OWNED BY storage.file_transcript.id;


--
-- Name: files_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: files_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.files_id_seq OWNED BY storage.files.id;


--
-- Name: files_statistics_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.files_statistics_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: files_statistics_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.files_statistics_id_seq OWNED BY storage.files_statistics.id;


--
-- Name: import_template; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.import_template (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    name text NOT NULL,
    description text,
    source_type character varying(50) NOT NULL,
    source_id bigint NOT NULL,
    parameters jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: import_template_acl; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.import_template_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL,
    object bigint NOT NULL
);


--
-- Name: import_template_acl_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.import_template_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: import_template_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.import_template_acl_id_seq OWNED BY storage.import_template_acl.id;


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
    t.domain_id,
    t.created_at,
    storage.get_lookup(c.id, (COALESCE(c.name, (c.username)::text))::character varying) AS created_by,
    t.updated_at,
    storage.get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS updated_by
   FROM (((storage.import_template t
     LEFT JOIN directory.wbt_user c ON ((c.id = t.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = t.updated_by)))
     LEFT JOIN LATERAL ( SELECT q.id,
            q.name
           FROM call_center.cc_queue q
          WHERE ((q.id = t.source_id) AND (q.domain_id = t.domain_id))
         LIMIT 1) s ON (true));


--
-- Name: jobs; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.jobs (
    id character varying(26) NOT NULL,
    type character varying(32),
    priority bigint,
    schedule_id bigint,
    schedule_time bigint,
    create_at bigint,
    start_at bigint,
    last_activity_at bigint,
    status character varying(32),
    progress bigint,
    data character varying
);


--
-- Name: media_files_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.media_files_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: media_files_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.media_files_id_seq OWNED BY storage.media_files.id;


--
-- Name: media_files_view; Type: VIEW; Schema: storage; Owner: -
--

CREATE VIEW storage.media_files_view AS
 SELECT f.id,
    f.name,
    f.created_at,
    storage.get_lookup(c.id, (c.name)::character varying) AS created_by,
    f.updated_at,
    storage.get_lookup(u.id, (u.name)::character varying) AS updated_by,
    f.mime_type,
    f.size,
    f.properties,
    f.domain_id
   FROM ((storage.media_files f
     LEFT JOIN directory.wbt_user c ON ((f.created_by = c.id)))
     LEFT JOIN directory.wbt_user u ON ((f.updated_by = u.id)));


--
-- Name: schedulers; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.schedulers (
    id bigint NOT NULL,
    cron_expression character varying(50) NOT NULL,
    type character varying(50) NOT NULL,
    name character varying(50) NOT NULL,
    description character varying(500),
    time_zone character varying(50),
    created_at bigint NOT NULL,
    enabled boolean NOT NULL
);


--
-- Name: schedulers_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.schedulers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedulers_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.schedulers_id_seq OWNED BY storage.schedulers.id;


--
-- Name: upload_file_jobs; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.upload_file_jobs (
    id bigint NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    name character varying NOT NULL,
    uuid character varying NOT NULL,
    mime_type character varying,
    size bigint NOT NULL,
    email_msg character varying(500) DEFAULT ''::character varying NOT NULL,
    email_sub character varying(150) DEFAULT ''::character varying NOT NULL,
    instance character varying,
    created_at bigint NOT NULL,
    updated_at bigint,
    attempts integer DEFAULT 0 NOT NULL,
    domain_id bigint NOT NULL,
    view_name character varying,
    props jsonb,
    sha256sum character varying
);


--
-- Name: upload_file_jobs_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.upload_file_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: upload_file_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.upload_file_jobs_id_seq OWNED BY storage.upload_file_jobs.id;


--
-- Name: cognitive_profile_services id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services ALTER COLUMN id SET DEFAULT nextval('storage.cognitive_profiles_id_seq'::regclass);


--
-- Name: cognitive_profile_services_acl id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services_acl ALTER COLUMN id SET DEFAULT nextval('storage.cognitive_profile_services_acl_id_seq'::regclass);


--
-- Name: file_backend_profiles id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles ALTER COLUMN id SET DEFAULT nextval('storage.file_backend_profiles_id_seq'::regclass);


--
-- Name: file_backend_profiles_acl id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles_acl ALTER COLUMN id SET DEFAULT nextval('storage.file_backend_profiles_acl_id_seq'::regclass);


--
-- Name: file_jobs id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_jobs ALTER COLUMN id SET DEFAULT nextval('storage.file_jobs_id_seq'::regclass);


--
-- Name: file_transcript id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_transcript ALTER COLUMN id SET DEFAULT nextval('storage.file_transcript_id_seq'::regclass);


--
-- Name: files_statistics id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.files_statistics ALTER COLUMN id SET DEFAULT nextval('storage.files_statistics_id_seq'::regclass);


--
-- Name: import_template id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template ALTER COLUMN id SET DEFAULT nextval('storage.import_template_id_seq'::regclass);


--
-- Name: import_template_acl id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl ALTER COLUMN id SET DEFAULT nextval('storage.import_template_acl_id_seq'::regclass);


--
-- Name: media_files id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.media_files ALTER COLUMN id SET DEFAULT nextval('storage.media_files_id_seq'::regclass);


--
-- Name: schedulers id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.schedulers ALTER COLUMN id SET DEFAULT nextval('storage.schedulers_id_seq'::regclass);


--
-- Name: upload_file_jobs id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.upload_file_jobs ALTER COLUMN id SET DEFAULT nextval('storage.upload_file_jobs_id_seq'::regclass);


--
-- Name: cognitive_profile_services_acl cognitive_profile_services_acl_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services_acl
    ADD CONSTRAINT cognitive_profile_services_acl_pk PRIMARY KEY (id);


--
-- Name: file_backend_profiles_acl file_backend_profiles_acl_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles_acl
    ADD CONSTRAINT file_backend_profiles_acl_pk PRIMARY KEY (id);


--
-- Name: file_backend_profiles file_backend_profiles_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles
    ADD CONSTRAINT file_backend_profiles_pkey PRIMARY KEY (id);


--
-- Name: file_jobs file_jobs_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_jobs
    ADD CONSTRAINT file_jobs_pkey PRIMARY KEY (id);


--
-- Name: file_transcript file_transcript_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_transcript
    ADD CONSTRAINT file_transcript_pk PRIMARY KEY (id);


--
-- Name: files files_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.files
    ADD CONSTRAINT files_pkey PRIMARY KEY (id);


--
-- Name: files_statistics files_statistics_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.files_statistics
    ADD CONSTRAINT files_statistics_pk PRIMARY KEY (id);


--
-- Name: import_template_acl import_template_acl_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_pk PRIMARY KEY (id);


--
-- Name: import_template import_template_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template
    ADD CONSTRAINT import_template_pk PRIMARY KEY (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: media_files media_files_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.media_files
    ADD CONSTRAINT media_files_pkey PRIMARY KEY (id);


--
-- Name: schedulers schedulers_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.schedulers
    ADD CONSTRAINT schedulers_pkey PRIMARY KEY (id);


--
-- Name: cognitive_profile_services stt_profiles_pk; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services
    ADD CONSTRAINT stt_profiles_pk PRIMARY KEY (id);


--
-- Name: upload_file_jobs upload_file_jobs_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.upload_file_jobs
    ADD CONSTRAINT upload_file_jobs_pkey PRIMARY KEY (id);


--
-- Name: cognitive_profile_services_acl_grantor_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX cognitive_profile_services_acl_grantor_idx ON storage.cognitive_profile_services_acl USING btree (grantor);


--
-- Name: cognitive_profile_services_acl_id_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX cognitive_profile_services_acl_id_uindex ON storage.cognitive_profile_services_acl USING btree (id);


--
-- Name: cognitive_profile_services_acl_object_subject_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX cognitive_profile_services_acl_object_subject_udx ON storage.cognitive_profile_services_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cognitive_profile_services_acl_subject_object_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX cognitive_profile_services_acl_subject_object_udx ON storage.cognitive_profile_services_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cognitive_profile_services_domain_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX cognitive_profile_services_domain_udx ON storage.cognitive_profile_services USING btree (id, domain_id DESC);


--
-- Name: file_backend_profiles_acl_grantor_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_backend_profiles_acl_grantor_idx ON storage.file_backend_profiles_acl USING btree (grantor);


--
-- Name: file_backend_profiles_acl_id_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX file_backend_profiles_acl_id_uindex ON storage.file_backend_profiles_acl USING btree (id);


--
-- Name: file_backend_profiles_acl_object_subject_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX file_backend_profiles_acl_object_subject_udx ON storage.file_backend_profiles_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: file_backend_profiles_acl_subject_object_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX file_backend_profiles_acl_subject_object_udx ON storage.file_backend_profiles_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: file_backend_profiles_domain_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX file_backend_profiles_domain_udx ON storage.file_backend_profiles USING btree (id, domain_id);


--
-- Name: file_jobs_file_id_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX file_jobs_file_id_uindex ON storage.file_jobs USING btree (file_id);


--
-- Name: file_transcript_file_id_profile_id_locale_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX file_transcript_file_id_profile_id_locale_uindex ON storage.file_transcript USING btree (file_id, profile_id, locale);


--
-- Name: file_transcript_fts_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_transcript_fts_idx ON storage.file_transcript USING gin (setweight(to_tsvector('english'::regconfig, transcript), 'A'::"char"));


--
-- Name: file_transcript_fts_ru_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_transcript_fts_ru_idx ON storage.file_transcript USING gin (setweight(to_tsvector('russian'::regconfig, transcript), 'A'::"char"));


--
-- Name: file_transcript_profile_id_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_transcript_profile_id_index ON storage.file_transcript USING btree (profile_id);


--
-- Name: file_transcript_uuid_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX file_transcript_uuid_index ON storage.file_transcript USING btree (((uuid)::character varying(50)));


--
-- Name: files_created_at_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_created_at_index ON storage.files USING btree (created_at) INCLUDE (profile_id, id);


--
-- Name: files_created_at_not_removed_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_created_at_not_removed_index ON storage.files USING btree (created_at) INCLUDE (id) WHERE removed;


--
-- Name: files_created_at_removed_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_created_at_removed_index ON storage.files USING btree (created_at) INCLUDE (id) WHERE removed;


--
-- Name: files_domain_id_uuid_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_domain_id_uuid_index ON storage.files USING btree (domain_id, uuid);


--
-- Name: files_profile_id_created_at_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_profile_id_created_at_index ON storage.files USING btree (created_at, COALESCE(profile_id, 0)) INCLUDE (id);


--
-- Name: files_statistics_domain_id_profile_id_mime_type_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX files_statistics_domain_id_profile_id_mime_type_uindex ON storage.files_statistics USING btree (domain_id, COALESCE(profile_id, 0), mime_type);


--
-- Name: files_statistics_id_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX files_statistics_id_uindex ON storage.files_statistics USING btree (id);


--
-- Name: import_template_acl_grantor_idx; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX import_template_acl_grantor_idx ON storage.import_template_acl USING btree (grantor);


--
-- Name: import_template_acl_object_subject_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX import_template_acl_object_subject_udx ON storage.import_template_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: import_template_acl_subject_object_udx; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX import_template_acl_subject_object_udx ON storage.import_template_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: import_template_id_domain_id_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX import_template_id_domain_id_uindex ON storage.import_template USING btree (id, domain_id);


--
-- Name: media_files_domain_id_name_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX media_files_domain_id_name_uindex ON storage.media_files USING btree (domain_id, name);


--
-- Name: cognitive_profile_services cognitive_profile_services_set_def_tg; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER cognitive_profile_services_set_def_tg BEFORE INSERT OR UPDATE ON storage.cognitive_profile_services FOR EACH ROW WHEN (new."default") EXECUTE FUNCTION storage.cognitive_profile_services_set_def();


--
-- Name: cognitive_profile_services cognitive_profile_services_set_rbac_acl; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER cognitive_profile_services_set_rbac_acl AFTER INSERT ON storage.cognitive_profile_services FOR EACH ROW EXECUTE FUNCTION storage.tg_obj_default_rbac('cognitive_profile_services');


--
-- Name: file_backend_profiles file_backend_profiles_set_rbac_acl; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER file_backend_profiles_set_rbac_acl AFTER INSERT ON storage.file_backend_profiles FOR EACH ROW EXECUTE FUNCTION storage.tg_obj_default_rbac('file_backend_profiles');


--
-- Name: import_template import_template_set_rbac_acl; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER import_template_set_rbac_acl AFTER INSERT ON storage.import_template FOR EACH ROW EXECUTE FUNCTION storage.tg_obj_default_rbac('import_template');


--
-- Name: files tg_files_statistics_deleted; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER tg_files_statistics_deleted AFTER DELETE ON storage.files REFERENCING OLD TABLE AS deleted FOR EACH STATEMENT EXECUTE FUNCTION storage.file_statistics_trigger_deleted();


--
-- Name: files tg_files_statistics_inserted; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER tg_files_statistics_inserted AFTER INSERT ON storage.files REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE FUNCTION storage.file_statistics_trigger_inserted();


--
-- Name: file_backend_profiles_acl file_backend_profiles_acl_domain_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles_acl
    ADD CONSTRAINT file_backend_profiles_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: file_backend_profiles_acl file_backend_profiles_acl_grantor_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles_acl
    ADD CONSTRAINT file_backend_profiles_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: file_backend_profiles_acl file_backend_profiles_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles_acl
    ADD CONSTRAINT file_backend_profiles_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: file_backend_profiles_acl file_backend_profiles_acl_object_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles_acl
    ADD CONSTRAINT file_backend_profiles_acl_object_fk FOREIGN KEY (object, dc) REFERENCES storage.file_backend_profiles(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: file_backend_profiles_acl file_backend_profiles_acl_subject_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles_acl
    ADD CONSTRAINT file_backend_profiles_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cognitive_profile_services_acl file_cognitive_profile_services_acl_domain_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services_acl
    ADD CONSTRAINT file_cognitive_profile_services_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cognitive_profile_services_acl file_cognitive_profile_services_acl_grantor_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services_acl
    ADD CONSTRAINT file_cognitive_profile_services_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cognitive_profile_services_acl file_cognitive_profile_services_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services_acl
    ADD CONSTRAINT file_cognitive_profile_services_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cognitive_profile_services_acl file_cognitive_profile_services_acl_object_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services_acl
    ADD CONSTRAINT file_cognitive_profile_services_acl_object_fk FOREIGN KEY (object, dc) REFERENCES storage.cognitive_profile_services(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cognitive_profile_services_acl file_cognitive_profile_services_acl_subject_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.cognitive_profile_services_acl
    ADD CONSTRAINT file_cognitive_profile_services_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: file_transcript file_transcript_cognitive_profile_services_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_transcript
    ADD CONSTRAINT file_transcript_cognitive_profile_services_id_fk FOREIGN KEY (profile_id) REFERENCES storage.cognitive_profile_services(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: file_transcript file_transcript_files_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_transcript
    ADD CONSTRAINT file_transcript_files_id_fk FOREIGN KEY (file_id) REFERENCES storage.files(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: import_template_acl import_template_acl_domain_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: import_template_acl import_template_acl_grantor_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: import_template_acl import_template_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: import_template_acl import_template_acl_import_template_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_import_template_id_fk FOREIGN KEY (object) REFERENCES storage.import_template(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: import_template_acl import_template_acl_object_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_object_fk FOREIGN KEY (object, dc) REFERENCES storage.import_template(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: import_template_acl import_template_acl_subject_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.import_template_acl
    ADD CONSTRAINT import_template_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: media_files media_files_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.media_files
    ADD CONSTRAINT media_files_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: media_files media_files_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.media_files
    ADD CONSTRAINT media_files_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: SCHEMA storage; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA storage TO grafana;


--
-- Name: TABLE media_files; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.media_files TO grafana;


--
-- Name: TABLE file_jobs; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.file_jobs TO grafana;


--
-- Name: TABLE file_transcript; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.file_transcript TO grafana;


--
-- Name: TABLE files; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.files TO grafana;


--
-- Name: TABLE cognitive_profile_services; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.cognitive_profile_services TO grafana;


--
-- Name: TABLE cognitive_profile_services_acl; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.cognitive_profile_services_acl TO grafana;


--
-- Name: SEQUENCE cognitive_profile_services_acl_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.cognitive_profile_services_acl_id_seq TO grafana;


--
-- Name: TABLE cognitive_profile_services_view; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.cognitive_profile_services_view TO grafana;


--
-- Name: SEQUENCE cognitive_profiles_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.cognitive_profiles_id_seq TO grafana;


--
-- Name: TABLE file_backend_profiles; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.file_backend_profiles TO grafana;


--
-- Name: TABLE file_backend_profiles_acl; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.file_backend_profiles_acl TO grafana;


--
-- Name: SEQUENCE file_backend_profiles_acl_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.file_backend_profiles_acl_id_seq TO grafana;


--
-- Name: SEQUENCE file_backend_profiles_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.file_backend_profiles_id_seq TO grafana;


--
-- Name: TABLE files_statistics; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.files_statistics TO grafana;


--
-- Name: TABLE file_backend_profiles_view; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.file_backend_profiles_view TO grafana;


--
-- Name: SEQUENCE file_jobs_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.file_jobs_id_seq TO grafana;


--
-- Name: SEQUENCE file_transcript_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.file_transcript_id_seq TO grafana;


--
-- Name: SEQUENCE files_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.files_id_seq TO grafana;


--
-- Name: SEQUENCE files_statistics_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.files_statistics_id_seq TO grafana;


--
-- Name: TABLE import_template; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.import_template TO grafana;


--
-- Name: TABLE import_template_acl; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.import_template_acl TO grafana;


--
-- Name: SEQUENCE import_template_acl_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.import_template_acl_id_seq TO grafana;


--
-- Name: SEQUENCE import_template_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.import_template_id_seq TO grafana;


--
-- Name: TABLE import_template_view; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.import_template_view TO grafana;


--
-- Name: TABLE jobs; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.jobs TO grafana;


--
-- Name: SEQUENCE media_files_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.media_files_id_seq TO grafana;


--
-- Name: TABLE media_files_view; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.media_files_view TO grafana;


--
-- Name: TABLE schedulers; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.schedulers TO grafana;


--
-- Name: SEQUENCE schedulers_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.schedulers_id_seq TO grafana;


--
-- Name: TABLE upload_file_jobs; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON TABLE storage.upload_file_jobs TO grafana;


--
-- Name: SEQUENCE upload_file_jobs_id_seq; Type: ACL; Schema: storage; Owner: -
--

GRANT SELECT ON SEQUENCE storage.upload_file_jobs_id_seq TO grafana;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: storage; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE opensips IN SCHEMA storage GRANT SELECT ON TABLES  TO grafana;


--
-- PostgreSQL database dump complete
--

