--
-- PostgreSQL database dump
--

-- Dumped from database version 12.7 (Debian 12.7-1.pgdg100+1)
-- Dumped by pg_dump version 12.7 (Debian 12.7-1.pgdg100+1)

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
-- Name: file_decrement_profile_size(); Type: FUNCTION; Schema: storage; Owner: -
--

CREATE FUNCTION storage.file_decrement_profile_size() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  update file_backend_profiles p
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
  update file_backend_profiles p
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

    insert into files_statistics (domain_id, profile_id, mime_type, count, size, not_exists_count)
    select s.domain_id, s.profile_id, s.mime_type, s.cnt, s.size, not_exists_count
    from (
        select f.domain_id, f.profile_id, f.mime_type, count(*) cnt, sum(f.size) size,
               count(*) filter ( where f.not_exists is true ) not_exists_count
        from deleted f
        group by f.domain_id, f.profile_id, f.mime_type
    ) s
    on conflict (domain_id, coalesce(profile_id, 0), mime_type)
            do update
            set count = files_statistics.count - EXCLUDED.count,
                size = files_statistics.size - EXCLUDED.size,
                not_exists_count = files_statistics.not_exists_count - EXCLUDED.not_exists_count;

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
    insert into files_statistics (domain_id, profile_id, mime_type, count, size, not_exists_count)
    select s.domain_id, s.profile_id, s.mime_type, s.cnt, s.size, not_exists_count
    from (
        select f.domain_id, f.profile_id, f.mime_type, count(*) cnt, sum(f.size) size,
               count(*) filter ( where f.not_exists is true ) not_exists_count
        from inserted f
        group by f.domain_id, f.profile_id, f.mime_type
    ) s
    on conflict (domain_id, coalesce(profile_id, 0), mime_type)
            do update
            set count   = EXCLUDED.count + files_statistics.count,
                size = EXCLUDED.size + files_statistics.size,
                not_exists_count = EXCLUDED.not_exists_count + files_statistics.not_exists_count;
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
  update file_backend_profiles p
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
  update file_backend_profiles p
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
    mime_type character varying(40),
    properties jsonb,
    instance character varying(50),
    created_at bigint,
    updated_at bigint,
    domain_id bigint NOT NULL,
    created_by bigint NOT NULL,
    updated_by bigint NOT NULL
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
    domain_id bigint NOT NULL
);


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
    grantor bigint NOT NULL,
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
-- Name: remove_file_jobs; Type: TABLE; Schema: storage; Owner: -
--

CREATE TABLE storage.remove_file_jobs (
    id integer NOT NULL,
    file_id bigint NOT NULL,
    created_at bigint,
    created_by character varying(50)
);


--
-- Name: remove_file_jobs_id_seq; Type: SEQUENCE; Schema: storage; Owner: -
--

CREATE SEQUENCE storage.remove_file_jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: remove_file_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: storage; Owner: -
--

ALTER SEQUENCE storage.remove_file_jobs_id_seq OWNED BY storage.remove_file_jobs.id;


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
    domain_id bigint NOT NULL
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
-- Name: file_backend_profiles id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles ALTER COLUMN id SET DEFAULT nextval('storage.file_backend_profiles_id_seq'::regclass);


--
-- Name: file_backend_profiles_acl id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.file_backend_profiles_acl ALTER COLUMN id SET DEFAULT nextval('storage.file_backend_profiles_acl_id_seq'::regclass);


--
-- Name: files_statistics id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.files_statistics ALTER COLUMN id SET DEFAULT nextval('storage.files_statistics_id_seq'::regclass);


--
-- Name: media_files id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.media_files ALTER COLUMN id SET DEFAULT nextval('storage.media_files_id_seq'::regclass);


--
-- Name: remove_file_jobs id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.remove_file_jobs ALTER COLUMN id SET DEFAULT nextval('storage.remove_file_jobs_id_seq'::regclass);


--
-- Name: schedulers id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.schedulers ALTER COLUMN id SET DEFAULT nextval('storage.schedulers_id_seq'::regclass);


--
-- Name: upload_file_jobs id; Type: DEFAULT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.upload_file_jobs ALTER COLUMN id SET DEFAULT nextval('storage.upload_file_jobs_id_seq'::regclass);


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
-- Name: remove_file_jobs remove_file_jobs_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.remove_file_jobs
    ADD CONSTRAINT remove_file_jobs_pkey PRIMARY KEY (id);


--
-- Name: schedulers schedulers_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.schedulers
    ADD CONSTRAINT schedulers_pkey PRIMARY KEY (id);


--
-- Name: upload_file_jobs upload_file_jobs_pkey; Type: CONSTRAINT; Schema: storage; Owner: -
--

ALTER TABLE ONLY storage.upload_file_jobs
    ADD CONSTRAINT upload_file_jobs_pkey PRIMARY KEY (id);


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
-- Name: files_domain_id_uuid_index; Type: INDEX; Schema: storage; Owner: -
--

CREATE INDEX files_domain_id_uuid_index ON storage.files USING btree (domain_id, uuid);


--
-- Name: files_statistics_domain_id_profile_id_mime_type_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX files_statistics_domain_id_profile_id_mime_type_uindex ON storage.files_statistics USING btree (domain_id, COALESCE(profile_id, 0), mime_type);


--
-- Name: files_statistics_id_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX files_statistics_id_uindex ON storage.files_statistics USING btree (id);


--
-- Name: media_files_domain_id_name_uindex; Type: INDEX; Schema: storage; Owner: -
--

CREATE UNIQUE INDEX media_files_domain_id_name_uindex ON storage.media_files USING btree (domain_id, name);


--
-- Name: file_backend_profiles file_backend_profiles_set_rbac_acl; Type: TRIGGER; Schema: storage; Owner: -
--

CREATE TRIGGER file_backend_profiles_set_rbac_acl AFTER INSERT ON storage.file_backend_profiles FOR EACH ROW EXECUTE FUNCTION storage.tg_obj_default_rbac('file_backend_profiles');


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
    ADD CONSTRAINT file_backend_profiles_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


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
-- PostgreSQL database dump complete
--

