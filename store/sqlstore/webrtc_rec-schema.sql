--
-- PostgreSQL database dump
--

\restrict qlDZgiBlEK83iSfXqyvzPJV8u6FWx0KjXbRvhkOnWiWjPCNYlW0oEPb0kVmVIL3

-- Dumped from database version 15.15 (Debian 15.15-1.pgdg12+1)
-- Dumped by pg_dump version 15.15 (Debian 15.15-1.pgdg12+1)

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
-- Name: webrtc_rec; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA webrtc_rec;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: file_jobs; Type: TABLE; Schema: webrtc_rec; Owner: -
--

CREATE TABLE webrtc_rec.file_jobs (
    id bigint NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    type text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    activity_at timestamp with time zone DEFAULT now() NOT NULL,
    instance text,
    config jsonb,
    file jsonb NOT NULL,
    error text,
    retry integer DEFAULT 0 NOT NULL
);


--
-- Name: file_jobs_id_seq; Type: SEQUENCE; Schema: webrtc_rec; Owner: -
--

CREATE SEQUENCE webrtc_rec.file_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: file_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: webrtc_rec; Owner: -
--

ALTER SEQUENCE webrtc_rec.file_jobs_id_seq OWNED BY webrtc_rec.file_jobs.id;


--
-- Name: file_jobs id; Type: DEFAULT; Schema: webrtc_rec; Owner: -
--

ALTER TABLE ONLY webrtc_rec.file_jobs ALTER COLUMN id SET DEFAULT nextval('webrtc_rec.file_jobs_id_seq'::regclass);


--
-- Name: file_jobs file_jobs_pkey; Type: CONSTRAINT; Schema: webrtc_rec; Owner: -
--

ALTER TABLE ONLY webrtc_rec.file_jobs
    ADD CONSTRAINT file_jobs_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--

\unrestrict qlDZgiBlEK83iSfXqyvzPJV8u6FWx0KjXbRvhkOnWiWjPCNYlW0oEPb0kVmVIL3

