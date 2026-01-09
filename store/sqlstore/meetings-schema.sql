--
-- PostgreSQL database dump
--

\restrict JY1Y9UYGB9iWsMCC2x42faJ7kFaWIKbny4ohds1JU9ZZuQTL0flD1CmaL6uEoUf

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
-- Name: meetings; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA meetings;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: web_meetings; Type: TABLE; Schema: meetings; Owner: -
--

CREATE TABLE meetings.web_meetings (
    id text NOT NULL,
    domain_id bigint NOT NULL,
    title text NOT NULL,
    created_at bigint NOT NULL,
    expires_at bigint NOT NULL,
    variables jsonb,
    url text,
    call_id text,
    satisfaction text,
    bridged boolean DEFAULT false
);


--
-- Name: web_meetings web_meetings_pkey; Type: CONSTRAINT; Schema: meetings; Owner: -
--

ALTER TABLE ONLY meetings.web_meetings
    ADD CONSTRAINT web_meetings_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--

\unrestrict JY1Y9UYGB9iWsMCC2x42faJ7kFaWIKbny4ohds1JU9ZZuQTL0flD1CmaL6uEoUf

