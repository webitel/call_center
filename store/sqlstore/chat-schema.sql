--
-- PostgreSQL database dump
--

-- Dumped from database version 12.4 (Debian 12.4-1.pgdg100+1)
-- Dumped by pg_dump version 12.4 (Debian 12.4-1.pgdg100+1)

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
-- Name: chat; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA chat;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_channel; Type: TABLE; Schema: chat; Owner: -
--

CREATE TABLE chat.active_channel (
    id character varying NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    state character varying NOT NULL,
    conversation_id character varying NOT NULL,
    type text NOT NULL,
    user_id bigint NOT NULL,
    connection text,
    internal boolean NOT NULL
);


--
-- Name: channel; Type: TABLE; Schema: chat; Owner: -
--

CREATE TABLE chat.channel (
    id character varying NOT NULL,
    type text NOT NULL,
    conversation_id character varying NOT NULL,
    user_id bigint NOT NULL,
    connection text,
    created_at timestamp with time zone NOT NULL,
    internal boolean NOT NULL,
    closed_at timestamp with time zone,
    domain_id bigint NOT NULL,
    flow_bridge boolean DEFAULT false NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    name text NOT NULL,
    joined_at timestamp with time zone,
    closed_cause character varying,
    host name
);


--
-- Name: channel_id_seq; Type: SEQUENCE; Schema: chat; Owner: -
--

CREATE SEQUENCE chat.channel_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: channel_id_seq; Type: SEQUENCE OWNED BY; Schema: chat; Owner: -
--

ALTER SEQUENCE chat.channel_id_seq OWNED BY chat.channel.id;


--
-- Name: client; Type: TABLE; Schema: chat; Owner: -
--

CREATE TABLE chat.client (
    id bigint NOT NULL,
    name text,
    number text,
    created_at timestamp with time zone NOT NULL,
    external_id text,
    first_name text,
    last_name text
);


--
-- Name: client_id_seq; Type: SEQUENCE; Schema: chat; Owner: -
--

CREATE SEQUENCE chat.client_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: client_id_seq; Type: SEQUENCE OWNED BY; Schema: chat; Owner: -
--

ALTER SEQUENCE chat.client_id_seq OWNED BY chat.client.id;


--
-- Name: conversation; Type: TABLE; Schema: chat; Owner: -
--

CREATE TABLE chat.conversation (
    id character varying NOT NULL,
    title text,
    created_at timestamp with time zone,
    closed_at timestamp with time zone,
    updated_at timestamp with time zone NOT NULL,
    domain_id bigint NOT NULL
);


--
-- Name: conversation_confirmation; Type: TABLE; Schema: chat; Owner: -
--

CREATE UNLOGGED TABLE chat.conversation_confirmation (
    conversation_id character varying NOT NULL,
    confirmation_id character varying NOT NULL
);


--
-- Name: conversation_id_seq; Type: SEQUENCE; Schema: chat; Owner: -
--

CREATE SEQUENCE chat.conversation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conversation_id_seq; Type: SEQUENCE OWNED BY; Schema: chat; Owner: -
--

ALTER SEQUENCE chat.conversation_id_seq OWNED BY chat.conversation.id;


--
-- Name: conversation_node; Type: TABLE; Schema: chat; Owner: -
--

CREATE UNLOGGED TABLE chat.conversation_node (
    conversation_id character varying NOT NULL,
    node_id character varying NOT NULL
);


--
-- Name: invite; Type: TABLE; Schema: chat; Owner: -
--

CREATE TABLE chat.invite (
    id character varying NOT NULL,
    conversation_id character varying NOT NULL,
    user_id bigint NOT NULL,
    title text,
    timeout_sec bigint DEFAULT 0 NOT NULL,
    inviter_channel_id character varying,
    closed_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    domain_id bigint NOT NULL
);


--
-- Name: invite_id_seq; Type: SEQUENCE; Schema: chat; Owner: -
--

CREATE SEQUENCE chat.invite_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: invite_id_seq; Type: SEQUENCE OWNED BY; Schema: chat; Owner: -
--

ALTER SEQUENCE chat.invite_id_seq OWNED BY chat.invite.id;


--
-- Name: message; Type: TABLE; Schema: chat; Owner: -
--

CREATE TABLE chat.message (
    id bigint NOT NULL,
    channel_id character varying,
    conversation_id character varying NOT NULL,
    text text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    type text NOT NULL,
    variables jsonb
);


--
-- Name: message_id_seq; Type: SEQUENCE; Schema: chat; Owner: -
--

CREATE SEQUENCE chat.message_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: message_id_seq; Type: SEQUENCE OWNED BY; Schema: chat; Owner: -
--

ALTER SEQUENCE chat.message_id_seq OWNED BY chat.message.id;


--
-- Name: profile; Type: TABLE; Schema: chat; Owner: -
--

CREATE TABLE chat.profile (
    id bigint NOT NULL,
    name text NOT NULL,
    schema_id bigint,
    type text NOT NULL,
    variables jsonb NOT NULL,
    domain_id bigint NOT NULL,
    created_at timestamp with time zone NOT NULL,
    url_id text NOT NULL
);


--
-- Name: profile_id_seq; Type: SEQUENCE; Schema: chat; Owner: -
--

CREATE SEQUENCE chat.profile_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: profile_id_seq; Type: SEQUENCE OWNED BY; Schema: chat; Owner: -
--

ALTER SEQUENCE chat.profile_id_seq OWNED BY chat.profile.id;


--
-- Name: client id; Type: DEFAULT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.client ALTER COLUMN id SET DEFAULT nextval('chat.client_id_seq'::regclass);


--
-- Name: message id; Type: DEFAULT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.message ALTER COLUMN id SET DEFAULT nextval('chat.message_id_seq'::regclass);


--
-- Name: profile id; Type: DEFAULT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.profile ALTER COLUMN id SET DEFAULT nextval('chat.profile_id_seq'::regclass);


--
-- Name: active_channel active_channel_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.active_channel
    ADD CONSTRAINT active_channel_pk PRIMARY KEY (id);


--
-- Name: channel channel_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.channel
    ADD CONSTRAINT channel_pk PRIMARY KEY (id);


--
-- Name: client client_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.client
    ADD CONSTRAINT client_pk PRIMARY KEY (id);


--
-- Name: conversation_confirmation conversation_confirmation_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.conversation_confirmation
    ADD CONSTRAINT conversation_confirmation_pk PRIMARY KEY (conversation_id);


--
-- Name: conversation_node conversation_node_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.conversation_node
    ADD CONSTRAINT conversation_node_pk UNIQUE (conversation_id);


--
-- Name: conversation conversation_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.conversation
    ADD CONSTRAINT conversation_pk PRIMARY KEY (id);


--
-- Name: invite invite_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.invite
    ADD CONSTRAINT invite_pk PRIMARY KEY (id);


--
-- Name: message message_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.message
    ADD CONSTRAINT message_pk PRIMARY KEY (id);


--
-- Name: profile profile_pk; Type: CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.profile
    ADD CONSTRAINT profile_pk PRIMARY KEY (id);


--
-- Name: active_channel_id_uindex; Type: INDEX; Schema: chat; Owner: -
--

CREATE UNIQUE INDEX active_channel_id_uindex ON chat.active_channel USING btree (id);


--
-- Name: channel_conversation_id_index; Type: INDEX; Schema: chat; Owner: -
--

CREATE INDEX channel_conversation_id_index ON chat.channel USING btree (conversation_id);


--
-- Name: channel_conversation_id_user_id_uindex; Type: INDEX; Schema: chat; Owner: -
--

CREATE UNIQUE INDEX channel_conversation_id_user_id_uindex ON chat.channel USING btree (conversation_id, user_id) WHERE (closed_at IS NULL);


--
-- Name: channel_user_id_conversation_id_uindex; Type: INDEX; Schema: chat; Owner: -
--

CREATE INDEX channel_user_id_conversation_id_uindex ON chat.channel USING btree (user_id, closed_at DESC);


--
-- Name: conversation_domain_id_created_at_index; Type: INDEX; Schema: chat; Owner: -
--

CREATE INDEX conversation_domain_id_created_at_index ON chat.conversation USING btree (domain_id, created_at) WHERE (closed_at IS NULL);


--
-- Name: invite_conversation_id_user_id_uindex; Type: INDEX; Schema: chat; Owner: -
--

CREATE UNIQUE INDEX invite_conversation_id_user_id_uindex ON chat.invite USING btree (conversation_id, user_id) WHERE (closed_at IS NULL);


--
-- Name: message_conversation_id_created_at_index; Type: INDEX; Schema: chat; Owner: -
--

CREATE INDEX message_conversation_id_created_at_index ON chat.message USING btree (conversation_id, created_at DESC);


--
-- Name: profile_url_id_uindex; Type: INDEX; Schema: chat; Owner: -
--

CREATE UNIQUE INDEX profile_url_id_uindex ON chat.profile USING btree (url_id);


--
-- Name: channel channel_conversation_fk; Type: FK CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.channel
    ADD CONSTRAINT channel_conversation_fk FOREIGN KEY (conversation_id) REFERENCES chat.conversation(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: invite invite_conversation_fk; Type: FK CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.invite
    ADD CONSTRAINT invite_conversation_fk FOREIGN KEY (conversation_id) REFERENCES chat.conversation(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: message message_conversation_fk; Type: FK CONSTRAINT; Schema: chat; Owner: -
--

ALTER TABLE ONLY chat.message
    ADD CONSTRAINT message_conversation_fk FOREIGN KEY (conversation_id) REFERENCES chat.conversation(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

