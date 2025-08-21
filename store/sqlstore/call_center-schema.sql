--
-- PostgreSQL database dump
--

\restrict QhqtLyw2KO5Nc7kUO4ltxqUKmJbta5jx0KHp2gaPEekw2gJhTWwDfOVtdmqaF4N

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
-- Name: call_center; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA call_center;


--
-- Name: calendar_accept_time; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.calendar_accept_time AS (
	disabled boolean,
	day smallint,
	start_time_of_day smallint,
	end_time_of_day smallint
);


--
-- Name: calendar_except_date; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.calendar_except_date AS (
	disabled boolean,
	date bigint,
	name character varying,
	repeat boolean
);


--
-- Name: cc_agent_in_attempt; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.cc_agent_in_attempt AS (
	attempt_id bigint,
	agent_id bigint
);


--
-- Name: cc_communication_type_l; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.cc_communication_type_l AS (
	type_id integer,
	l interval[]
);


--
-- Name: cc_member_destination_view; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.cc_member_destination_view AS (
	id smallint,
	destination character varying,
	resource jsonb,
	type jsonb,
	priority integer,
	state smallint,
	description character varying,
	last_activity_at bigint,
	attempts integer,
	last_cause character varying,
	display character varying
);


--
-- Name: composite_type_audit_q_297; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_297 AS (
	"1 *Наскільки задоволені Ви якіс" numeric,
	"2 Як оцінюєте оператора кол-цен" numeric,
	"3 *Як би ви оцінили оператора к" numeric,
	"4 *Наскільки ефективно оператор" numeric,
	"5 Чи зрозуміло оператор кол-цен" numeric,
	"6 *Чи були оператори кол-центру" numeric,
	"7 Як оцінюєте оператора кол-цен" numeric
);


--
-- Name: composite_type_audit_q_298; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_298 AS (
	"1 *ferf" numeric,
	"2 hfddh" numeric
);


--
-- Name: composite_type_audit_q_299; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_299 AS (
	"1 *віавпирол" numeric,
	"2 вкарепноргло" numeric
);


--
-- Name: composite_type_audit_q_300; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_300 AS (
	"1 *тест" numeric,
	"2 *тест" numeric
);


--
-- Name: composite_type_audit_q_303; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_303 AS (
	"1 *some 1?" numeric,
	"2 some 2" numeric
);


--
-- Name: composite_type_audit_q_308; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_308 AS (
	"1 *к1 1-5 б" numeric,
	"2 *к2 з 1-5 б" numeric,
	"3 к3 необ" numeric
);


--
-- Name: composite_type_audit_q_309; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_309 AS (
	"1 *к1 1-5 б" numeric,
	"2 *к2 з 1-5 б" numeric,
	"3 к3 необ" numeric
);


--
-- Name: composite_type_audit_q_338; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_338 AS (
	"1 *gggggggg" numeric
);


--
-- Name: composite_type_audit_q_339; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_339 AS (
	"1 *аааааааа" numeric
);


--
-- Name: composite_type_audit_q_341; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_341 AS (
	"1 *тест" numeric,
	"2 *тест" numeric,
	"3 театссстстс" numeric
);


--
-- Name: composite_type_audit_q_344; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_344 AS (
	"1 *yy" numeric,
	"2 *kyfk" numeric
);


--
-- Name: composite_type_audit_q_345; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_345 AS (
	"1 *2" numeric,
	"2 tertw" numeric,
	"3 *urur" numeric,
	"4 irityi" numeric
);


--
-- Name: composite_type_audit_q_346; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_346 AS (
	"1 *gh" numeric
);


--
-- Name: composite_type_audit_q_347; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_347 AS (
	"1 *обов'язковий" numeric,
	"2 *обов'язковий" numeric,
	"3 не обов'язковий" numeric,
	"4 не обов'язковий" numeric
);


--
-- Name: composite_type_audit_q_350; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_350 AS (
	"1 *обов'язковий" numeric,
	"2 *обов'язковий" numeric,
	"3 не обов'язковий" numeric,
	"4 не обов'язковий" numeric
);


--
-- Name: composite_type_audit_q_352; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_352 AS (
	"1 *question 1" numeric,
	"2 question 2" numeric,
	"3 *question 3" numeric,
	"4 question 4" numeric
);


--
-- Name: composite_type_audit_q_356; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_356 AS (
	"1 *some 1?" numeric,
	"2 some 2" numeric
);


--
-- Name: composite_type_audit_q_358; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_358 AS (
	"1 *dsadasdsadsa" numeric
);


--
-- Name: composite_type_audit_q_360; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_360 AS (
	"1 *тест" numeric,
	"2 кв" numeric
);


--
-- Name: composite_type_audit_q_361; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_361 AS (
	"1 *1" numeric,
	"2 fdnkfd" numeric
);


--
-- Name: composite_type_audit_q_363; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_363 AS (
	"1 *Наскільки задоволені Ви якіс" numeric,
	"2 Як оцінюєте оператора кол-цен" numeric,
	"3 *Як би ви оцінили оператора к" numeric,
	"4 *Наскільки ефективно оператор" numeric,
	"5 Чи зрозуміло оператор кол-цен" numeric,
	"6 *Чи були оператори кол-центру" numeric,
	"7 Як оцінюєте оператора кол-цен" numeric
);


--
-- Name: composite_type_audit_q_371; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_371 AS (
	"1 *вфівіфвфівфвф" numeric
);


--
-- Name: composite_type_audit_q_372; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_372 AS (
	"1 *dasdsadasdas" numeric
);


--
-- Name: composite_type_audit_q_373; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_373 AS (
	"1 *dasdsadasdas" numeric
);


--
-- Name: composite_type_audit_q_374; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_374 AS (
	"1 *dd3we1q21321" numeric,
	"2 *dddddd" numeric
);


--
-- Name: composite_type_audit_q_378; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_378 AS (
	"1 *перший критерій" numeric,
	"2 *другий критерій" numeric,
	"3 *третій критерій" numeric
);


--
-- Name: composite_type_audit_q_380; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_380 AS (
	"1 *Завершення розмови" numeric
);


--
-- Name: composite_type_audit_q_382; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_382 AS (
	"1 *required" numeric,
	"2 *required 2.0" numeric,
	"3 Not required " numeric,
	"4 *required  3.0" numeric
);


--
-- Name: composite_type_audit_q_384; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_384 AS (
	"1 *required" numeric,
	"2 *required 2.0" numeric,
	"3 Not required " numeric,
	"4 *required " numeric,
	"5 Not required " numeric,
	"6 *required 4.0" numeric,
	"7 *required  5.0" numeric,
	"8 *required  6.0" numeric,
	"9 *not required  7.0" numeric,
	"10 *required  8.0" numeric,
	"11 *required  9.0" numeric,
	"12 not required  10.0" numeric
);


--
-- Name: composite_type_audit_q_385; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_385 AS (
	"1 *Привітання" numeric,
	"2 *Назва" numeric,
	"3 *Привітання" numeric,
	"4 *Назва 3" numeric,
	"5 *Назва 4" numeric,
	"6 *Назва 5" numeric,
	"7 *Назва 6" numeric,
	"8 *Назва 7" numeric,
	"9 *Назва 8" numeric,
	"10 *Назва 9" numeric,
	"11 *Назва 10" numeric
);


--
-- Name: composite_type_audit_q_386; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_386 AS (
	"1 *Lorem ipsum dolor sit amet, " numeric
);


--
-- Name: composite_type_audit_q_390; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_390 AS (
	"1 *required" numeric,
	"2 *required 2.0" numeric,
	"3 Not required " numeric,
	"4 required  3.0" numeric
);


--
-- Name: composite_type_audit_q_392; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_392 AS (
	"1 *required" numeric,
	"2 *required 2.0" numeric,
	"3 *Not required " numeric,
	"4 required  3.0" numeric
);


--
-- Name: composite_type_audit_q_393; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_393 AS (
	"1 *Pozdrav/Představení se" numeric,
	"2 *Test score" numeric
);


--
-- Name: composite_type_audit_q_397; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_397 AS (
	"1 *питання" numeric,
	"2 *питання 2 " numeric,
	"3 питання 3" numeric,
	"4 *питання 4 " numeric,
	"5 питання 5 " numeric,
	"6 *питання 6" numeric
);


--
-- Name: composite_type_audit_q_398; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_398 AS (
	"1 *q1" numeric,
	"2 q1" numeric,
	"3 *q2" numeric,
	"4 q3" numeric
);


--
-- Name: composite_type_audit_q_399; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_399 AS (
	"1 *питання" numeric
);


--
-- Name: composite_type_audit_q_400; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_400 AS (
	"1 *питання 1" numeric,
	"2 *питання 2" numeric,
	"3 *питання 3" numeric,
	"4 *питання 4" numeric
);


--
-- Name: composite_type_audit_q_401; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_401 AS (
	"1 *Питання 1 " numeric,
	"2 *Питання 2" numeric,
	"3 Питання 3" numeric
);


--
-- Name: composite_type_audit_q_403; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_403 AS (
	"1 *Прозвучало ли приветствие?" numeric,
	"2 *Какой балл вы выставите за в" numeric,
	"3 *Оцените полноту ответа опера" numeric
);


--
-- Name: composite_type_audit_q_406; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_406 AS (
	"1 *123" numeric
);


--
-- Name: composite_type_audit_q_412; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_412 AS (
	"1 *123" numeric
);


--
-- Name: composite_type_audit_q_414; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_414 AS (
	"1 *критерій" numeric
);


--
-- Name: composite_type_audit_q_416; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_416 AS (
	"1 *критерій" numeric
);


--
-- Name: composite_type_audit_q_417; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_417 AS (
	"1 *критерій" numeric
);


--
-- Name: composite_type_audit_q_418; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_418 AS (
	"1 *e" numeric
);


--
-- Name: composite_type_audit_q_423; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_423 AS (
	"1 *dsfd" numeric
);


--
-- Name: composite_type_audit_q_425; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_425 AS (
	"1 *Criteria" numeric
);


--
-- Name: composite_type_audit_q_454; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_454 AS (
	"1 *Criteria" numeric
);


--
-- Name: composite_type_audit_q_466; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_466 AS (
	"1 *criteria" numeric
);


--
-- Name: composite_type_audit_q_474; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_474 AS (
	"1 *ффф" numeric
);


--
-- Name: composite_type_audit_q_475; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_475 AS (
	"1 *сччяячсчяч" numeric
);


--
-- Name: composite_type_audit_q_476; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_476 AS (
	"1 *Criteria" numeric
);


--
-- Name: composite_type_audit_q_478; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_478 AS (
	"1 *Criteria" numeric
);


--
-- Name: composite_type_audit_q_484; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_484 AS (
	"1 *fc" numeric
);


--
-- Name: composite_type_audit_q_498; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_498 AS (
	"1 *aaaa" numeric
);


--
-- Name: composite_type_audit_q_503; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_503 AS (
	"1 *aaaaa122334" numeric,
	"2 *aaaaa122334" numeric
);


--
-- Name: composite_type_audit_q_513; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_513 AS (
	"1 *чссччс" numeric
);


--
-- Name: composite_type_audit_q_516; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_516 AS (
	"1 *TestDmytro01" numeric,
	"2 *a1" numeric
);


--
-- Name: composite_type_audit_q_517; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_517 AS (
	"1 *ТестКритерій" numeric
);


--
-- Name: composite_type_audit_q_523; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_523 AS (
	"1 *speed" numeric,
	"2 answer sit" numeric,
	"3 *Did the agent verify custome" numeric,
	"4 Did the agent verify first id" numeric,
	"5 *Did the agent verify second " numeric
);


--
-- Name: composite_type_audit_q_526; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_526 AS (
	"1 *speed" numeric,
	"2 answer sit" numeric,
	"3 *second option" numeric,
	"4 *3'rd option" numeric
);


--
-- Name: composite_type_audit_q_533; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.composite_type_audit_q_533 AS (
	"1 *speed" numeric,
	"2 answer sit" numeric,
	"3 *second option" numeric,
	"4 *3'rd option" numeric
);


--
-- Name: appointment_widget(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.appointment_widget(_uri character varying) RETURNS TABLE(profile jsonb, list jsonb)
    LANGUAGE sql ROWS 1
    AS $$
with profile as (
        select
           (config['queue']->>'id')::int as queue_id,
           (config['communicationType']->>'id')::int as communication_type,
           (config->>'duration')::interval as duration,
           (config->>'days')::int as days,
           (config->>'availableAgents')::int as available_agents,
           string_to_array((b.metadata->>'allow_origin'), ',') as allow_origins,
           q.calendar_id,
           b.id,
           b.uri,
           b.dc as domain_id,
           c.timezone_id,
           tz.sys_name as timezone
        from chat.bot b
            inner join lateral (select (b.metadata->>'appointment')::jsonb as config) as cfx on true
            inner join call_center.cc_queue q on q.id = (config['queue']->>'id')::int
            inner join flow.calendar c on c.id = q.calendar_id
            inner join flow.calendar_timezones tz on tz.id = c.timezone_id
        where b.uri = _uri and b.enabled
        limit 1
    ), d as materialized (
        select  q.queue_id,
                q.duration,
                q.available_agents,
                q.timezone,
                x,
               (extract(isodow from x::timestamp)  ) - 1 as day,
               dy.*,
               min(dy.ss::time) over () mins,
               max(dy.se::time) over () maxe
        from profile  q ,
            flow.calendar_day_range(q.calendar_id, least(q.days, 7)) x
            left join lateral (
                select t.*, tz.sys_name, c.excepts
                from flow.calendar c
                    inner join flow.calendar_timezones tz on tz.id = c.timezone_id
                    inner join lateral unnest(c.accepts::flow.calendar_accept_time[]) t on true
                where c.id = q.calendar_id
                    and not t.disabled
                order by 1 asc
        ) y on y.day = (extract(isodow from x)  ) - 1
        left join lateral (
            select (x + (y.start_time_of_day || 'm')::interval)::timestamp as ss,
                case when date_bin(q.duration, (x + (y.end_time_of_day || 'm')::interval)::timestamp, x::timestamp) < (x + (y.end_time_of_day || 'm')::interval)::timestamp
                    then date_bin(q.duration, (x + (y.end_time_of_day || 'm')::interval)::timestamp, x::timestamp) - q.duration
                    else date_bin(q.duration, (x + (y.end_time_of_day || 'm')::interval)::timestamp, x::timestamp) - q.duration end as se
        ) dy on true
    )
    , min_max as materialized (
        select
            queue_id,
            x,
            duration,
            min(ss)  min_ss,
            max(se)  max_se
        from d
        group by 1, 2, 3
    )
    ,res as materialized (
        select
        mem.*
        from min_max
            left join lateral (
                select
                    date_bin(min_max.duration, coalesce(ready_at, created_at), coalesce(ready_at, created_at)::date)::timestamp d,
                    count(*) cnt
                from call_center.cc_member m
                where m.stop_at isnull
                    and m.queue_id = min_max.queue_id
                    and coalesce(ready_at, created_at) between min_max.min_ss and min_max.max_se
                group by 1
            ) mem on true
        where mem notnull
    )
    , list as (
        select
            d.*,
            res.*,
            xx,
            case when xx < now() at time zone d.timezone or coalesce(res.cnt, 0) >= d.available_agents or xx < d.ss or xx > d.se then true
                else false end as reserved
        from d
            left join generate_series((d.x || ' ' || d.mins)::timestamp, (d.x || ' ' || d.maxe)::timestamp, d.duration) xx on true
            left join res on res.d = xx
        limit 10080
    )
    , ranges AS (
        select
            to_char(list.x::date,'YYYY-MM-DD')::text as date,
            jsonb_agg(jsonb_build_object('time', to_char(list.xx::time, 'HH24:MI'), 'reserved', list.reserved) order by list.x, list.xx) as times
        from list
        group by 1
    )
    select
        row_to_json(p) as profile,
        jsonb_agg(row_to_json(r)) as list
    from profile p
        left join lateral (
            select *
            from ranges
        ) r on true
    group by p
$$;


--
-- Name: cc_agent_init_channel(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_agent_init_channel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
        insert into call_center.cc_agent_channel (agent_id, channel, state)
        select new.id, c, 'waiting'
        from unnest('{chat,call,task,out_call}'::text[]) c;
        RETURN NEW;
    END;
$$;


--
-- Name: cc_agent_screen_control_tg(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_agent_screen_control_tg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    declare team_sc bool = false;
BEGIN

    if TG_OP = 'INSERT' OR new.screen_control IS DISTINCT FROM old.screen_control then
        select screen_control
        into team_sc
        from call_center.cc_team t
        where t.id = new.team_id;

        if TG_OP = 'INSERT' then
            new.screen_control = team_sc;
        end if;

        if team_sc and not new.screen_control then
            RAISE EXCEPTION 'The screen_control option is enabled at the team level for this agent. This setting has priority and cannot be overridden at the agent level.'               --'Changing agent''s screen_control is not allowed.'
            USING
                DETAIL = 'The screen_control option is enabled at the team level for this agent. This setting has priority and cannot be overridden at the agent level.',
                HINT = 'To change this setting, disable the screen_control option in the team settings or move the agent to another team.',
                ERRCODE = '09000';
        end if;
    end if;

    RETURN new;
END;
$$;


--
-- Name: cc_agent_set_channel_waiting(integer, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_agent_set_channel_waiting(agent_id_ integer, channel_ character varying) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare attempt_id_ int8;
        state_ varchar;
        joined_at_ timestamptz;
begin
    select a.id, a.state
    into attempt_id_, state_
    from call_center.cc_member_attempt a
    where a.agent_id = agent_id_ and a.state != 'leaving' and a.channel = channel_;

    if attempt_id_ notnull then
        raise exception 'agent % has task % in the status of %', agent_id_, attempt_id_, state_;
    end if;

    update call_center.cc_agent_channel c
    set state = 'waiting',
        joined_at = now(),
        queue_id = null,
        attempt_id = null,
        timeout = null
    where c.agent_id = agent_id_ and c.state in ('wrap_time', 'missed') and c.channel = channel_
    returning joined_at into joined_at_;

    return row(joined_at_);
end;
$$;


--
-- Name: cc_agent_set_login(integer, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_agent_set_login(agent_id_ integer, on_demand_ boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    screen_control_ bool;
    res_ jsonb;
    user_id_
         int8;
begin
    update call_center.cc_agent
    set status            = 'online', -- enum added
        status_payload    = null,
        on_demand         = on_demand_,
--         updated_at = case when on_demand != on_demand_ then cc_view_timestamp(now()) else updated_at end,
        last_state_change = now()     -- todo rename to status
    where call_center.cc_agent.id = agent_id_
    returning user_id, screen_control into user_id_, screen_control_;

    if screen_control_ and not exists(select 1 from call_center.socket_session ss
                                              where ss.user_id = user_id_ and application_name = 'desc_track' and now() - ss.updated_at < '65 sec'::interval) then
        RAISE EXCEPTION 'The agent must connect via the "desc_track" client application.'
        USING
            DETAIL = 'The agent must connect via the "desc_track" client application.',
            ERRCODE = '09000';
    end if;

    if
        NOT (exists(select 1
                    from directory.wbt_user_presence p
                    where user_id = user_id_
                      and open > 0
                      and status in ('sip', 'web'))
            or exists(SELECT 1
                      FROM directory.wbt_session s
                      WHERE ((user_id IS NOT NULL) AND (NULLIF((props ->> 'pn-rpid'::text), ''::text) IS NOT NULL))
                        and s.user_id = user_id_::int8
                        and s.access notnull
                        AND s.expires > now() at time zone 'UTC')) then
        raise exception 'not found: sip, web or pn';
    end if;

    with chls as (
        update call_center.cc_agent_channel c
            set state = case when x.x = 1 then c.state else 'waiting' end,
                online = true,
                no_answers = 0,
                timeout = case when x.x = 1 then c.timeout else null end
            from call_center.cc_agent_channel c2
                left join LATERAL (
                    select a.channel, 1 x
                    from call_center.cc_member_attempt a
                    where a.agent_id = agent_id_
                      and a.channel = c2.channel
                    limit 1
                    ) x
                on true
            where c2.agent_id = agent_id_
                and (c.agent_id, c.channel) = (c2.agent_id, c2.channel)
            returning jsonb_build_object('channel'
                , c.channel
                , 'joined_at'
                , call_center.cc_view_timestamp(c.joined_at)
                , 'state'
                , c.state
                , 'no_answers'
                , c.no_answers) xx
    )
    select jsonb_agg(chls.xx)
    from chls
    into res_;

    return row (res_::jsonb, call_center.cc_view_timestamp(now()));
end;
$$;


--
-- Name: cc_arr_type_to_jsonb(anyarray); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_arr_type_to_jsonb(anyarray) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $_$
select jsonb_agg(row_to_json(a))
    from unnest($1) a;
$_$;


--
-- Name: cc_array_merge(anyarray, anyarray); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_array_merge(arr1 anyarray, arr2 anyarray) RETURNS anyarray
    LANGUAGE sql IMMUTABLE
    AS $$
select array_agg(distinct elem order by elem)
    from (
        select unnest(arr1) elem
        union
        select unnest(arr2)
    ) s
$$;


--
-- Name: cc_array_to_string(text[], text); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_array_to_string(text[], text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$SELECT array_to_string($1, $2)$_$;


--
-- Name: cc_attempt_abandoned(bigint, integer, integer, jsonb, boolean, boolean, boolean, character varying, integer, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_abandoned(attempt_id_ bigint, _max_count integer DEFAULT 0, _next_after integer DEFAULT 0, vars_ jsonb DEFAULT NULL::jsonb, _per_number boolean DEFAULT false, exclude_dest boolean DEFAULT false, redial boolean DEFAULT false, _description character varying DEFAULT NULL::character varying, _sticky_agent_id integer DEFAULT NULL::integer, _display boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt  call_center.cc_member_attempt%rowtype;
    member_stop_cause varchar;
begin
    update call_center.cc_member_attempt
        set leaving_at = now(),
            last_state_change = now(),
            result = case when offering_at isnull and resource_id notnull then 'failed' else 'abandoned' end,
            state = 'leaving',
            description = case when _description notnull then _description else description end
    where id = attempt_id_
    returning * into attempt;

    if attempt.member_id notnull then
        update call_center.cc_member
        set last_hangup_at  = (extract(EPOCH from now() ) * 1000)::int8,
            last_agent      = coalesce(attempt.agent_id, last_agent),
            stop_at = case when (stop_cause notnull or
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (_max_count > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < _max_count)) else (_max_count > 0 and (attempts + 1 < _max_count)) end
                                 )  then stop_at else  attempt.leaving_at end,
            stop_cause = case when (stop_cause notnull or
                                 case when _per_number is true then (attempt.waiting_other_numbers > 0 or (_max_count > 0 and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < _max_count)) else (_max_count > 0 and (attempts + 1 < _max_count)) end
                                 ) then stop_cause else attempt.result end,
            ready_at = now() + (_next_after || ' sec')::interval,
            communications =  jsonb_set(communications, (array[attempt.communication_idx::int])::text[], communications->(attempt.communication_idx::int) ||
                jsonb_build_object('last_activity_at', (case when redial is true then 0 else extract(epoch  from attempt.leaving_at) * 1000 end )::int8::text::jsonb) ||
                jsonb_build_object('attempt_id', attempt_id_) ||
                jsonb_build_object('attempts', coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                case when exclude_dest or (_per_number is true and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= _max_count) then jsonb_build_object('stop_at', (extract(EPOCH from now() ) * 1000)::int8) else '{}'::jsonb end
            ),
            variables = case when vars_ notnull then coalesce(variables::jsonb, '{}') || vars_ else variables end,
            attempts        = attempts + 1,                     --TODO
            agent_id = case when _sticky_agent_id notnull then _sticky_agent_id else agent_id end
        where id = attempt.member_id
        returning stop_cause into member_stop_cause;
    end if;


    return row(attempt.last_state_change::timestamptz, member_stop_cause::varchar, attempt.result::varchar);
end;
$$;


--
-- Name: cc_attempt_agent_cancel(bigint, character varying, character varying, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_agent_cancel(attempt_id_ bigint, result_ character varying, agent_status_ character varying, agent_hold_sec_ integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
    no_answers_ int4;
begin
    update call_center.cc_member_attempt
        set leaving_at = now(),
            result = result_,
            state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    if attempt.agent_id notnull then
        update call_center.cc_agent_channel c
        set state = agent_status_,
            joined_at = attempt.leaving_at,
            no_answers = no_answers + 1,
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where c.agent_id = attempt.agent_id and c.channel = attempt.channel
        returning no_answers into no_answers_;

    end if;

    return row(attempt.leaving_at, no_answers_);
end;
$$;


--
-- Name: cc_attempt_bridged(bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_bridged(attempt_id_ bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
begin

    update call_center.cc_member_attempt
    set state = 'bridged',
        bridged_at = now(),
        last_state_change = now()
    where id = attempt_id_
    returning * into attempt;


    if attempt.agent_id notnull then
        update call_center.cc_agent_channel ch
        set state = attempt.state,
            no_answers = 0,
            joined_at = attempt.bridged_at,
            last_bridged_at = now()
        where  ch.agent_id = attempt.agent_id and ch.channel = attempt.channel;
    end if;

    return row(attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_attempt_distribute_cancel(bigint, character varying, integer, boolean, jsonb); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_attempt_distribute_cancel(IN attempt_id_ bigint, IN description_ character varying, IN next_distribute_sec_ integer, IN stop_ boolean, IN vars_ jsonb)
    LANGUAGE plpgsql
    AS $$
declare
    attempt  call_center.cc_member_attempt%rowtype;
begin
    update call_center.cc_member_attempt
        set leaving_at = now(),
            description = description_,
            last_state_change = now(),
            result = 'cancel', --TODO
            state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    update call_center.cc_member
    set last_hangup_at  = (extract(EPOCH from now() ) * 1000)::int8,
        last_agent      = coalesce(attempt.agent_id, last_agent),
        variables = case when vars_ notnull  then coalesce(variables, '{}'::jsonb) || vars_ else variables end,
        ready_at = case when next_distribute_sec_ > 0 then now() + (next_distribute_sec_::text || ' sec')::interval else now() end,
        stop_at = case when stop_ is true and stop_at isnull then attempt.leaving_at else stop_at end,
        stop_cause = case when stop_ is true and stop_cause isnull then attempt.result else stop_cause end
    where id = attempt.member_id;

end;
$$;


--
-- Name: cc_attempt_end_reporting(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb, integer, integer, boolean, boolean, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, exclude_dest boolean DEFAULT NULL::boolean, per_number_ boolean DEFAULT false, only_current_communication_ boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
    agent_timeout_ timestamptz;
    time_ int8 = extract(EPOCH  from now()) * 1000;
    user_id_ int8 = null;
    domain_id_ int8;
    wrap_time_ int;
    other_cnt_ int;
    stop_cause_ varchar;
    agent_channel_ varchar;
begin

    if next_offering_at_ notnull and not attempt.result in ('success', 'cancel') and next_offering_at_ < now() then
        -- todo move to application
        raise exception 'bad parameter: next distribute at';
    end if;


    update call_center.cc_member_attempt
        set state  =  'leaving',
            reporting_at = now(),
            leaving_at = case when leaving_at isnull then now() else leaving_at end,
            result = status_,
            variables = case when variables_ notnull then coalesce(variables::jsonb, '{}') || variables_ else variables end,
            description = description_
    where id = attempt_id_ and state != 'leaving'
    returning * into attempt;

    if attempt.id isnull then
        return null;
--         raise exception  'not found %', attempt_id_;
    end if;

    if attempt.member_id notnull then
        update call_center.cc_member m
        set last_hangup_at  = time_,
            variables = case when variables_ notnull then coalesce(m.variables::jsonb, '{}') || variables_ else m.variables end,
            expire_at = case when expire_at_ isnull then m.expire_at else expire_at_ end,
            agent_id = case when sticky_agent_id_ isnull then m.agent_id else sticky_agent_id_ end,

            stop_at = case when next_offering_at_ notnull or
                                m.stop_at notnull or
                                only_current_communication_ or
                                (not attempt.result in ('success', 'cancel') and
                                 case when per_number_ is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                 )
                then m.stop_at else  attempt.leaving_at end,
            stop_cause = case when next_offering_at_ notnull or
                                m.stop_at notnull or
                                only_current_communication_ or
                                (not attempt.result in ('success', 'cancel') and
                                   case when per_number_ is true then (attempt.waiting_other_numbers > 0 or (max_attempts_ > 0 and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 < max_attempts_)) else (max_attempts_ > 0 and (m.attempts + 1 < max_attempts_)) end
                                 )
                then m.stop_cause else  attempt.result end,

            ready_at = case when next_offering_at_ notnull then next_offering_at_ at time zone tz.names[1]
                else now() + (wait_between_retries_ || ' sec')::interval end,

            last_agent      = coalesce(attempt.agent_id, m.last_agent),
            communications =  jsonb_set(
                   --WTEL-5908
                    case when only_current_communication_
                             then (select jsonb_agg(x || case
                                        when coalesce((x->>'stop_at')::int8, 0) = 0 and rn - 1 != attempt.communication_idx::int
                                            then jsonb_build_object('stop_at', time_)
                                            else '{}'
                                        end order by rn)
                                   from jsonb_array_elements(m.communications) WITH ORDINALITY AS t (x, rn)
                        ) else m.communications end
                , (array[attempt.communication_idx::int])::text[], m.communications->(attempt.communication_idx::int) ||
                jsonb_build_object('last_activity_at', case when next_offering_at_ notnull then '0'::text::jsonb else time_::text::jsonb end) ||
                jsonb_build_object('attempt_id', attempt_id_) ||
                jsonb_build_object('attempts', coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                case when exclude_dest or
                          (per_number_ is true and coalesce((m.communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= max_attempts_) then jsonb_build_object('stop_at', time_) else '{}'::jsonb end
            ),
            attempts        = m.attempts + 1                     --TODO
        from call_center.cc_member m2
            left join flow.calendar_timezone_offsets tz on tz.id = m2.sys_offset_id
        where m.id = attempt.member_id and m.id = m2.id
        returning m.stop_cause into stop_cause_;
    end if;

    if attempt.agent_id notnull then
        select a.user_id, a.domain_id, case when a.on_demand then null else coalesce(tm.wrap_up_time, 0) end,
               case when attempt.channel = 'chat' then (select count(1)
                                                        from call_center.cc_member_attempt aa
                                                        where aa.agent_id = attempt.agent_id and aa.id != attempt.id and aa.state != 'leaving') else 0 end as other
        into user_id_, domain_id_, wrap_time_, other_cnt_
        from call_center.cc_agent a
            left join call_center.cc_team tm on tm.id = attempt.team_id
        where a.id = attempt.agent_id;

        if other_cnt_ > 0 then
            update call_center.cc_agent_channel c
            set last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning null, channel into agent_timeout_, agent_channel_;
        elseif wrap_time_ > 0 or wrap_time_ isnull then
            update call_center.cc_agent_channel c
            set state = 'wrap_time',
                joined_at = now(),
                timeout = case when wrap_time_ > 0 then now() + (wrap_time_ || ' sec')::interval end,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning timeout, channel into agent_timeout_, agent_channel_;
        else
            update call_center.cc_agent_channel c
            set state = 'waiting',
                joined_at = now(),
                timeout = null,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id),
                queue_id = null
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning timeout, channel into agent_timeout_, agent_channel_;
        end if;
    end if;

    return row(call_center.cc_view_timestamp(now()),
        attempt.channel,
        attempt.queue_id,
        attempt.agent_call_id,
        attempt.agent_id,
        user_id_,
        domain_id_,
        call_center.cc_view_timestamp(agent_timeout_),
        stop_cause_,
        attempt.member_id
        );
end;
$$;


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


--
-- Name: cc_attempt_leaving(bigint, character varying, character varying, integer, jsonb, integer, integer, boolean, character varying, integer, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_leaving(attempt_id_ bigint, result_ character varying, agent_status_ character varying, agent_hold_sec_ integer, vars_ jsonb DEFAULT NULL::jsonb, max_attempts_ integer DEFAULT 0, wait_between_retries_ integer DEFAULT 60, per_number_ boolean DEFAULT false, _description character varying DEFAULT NULL::character varying, _sticky_agent_id integer DEFAULT NULL::integer, _display boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
    no_answers_ int;
    member_stop_cause varchar;
begin
    /*
     FIXME
     */
    update call_center.cc_member_attempt
    set leaving_at = now(),
        result = result_,
        state = 'leaving',
        description = case when _description notnull then _description else description end
    where id = attempt_id_
    returning * into attempt;

    if attempt.member_id notnull then
        update call_center.cc_member m
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

            ready_at = now() + (coalesce(wait_between_retries_, 0) || ' sec')::interval,

            communications =  jsonb_set(communications, (array[attempt.communication_idx::int])::text[], communications->(attempt.communication_idx::int) ||
                                                                                                         jsonb_build_object('last_activity_at', (extract(epoch  from attempt.leaving_at) * 1000)::int8::text::jsonb) ||
                                                                                                         jsonb_build_object('attempt_id', attempt_id_) ||
                                                                                                         jsonb_build_object('attempts', coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1) ||
                                                                                                         case when (per_number_ is true and coalesce((communications#>(format('{%s,attempts}', attempt.communication_idx::int)::text[]))::int, 0) + 1 >= max_attempts_) then jsonb_build_object('stop_at', (extract(EPOCH from now() ) * 1000)::int8) else '{}'::jsonb end
                ),
            attempts        = attempts + 1,
            variables = case when vars_ notnull then coalesce(variables::jsonb, '{}') || vars_ else variables end,
            agent_id = case when _sticky_agent_id notnull then _sticky_agent_id else agent_id end
        where id = attempt.member_id
        returning stop_cause into member_stop_cause;
    end if;

    if attempt.agent_id notnull then
        update call_center.cc_agent_channel c
        set state = case when agent_hold_sec_ > 0 then 'wrap_time' else 'waiting' end,
            joined_at = now(),
            no_answers = case when attempt.bridged_at notnull then 0 else no_answers + 1 end,
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where c.agent_id = attempt.agent_id and c.channel = attempt.channel
        returning no_answers into no_answers_;

    end if;

    return row(attempt.leaving_at, no_answers_, member_stop_cause);
end;
$$;


--
-- Name: cc_attempt_missed_agent(bigint, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_missed_agent(attempt_id_ bigint, agent_hold_ integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    last_state_change_ timestamptz;
    channel_ varchar;
    agent_id_ int4;
    no_answers_ int4;
begin
    update call_center.cc_member_attempt  n
    set state = 'wait_agent',
        last_state_change = now(),
        agent_id = null ,
        team_id = null,
        agent_call_id = null
    from call_center.cc_member_attempt a
    where a.id = n.id and a.id = attempt_id_
    returning n.last_state_change, a.agent_id, n.channel into last_state_change_, agent_id_, channel_;

    if agent_id_ notnull then
        update call_center.cc_agent_channel c
        set state = 'missed',
            joined_at = last_state_change_,
            timeout  = now() + (agent_hold_::varchar || ' sec')::interval,
            no_answers = (no_answers + 1),
            last_missed_at = now()
        where c.agent_id = agent_id_ and c.channel = channel_
        returning no_answers into no_answers_;
    end if;

    return row(last_state_change_, no_answers_);
end;
$$;


--
-- Name: cc_attempt_offering(bigint, integer, character varying, character varying, character varying, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_offering(attempt_id_ bigint, agent_id_ integer, agent_call_id_ character varying, member_call_id_ character varying, dest_ character varying, displ_ character varying) RETURNS record
    LANGUAGE plpgsql
    AS $$declare
    attempt call_center.cc_member_attempt%rowtype;
begin

    update call_center.cc_member_attempt
    set state             = 'offering',
        last_state_change = now(),
        offered_agent_ids = case when coalesce(agent_id, agent_id_) = any (cc_member_attempt.offered_agent_ids)
             then cc_member_attempt.offered_agent_ids else array_append(offered_agent_ids, coalesce(agent_id, agent_id_)) end,
        display = displ_,
        offering_at       = now(),
        agent_id          = coalesce(agent_id, agent_id_),
        agent_call_id     = coalesce(agent_call_id, agent_call_id_::varchar),
        -- todo for queue preview
        member_call_id    = coalesce(member_call_id, member_call_id_)
    where id = attempt_id_
    returning * into attempt;


    if attempt.agent_id notnull then
        update call_center.cc_agent_channel ch
        set state            = 'offering',
            joined_at        = now(),
            last_offering_at = now(),
            queue_id         = attempt.queue_id,
            attempt_id         = case when attempt.channel = 'call' then attempt.id else null end,
            last_bucket_id   = coalesce(attempt.bucket_id, last_bucket_id)
        where (ch.agent_id, ch.channel) = (attempt.agent_id, attempt.channel);
    end if;

    return row (attempt.last_state_change::timestamptz);
end;
$$;


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
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where c.agent_id = attempt.agent_id and c.channel = attempt.channel;

    end if;

    return now();
end;
$$;


--
-- Name: cc_attempt_transferred_from(bigint, bigint, integer, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_transferred_from(attempt_id_ bigint, to_attempt_id_ bigint, to_agent_id_ integer, agent_sess_id_ character varying) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
        user_id_ int8 = null;
    domain_id_ int8;
    wrap_time_ int;
     agent_timeout_ timestamptz;
begin

    update call_center.cc_member_attempt
    set transferred_agent_id = agent_id,
        agent_id = to_agent_id_,
        agent_call_id = agent_sess_id_
    where id = attempt_id_
    returning * into attempt;

    insert into call_center.cc_member_attempt_transferred (from_id, to_id, from_agent_id, to_agent_id)
    values (to_attempt_id_, attempt_id_, attempt.transferred_agent_id, attempt.agent_id);

    if attempt.transferred_agent_id notnull then
        select a.user_id, a.domain_id, case when a.on_demand then null else coalesce(tm.wrap_up_time, 0) end
        into user_id_, domain_id_, wrap_time_
        from call_center.cc_agent a
            left join call_center.cc_team tm on tm.id = attempt.team_id
        where a.id = attempt.transferred_agent_id;

        if wrap_time_ > 0 or wrap_time_ isnull then
            update call_center.cc_agent_channel c
            set state = 'wrap_time',
                joined_at = now(),
                timeout = case when wrap_time_ > 0 then now() + (wrap_time_ || ' sec')::interval end,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.transferred_agent_id, attempt.channel)
            returning timeout into agent_timeout_;
        else
            update call_center.cc_agent_channel c
            set state = 'waiting',
                joined_at = now(),
                timeout = null,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id),
                queue_id = null
            where (c.agent_id, c.channel) = (attempt.transferred_agent_id, attempt.channel)
            returning timeout into agent_timeout_;
        end if;
    end if;


    return row(attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_attempt_transferred_to(bigint, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_transferred_to(attempt_id_ bigint, to_attempt_id_ bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
begin

    update call_center.cc_member_attempt
    set transferred_attempt_id = to_attempt_id_,
        result = 'transferred',
        leaving_at = now(),
        last_state_change = now(),
        state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    return row(attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_attempt_waiting_agent(bigint, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_waiting_agent(attempt_id_ bigint, agent_hold_ integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    last_state_change_ timestamptz;
    channel_ varchar;
    agent_id_ int4;
    no_answers_ int4;
begin
    update call_center.cc_member_attempt  n
    set state = 'wait_agent',
        last_state_change = now(),
        agent_id = null ,
        team_id = null,
        agent_call_id = null
    from call_center.cc_member_attempt a
    where a.id = n.id and a.id = attempt_id_
    returning n.last_state_change, a.agent_id, n.channel into last_state_change_, agent_id_, channel_;

    if agent_id_ notnull then
        update call_center.cc_agent_channel c
        set state = 'waiting',
            joined_at = last_state_change_,
            timeout  = null,
            no_answers = 0,
            last_missed_at = now(),
            attempt_id = null,
            queue_id = null
        where c.agent_id = agent_id_ and c.channel = channel_
        returning no_answers into no_answers_;
    end if;

    return row(last_state_change_, no_answers_);
end;
$$;


--
-- Name: cc_bridged_id(uuid); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_bridged_id(uuid) RETURNS uuid
    LANGUAGE sql IMMUTABLE
    AS $_$
select lega.bridged_id from call_center.cc_calls_history lega where lega.id = $1
$_$;


--
-- Name: cc_call_active_numbers(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_call_active_numbers() RETURNS SETOF character varying
    LANGUAGE plpgsql
    AS $$declare
        c call_center.cc_calls;
BEGIN

    for c in select *
            from call_center.cc_calls cc where cc.hangup_at isnull and not cc.direction isnull
            and ( (cc.gateway_id notnull and cc.direction = 'outbound') or (cc.gateway_id notnull and cc.direction = 'inbound') )
    loop
        if c.gateway_id notnull and c.direction = 'outbound' then
            return next c.to_number;
        elseif c.gateway_id notnull and c.direction = 'inbound' then
            return next c.from_number;
        end if;

    end loop;
    END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cc_calls; Type: TABLE; Schema: call_center; Owner: -
--

CREATE UNLOGGED TABLE call_center.cc_calls (
    id uuid NOT NULL,
    direction character varying,
    destination character varying,
    parent_id uuid,
    state character varying NOT NULL,
    app_id character varying NOT NULL,
    from_type character varying,
    from_name character varying,
    from_number character varying,
    from_id character varying,
    to_type character varying,
    to_name character varying,
    to_number character varying,
    to_id character varying,
    payload jsonb,
    domain_id bigint NOT NULL,
    hold_sec integer DEFAULT 0 NOT NULL,
    cause character varying,
    sip_code smallint,
    bridged_id uuid,
    user_id bigint,
    gateway_id bigint,
    queue_id integer,
    agent_id integer,
    team_id integer,
    attempt_id bigint,
    member_id bigint,
    type character varying DEFAULT 'call'::character varying,
    "timestamp" timestamp with time zone,
    answered_at timestamp with time zone,
    bridged_at timestamp with time zone,
    hangup_at timestamp with time zone,
    created_at timestamp with time zone,
    hangup_by character varying,
    transfer_from uuid,
    transfer_to uuid,
    amd_result character varying,
    amd_duration interval,
    tags character varying[],
    region_id integer,
    grantee_id integer,
    hold jsonb,
    params jsonb,
    blind_transfer character varying,
    talk_sec integer DEFAULT 0 NOT NULL,
    amd_ai_result character varying,
    amd_ai_logs character varying[],
    amd_ai_positive boolean,
    contact_id bigint,
    schema_ids integer[],
    heartbeat timestamp with time zone,
    hangup_phrase character varying,
    blind_transfers jsonb,
    did text,
    destination_name text,
    attempt_ids bigint[]
)
WITH (fillfactor='20', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01');


--
-- Name: cc_call_get_owner_leg(call_center.cc_calls); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_call_get_owner_leg(c_ call_center.cc_calls, OUT number_ character varying, OUT name_ character varying, OUT type_ character varying, OUT id_ character varying) RETURNS record
    LANGUAGE plpgsql IMMUTABLE
    AS $$
begin
    if c_.direction = 'inbound' or (c_.direction = 'outbound' and c_.gateway_id notnull ) then
        number_ := c_.to_number;
--         number_ := 'xxxxxx';
        name_ := c_.to_name;
        type_ := c_.to_type;
        id_ := c_.to_id;
    else
        number_ := c_.from_number;
        name_ := c_.from_name;
        type_ := c_.from_type;
        id_ := c_.from_id;

    end if;
end;
$$;


--
-- Name: cc_call_set_bridged(uuid, character varying, timestamp with time zone, character varying, bigint, uuid); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_call_set_bridged(IN call_id_ uuid, IN state_ character varying, IN timestamp_ timestamp with time zone, IN app_id_ character varying, IN domain_id_ bigint, IN call_bridged_id_ uuid)
    LANGUAGE plpgsql
    AS $$
declare
        transfer_to_ uuid;
        transfer_from_ uuid;
        transfer_from_name_ varchar;
        transfer_from_number_ varchar;
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
    returning c.transfer_to, cc.from_name, cc.from_number
        into transfer_to_, transfer_from_name_, transfer_from_number_;


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

        from_number = case
                            when transfer_from_number_ notnull and direction = 'inbound' and transfer_to_ notnull and cc.parent_id notnull and cc.parent_id != c.bridged_id
                            then transfer_from_number_
                            else from_number end,
        from_name = case
                            when transfer_from_name_ notnull and direction = 'inbound' and transfer_to_ notnull and cc.parent_id notnull and cc.parent_id != c.bridged_id
                            then transfer_from_name_
                            else from_name end,
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


--
-- Name: cc_calls_rbac_queues(bigint, bigint, integer[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_calls_rbac_queues(_domain_id bigint, _user_id bigint, _groups integer[]) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
    AS $$with x as (select a.user_id, a.id agent_id, a.supervisor, a.domain_id
               from directory.wbt_user u
                        inner join call_center.cc_agent a on a.user_id = u.id and a.domain_id = u.dc
               where u.id = _user_id
                 and u.dc = _domain_id)
    select array_agg(distinct t.queue_id)
    from (select qs.queue_id::int as queue_id
    from x
             left join lateral (
        select a.id, a.auditor_ids && array [x.user_id] aud
        from call_center.cc_agent a
        where (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and a.supervisor))
        union
        distinct
        select a.id, a.auditor_ids && array [x.user_id] aud
        from call_center.cc_team t
                 inner join call_center.cc_agent a on a.team_id = t.id
        where t.admin_ids && array [x.agent_id]
        ) a on true
             inner join call_center.cc_skill_in_agent sa on sa.agent_id = a.id
             inner join call_center.cc_queue_skill qs
                        on qs.skill_id = sa.skill_id and sa.capacity between qs.min_capacity and qs.max_capacity
    where sa.enabled
      and qs.enabled
      and a.aud
    union distinct
    select q.id
    from call_center.cc_queue q
    where q.domain_id = _domain_id
      and q.grantee_id = any (_groups)) t
$$;


--
-- Name: cc_calls_rbac_users(bigint, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_calls_rbac_users(_domain_id bigint, _user_id bigint) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
    AS $$
    with x as materialized (
        select a.user_id, a.id agent_id, a.supervisor, a.domain_id
        from directory.wbt_user u
                 inner join call_center.cc_agent a on a.user_id = u.id
        where u.id = _user_id
          and u.dc = _domain_id
    )
    select array_agg(distinct a.user_id::int) users
    from x
             left join lateral (
        select a.user_id, a.auditor_ids && array [x.user_id] aud
        from call_center.cc_agent a
        where a.domain_id = x.domain_id
          and (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and a.supervisor) or
               a.auditor_ids && array [x.user_id])

        union
        distinct

        select a.user_id, a.auditor_ids && array [x.user_id] aud
        from call_center.cc_team t
                 inner join call_center.cc_agent a on a.team_id = t.id
        where t.admin_ids && array [x.agent_id]
          and x.domain_id = t.domain_id
        ) a on true
$$;


--
-- Name: cc_calls_set_timing(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_calls_set_timing() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    if new.state = old.state then
        return new;
    end if;

    if new.state = 'active' then
        if new.answered_at isnull then
            new.answered_at = new.timestamp;

            if new.direction = 'inbound' and new.parent_id notnull and new.bridged_at isnull then
                new.bridged_at = new.answered_at;
            end if;

        else if old.state = 'hold' then
            new.hold_sec =  coalesce(old.hold_sec, 0) + extract ('epoch' from new.timestamp - old.timestamp)::double precision;
            if new.hold isnull then
                new.hold = '[]';
            end if;

            new.hold = new.hold || jsonb_build_object(
                'start', (extract(epoch from old.timestamp)::double precision * 1000)::int8,
                'finish', (extract(epoch from new.timestamp)::double precision * 1000)::int8,
                'sec', extract ('epoch' from new.timestamp - old.timestamp)::int8
            );


--             if new.parent_id notnull then
--                 update cc_calls set hold_sec  = hold_sec + new.hold_sec  where id = new.parent_id;
--             end if;
        end if;

        end if;
    else if (new.state = 'bridge') then
        new.bridged_at = coalesce(new.bridged_at, new.timestamp);
    else if new.state = 'hangup' then
        new.hangup_at = new.timestamp;
        -- TODO
        if old.state = 'hold' then
            new.hold_sec =  coalesce(old.hold_sec, 0) + extract ('epoch' from new.timestamp - old.timestamp)::double precision;
            if new.hold isnull then
                new.hold = '[]';
            end if;

            new.hold = new.hold || jsonb_build_object(
                'start', (extract(epoch from old.timestamp)::double precision * 1000)::int8,
                'finish', (extract(epoch from new.timestamp)::double precision * 1000)::int8,
                'sec', extract ('epoch' from new.timestamp - old.timestamp)::int8
            );


--             if new.parent_id notnull then
--                 update cc_calls set hold_sec  = hold_sec + new.hold_sec  where id = new.parent_id;
--             end if;
        end if;
    end if;
    end if;
    end if;

    RETURN new;
END
$$;


--
-- Name: cc_communication_set_def(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_communication_set_def() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
    if new.default is distinct from old."default" or new.channel is distinct from old."channel"  then
        update call_center.cc_communication c
            set  "default" = false
        where c.domain_id = new.domain_id and c.id != new.id and c.channel = new.channel;
    end if;
    return new;
end;
$$;


--
-- Name: cc_confirm_agent_attempt(bigint, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_confirm_agent_attempt(_agent_id bigint, _attempt_id bigint) RETURNS SETOF character varying
    LANGUAGE plpgsql
    AS $$
BEGIN
    return query update call_center.cc_member_attempt
    set result = case when id = _attempt_id then null else 'cancel' end,
        leaving_at = case when id = _attempt_id then null else now() end
    where agent_id = _agent_id and not exists(
       select 1
       from call_center.cc_member_attempt a
       where a.agent_id = _agent_id and a.leaving_at notnull and a.result = 'cancel'
       for update
    )
    returning member_call_id;
END;
$$;


--
-- Name: cc_cron_next_after_now(character varying, timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_cron_next_after_now(expression character varying, shed timestamp without time zone, nowtz timestamp without time zone) RETURNS timestamp without time zone
    LANGUAGE plpgsql
    AS $$
    declare n timestamp = (call_center.cc_cron_next(expression, shed))::timestamp;
    declare i int = 0;
begin
        if n < nowtz then
            n = nowtz;
        end if;

        while n <= nowtz and i < 1000 loop -- TODO
            n = (call_center.cc_cron_next(expression, n) )::timestamp;
            i = i + 1;
        end loop;


        return n;
end;
$$;


--
-- Name: cc_distribute(boolean); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean)
    LANGUAGE plpgsql
    AS $$begin
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
                                                   communication_idx, member_call_id, team_id, resource_group_id, domain_id, import_id, sticky_agent_id, queue_params, queue_type)
            select case when q.type = 7 then 'task' else 'call' end, --todo
                   dis.id,
                   dis.queue_id,
                   dis.resource_id,
                   dis.agent_id,
                   dis.bucket_id,
                   jsonb_set(x, '{type,channel}'::text[], to_jsonb(c.channel::text)),
                   dis.comm_idx,
                   uuid_generate_v4(),
                   dis.team_id,
                   dis.resource_group_id,
                   q.domain_id,
                   m.import_id,
                   case when q.type = 5 and q.sticky_agent and m.agent_id notnull then dis.agent_id end,
                   call_center.cc_queue_params(q),
                   q.type
            from dis
                     inner join call_center.cc_queue q on q.id = dis.queue_id
                     inner join call_center.cc_member m on m.id = dis.id
                     inner join lateral jsonb_extract_path(m.communications, (dis.comm_idx)::text) x on true
                     left join call_center.cc_communication c on c.id = (x->'type'->'id')::int
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
-- Name: cc_distribute_direct_member_to_queue(character varying, bigint, integer, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint, seq integer, communication_idx integer, bucket_id bigint)
    LANGUAGE plpgsql
    AS $$BEGIN
    return query with attempts as (
        insert into call_center.cc_member_attempt (state, queue_id, member_id, destination, communication_idx, node_id, agent_id, resource_id,
                                       bucket_id, seq, team_id, domain_id, queue_params, queue_type)
            select 1,
                   m.queue_id,
                   m.id,
                   m.communications -> (_communication_id::int2),
                   (_communication_id::int2),
                   _node_name,
                   _agent_id,
                   r.resource_id,
                   m.bucket_id,
                   m.attempts + 1,
                   q.team_id,
                   q.domain_id,
                   call_center.cc_queue_params(q),
                   q.type
            from call_center.cc_member m
                     inner join call_center.cc_queue q on q.id = m.queue_id
                     inner join lateral (
                select (t::call_center.cc_sys_distribute_type).resource_id
                from call_center.cc_sys_queue_distribute_resources r,
                     unnest(r.types) t
                where r.queue_id = m.queue_id
                  and (t::call_center.cc_sys_distribute_type).type_id =
                      (m.communications -> (_communication_id::int2) -> 'type' -> 'id')::int4
                limit 1
                ) r on true
                     left join call_center.cc_outbound_resource cor on cor.id = r.resource_id
            where m.id = _member_id
              and m.communications -> (_communication_id::int2) notnull
              and not exists(select 1 from call_center.cc_member_attempt ma  where ma.member_id = _member_id )
            returning call_center.cc_member_attempt.*
    )
                 select a.id,
                        a.member_id,
                        null::varchar          result,
                        a.queue_id,
                        cq.updated_at as       queue_updated_at,
                        0::integer             queue_count,
                        0::integer             queue_active_count,
                        0::integer             queue_waiting_count,
                        a.resource_id::integer resource_id,
                        r.updated_at::bigint   resource_updated_at,
                        null::bigint           gateway_updated_at,
                        a.destination          destination,
                        cm.variables,
                        cm.name,
                        null::varchar,
                        a.agent_id::bigint     agent_id,
                        ag.updated_at::bigint  agent_updated_at,
                        t.updated_at::bigint   team_updated_at,
                        a.seq::int seq,
                        a.communication_idx::int communication_idx,
                        a.bucket_id
                 from attempts a
                          left join call_center.cc_member cm on a.member_id = cm.id
                          inner join call_center.cc_queue cq on a.queue_id = cq.id
                          left join call_center.cc_outbound_resource r on r.id = a.resource_id
                          left join call_center.cc_agent ag on ag.id = a.agent_id
                          inner join call_center.cc_team t on t.id = ag.team_id;

    --raise notice '%', _attempt_id;

END;
$$;


--
-- Name: cc_distribute_inbound_call_to_agent(character varying, character varying, jsonb, integer, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer, q_params jsonb DEFAULT NULL::jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$declare
    _domain_id int8;
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;

    _call record;
    _attempt record;

    _a_status varchar;
    _a_state varchar;
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
  ELSIF _call.direction <> 'outbound' or _call.user_id notnull then
      _number = _call.from_number;
  else
      _number = _call.destination;
  end if;

  select
    a.team_id,
    t.updated_at,
    a.status,
    cac.state,
    a.domain_id,
    (a.updated_at - extract(epoch from u.updated_at))::int8,
    exists (select 1 from call_center.cc_calls c where c.user_id = a.user_id and c.queue_id isnull and c.hangup_at isnull ) busy_ext
  from call_center.cc_agent a
      inner join call_center.cc_team t on t.id = a.team_id
      inner join call_center.cc_agent_channel cac on a.id = cac.agent_id and cac.channel = 'call'
      inner join directory.wbt_user u on u.id = a.user_id
  where a.id = _agent_id -- check attempt
    and length(coalesce(u.extension, '')) > 0
  for update
  into _team_id_,
      _team_updated_at,
      _a_status,
      _a_state,
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

  if _a_state != 'waiting'  then
      raise exception 'agent is busy';
  end if;

  if _busy_ext then
      raise exception 'agent has external call';
  end if;


  insert into call_center.cc_member_attempt (domain_id, state, team_id, member_call_id, destination, node_id, agent_id, parent_id, queue_params)
  values (_domain_id, 'waiting', _team_id_, _call_id, jsonb_build_object('destination', _number),
              _node_name, _agent_id, _call.attempt_id, q_params)
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


--
-- Name: cc_distribute_inbound_call_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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

CREATE FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
                            where (clc.list_id = dnc_list_id_ and clc.number = _con_name)), _qparams, 6) -- todo inbound chat queue
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
      call_center.cc_view_timestamp(_con_created)::int8,
      _attempt.list_communication_id::int8
  );
END;
$$;


--
-- Name: cc_distribute_members_list(integer, integer, smallint, boolean, smallint[], integer, integer, boolean, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_members_list(_queue_id integer, _bucket_id integer, strategy smallint, wait_between_retries_desc boolean DEFAULT false, l smallint[] DEFAULT '{}'::smallint[], lim integer DEFAULT 40, offs integer DEFAULT 0, sticky_agent boolean DEFAULT false, sticky_agent_sec integer DEFAULT 0, _agent_id integer DEFAULT 0) RETURNS SETOF bigint
    LANGUAGE plpgsql STABLE
    AS $_$begin return query
    select m.id::int8
    from call_center.cc_member m
    where m.queue_id = _queue_id
        and m.stop_at isnull
        and m.skill_id isnull
        and case when _bucket_id isnull then m.bucket_id isnull else m.bucket_id = _bucket_id end
        and (m.expire_at isnull or m.expire_at > now())
        and (m.ready_at isnull or m.ready_at < now())
        and (not sticky_agent or (m.agent_id isnull or m.agent_id = _agent_id))
        and not m.search_destinations && array(select call_center.cc_call_active_numbers())
        and m.id not in (select distinct a.member_id from call_center.cc_member_attempt a where a.member_id notnull)
        and m.sys_offset_id = any($5::int2[])
    order by m.bucket_id nulls last,
             m.skill_id,
             m.agent_id,
             m.priority desc,
             case when coalesce(wait_between_retries_desc, false) then m.ready_at end desc nulls last ,
             case when not coalesce(wait_between_retries_desc, false) then m.ready_at end asc nulls last ,

             case when coalesce(strategy, 0) = 1 then m.id end desc ,
             case when coalesce(strategy, 0) != 1 then m.id end asc
    limit lim
    offset offs
--     for update of m skip locked
        ;
end
$_$;


--
-- Name: cc_distribute_outbound_call(character varying, character varying, jsonb, bigint, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_outbound_call(_node_name character varying, _call_id character varying, variables_ jsonb, _user_id bigint DEFAULT NULL::integer, q_params jsonb DEFAULT NULL::jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$declare
    _domain_id int8;
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;
    _agent_id int;

    _call record;
    _attempt record;

    _number varchar;
BEGIN

  select *
  from call_center.cc_calls c
  where c.id = _call_id::uuid
--   for update
  into _call;

  if _call.id isnull or _call.direction isnull then
      raise exception 'not found call';
  elseif _call.direction <> 'outbound' then
      _number = _call.from_number;
  else
      _number = _call.destination;
  end if;


  select
    a.id,
    a.team_id,
    t.updated_at,
    a.domain_id,
    (a.updated_at - extract(epoch from u.updated_at))::int8
  from call_center.cc_agent a
      inner join call_center.cc_team t on t.id = a.team_id
      inner join directory.wbt_user u on u.id = a.user_id
  where a.user_id = _user_id -- check attempt
    and length(coalesce(u.extension, '')) > 0
  for update
  into _agent_id,
      _team_id_,
      _team_updated_at,
      _domain_id,
      _agent_updated_at
      ;

  if _call.domain_id != _domain_id then
      raise exception 'the queue on another domain';
  end if;

  if _team_id_ isnull then
      raise exception 'not found agent';
  end if;


  insert into call_center.cc_member_attempt (channel, domain_id, state, team_id, member_call_id, destination, node_id, agent_id, parent_id, queue_params)
  values ('out_call', _domain_id, 'active', _team_id_, _call_id, jsonb_build_object('destination', _number),
              _node_name, _agent_id, _call.attempt_id, q_params)
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
      call_center.cc_view_timestamp(_call.created_at)::int8,
      _agent_id
  );
END;
$$;


--
-- Name: cc_distribute_task_to_agent(character varying, bigint, integer, jsonb, jsonb, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_task_to_agent(_node_name character varying, _domain_id bigint, _agent_id integer, _destination jsonb, variables_ jsonb, _qparams jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$declare
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;

    _attempt record;

    _a_status varchar;
    _a_state varchar;
    _busy_ext bool;
BEGIN

  select
    a.team_id,
    t.updated_at,
    a.status,
    cac.state,
    (a.updated_at - extract(epoch from u.updated_at))::int8,
    exists (select 1 from call_center.cc_calls c where c.user_id = a.user_id and c.queue_id isnull and c.hangup_at isnull ) busy_ext
  from call_center.cc_agent a
      inner join call_center.cc_team t on t.id = a.team_id
      inner join call_center.cc_agent_channel cac on a.id = cac.agent_id and cac.channel = 'task'
      inner join directory.wbt_user u on u.id = a.user_id
  where a.id = _agent_id -- check attempt
    and a.domain_id = _domain_id
  for update
  into _team_id_,
      _team_updated_at,
      _a_status,
      _a_state,
      _agent_updated_at,
      _busy_ext
      ;

  if _team_id_ isnull then
      raise exception 'not found agent';
  end if;


  insert into call_center.cc_member_attempt (channel, domain_id, state, team_id, member_call_id, destination, node_id,
                                             agent_id, queue_params, queue_type)
  values ('task', _domain_id, 'waiting', _team_id_, null, _destination,
              _node_name, _agent_id, _qparams, 7) -- todo task agent queue
  returning * into _attempt;

  return row(
      _attempt.id::int8,
      _attempt.destination::jsonb,
      variables_::jsonb,
      _team_id_::int,
      _team_updated_at::int8,
      _agent_updated_at::int8
  );
END;
$$;


--
-- Name: cc_epoch_to_timestamp(bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_epoch_to_timestamp(bigint) RETURNS timestamp with time zone
    LANGUAGE plpgsql IMMUTABLE
    AS $_$
begin
    return to_timestamp($1/1000);
end;
$_$;


--
-- Name: cc_get_lookup(bigint, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_get_lookup(_id bigint, _name character varying) RETURNS jsonb
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
-- Name: cc_get_time(character varying, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_get_time(_t character varying, _def_t character varying) RETURNS integer
    LANGUAGE plpgsql IMMUTABLE
    AS $$
BEGIN
  return (to_char(current_timestamp AT TIME ZONE coalesce(_t, _def_t), 'SSSS') :: int / 60)::int;
END;
$$;


--
-- Name: cc_is_lookup(text, text); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_is_lookup(_table_name text, _col_name text) RETURNS boolean
    LANGUAGE plpgsql IMMUTABLE
    AS $$
begin
    return exists(select 1
from information_schema.columns
where table_name = _table_name
    and column_name = _col_name
    and _col_name != 'value'
    and data_type in ('json', 'jsonb'));
end;
$$;


--
-- Name: cc_jsonb_show_fields(jsonb, character varying[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_jsonb_show_fields(j jsonb, keys character varying[]) RETURNS jsonb
    LANGUAGE sql
    AS $$select json_object_agg(key, value)
    from jsonb_each(j)
    where key = any(keys)$$;


--
-- Name: cc_list_statistics_trigger_deleted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_list_statistics_trigger_deleted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    insert into call_center.cc_list_statistics (list_id, count)
    select l.list_id, l.cnt
    from (
             select l.list_id, count(*) cnt
             from deleted l
                inner join call_center.cc_list li on li.id = l.list_id
             group by l.list_id
         ) l
    on conflict (list_id)
        do update
        set count = call_center.cc_list_statistics.count - EXCLUDED.count ;

    RETURN NULL;
END
$$;


--
-- Name: cc_list_statistics_trigger_inserted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_list_statistics_trigger_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    insert into call_center.cc_list_statistics (list_id, count)
    select l.list_id, l.cnt
    from (
             select l.list_id, count(*) cnt
             from inserted l
             group by l.list_id
         ) l
    on conflict (list_id)
        do update
        set count = EXCLUDED.count + call_center.cc_list_statistics.count;
    RETURN NULL;
END
$$;


--
-- Name: cc_member_communication_types(jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_communication_types(jsonb) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
    AS $_$
    SELECT array_agg(x->'type')::int[] || ARRAY[]::int[] FROM jsonb_array_elements($1) t(x);
$_$;


--
-- Name: cc_member_communications(jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_communications(jsonb) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $_$
select (select json_agg(x)
                from (
                         select x ->> 'destination'                destination,
                                call_center.cc_get_lookup(c.id, c.name)       as type,
                                (x -> 'priority')::int          as priority,
                                (x -> 'state')::int             as state,
                                x -> 'description'              as description,
                                (x -> 'last_activity_at')::int8 as last_activity_at,
                                (x -> 'attempts')::int          as attempts,
                                x ->> 'last_cause'              as last_cause,
                                call_center.cc_get_lookup(r.id, r.name)       as resource,
                                x ->> 'display'                 as display,
                                x ->> 'dtmf'                 as dtmf,
                                (x -> 'stop_at')::int8                 as stop_at
                         from jsonb_array_elements($1) x
                                  left join call_center.cc_communication c on c.id = (x -> 'type' -> 'id')::int
                                  left join call_center.cc_outbound_resource r on r.id = (x -> 'resource' -> 'id')::int
                     ) x)::jsonb
$_$;


--
-- Name: cc_member_destination_views_to_json(call_center.cc_member_destination_view[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_destination_views_to_json(in_ call_center.cc_member_destination_view[]) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
select jsonb_agg(x)
    from unnest(in_) x
$$;


--
-- Name: cc_member_set_sys_destinations_tg(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_set_sys_destinations_tg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    if new.stop_cause notnull then
        new.ready_at = null;
    end if;

    if new.communications notnull and jsonb_typeof(new.communications) = 'array' then
        new.sys_destinations = (select array(select call_center.cc_destination_in(idx::int4 - 1, (x -> 'type' ->> 'id')::int4, (x ->> 'last_activity_at')::int8,  (x -> 'resource' ->> 'id')::int, (x ->> 'priority')::int)
         from jsonb_array_elements(new.communications) with ordinality as x(x, idx)
         where coalesce((x.x -> 'stop_at')::int8, 0) = 0
         and idx > -1
            order by coalesce((x ->> 'priority')::int, 0) desc, (x ->> 'last_activity_at')::int8 asc nulls first ));

        new.search_destinations = (select array_agg( x->>'destination'::varchar)
            from jsonb_array_elements(new.communications) x);

        if new.stop_at isnull and coalesce(array_length(new.sys_destinations, 1), 0 ) = 0 then
            new.stop_at = now();
            new.stop_cause = 'no_communications';
        end if;

    else
        new.sys_destinations = null;
        new.search_destinations = null;
    end if;

    return new;
END
$$;


--
-- Name: cc_member_statistic_skill_trigger_deleted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_skill_trigger_deleted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    insert into call_center.cc_queue_skill_statistics (queue_id, skill_id, member_count, member_waiting)
    select t.queue_id, t.skill_id, t.cnt, t.cntwait
    from (
             select queue_id, skill_id, count(*) cnt, count(*) filter ( where m.stop_at isnull ) cntwait
             from deleted m
             group by queue_id, skill_id
         ) t
    where t.skill_id notnull
    on conflict (queue_id, skill_id)
        do update
        set member_count   = call_center.cc_queue_skill_statistics.member_count - EXCLUDED.member_count,
            member_waiting = call_center.cc_queue_skill_statistics.member_waiting - EXCLUDED.member_waiting
    ;

    RETURN NULL;
END
$$;


--
-- Name: cc_member_statistic_skill_trigger_inserted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_skill_trigger_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    insert into call_center.cc_queue_skill_statistics (queue_id, skill_id, member_count, member_waiting)
    select t.queue_id, t.skill_id, t.cnt, t.cntwait
    from (
             select queue_id, skill_id, count(*) cnt, count(*) filter ( where m.stop_at isnull ) cntwait
             from inserted m
             where m.skill_id notnull
             group by queue_id, skill_id
         ) t
    on conflict (queue_id, skill_id)
        do update
        set member_count   = EXCLUDED.member_count + call_center.cc_queue_skill_statistics.member_count,
            member_waiting = EXCLUDED.member_waiting + call_center.cc_queue_skill_statistics.member_waiting;

    RETURN NULL;
END
$$;


--
-- Name: cc_member_statistic_skill_trigger_updated(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_skill_trigger_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    insert into call_center.cc_queue_skill_statistics (queue_id, skill_id, member_count, member_waiting)
    select t.queue_id, t.skill_id, t.cnt, t.cntwait
    from (
        select queue_id, skill_id, sum(cnt) cnt, sum(cntwait) cntwait
        from (
             select m.queue_id,
                    m.skill_id,
                    -1 * count(*) cnt,
                    -1 * count(*) filter ( where m.stop_at isnull ) cntwait
             from old_data m
             group by m.queue_id, m.skill_id

             union all
            select m.queue_id,
                   m.skill_id,
                   count(*) cnt,
                   count(*) filter ( where m.stop_at isnull ) cntwait
             from new_data m
--              where m.skill_id notnull
             group by m.queue_id, m.skill_id
        ) o
        group by queue_id, skill_id
    ) t
        where t.skill_id notnull
    on conflict (queue_id, skill_id) do update
        set member_waiting = excluded.member_waiting + call_center.cc_queue_skill_statistics.member_waiting,
            member_count = excluded.member_count + call_center.cc_queue_skill_statistics.member_count
    ;

   RETURN NULL;
END
$$;


--
-- Name: cc_member_statistic_trigger_deleted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_trigger_deleted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    insert into call_center.cc_queue_statistics (bucket_id, queue_id, member_count, member_waiting)
    select t.bucket_id, t.queue_id, t.cnt, t.cntwait
    from (
             select queue_id, bucket_id, count(*) cnt, count(*) filter ( where m.stop_at isnull ) cntwait
             from deleted m
                inner join call_center.cc_queue q on q.id = m.queue_id
             group by queue_id, bucket_id
         ) t
    on conflict (queue_id, coalesce(bucket_id, 0))
        do update
        set member_count   = call_center.cc_queue_statistics.member_count - EXCLUDED.member_count,
            member_waiting = call_center.cc_queue_statistics.member_waiting - EXCLUDED.member_waiting;

    RETURN NULL;
END
$$;


--
-- Name: cc_member_statistic_trigger_inserted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_trigger_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
BEGIN
    if exists(select 1
        from inserted m,
             (select c.domain_id, array_agg(c.id) ids
        from call_center.cc_communication c group by 1) c
        where m.domain_id = c.domain_id
            and array_length(TRANSLATE(jsonb_path_query_array(communications, '$[*].type.id')::text , '[]','{}')::INT[] - c.ids, 1)  > 0)
    then
        raise exception 'bad communication type.id' using errcode = '23503';
    end if;

    insert into call_center.cc_queue_statistics (queue_id, bucket_id, member_count, member_waiting)
    select t.queue_id, t.bucket_id, t.cnt, t.cntwait
    from (
             select queue_id, bucket_id, count(*) cnt, count(*) filter ( where m.stop_at isnull ) cntwait
             from inserted m
             group by queue_id, bucket_id
         ) t
    on conflict (queue_id, coalesce(bucket_id, 0))
        do update
        set member_count   = EXCLUDED.member_count + call_center.cc_queue_statistics.member_count,
            member_waiting = EXCLUDED.member_waiting + call_center.cc_queue_statistics.member_waiting;


    --    raise notice '% % %', TG_TABLE_NAME, TG_OP, (select count(*) from inserted );
--    PERFORM pg_notify(TG_TABLE_NAME, TG_OP);
    RETURN NULL;
END
$_$;


--
-- Name: cc_member_statistic_trigger_updated(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_trigger_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
BEGIN
    if exists(select 1
        from new_data m,
             (select c.domain_id, array_agg(c.id) ids
        from call_center.cc_communication c group by 1) c
        where m.domain_id = c.domain_id
            and array_length(TRANSLATE(jsonb_path_query_array(communications, '$[*].type.id')::text , '[]','{}')::INT[] - c.ids, 1)  > 0)
    then
        raise exception 'bad communication type.id' using errcode = '23503';
    end if;

    insert into call_center.cc_queue_statistics (queue_id, bucket_id, member_count, member_waiting)
    select t.queue_id, t.bucket_id, t.cnt, t.cntwait
    from (
        select queue_id, bucket_id, sum(cnt) cnt, sum(cntwait) cntwait
        from (
             select m.queue_id,
                    m.bucket_id,
                    -1 * count(*) cnt,
                    -1 * count(*) filter ( where m.stop_at isnull ) cntwait
             from old_data m
             group by m.queue_id, m.bucket_id

             union all
            select m.queue_id,
                    m.bucket_id   bucket_id ,
                    count(*) cnt,
                    count(*) filter ( where m.stop_at isnull ) cntwait
             from new_data m
             group by m.queue_id, m.bucket_id
        ) o
        group by queue_id, bucket_id
    ) t
    --where t.cntwait != 0
    on conflict (queue_id, coalesce(bucket_id, 0)) do update
        set member_waiting = excluded.member_waiting + call_center.cc_queue_statistics.member_waiting,
            member_count = excluded.member_count + call_center.cc_queue_statistics.member_count;

   RETURN NULL;
END
$_$;


--
-- Name: cc_member_sys_offset_id_trigger_inserted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_sys_offset_id_trigger_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare res int4[];
BEGIN
    if new.timezone_id isnull or new.timezone_id = 0 then
        res = call_center.cc_queue_default_timezone_offset_id(new.queue_id);
        new.timezone_id = res[1];
        new.sys_offset_id = res[2];
    else
        new.sys_offset_id = call_center.cc_timezone_offset_id(new.timezone_id);
    end if;

    if new.timezone_id isnull or new.sys_offset_id isnull then
        raise exception 'not found timezone';
    end if;

    RETURN new;
END
$$;


--
-- Name: cc_member_sys_offset_id_trigger_update(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_sys_offset_id_trigger_update() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare res int4[];
BEGIN
    new.sys_offset_id = call_center.cc_timezone_offset_id(new.timezone_id);

    if new.timezone_id isnull or new.sys_offset_id isnull then
        raise exception 'not found timezone';
    end if;

    RETURN new;
END
$$;


--
-- Name: cc_offline_members_ids(bigint, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_offline_members_ids(_domain_id bigint, _agent_id integer, _lim integer) RETURNS SETOF bigint
    LANGUAGE plpgsql IMMUTABLE
    AS $$begin
    return query
    with queues as (
    select  q_1.domain_id,
            q_1.id,
            q_1.calendar_id,
            q_1.type,
            q_1.sticky_agent,
            q_1.recall_calendar,
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
            array_agg(ROW((m.bucket_id)::integer, (m.member_waiting)::integer, m.op)::call_center.cc_sys_distribute_bucket ORDER BY cbiq.priority DESC NULLS LAST, cbiq.ratio DESC NULLS LAST, m.bucket_id)
                filter ( where  coalesce(m.bucket_id, 0) = any(bb.bb)) AS buckets,
            m.op
           FROM ((( WITH mem AS MATERIALIZED (
                         SELECT a.queue_id,
                            a.bucket_id,
                            count(*) AS member_waiting,
                            false AS op
                           FROM call_center.cc_member_attempt a
                          WHERE ((a.bridged_at IS NULL) AND (a.leaving_at IS NULL) AND ((a.state)::text = 'wait_agent'::text))
                          GROUP BY a.queue_id, a.bucket_id
                        UNION ALL
                         SELECT q_2.queue_id,
                            q_2.bucket_id,
                            q_2.member_waiting,
                            true AS op
                           FROM call_center.cc_queue_statistics q_2
                          WHERE (q_2.member_waiting > 0)
                        )
                 SELECT rank() OVER (PARTITION BY mem.queue_id ORDER BY mem.op) AS pos,
                    mem.queue_id,
                    mem.bucket_id,
                    mem.member_waiting,
                    mem.op
                   FROM mem) m
             JOIN call_center.cc_queue q_1 ON ((q_1.id = m.queue_id)))
             LEFT JOIN call_center.cc_bucket_in_queue cbiq ON (((cbiq.queue_id = m.queue_id) AND (cbiq.bucket_id = m.bucket_id))))
             cross join lateral (
                 select cqs.queue_id, array_agg(distinct coalesce(bb, 0)) bb
                from call_center.cc_skill_in_agent sa
                    inner join call_center.cc_queue_skill cqs on cqs.skill_id = sa.skill_id
                                                                     and sa.capacity between cqs.min_capacity and cqs.max_capacity
                    left join lateral unnest(cqs.bucket_ids) bb on true
                where  sa.enabled and cqs.enabled and sa.agent_id = _agent_id
                 group by 1
               ) bb
          WHERE ((m.member_waiting > 0) AND q_1.enabled AND  (m.pos = 1) AND ((cbiq.bucket_id IS NULL) OR (NOT cbiq.disabled)))
            and q_1.type = 0
            and q_1.domain_id = _domain_id
            and q_1.id = bb.queue_id
          GROUP BY q_1.domain_id, q_1.id, q_1.calendar_id, q_1.type, m.op
), calend AS MATERIALIZED (
         SELECT c.id AS calendar_id,
            queues.id AS queue_id,
                CASE
                    WHEN (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) THEN ((array_agg(DISTINCT o1.id))::int2[] + (tz.offset_id)::int2)
                    ELSE (array_agg(DISTINCT o1.id))::int2[]
                END AS l,
            (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) AS recall_calendar
           FROM ((((flow.calendar c
             LEFT JOIN flow.calendar_timezones tz ON ((tz.id = c.timezone_id)))
             JOIN queues ON ((queues.calendar_id = c.id)))
             JOIN LATERAL unnest(c.accepts) a(disabled, day, start_time_of_day, end_time_of_day) ON (true))
             JOIN flow.calendar_timezone_offsets o1 ON ((((a.day + 1) = (date_part('isodow'::text, timezone(o1.names[1], now())))::integer) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) >= a.start_time_of_day) AND (((to_char(timezone(o1.names[1], now()), 'SSSS'::text))::integer / 60) <= a.end_time_of_day))))
          WHERE (NOT (a.disabled IS TRUE))
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
 , request as  (
     SELECT distinct q.id,
    (q.strategy)::int2 AS strategy,
    q.team_id,
    bs.bucket_id::int as bucket_id,
    r.types,
    r.resources,
    q.priority,
    q.sticky_agent,
    q.sticky_agent_sec,
    calend.recall_calendar,
    q.wait_between_retries_desc,
    q.strict_circuit,
    calend.l
   FROM (((queues q
     LEFT JOIN calend ON ((calend.queue_id = q.id)))
     LEFT JOIN resources r ON ((q.op AND (r.queue_id = q.id))))
     LEFT JOIN LATERAL ( SELECT count(*) AS usage
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND ((a.state)::text <> 'leaving'::text))) l ON ((q.lim > 0)))
    join lateral unnest(q.buckets) bs on true
    where r.* IS NOT NULL
)
select x
from request
left join lateral call_center.cc_distribute_members_list(request.id::int, request.bucket_id::int,
            request.strategy::int2, request.wait_between_retries_desc, request.l::int2[], _lim::int,
    0, request.sticky_agent::bool, request.sticky_agent_sec::int, _agent_id::int) x on true
order by request.priority desc
limit _lim;
end
$$;


--
-- Name: cc_outbound_resource_display_changed(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_outbound_resource_display_changed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
        update call_center.cc_outbound_resource r
        set updated_at = (extract(epoch from now()) * 1000)::int8
        where r.id = coalesce(NEW.resource_id, OLD.resource_id);

        RETURN NEW;
    END;
$$;


--
-- Name: cc_outbound_resource_timing(jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_outbound_resource_timing(jsonb) RETURNS smallint[]
    LANGUAGE plpgsql IMMUTABLE STRICT
    AS $_$
declare res_ smallint[];
BEGIN
    with times as (
        select (e->'start_time_of_day')::int as start, (e->'end_time_of_day')::int as end
        from jsonb_array_elements($1) e
    )
    select array_agg(distinct t.id) x
    into res_
    from flow.calendar_timezone_offsets t,
         lateral (select current_timestamp AT TIME ZONE t.names[1] t) with_timezone
    where exists (select 1 from times where (to_char(with_timezone.t, 'SSSS') :: int / 60) between times.start and times.end);

    return res_;
END;
$_$;


--
-- Name: cc_queue_default_timezone_offset_id(integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_queue_default_timezone_offset_id(integer) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
    AS $_$
select array[c.timezone_id, z.offset_id]::int4[]
    from call_center.cc_queue q
        inner join flow.calendar c on c.id = q.calendar_id
        inner join flow.calendar_timezones z on z.id = c.timezone_id
    where q.id = $1;
$_$;


--
-- Name: cc_queue_event_changed_tg(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_queue_event_changed_tg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        update call_center.cc_queue
        set updated_at = (extract(epoch from now()) * 1000)::int8
        where id = old.queue_id;

        return old;
    else
        update call_center.cc_queue
        set updated_at = (extract(epoch from new.updated_at) * 1000)::int8,
            updated_by = new.updated_by
        where id = new.queue_id;

        return new;
    end if;
END;
$$;


--
-- Name: cc_queue; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue (
    id integer NOT NULL,
    strategy character varying(20) NOT NULL,
    enabled boolean NOT NULL,
    payload jsonb,
    calendar_id integer,
    priority integer DEFAULT 0 NOT NULL,
    updated_at bigint DEFAULT ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint NOT NULL,
    name character varying NOT NULL,
    variables jsonb DEFAULT '{}'::jsonb NOT NULL,
    domain_id bigint NOT NULL,
    dnc_list_id bigint,
    type smallint DEFAULT 1 NOT NULL,
    team_id bigint,
    created_at bigint NOT NULL,
    created_by bigint,
    updated_by bigint,
    schema_id integer,
    description character varying DEFAULT ''::character varying,
    ringtone_id integer,
    do_schema_id integer,
    after_schema_id integer,
    sticky_agent boolean DEFAULT false NOT NULL,
    processing boolean DEFAULT false NOT NULL,
    processing_sec integer DEFAULT 30 NOT NULL,
    processing_renewal_sec integer DEFAULT 0 NOT NULL,
    grantee_id bigint,
    recall_calendar boolean DEFAULT false,
    form_schema_id integer,
    tags character varying[]
);


--
-- Name: cc_queue_params(call_center.cc_queue); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_queue_params(q call_center.cc_queue) RETURNS jsonb
    LANGUAGE sql IMMUTABLE
    AS $$
    select jsonb_build_object('has_reporting', q.processing)
    || jsonb_build_object('has_form', q.processing and q.form_schema_id notnull)
    || jsonb_build_object('processing_sec', q.processing_sec)
    || jsonb_build_object('processing_renewal_sec', q.processing_renewal_sec)
    || jsonb_build_object('queue_name', q.name) as queue_params;
$$;


--
-- Name: cc_resource_set_error(bigint, bigint, character varying, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_resource_set_error(_id bigint, _routing_id bigint, _error_id character varying, _strategy character varying) RETURNS record
    LANGUAGE plpgsql
    AS $$
DECLARE _res record;
  _stopped boolean;
  _successively_errors smallint;
  _un_reserved_id bigint;
BEGIN

  update call_center.cc_outbound_resource
  set last_error_id = _error_id,
      last_error_at = now(),
    successively_errors = case when successively_errors + 1 >= max_successively_errors then 0 else successively_errors + 1 end,
    enabled = case when successively_errors + 1 >= max_successively_errors then false else enabled end
  where id = _id and "enabled" is true
  returning not enabled, successively_errors
      into _stopped, _successively_errors
  ;

  select _successively_errors::smallint, _stopped::boolean, _un_reserved_id::bigint into _res;
  return _res;
END;
$$;


--
-- Name: cc_scheduler_jobs(); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_scheduler_jobs()
    LANGUAGE plpgsql
    AS $$
begin

    if NOT pg_try_advisory_xact_lock(132132118) then
        raise exception 'LOCKED cc_scheduler_jobs';
end if;

with del as (
delete from call_center.cc_trigger_job
where stopped_at notnull
        returning id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
    )
insert into call_center.cc_trigger_job_log (id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id)
select id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
from del
;

with u as (
update call_center.cc_trigger t2
set schedule_at = (t.new_schedule_at)::timestamp
from (select t.id,
    jsonb_build_object('variables', t.variables,
    'schema_id', t.schema_id,
    'timeout', t.timeout_sec
    ) as                                      params,
    call_center.cc_cron_next_after_now(t.expression, (t.schedule_at)::timestamp, (now() at time zone tz.sys_name)::timestamp) new_schedule_at,
    t.domain_id,
    (t.schedule_at)::timestamp as old_schedule_at,
    (now() at time zone tz.sys_name)::timestamp - (t.schedule_at)::timestamp < interval '5m' valid
    from call_center.cc_trigger t
    inner join flow.calendar_timezones tz on tz.id = t.timezone_id
    where t.enabled
    and t.type = 'cron'
    and (t.schedule_at)::timestamp <= (now() at time zone tz.sys_name)::timestamp
    and not exists(select 1 from call_center.cc_trigger_job tj where tj.trigger_id = t.id and tj.state = 0)
    for update of t skip locked) t
where t2.id = t.id
    returning t.*
    )
insert
into call_center.cc_trigger_job(trigger_id, parameters, domain_id)
select id, params, domain_id
from u
where u.valid;
end;
$$;


--
-- Name: cc_set_active_members(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer, communication_idx integer, timezone character varying, bucket_id bigint)
    LANGUAGE plpgsql
    AS $$BEGIN
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
       cm.id as member_id,
       tz.sys_name::varchar as member_timezone,
       c.bucket_id
from call_center.cc_member_attempt c
         left join call_center.cc_member cm on c.member_id = cm.id
         left join lateral (
            select count(*) cnt
            from jsonb_array_elements(cm.communications) WITH ORDINALITY AS x(c, n)
            where coalesce((x.c -> 'stop_at')::int8, 0) < 1
              and x.n != (c.communication_idx + 1)
            ) x on c.member_id notnull
                 inner join call_center.cc_queue cq on c.queue_id = cq.id
                 left join call_center.cc_team tm on tm.id = c.team_id
                 left join call_center.cc_outbound_resource r on r.id = c.resource_id
                 left join directory.sip_gateway gw on gw.id = r.gateway_id
                 left join call_center.cc_agent ca on c.agent_id = ca.id
                 left join call_center.cc_queue_statistics cqs on cq.id = cqs.queue_id
                 left join directory.wbt_user u on u.id = ca.user_id
                 left join flow.calendar cr on cr.id = cq.calendar_id
                 left join flow.calendar_timezones tz on tz.id = coalesce(cm.timezone_id, cr.timezone_id)
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
            a.communication_idx,
            c.member_timezone,
            c.bucket_id
    ;
END;
$$;


--
-- Name: cc_set_agent_change_status(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_set_agent_change_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    if TG_OP = 'INSERT' then
        return new;
    end if;

    insert into call_center.cc_agent_state_history (agent_id, joined_at, state, duration, payload)
    values (old.id, old.last_state_change, old.status,  new.last_state_change - old.last_state_change, old.status_payload);


    insert into call_center.cc_agent_status_log (agent_id, joined_at, status, duration, payload)
    values (old.id, old.last_state_change, old.status,  new.last_state_change - old.last_state_change, old.status_payload)
    on conflict do nothing ;
    RETURN new;
END;
$$;


--
-- Name: cc_set_agent_channel_change_status(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_set_agent_channel_change_status() RETURNS trigger
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


--
-- Name: cc_team_changed_tg(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_team_changed_tg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    update call_center.cc_agent
        set screen_control = new.screen_control
    where team_id = new.id;

    RETURN new;
END;
$$;


--
-- Name: cc_team_event_changed_tg(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_team_event_changed_tg() RETURNS trigger
    LANGUAGE plpgsql
    AS $$BEGIN
    IF (TG_OP = 'DELETE') THEN
        update call_center.cc_team
        set updated_at = (extract(epoch from now()) * 1000)::int8
        where id = old.team_id;

        return old;
    else
        update call_center.cc_team
        set updated_at = (extract(epoch from new.updated_at) * 1000)::int8,
            updated_by = new.updated_by
        where id = new.team_id;

        return new;
    end if;
END;
$$;


--
-- Name: cc_timezone_offset_id(integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_timezone_offset_id(integer) RETURNS smallint
    LANGUAGE sql IMMUTABLE
    AS $_$
select z.offset_id
    from flow.calendar_timezones z
    where z.id = $1;
$_$;


--
-- Name: cc_trigger_ins_upd(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_trigger_ins_upd() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
        if NEW.type <> 'cron' then
           return NEW;
        end if;
        if call_center.cc_cron_valid(NEW.expression) is not true then
            raise exception 'invalid expression % [%]', NEW.expression, NEW.type using errcode ='20808';
        end if;

        if old.enabled != new.enabled or old.expression != new.expression or old.timezone_id != new.timezone_id then
            select
                call_center.cc_cron_next_after_now(new.expression, (now() at time zone tz.sys_name)::timestamp, (now() at time zone tz.sys_name)::timestamp)
            into new.schedule_at
            from flow.calendar_timezones tz
            where tz.id = NEW.timezone_id;
        end if;

        RETURN NEW;
    END;
$$;


--
-- Name: cc_un_reserve_members_with_resources(character varying, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_un_reserve_members_with_resources(node character varying, res character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    count integer;
BEGIN
    update call_center.cc_member_attempt
      set state  =  'leaving',
          leaving_at = now(),
          result = res
    where leaving_at isnull and node_id = node and state = 'idle';

    get diagnostics count = row_count;
    return count;
END;
$$;


--
-- Name: cc_update_array_elements(jsonb, text[], jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_update_array_elements(target jsonb, path text[], new_value jsonb) RETURNS jsonb
    LANGUAGE sql
    AS $$
    -- aggregate the jsonb from parts created in LATERAL
    SELECT jsonb_agg(updated_jsonb)
    -- split the target array to individual objects...
    FROM jsonb_array_elements(target) individual_object,
    -- operate on each object and apply jsonb_set to it. The results are aggregated in SELECT
    LATERAL jsonb_set(individual_object, path, new_value) updated_jsonb
  $$;


--
-- Name: cc_view_timestamp(timestamp with time zone); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_view_timestamp(t timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql IMMUTABLE
    AS $$
begin
    if t isnull then
        return 0::int8;
    else
        return (extract(EPOCH from t) * 1000)::int8;
    end if;
end;
$$;


--
-- Name: cc_wrap_over_dial(numeric, numeric, numeric, numeric, numeric); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_wrap_over_dial(over numeric DEFAULT 1, current numeric DEFAULT 0, target numeric DEFAULT 5, max numeric DEFAULT 7, q numeric DEFAULT 10) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    AS $$declare dx numeric;
begin
    if current >= max then
        return 1;
    end if;

    dx = target - current;
    if dx = 0 then
        dx = 0.99;
    end if;

    if dx > 0 then
        return over + ( (over * dx * q) / 100 );
    else
        return (over * (((max - current) * (100 + q )) / max) ) / 100;
    end if;
end;
$$;


--
-- Name: composite_type_audit_q(bigint, bigint); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.composite_type_audit_q(IN domain_id_ bigint, IN form_id_ bigint)
    LANGUAGE plpgsql
    AS $$
declare
    column_list text;
begin
    select string_agg('"' || left(c.row_idx || ' ' || replace(c.question, '"', ''), 31) || '" decimal', ', ')
    into column_list
    FROM (with form_questions as (select x.form_id,
                                         x.form_name,
                                         row_number() over (partition by x.form_id) row_idx,
                                         x.question
                                  from (select form.id                              form_id,
                                               form.name                            form_name,
                                               jsonb_array_elements(form.questions) question
                                        from call_center.cc_audit_form form
                                        where form.domain_id = domain_id_
                                          and form.id = form_id_) x)

          select form.form_id
               , form.row_idx
               , case
                     when (form.question ->> 'required')::bool then '*' || (form.question ->> 'question')::text
                     else form.question ->> 'question' end question
          from form_questions form
          order by 2) as c;
    execute 'drop type if exists call_center.composite_type_audit_q_' || form_id_;
    execute 'create type call_center.composite_type_audit_q_' || form_id_ || ' as (' || column_list || ')';
end ;
$$;


--
-- Name: create_composite_type_audit_q(bigint, bigint[]); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.create_composite_type_audit_q(IN domain_id_ bigint, IN form_ids_ bigint[])
    LANGUAGE plpgsql
    AS $$
begin
    for i in 1..array_length(form_ids_, 1)
        loop
            call call_center.composite_type_audit_q(domain_id_, (form_ids_)[i]);
        end loop;
end ;
$$;


--
-- Name: rbac_users_from_group(character varying, bigint, smallint, integer[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.rbac_users_from_group(_class_name character varying, _domain_id bigint, _access smallint, _groups integer[]) RETURNS integer[]
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


--
-- Name: tg_obj_default_rbac(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.tg_obj_default_rbac() RETURNS trigger
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


--
-- Name: cc_array_merge_agg(anyarray); Type: AGGREGATE; Schema: call_center; Owner: -
--

CREATE AGGREGATE call_center.cc_array_merge_agg(anyarray) (
    SFUNC = call_center.cc_array_merge,
    STYPE = anyarray
);


--
-- Name: jsonb_concat_agg(jsonb); Type: AGGREGATE; Schema: call_center; Owner: -
--

CREATE AGGREGATE call_center.jsonb_concat_agg(jsonb) (
    SFUNC = jsonb_concat,
    STYPE = jsonb
);


--
-- Name: cc_agent; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent (
    id integer NOT NULL,
    user_id bigint NOT NULL,
    updated_at bigint DEFAULT 0 NOT NULL,
    status character varying(20) DEFAULT 'offline'::character varying NOT NULL,
    description character varying(250) DEFAULT ''::character varying NOT NULL,
    domain_id bigint NOT NULL,
    created_at bigint,
    created_by bigint,
    updated_by bigint,
    status_payload character varying,
    progressive_count integer DEFAULT 1,
    last_state_change timestamp with time zone DEFAULT now() NOT NULL,
    on_demand boolean DEFAULT false NOT NULL,
    allow_channels character varying[] DEFAULT '{call}'::character varying[],
    greeting_media_id integer,
    chat_count smallint DEFAULT 1,
    team_id integer,
    region_id integer,
    supervisor boolean DEFAULT false NOT NULL,
    supervisor_ids integer[],
    auditor_ids bigint[],
    task_count smallint DEFAULT 1 NOT NULL,
    screen_control boolean DEFAULT false NOT NULL,
    CONSTRAINT cc_agent_chat_count_c CHECK ((chat_count > '-1'::integer)),
    CONSTRAINT cc_agent_progress_count_c CHECK ((progressive_count > '-1'::integer))
)
WITH (fillfactor='20', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


--
-- Name: cc_agent_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    object integer NOT NULL,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL
);


--
-- Name: cc_agent_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_agent_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_agent_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_agent_acl_id_seq OWNED BY call_center.cc_agent_acl.id;


--
-- Name: cc_agent_channel; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_channel (
    agent_id integer NOT NULL,
    state character varying NOT NULL,
    channel character varying NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    timeout timestamp with time zone,
    no_answers integer DEFAULT 0 NOT NULL,
    queue_id integer,
    last_offering_at timestamp with time zone,
    last_bridged_at timestamp with time zone,
    last_missed_at timestamp with time zone,
    last_bucket_id integer,
    channel_changed_at timestamp with time zone DEFAULT now() NOT NULL,
    online boolean DEFAULT false NOT NULL,
    lose_attempt integer DEFAULT 0 NOT NULL,
    attempt_id integer,
    max_opened smallint DEFAULT 0
)
WITH (fillfactor='20', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


--
-- Name: cc_agent_state_history; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_state_history (
    id bigint NOT NULL,
    agent_id integer NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    state character varying(20) NOT NULL,
    channel character varying,
    duration interval DEFAULT '00:00:00'::interval NOT NULL,
    payload character varying,
    queue_id integer,
    attempt_id integer
);


--
-- Name: cc_agent_history_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_agent_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_agent_history_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_agent_history_id_seq OWNED BY call_center.cc_agent_state_history.id;


--
-- Name: cc_agent_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_agent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_agent_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_agent_id_seq OWNED BY call_center.cc_agent.id;


--
-- Name: cc_agent_in_queue_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_agent_in_queue_view AS
SELECT
    NULL::jsonb AS queue,
    NULL::integer AS priority,
    NULL::smallint AS type,
    NULL::character varying(20) AS strategy,
    NULL::boolean AS enabled,
    NULL::bigint AS count_members,
    NULL::bigint AS waiting_members,
    NULL::bigint AS active_members,
    NULL::integer AS queue_id,
    NULL::character varying AS queue_name,
    NULL::bigint AS team_id,
    NULL::bigint AS domain_id,
    NULL::integer AS agent_id,
    NULL::jsonb AS agents,
    NULL::integer AS max_member_limit;


--
-- Name: cc_agent_with_user; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_agent_with_user AS
 SELECT a.id,
    call_center.cc_get_lookup((a.id)::bigint, (COALESCE(u.name, (u.username)::text))::character varying) AS "user"
   FROM (call_center.cc_agent a
     JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (a.domain_id = u.dc))));


--
-- Name: cc_skill; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_skill (
    id integer NOT NULL,
    name character varying NOT NULL,
    domain_id bigint NOT NULL,
    description character varying DEFAULT ''::character varying NOT NULL,
    created_at timestamp with time zone,
    created_by bigint,
    updated_at timestamp with time zone,
    updated_by bigint
);


--
-- Name: cc_skill_in_agent; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_skill_in_agent (
    id integer NOT NULL,
    skill_id integer NOT NULL,
    agent_id integer NOT NULL,
    capacity smallint DEFAULT 0 NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint,
    updated_at bigint NOT NULL,
    updated_by bigint,
    enabled boolean DEFAULT true NOT NULL
);


--
-- Name: cc_team; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_team (
    id bigint NOT NULL,
    domain_id bigint NOT NULL,
    name character varying(50) NOT NULL,
    description character varying DEFAULT ''::character varying NOT NULL,
    strategy character varying NOT NULL,
    max_no_answer smallint DEFAULT 0 NOT NULL,
    wrap_up_time smallint DEFAULT 0 NOT NULL,
    no_answer_delay_time smallint DEFAULT 0 NOT NULL,
    call_timeout smallint DEFAULT 0 NOT NULL,
    updated_at bigint DEFAULT 0 NOT NULL,
    created_at bigint,
    created_by bigint,
    updated_by bigint,
    admin_ids integer[],
    invite_chat_timeout smallint DEFAULT 30 NOT NULL,
    task_accept_timeout smallint DEFAULT 30 NOT NULL,
    forecast_calculation_id bigint,
    screen_control boolean DEFAULT false NOT NULL
);


--
-- Name: cc_agent_list; Type: VIEW; Schema: call_center; Owner: -
--

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
    a.task_count,
    a.screen_control,
    (t.screen_control IS FALSE) AS allow_set_screen_control
   FROM (((((call_center.cc_agent a
     LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
     LEFT JOIN storage.media_files g ON ((g.id = a.greeting_media_id)))
     LEFT JOIN call_center.cc_team t ON ((t.id = a.team_id)))
     LEFT JOIN flow.region r ON ((r.id = a.region_id)))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint)) AS x
           FROM call_center.cc_agent_channel c
          WHERE (c.agent_id = a.id)) ch ON (true));


--
-- Name: cc_agent_status_log; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_status_log (
    id bigint NOT NULL,
    agent_id integer NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    status character varying NOT NULL,
    payload character varying,
    duration interval DEFAULT '00:00:00'::interval NOT NULL
);


--
-- Name: cc_agent_status_log_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_agent_status_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_agent_status_log_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_agent_status_log_id_seq OWNED BY call_center.cc_agent_status_log.id;


--
-- Name: cc_agent_today_pause_cause; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_agent_today_pause_cause AS
 SELECT a.id,
    ((now())::date + age(now(), (timezone(COALESCE(t.sys_name, 'UTC'::text), now()))::timestamp with time zone)) AS today,
    p.payload AS cause,
    p.d AS duration
   FROM (((call_center.cc_agent a
     LEFT JOIN flow.region r ON ((r.id = a.region_id)))
     LEFT JOIN flow.calendar_timezones t ON ((t.id = r.timezone_id)))
     LEFT JOIN LATERAL ( SELECT cc_agent_state_history.payload,
            sum(cc_agent_state_history.duration) AS d
           FROM call_center.cc_agent_state_history
          WHERE ((cc_agent_state_history.joined_at > ((now())::date + age(now(), (timezone(COALESCE(t.sys_name, 'UTC'::text), now()))::timestamp with time zone))) AND (cc_agent_state_history.agent_id = a.id) AND ((cc_agent_state_history.state)::text = 'pause'::text) AND (cc_agent_state_history.channel IS NULL))
          GROUP BY cc_agent_state_history.payload) p ON (true))
  WHERE (p.d IS NOT NULL)
  WITH NO DATA;


--
-- Name: cc_audit_rate; Type: TABLE; Schema: call_center; Owner: -
--

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
    rated_user_id bigint,
    call_created_at timestamp with time zone,
    select_yes_count bigint DEFAULT 0,
    critical_count bigint DEFAULT 0
);


--
-- Name: cc_calls_history; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_calls_history (
    id uuid NOT NULL,
    direction character varying,
    destination character varying,
    parent_id uuid,
    app_id character varying NOT NULL,
    from_type character varying,
    from_name character varying,
    from_number character varying,
    from_id character varying,
    to_type character varying,
    to_name character varying,
    to_number character varying,
    to_id character varying,
    payload jsonb,
    domain_id bigint NOT NULL,
    hold_sec integer DEFAULT 0,
    cause character varying,
    sip_code integer,
    bridged_id uuid,
    gateway_id bigint,
    user_id integer,
    queue_id integer,
    team_id integer,
    agent_id integer,
    attempt_id bigint,
    member_id bigint,
    duration integer DEFAULT 0 NOT NULL,
    description character varying,
    tags character varying[],
    answered_at timestamp with time zone,
    bridged_at timestamp with time zone,
    hangup_at timestamp with time zone,
    created_at timestamp with time zone NOT NULL,
    hangup_by character varying,
    stored_at timestamp with time zone DEFAULT now() NOT NULL,
    rating smallint,
    notes text,
    transfer_from uuid,
    transfer_to uuid,
    amd_result character varying,
    amd_duration interval,
    grantee_id bigint,
    hold jsonb,
    agent_ids integer[],
    user_ids bigint[],
    queue_ids integer[],
    gateway_ids bigint[],
    team_ids integer[],
    params jsonb,
    blind_transfer character varying,
    talk_sec integer DEFAULT 0 NOT NULL,
    amd_ai_result character varying,
    amd_ai_logs character varying[],
    amd_ai_positive boolean,
    contact_id bigint,
    search_number text,
    hide_missed boolean,
    redial_id uuid,
    schema_ids integer[],
    hangup_phrase character varying,
    blind_transfers jsonb,
    destination_name text,
    attempt_ids bigint[]
);


--
-- Name: cc_member_attempt_history; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_member_attempt_history (
    id bigint NOT NULL,
    queue_id integer,
    member_id bigint,
    weight integer,
    resource_id integer,
    node_id character varying(20),
    result character varying(200) NOT NULL,
    agent_id integer,
    bucket_id bigint,
    display character varying(50),
    description character varying,
    list_communication_id bigint,
    joined_at timestamp with time zone NOT NULL,
    leaving_at timestamp with time zone,
    agent_call_id character varying,
    member_call_id character varying,
    offering_at timestamp with time zone,
    reporting_at timestamp with time zone,
    bridged_at timestamp with time zone,
    channel character varying,
    domain_id bigint NOT NULL,
    destination jsonb,
    seq integer DEFAULT 0 NOT NULL,
    team_id integer,
    resource_group_id integer,
    answered_at timestamp with time zone,
    region_id integer,
    transferred_at timestamp with time zone,
    transferred_agent_id integer,
    transferred_attempt_id bigint,
    parent_id bigint,
    form_fields jsonb,
    import_id character varying(120),
    variables jsonb,
    offered_agent_ids integer[]
);


--
-- Name: COLUMN cc_member_attempt_history.result; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON COLUMN call_center.cc_member_attempt_history.result IS 'fixme';


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
          WHERE ((h.joined_at > ((now())::date - '1 day'::interval)) AND (h.domain_id = agents.domain_id) AND (h.joined_at >= agents."from") AND (h.joined_at <= agents."to") AND ((h.channel)::text = 'call'::text))
          GROUP BY h.agent_id
        ), attempts AS MATERIALIZED (
         WITH rng(agent_id, c, s, e, b, ac) AS (
                 SELECT h.agent_id,
                    h.channel,
                    h.offering_at,
                    COALESCE(h.reporting_at, h.leaving_at) AS e,
                    h.bridged_at AS v,
                        CASE
                            WHEN (h.bridged_at IS NOT NULL) THEN 1
                            WHEN (((h.channel)::text = 'task'::text) AND (h.reporting_at IS NOT NULL)) THEN 1
                            ELSE 0
                        END AS ac
                   FROM (agents a_1
                     JOIN call_center.cc_member_attempt_history h ON ((h.agent_id = a_1.id)))
                  WHERE ((h.leaving_at > ((now())::date - '2 days'::interval)) AND ((h.leaving_at >= a_1."from") AND (h.leaving_at <= a_1."to")) AND ((h.channel)::text = ANY (ARRAY['chat'::text, 'task'::text])) AND (h.agent_id IS NOT NULL) AND (1 = 1))
                )
         SELECT t.agent_id,
            t.c AS channel,
            sum(t.delta) AS sht,
            sum(t.ac) AS bridged_cnt,
            (EXTRACT(epoch FROM avg((t.e - t.b))))::bigint AS aht
           FROM ( SELECT rng.agent_id,
                    rng.c,
                    rng.s,
                    rng.e,
                    rng.b,
                    rng.ac,
                    GREATEST((rng.e - GREATEST(max(rng.e) OVER (PARTITION BY rng.agent_id, rng.c ORDER BY rng.s, rng.e ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), rng.s)), '00:00:00'::interval) AS delta
                   FROM rng) t
          GROUP BY t.agent_id, t.c
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
            count(h.parent_id) FILTER (WHERE ((h.bridged_at IS NULL) AND (NOT (h.hide_missed IS TRUE)) AND (h.queue_id IS NOT NULL))) AS queue_missed,
            count(*) FILTER (WHERE (((h.direction)::text = 'inbound'::text) AND (h.bridged_at IS NULL) AND (h.queue_id IS NOT NULL) AND ((h.cause)::text = ANY (ARRAY[('NO_ANSWER'::character varying)::text, ('USER_BUSY'::character varying)::text])))) AS abandoned,
            count(*) FILTER (WHERE ((cq.type = ANY (ARRAY[(3)::smallint, (4)::smallint, (5)::smallint])) AND (h.bridged_at IS NOT NULL))) AS outbound_queue,
            count(*) FILTER (WHERE ((h.parent_id IS NULL) AND ((h.direction)::text = 'outbound'::text) AND (h.queue_id IS NULL))) AS manual_call,
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
          WHERE ((ar.call_created_at >= (date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) AT TIME ZONE a_1.tz_name)) AND (ar.call_created_at <= (((date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) + '1 mon'::interval) - '1 day 00:00:01'::interval) AT TIME ZONE a_1.tz_name)))
          GROUP BY a_1.user_id
        )
 SELECT a.id AS agent_id,
    a.user_id,
    a.domain_id,
    COALESCE(c.missed, (0)::bigint) AS call_missed,
    COALESCE(c.queue_missed, (0)::bigint) AS call_queue_missed,
    COALESCE(c.abandoned, (0)::bigint) AS call_abandoned,
    COALESCE(c.inbound_bridged, (0)::bigint) AS call_inbound,
    COALESCE(c."inbound queue", (0)::bigint) AS call_inbound_queue,
    COALESCE(c.outbound_queue, (0)::bigint) AS call_dialer_queue,
    COALESCE(c.manual_call, (0)::bigint) AS call_manual,
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
    COALESCE(chc.aht, (0)::bigint) AS chat_aht,
    (((COALESCE(cht.bridged_cnt, (0)::bigint) + COALESCE(chc.bridged_cnt, (0)::bigint)) + COALESCE(c.handled, (0)::bigint)) - COALESCE(c.user_2user, (0)::bigint)) AS task_accepts,
    (COALESCE(EXTRACT(epoch FROM (stats.online - COALESCE(stats.lunch, '00:00:00'::interval))), (0)::numeric))::bigint AS online,
    COALESCE(chc.bridged_cnt, (0)::bigint) AS chat_accepts,
    COALESCE(rate.count, (0)::bigint) AS score_count,
    (COALESCE(EXTRACT(epoch FROM eff.processing), ((0)::bigint)::numeric))::integer AS processing,
    COALESCE(rate.score_optional_avg, (0)::numeric) AS score_optional_avg,
    COALESCE(rate.score_optional_sum, ((0)::bigint)::numeric) AS score_optional_sum,
    COALESCE(rate.score_required_avg, (0)::numeric) AS score_required_avg,
    COALESCE(rate.score_required_sum, ((0)::bigint)::numeric) AS score_required_sum
   FROM (((((((agents a
     LEFT JOIN call_center.cc_agent_with_user u ON ((u.id = a.id)))
     LEFT JOIN stats ON ((stats.agent_id = a.id)))
     LEFT JOIN eff ON ((eff.agent_id = a.id)))
     LEFT JOIN calls c ON ((c.user_id = a.user_id)))
     LEFT JOIN attempts chc ON (((chc.agent_id = a.id) AND ((chc.channel)::text = 'chat'::text))))
     LEFT JOIN attempts cht ON (((cht.agent_id = a.id) AND ((cht.channel)::text = 'task'::text))))
     LEFT JOIN rate ON ((rate.user_id = a.user_id)))
  WITH NO DATA;


--
-- Name: cc_agent_waiting; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_agent_waiting AS
 SELECT a.id,
    COALESCE(u.name, (u.username)::text) AS name,
    u.extension AS desctination
   FROM (call_center.cc_agent a
     JOIN directory.wbt_user u ON ((u.id = a.user_id)))
  WHERE (((a.status)::text = 'online'::text) AND (NOT (EXISTS ( SELECT 1
           FROM call_center.cc_calls c
          WHERE ((c.user_id = u.id) AND (c.hangup_at IS NULL))))));


--
-- Name: cc_member_attempt_transferred; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_member_attempt_transferred (
    id bigint NOT NULL,
    from_id bigint NOT NULL,
    to_id bigint NOT NULL,
    transferred_at timestamp with time zone DEFAULT now() NOT NULL,
    from_agent_id integer NOT NULL,
    to_agent_id integer
);


--
-- Name: cc_attempt_transferred_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_attempt_transferred_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_attempt_transferred_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_attempt_transferred_id_seq OWNED BY call_center.cc_member_attempt_transferred.id;


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
    updated_by bigint,
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
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
    i.updated_at,
    call_center.cc_get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS updated_by,
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
    ans.v AS answers,
    r.score_required,
    r.score_optional,
    r.comment,
    r.call_id,
    f.questions,
    r.rated_user_id,
    r.created_by AS grantor,
    r.select_yes_count,
    r.critical_count
   FROM (((((call_center.cc_audit_rate r
     LEFT JOIN LATERAL ( SELECT jsonb_agg(
                CASE
                    WHEN (u_1.id IS NOT NULL) THEN (x.j || jsonb_build_object('updated_by', call_center.cc_get_lookup(u_1.id, (COALESCE(u_1.name, (u_1.username)::text))::character varying)))
                    ELSE x.j
                END ORDER BY x.i) AS v
           FROM (jsonb_array_elements(r.answers) WITH ORDINALITY x(j, i)
             LEFT JOIN directory.wbt_user u_1 ON ((u_1.id = (((x.j -> 'updated_by'::text) -> 'id'::text))::bigint)))) ans ON (true))
     LEFT JOIN call_center.cc_audit_form f ON ((f.id = r.form_id)))
     LEFT JOIN directory.wbt_user ur ON ((ur.id = r.rated_user_id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = r.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = r.updated_by)));


--
-- Name: cc_bucket; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_bucket (
    id bigint NOT NULL,
    name name NOT NULL,
    domain_id bigint NOT NULL,
    description character varying(200) DEFAULT ''::character varying NOT NULL,
    created_at bigint,
    created_by bigint,
    updated_at bigint,
    updated_by bigint
);


--
-- Name: cc_bucket_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_bucket_acl (
    dc bigint NOT NULL,
    object integer NOT NULL,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL,
    grantor bigint
);


--
-- Name: cc_bucket_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_bucket_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_bucket_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_bucket_id_seq OWNED BY call_center.cc_bucket.id;


--
-- Name: cc_bucket_in_queue; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_bucket_in_queue (
    id integer NOT NULL,
    queue_id integer NOT NULL,
    ratio integer DEFAULT 0 NOT NULL,
    bucket_id integer NOT NULL,
    disabled boolean DEFAULT false NOT NULL,
    priority integer DEFAULT 0 NOT NULL
);


--
-- Name: cc_bucket_in_queue_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_bucket_in_queue_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_bucket_in_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_bucket_in_queue_id_seq OWNED BY call_center.cc_bucket_in_queue.id;


--
-- Name: cc_bucket_in_queue_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_bucket_in_queue_view AS
 SELECT q.id,
    q.ratio,
    q.priority,
    call_center.cc_get_lookup(cb.id, ((cb.name)::text)::character varying) AS bucket,
    q.queue_id,
    q.bucket_id,
    cb.domain_id,
    cb.name AS bucket_name,
    q.disabled
   FROM (call_center.cc_bucket_in_queue q
     LEFT JOIN call_center.cc_bucket cb ON ((q.bucket_id = cb.id)));


--
-- Name: cc_bucket_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_bucket_view AS
 SELECT b.id,
    ((b.name)::character varying COLLATE "default") AS name,
    b.description,
    b.domain_id
   FROM call_center.cc_bucket b;


--
-- Name: cc_member; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_member (
    id integer NOT NULL,
    queue_id integer NOT NULL,
    priority smallint DEFAULT 0 NOT NULL,
    variables jsonb DEFAULT '{}'::jsonb,
    name character varying(250) DEFAULT ''::character varying NOT NULL,
    stop_cause character varying(50),
    attempts integer DEFAULT 0 NOT NULL,
    agent_id integer,
    communications jsonb,
    bucket_id integer,
    timezone_id integer,
    last_agent integer,
    sys_offset_id smallint,
    domain_id bigint NOT NULL,
    ready_at timestamp with time zone,
    stop_at timestamp with time zone,
    last_hangup_at bigint DEFAULT 0 NOT NULL,
    search_destinations character varying[],
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expire_at timestamp with time zone,
    skill_id integer,
    import_id character varying(120),
    sys_destinations call_center.cc_destination[],
    CONSTRAINT cc_member_bucket_skill_check CHECK ((NOT ((bucket_id IS NOT NULL) AND (skill_id IS NOT NULL))))
)
WITH (autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_vacuum_cost_delay='20', autovacuum_enabled='1', autovacuum_analyze_threshold='2000', fillfactor='20');
ALTER TABLE ONLY call_center.cc_member ALTER COLUMN communications SET STATISTICS 100;


--
-- Name: cc_member_attempt; Type: TABLE; Schema: call_center; Owner: -
--

CREATE UNLOGGED TABLE call_center.cc_member_attempt (
    id bigint NOT NULL,
    queue_id integer,
    member_id bigint,
    weight integer DEFAULT 0 NOT NULL,
    resource_id integer,
    node_id character varying(20),
    result character varying(200),
    agent_id integer,
    bucket_id bigint,
    display character varying(50),
    description character varying,
    list_communication_id bigint,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    leaving_at timestamp with time zone,
    agent_call_id character varying,
    member_call_id character varying,
    offering_at timestamp with time zone,
    reporting_at timestamp with time zone,
    state character varying DEFAULT 'idle'::character varying NOT NULL,
    bridged_at timestamp with time zone,
    channel character varying DEFAULT 'call'::character varying NOT NULL,
    timeout timestamp with time zone,
    last_state_change timestamp with time zone DEFAULT now() NOT NULL,
    communication_idx integer DEFAULT 1 NOT NULL,
    resource_group_id integer,
    destination jsonb,
    seq integer DEFAULT 0 NOT NULL,
    answered_at timestamp with time zone,
    team_id integer,
    sticky_agent_id integer,
    domain_id bigint NOT NULL,
    transferred_at timestamp with time zone,
    transferred_agent_id integer,
    transferred_attempt_id bigint,
    parent_id bigint,
    waiting_other_numbers integer DEFAULT 0 NOT NULL,
    form_fields jsonb,
    form_view jsonb,
    import_id character varying(120),
    schema_processing boolean DEFAULT false,
    queue_params jsonb,
    variables jsonb,
    queue_type smallint,
    offered_agent_ids integer[]
)
WITH (fillfactor='20', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01');


--
-- Name: TABLE cc_member_attempt; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON TABLE call_center.cc_member_attempt IS 'todo';


--
-- Name: COLUMN cc_member_attempt.communication_idx; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON COLUMN call_center.cc_member_attempt.communication_idx IS 'fixme';


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
-- Name: cc_calls_annotation; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_calls_annotation (
    id bigint NOT NULL,
    call_id character varying NOT NULL,
    created_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    note text NOT NULL,
    start_sec integer DEFAULT 0 NOT NULL,
    end_sec integer DEFAULT 0 NOT NULL,
    updated_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cc_call_annotation_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_call_annotation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_call_annotation_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_call_annotation_id_seq OWNED BY call_center.cc_calls_annotation.id;


--
-- Name: cc_list; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_list (
    id bigint NOT NULL,
    name character varying(50) NOT NULL,
    type integer DEFAULT 0 NOT NULL,
    description character varying,
    domain_id bigint NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint,
    updated_at bigint NOT NULL,
    updated_by bigint
);


--
-- Name: cc_call_list_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_call_list_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_call_list_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_call_list_id_seq OWNED BY call_center.cc_list.id;


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
            WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND (c.id <> call_center.cc_bridged_id(c.parent_id))) THEN call_center.cc_bridged_id(c.parent_id)
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
    ( SELECT json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at', ((c.params -> 'record_start'::text))::bigint, 'stop_at', ((c.params -> 'record_stop'::text))::bigint, 'start_record', f_1.sr)) AS files
           FROM ( SELECT f1.id,
                    f1.size,
                    f1.mime_type,
                    f1.name,
                        CASE
                            WHEN (((c.direction)::text = 'outbound'::text) AND (c.user_id IS NOT NULL) AND ((c.queue_id IS NULL) OR (cq.type = 2))) THEN 'operator'::text
                            ELSE 'client'::text
                        END AS sr
                   FROM storage.files f1
                  WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.id)::text))
                UNION ALL
                 SELECT f1.id,
                    f1.size,
                    f1.mime_type,
                    f1.name,
                    NULL::text AS sr
                   FROM storage.files f1
                  WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND (c.parent_id IS NOT NULL) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) AS files,
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
          WHERE ((c.parent_id IS NULL) AND (hp.parent_id = c.id) AND (hp.created_at > (c.created_at)::date)))) AS has_children,
    (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), (''::character varying)::text))::character varying AS agent_description,
    c.grantee_id,
    ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
           FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                   FROM call_center.cc_calls_history chh
                  WHERE ((chh.parent_id = c.id) AND (chh.created_at > (c.created_at)::date) AND (chh.hold IS NOT NULL))
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
            WHEN (((c.cause)::text = 'ORIGINATOR_CANCEL'::text) OR (((c.cause)::text = 'NORMAL_UNSPECIFIED'::text) AND (c.amd_ai_result IS NOT NULL)) OR (((c.cause)::text = 'LOSE_RACE'::text) AND (cq.type = 4))) THEN 'cancelled'::text
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
          WHERE (j.file_id IN ( SELECT f_1.id
                   FROM ( SELECT f1.id
                           FROM storage.files f1
                          WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.id)::text))
                        UNION
                         SELECT f1.id
                           FROM storage.files f1
                          WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1))) AS files_job,
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
    ((EXISTS ( SELECT 1
          WHERE ((c.answered_at IS NOT NULL) AND (cq.type = 2)))) OR (EXISTS ( SELECT 1
           FROM call_center.cc_calls_history cr
          WHERE ((cr.id = c.bridged_id) AND (c.bridged_id IS NOT NULL) AND (c.blind_transfer IS NULL) AND (cr.blind_transfer IS NULL) AND (c.transfer_to IS NULL) AND (cr.transfer_to IS NULL) AND (c.transfer_from IS NULL) AND (cr.transfer_from IS NULL) AND (COALESCE(cr.user_id, c.user_id) IS NOT NULL))))) AS allow_evaluation,
    cma.form_fields,
    c.bridged_id,
    call_center.cc_get_lookup(cc.id, (cc.common_name)::character varying) AS contact,
    c.contact_id,
    c.search_number,
    c.hide_missed,
    c.redial_id,
    ((c.parent_id IS NOT NULL) AND (EXISTS ( SELECT 1
           FROM call_center.cc_calls_history lega
          WHERE ((lega.id = c.parent_id) AND (lega.domain_id = c.domain_id) AND (lega.bridged_at IS NOT NULL))))) AS parent_bridged,
    ( SELECT jsonb_agg(call_center.cc_get_lookup(ash.id, ash.name)) AS jsonb_agg
           FROM flow.acr_routing_scheme ash
          WHERE (ash.id = ANY (c.schema_ids))) AS schemas,
    c.schema_ids,
    c.hangup_phrase,
    c.blind_transfers,
    c.destination_name,
    c.attempt_ids,
    ( SELECT jsonb_agg(json_build_object('id', p.id, 'agent', u_1."user", 'form_fields', p.form_fields, 'reporting_at', call_center.cc_view_timestamp(p.reporting_at))) AS jsonb_agg
           FROM (call_center.cc_member_attempt_history p
             LEFT JOIN call_center.cc_agent_with_user u_1 ON ((u_1.id = p.agent_id)))
          WHERE ((p.id IN ( SELECT DISTINCT x.x
                   FROM unnest((c.attempt_ids || c.attempt_id)) x(x))) AND (p.reporting_at IS NOT NULL))
         LIMIT 20) AS forms
   FROM (((((((((((((call_center.cc_calls_history c
     LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
     LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
     LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
     LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
     LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
     LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
     LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
     LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
     LEFT JOIN directory.wbt_user aru ON ((aru.id = ar.rated_user_id)))
     LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by)))
     LEFT JOIN contacts.contact cc ON ((cc.id = c.contact_id)));


--
-- Name: cc_calls_transcribe; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_calls_transcribe (
    id bigint NOT NULL,
    call_id character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    transcribe character varying,
    confidence numeric DEFAULT 0.0 NOT NULL,
    response jsonb,
    question character varying
);


--
-- Name: cc_calls_transcribe_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_calls_transcribe_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_calls_transcribe_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_calls_transcribe_id_seq OWNED BY call_center.cc_calls_transcribe.id;


--
-- Name: cc_cluster; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_cluster (
    id integer NOT NULL,
    node_name character varying(20) NOT NULL,
    updated_at bigint NOT NULL,
    master boolean NOT NULL,
    started_at bigint DEFAULT 0 NOT NULL
);


--
-- Name: cc_cluster_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_cluster_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_cluster_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_cluster_id_seq OWNED BY call_center.cc_cluster.id;


--
-- Name: cc_communication; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_communication (
    id integer NOT NULL,
    name character varying(50) NOT NULL,
    code character varying(100) NOT NULL,
    channel character varying,
    domain_id bigint NOT NULL,
    description character varying(200) DEFAULT ''::character varying,
    "default" boolean DEFAULT false NOT NULL
);


--
-- Name: cc_communication_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_communication_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_communication_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_communication_id_seq OWNED BY call_center.cc_communication.id;


--
-- Name: cc_communication_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_communication_list AS
 SELECT c.id,
    c.name,
    c.code,
    c.description,
    c.channel,
    c."default",
    c.domain_id
   FROM call_center.cc_communication c;


--
-- Name: cc_distribute_stage_1; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_distribute_stage_1 AS
SELECT
    NULL::integer AS id,
    NULL::smallint AS type,
    NULL::smallint AS strategy,
    NULL::bigint AS team_id,
    NULL::call_center.cc_sys_distribute_bucket[] AS buckets,
    NULL::call_center.cc_sys_distribute_type[] AS types,
    NULL::call_center.cc_sys_distribute_resource[] AS resources,
    NULL::integer[] AS offset_ids,
    NULL::integer AS lim,
    NULL::bigint AS domain_id,
    NULL::integer AS priority,
    NULL::boolean AS sticky_agent,
    NULL::integer AS sticky_agent_sec,
    NULL::boolean AS recall_calendar,
    NULL::boolean AS wait_between_retries_desc,
    NULL::boolean AS strict_circuit,
    NULL::boolean AS ins,
    NULL::bigint AS min_wt;


--
-- Name: system_settings; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.system_settings (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    name character varying NOT NULL,
    value jsonb
);


--
-- Name: cc_distribute_stats; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_distribute_stats AS
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
    (call_center.cc_wrap_over_dial((s.over_dial)::numeric, (s.abandoned_rate)::numeric, COALESCE(((q.payload -> 'target_abandoned_rate'::text))::numeric, COALESCE(((q.payload -> 'max_abandoned_rate'::text))::numeric, 3.0)), COALESCE(((q.payload -> 'max_abandoned_rate'::text))::numeric, 3.0), COALESCE(((q.payload -> 'load_factor'::text))::numeric, 10.0)))::double precision AS over_dial,
    GREATEST(s.abandoned_rate, (0)::double precision) AS abandoned_rate,
    s.hit_rate,
    s.agents,
    s.aggent_ids
   FROM (((call_center.cc_queue q
     LEFT JOIN LATERAL ( SELECT
                CASE
                    WHEN ((jsonb_typeof(s_1.value) = 'boolean'::text) AND (s_1.value)::boolean) THEN true
                    ELSE false
                END AS amd_cancel_not_human
           FROM call_center.system_settings s_1
          WHERE ((s_1.domain_id = q.domain_id) AND ((s_1.name)::text = 'amd_cancel_not_human'::text))) sys ON (true))
     LEFT JOIN LATERAL ( SELECT
                CASE
                    WHEN sys.amd_cancel_not_human THEN tmp.v
                    ELSE (tmp.v || 'CANCEL'::text)
                END AS arr
           FROM ( SELECT
                        CASE
                            WHEN ((((q.payload -> 'amd'::text) -> 'allow_not_sure'::text))::boolean IS TRUE) THEN ARRAY['HUMAN'::text, 'NOTSURE'::text]
                            ELSE ARRAY['HUMAN'::text]
                        END AS v) tmp) amd ON (true))
     JOIN LATERAL ( SELECT att.queue_id,
            att.bucket_id,
            min(att.joined_at) AS start_stat,
            max(att.joined_at) AS stop_stat,
            count(*) AS call_attempts,
            COALESCE(avg(date_part('epoch'::text, (COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))) FILTER (WHERE (att.bridged_at IS NOT NULL)), (0)::double precision) AS avg_handle,
            COALESCE(avg(DISTINCT (round(date_part('epoch'::text, (COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))))::real) FILTER (WHERE (att.bridged_at IS NOT NULL)), (0)::double precision) AS med_handle,
            COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE (ch.answered_at IS NOT NULL)), (0)::double precision) AS avg_member_answer,
            COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (ch.bridged_at IS NULL))), (0)::double precision) AS avg_member_answer_not_bridged,
            COALESCE(avg(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (ch.bridged_at IS NOT NULL))), (0)::double precision) AS avg_member_answer_bridged,
            COALESCE(max(date_part('epoch'::text, (ch.answered_at - att.joined_at))) FILTER (WHERE (ch.answered_at IS NOT NULL)), (0)::double precision) AS max_member_answer,
            count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)) AS connected_calls,
            count(*) FILTER (WHERE (att.bridged_at IS NOT NULL)) AS bridged_calls,
            count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (att.bridged_at IS NULL) AND amd_res.human)) AS abandoned_calls,
            ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) AS connection_rate,
                CASE
                    WHEN (((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) > (0)::double precision) THEN ((1)::double precision / ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision))
                    ELSE (((count(*) / GREATEST(count(DISTINCT att.agent_id), (1)::bigint)) - 1))::double precision
                END AS over_dial,
            COALESCE(((((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND (att.bridged_at IS NULL) AND amd_res.human)))::double precision - (COALESCE(((q.payload -> 'abandon_rate_adjustment'::text))::integer, 0))::double precision) / (NULLIF(count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)), 0))::double precision) * (100)::double precision), (0)::double precision) AS abandoned_rate,
            ((count(*) FILTER (WHERE ((ch.answered_at IS NOT NULL) AND amd_res.human)))::double precision / (count(*))::double precision) AS hit_rate,
            count(DISTINCT att.agent_id) AS agents,
            array_agg(DISTINCT att.agent_id) FILTER (WHERE (att.agent_id IS NOT NULL)) AS aggent_ids
           FROM ((call_center.cc_member_attempt_history att
             LEFT JOIN call_center.cc_calls_history ch ON (((ch.domain_id = att.domain_id) AND (ch.id = (att.member_call_id)::uuid) AND (ch.created_at > ((now())::date - '1 day'::interval)))))
             LEFT JOIN LATERAL ( SELECT (((ch.amd_result IS NULL) AND (ch.amd_ai_positive IS NULL)) OR ((ch.amd_result)::text = ANY (amd.arr)) OR (ch.amd_ai_positive IS TRUE)) AS human) amd_res ON (true))
          WHERE (((att.channel)::text = 'call'::text) AND (att.joined_at > (now() - ((COALESCE(((q.payload -> 'statistic_time'::text))::integer, 60) || ' min'::text))::interval)) AND (att.queue_id = q.id) AND (att.domain_id = q.domain_id))
          GROUP BY att.queue_id, att.bucket_id) s ON ((s.queue_id IS NOT NULL)))
  WHERE ((q.type = 5) AND q.enabled)
  WITH NO DATA;


--
-- Name: cc_email; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_email (
    id bigint NOT NULL,
    "from" character varying[] NOT NULL,
    "to" character varying[],
    profile_id integer NOT NULL,
    subject character varying,
    cc character varying[],
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    parent_id bigint,
    direction character varying,
    user_id bigint,
    attempt_id bigint,
    message_id character varying NOT NULL,
    sender character varying[],
    reply_to character varying[],
    in_reply_to character varying,
    variables jsonb,
    root_id character varying,
    flow_id integer,
    body text,
    html text,
    attachment_ids bigint[],
    contact_ids bigint[],
    owner_id bigint,
    cid jsonb
);


--
-- Name: cc_email_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_email_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_email_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_email_id_seq OWNED BY call_center.cc_email.id;


--
-- Name: cc_email_profile; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_email_profile (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    name character varying NOT NULL,
    description character varying DEFAULT ''::character varying NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    last_activity_at timestamp with time zone,
    fetch_err character varying,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    fetch_interval integer DEFAULT 5 NOT NULL,
    state character varying DEFAULT 'idle'::character varying NOT NULL,
    flow_id integer,
    imap_host character varying,
    mailbox character varying,
    imap_port integer,
    smtp_port integer,
    login character varying,
    password character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_by bigint,
    smtp_host character varying,
    params jsonb,
    auth_type character varying DEFAULT 'plain'::character varying NOT NULL,
    listen boolean DEFAULT false NOT NULL,
    token jsonb
);


--
-- Name: COLUMN cc_email_profile.fetch_interval; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON COLUMN call_center.cc_email_profile.fetch_interval IS 'sec; TODO add check > 5';


--
-- Name: cc_email_profile_list; Type: VIEW; Schema: call_center; Owner: -
--

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
-- Name: cc_email_profiles_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_email_profiles_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_email_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_email_profiles_id_seq OWNED BY call_center.cc_email_profile.id;


--
-- Name: cc_inbound_stats; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_inbound_stats AS
 SELECT h.queue_id,
    h.bucket_id,
    COALESCE(avg(date_part('epoch'::text, (COALESCE(h.bridged_at, h.reporting_at, h.leaving_at) - h.joined_at))) FILTER (WHERE (h.bridged_at IS NOT NULL)), (0)::double precision) AS ata,
    count(DISTINCT h.agent_id) AS agent_cnt,
    COALESCE(avg(date_part('epoch'::text, (COALESCE(h.reporting_at, h.leaving_at) - h.joined_at))) FILTER (WHERE (h.bridged_at IS NOT NULL)), (0)::double precision) AS aha,
    count(*) AS cnt,
    count(*) FILTER (WHERE (h.bridged_at IS NOT NULL)) AS cntb,
    (((count(*) FILTER (WHERE ((h.bridged_at - h.joined_at) < '00:00:20'::interval)))::double precision * (100)::double precision) / (count(*))::double precision) AS sl20,
    (((count(*) FILTER (WHERE ((h.bridged_at - h.joined_at) < '00:00:30'::interval)))::double precision * (100)::double precision) / (count(*))::double precision) AS sl30
   FROM call_center.cc_member_attempt_history h
  WHERE ((h.leaving_at > (now() - '01:00:00'::interval)) AND (h.queue_id = ANY (ARRAY( SELECT q.id
           FROM call_center.cc_queue q
          WHERE (q.enabled AND (q.type = 1))))))
  GROUP BY h.queue_id, h.bucket_id
  WITH NO DATA;


--
-- Name: cc_list_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_list_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    object bigint NOT NULL,
    grantor bigint,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL
);


--
-- Name: cc_list_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_list_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_list_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_list_acl_id_seq OWNED BY call_center.cc_list_acl.id;


--
-- Name: cc_list_communications; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_list_communications (
    list_id bigint NOT NULL,
    number character varying(256) NOT NULL,
    id bigint NOT NULL,
    description text,
    expire_at timestamp with time zone
);


--
-- Name: cc_list_communications_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_list_communications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_list_communications_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_list_communications_id_seq OWNED BY call_center.cc_list_communications.id;


--
-- Name: cc_list_communications_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_list_communications_view AS
 SELECT i.id,
    i.number,
    i.description,
    i.list_id,
    cl.domain_id,
    i.expire_at
   FROM (call_center.cc_list_communications i
     LEFT JOIN call_center.cc_list cl ON ((cl.id = i.list_id)));


--
-- Name: cc_list_statistics; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_list_statistics (
    list_id integer NOT NULL,
    count integer DEFAULT 0 NOT NULL
);


--
-- Name: cc_list_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_list_view AS
 SELECT i.id,
    i.name,
    i.description,
    i.domain_id,
    i.created_at,
    call_center.cc_get_lookup(uc.id, (uc.name)::character varying) AS created_by,
    i.updated_at,
    call_center.cc_get_lookup(u.id, (u.name)::character varying) AS updated_by,
    COALESCE(cls.count, 0) AS count
   FROM (((call_center.cc_list i
     LEFT JOIN directory.wbt_user uc ON ((uc.id = i.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = i.updated_by)))
     LEFT JOIN call_center.cc_list_statistics cls ON ((i.id = cls.list_id)));


--
-- Name: cc_queue_skill; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue_skill (
    id integer NOT NULL,
    queue_id integer NOT NULL,
    skill_id integer NOT NULL,
    bucket_ids integer[],
    lvl smallint DEFAULT 0 NOT NULL,
    min_capacity smallint DEFAULT 0 NOT NULL,
    max_capacity smallint DEFAULT 100 NOT NULL,
    enabled boolean DEFAULT true NOT NULL
);


--
-- Name: cc_manual_queue_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_manual_queue_list AS
 WITH manual_queue AS MATERIALIZED (
         SELECT q.domain_id,
            q.id,
            call_center.cc_get_lookup((q.id)::bigint, q.name) AS queue,
            q.priority,
            q.sticky_agent,
            q.team_id,
            COALESCE(((q.payload -> 'max_wait_time'::text))::integer, 0) AS max_wait_time,
            COALESCE(((q.payload -> 'sticky_agent_sec'::text))::integer, 0) AS sticky_agent_sec
           FROM call_center.cc_queue q
          WHERE (COALESCE(((q.payload -> 'manual_distribution'::text))::boolean, false) AND q.enabled)
          ORDER BY q.domain_id
        ), queues AS MATERIALIZED (
         SELECT DISTINCT q.domain_id,
            q.queue,
            qs.queue_id,
            q.priority,
            bq.priority AS bucket_pri,
            q.max_wait_time,
            q.sticky_agent_sec,
            q.sticky_agent,
            b.b AS bucket_id,
            csia.agent_id,
            a.user_id,
            max(qs.lvl) AS lvl
           FROM (((((manual_queue q
             JOIN call_center.cc_queue_skill qs ON ((qs.queue_id = q.id)))
             JOIN call_center.cc_skill_in_agent csia ON ((csia.skill_id = qs.skill_id)))
             JOIN call_center.cc_agent a ON (((a.id = csia.agent_id) AND ((q.team_id IS NULL) OR (q.team_id = a.team_id)))))
             LEFT JOIN LATERAL unnest(qs.bucket_ids) b(b) ON (true))
             LEFT JOIN call_center.cc_bucket_in_queue bq ON (((bq.queue_id = q.id) AND (bq.bucket_id = b.b))))
          WHERE (qs.enabled AND csia.enabled AND (csia.capacity >= qs.min_capacity) AND (csia.capacity <= qs.max_capacity) AND (q.domain_id = a.domain_id) AND ((a.status)::text = 'online'::text))
          GROUP BY q.domain_id, q.queue, qs.queue_id, q.priority, bq.priority, q.max_wait_time, q.sticky_agent_sec, q.sticky_agent, b.b, csia.agent_id, a.user_id
        ), attempts AS MATERIALIZED (
         SELECT q.domain_id,
            q.queue,
            q.queue_id,
            q.priority,
            q.bucket_pri,
            q.max_wait_time,
            q.sticky_agent_sec,
            q.sticky_agent,
            q.bucket_id,
            q.agent_id,
            q.user_id,
            q.lvl,
            a.id AS attempt_id,
            a.joined_at,
            a.member_call_id AS session_id,
            (EXTRACT(epoch FROM (now() - a.joined_at)))::integer AS wait,
            a.destination AS communication,
            a.sticky_agent_id,
            a.channel,
            (((EXTRACT(epoch FROM (now() - a.joined_at)) / (q.max_wait_time)::numeric) * (100)::numeric))::integer AS deadline
           FROM (call_center.cc_member_attempt a
             JOIN queues q ON ((q.queue_id = a.queue_id)))
          WHERE ((a.domain_id = q.domain_id) AND (a.agent_id IS NULL) AND ((a.state)::text = 'wait_agent'::text) AND (a.queue_id = q.queue_id) AND (COALESCE(q.bucket_id, 0) = COALESCE(a.bucket_id, (0)::bigint)) AND ((a.sticky_agent_id IS NULL) OR (a.sticky_agent_id = q.agent_id) OR (a.joined_at < (now() - ((q.sticky_agent_sec || ' sec'::text))::interval))))
         FOR UPDATE OF a SKIP LOCKED
        )
 SELECT x.domain_id,
    array_agg(x.user_id) AS users,
    array_to_json(x.calls[1:10]) AS calls,
    array_to_json(x.chats[1:100]) AS chats
   FROM ( SELECT a.domain_id,
            a.user_id,
            array_agg(jsonb_build_object('attempt_id', a.attempt_id, 'wait', a.wait, 'communication', a.communication, 'queue', a.queue, 'bucket', call_center.cc_get_lookup(b.id, ((b.name)::text)::character varying), 'deadline', a.deadline, 'session_id', a.session_id) ORDER BY a.lvl, a.priority DESC, a.bucket_pri DESC NULLS LAST, a.wait DESC) FILTER (WHERE ((a.channel)::text = 'call'::text)) AS calls,
            array_agg(jsonb_build_object('attempt_id', a.attempt_id, 'wait', a.wait, 'communication', a.communication, 'queue', a.queue, 'bucket', call_center.cc_get_lookup(b.id, ((b.name)::text)::character varying), 'deadline', a.deadline, 'session_id', a.session_id) ORDER BY a.lvl, a.priority DESC, a.bucket_pri DESC NULLS LAST, a.wait DESC) FILTER (WHERE ((a.channel)::text = 'chat'::text)) AS chats
           FROM (attempts a
             LEFT JOIN call_center.cc_bucket b ON ((b.id = a.bucket_id)))
          GROUP BY a.domain_id, a.user_id) x
  GROUP BY x.domain_id, x.calls[1:10], x.chats[1:100];


--
-- Name: cc_member_attempt_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_member_attempt_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_member_attempt_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_member_attempt_id_seq OWNED BY call_center.cc_member_attempt.id;


--
-- Name: cc_member_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_member_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_member_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_member_id_seq OWNED BY call_center.cc_member.id;


--
-- Name: cc_member_messages; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_member_messages (
    id bigint NOT NULL,
    member_id bigint NOT NULL,
    communication_id bigint NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    created_at bigint DEFAULT 0 NOT NULL,
    message bytea
);


--
-- Name: cc_member_messages_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_member_messages_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_member_messages_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_member_messages_id_seq OWNED BY call_center.cc_member_messages.id;


--
-- Name: cc_outbound_resource; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource (
    id integer NOT NULL,
    "limit" integer DEFAULT 0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    updated_at bigint NOT NULL,
    rps integer DEFAULT '-1'::integer,
    domain_id bigint NOT NULL,
    reserve boolean DEFAULT false,
    variables jsonb DEFAULT '{}'::jsonb NOT NULL,
    number character varying(20) NOT NULL,
    max_successively_errors integer DEFAULT 0,
    name character varying(50) NOT NULL,
    last_error_id character varying(50),
    successively_errors smallint DEFAULT 0 NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint,
    updated_by bigint,
    error_ids character varying(50)[] DEFAULT '{}'::character varying[],
    gateway_id bigint,
    email_profile_id integer,
    payload jsonb,
    description character varying,
    patterns character varying[],
    failure_dial_delay integer DEFAULT 0,
    last_error_at timestamp with time zone,
    parameters jsonb
);


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
    ( SELECT jsonb_agg(ofa."user") AS jsonb_agg
           FROM call_center.cc_agent_with_user ofa
          WHERE (ofa.id = ANY (t.offered_agent_ids))) AS offered_agents,
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
    c.amd_result,
    t.offered_agent_ids
   FROM ((((((((call_center.cc_member_attempt_history t
     LEFT JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
     LEFT JOIN call_center.cc_member cm ON ((t.member_id = cm.id)))
     LEFT JOIN call_center.cc_agent a ON ((t.agent_id = a.id)))
     LEFT JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (u.dc = a.domain_id))))
     LEFT JOIN call_center.cc_outbound_resource r ON ((r.id = t.resource_id)))
     LEFT JOIN call_center.cc_bucket cb ON ((cb.id = t.bucket_id)))
     LEFT JOIN call_center.cc_list l ON ((l.id = t.list_communication_id)))
     LEFT JOIN call_center.cc_calls_history c ON (((c.domain_id = t.domain_id) AND (c.id = (t.member_call_id)::uuid))));


--
-- Name: cc_notification; Type: TABLE; Schema: call_center; Owner: -
--

CREATE UNLOGGED TABLE call_center.cc_notification (
    id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    accepted_at timestamp with time zone,
    accepted_by bigint,
    closed_at timestamp with time zone,
    description character varying,
    for_users bigint[],
    action character varying NOT NULL,
    domain_id bigint NOT NULL,
    timeout timestamp with time zone,
    object_id character varying
);


--
-- Name: cc_notification_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_notification_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_notification_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_notification_id_seq OWNED BY call_center.cc_notification.id;


--
-- Name: cc_outbound_resource_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    object bigint NOT NULL,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL
);


--
-- Name: cc_outbound_resource_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_outbound_resource_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_outbound_resource_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_outbound_resource_acl_id_seq OWNED BY call_center.cc_outbound_resource_acl.id;


--
-- Name: cc_outbound_resource_display; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource_display (
    id bigint NOT NULL,
    resource_id bigint NOT NULL,
    display character varying(50) NOT NULL
);


--
-- Name: cc_outbound_resource_display_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_outbound_resource_display_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_outbound_resource_display_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_outbound_resource_display_id_seq OWNED BY call_center.cc_outbound_resource_display.id;


--
-- Name: cc_outbound_resource_display_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_outbound_resource_display_view AS
 SELECT d.id,
    d.display,
    d.resource_id,
    cor.domain_id
   FROM (call_center.cc_outbound_resource_display d
     LEFT JOIN call_center.cc_outbound_resource cor ON ((d.resource_id = cor.id)));


--
-- Name: cc_outbound_resource_group; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource_group (
    id bigint NOT NULL,
    domain_id bigint NOT NULL,
    name character varying(50) NOT NULL,
    strategy character varying(10) NOT NULL,
    description character varying(200) DEFAULT ''::character varying NOT NULL,
    communication_id bigint NOT NULL,
    created_at bigint NOT NULL,
    created_by bigint,
    updated_at bigint NOT NULL,
    updated_by bigint,
    "time" jsonb
);


--
-- Name: cc_outbound_resource_group_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource_group_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    subject bigint NOT NULL,
    object bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL
);


--
-- Name: cc_outbound_resource_group_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_outbound_resource_group_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_outbound_resource_group_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_outbound_resource_group_acl_id_seq OWNED BY call_center.cc_outbound_resource_group_acl.id;


--
-- Name: cc_outbound_resource_group_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_outbound_resource_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_outbound_resource_group_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_outbound_resource_group_id_seq OWNED BY call_center.cc_outbound_resource_group.id;


--
-- Name: cc_outbound_resource_group_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_outbound_resource_group_view AS
 SELECT s.id,
    s.domain_id,
    s.name,
    s.strategy,
    s.description,
    call_center.cc_get_lookup((comm.id)::bigint, comm.name) AS communication,
    s.created_at,
    call_center.cc_get_lookup(c.id, (c.name)::character varying) AS created_by,
    s.updated_at,
    call_center.cc_get_lookup(u.id, (u.name)::character varying) AS updated_by,
    s.communication_id,
    s."time"
   FROM (((call_center.cc_outbound_resource_group s
     JOIN call_center.cc_communication comm ON ((comm.id = s.communication_id)))
     LEFT JOIN directory.wbt_user c ON ((c.id = s.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = s.updated_by)));


--
-- Name: cc_outbound_resource_in_group; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource_in_group (
    id bigint NOT NULL,
    resource_id bigint NOT NULL,
    group_id bigint NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    reserve_resource_id bigint
);


--
-- Name: cc_outbound_resource_in_group_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_outbound_resource_in_group_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_outbound_resource_in_group_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_outbound_resource_in_group_id_seq OWNED BY call_center.cc_outbound_resource_in_group.id;


--
-- Name: cc_outbound_resource_in_group_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_outbound_resource_in_group_view AS
 SELECT s.id,
    s.group_id,
    call_center.cc_get_lookup((cor.id)::bigint, cor.name) AS resource,
    call_center.cc_get_lookup((res.id)::bigint, res.name) AS reserve_resource,
    s.resource_id,
    cor.name AS resource_name,
    s.priority,
    cor.domain_id
   FROM (((call_center.cc_outbound_resource_in_group s
     LEFT JOIN call_center.cc_outbound_resource cor ON ((s.resource_id = cor.id)))
     LEFT JOIN call_center.cc_outbound_resource_group corg ON ((s.group_id = corg.id)))
     LEFT JOIN call_center.cc_outbound_resource res ON ((res.id = s.reserve_resource_id)));


--
-- Name: cc_outbound_resource_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_outbound_resource_view AS
 SELECT s.id,
    s."limit",
    s.enabled,
    s.updated_at,
    s.rps,
    s.domain_id,
    s.reserve,
    s.variables,
    s.number,
    s.max_successively_errors,
    s.name,
    s.error_ids,
    s.last_error_id,
    s.successively_errors,
    s.last_error_at,
    s.created_at,
    call_center.cc_get_lookup(c.id, (c.name)::character varying) AS created_by,
    call_center.cc_get_lookup(u.id, (u.name)::character varying) AS updated_by,
    call_center.cc_get_lookup(gw.id, gw.name) AS gateway,
    s.gateway_id,
    s.description,
    s.patterns,
    s.failure_dial_delay
   FROM (((call_center.cc_outbound_resource s
     LEFT JOIN directory.wbt_user c ON ((c.id = s.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = s.updated_by)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = s.gateway_id)));


--
-- Name: cc_pause_cause; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_pause_cause (
    id integer NOT NULL,
    name character varying NOT NULL,
    limit_min integer DEFAULT 0 NOT NULL,
    allow_supervisor boolean DEFAULT true NOT NULL,
    allow_agent boolean DEFAULT true NOT NULL,
    domain_id bigint NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_by bigint,
    description character varying DEFAULT ''::character varying NOT NULL,
    allow_admin boolean DEFAULT true NOT NULL
);


--
-- Name: cc_pause_cause_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_pause_cause_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_pause_cause_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_pause_cause_id_seq OWNED BY call_center.cc_pause_cause.id;


--
-- Name: cc_pause_cause_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_pause_cause_list AS
 SELECT s.id,
    s.created_at,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
    s.updated_at,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS updated_by,
    s.name,
    s.description,
    s.limit_min,
    s.allow_agent,
    s.allow_supervisor,
    s.allow_admin,
    s.domain_id
   FROM ((call_center.cc_pause_cause s
     LEFT JOIN directory.wbt_user uc ON ((uc.id = s.created_by)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = s.updated_by)));


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
-- Name: cc_queue_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL,
    object bigint NOT NULL
);


--
-- Name: cc_queue_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_queue_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_queue_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_queue_acl_id_seq OWNED BY call_center.cc_queue_acl.id;


--
-- Name: cc_queue_events; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue_events (
    id integer NOT NULL,
    schema_id integer NOT NULL,
    event character varying NOT NULL,
    properties character varying[],
    queue_id integer NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    updated_by integer,
    updated_at timestamp with time zone
);


--
-- Name: cc_queue_events_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_queue_events_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_queue_events_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_queue_events_id_seq OWNED BY call_center.cc_queue_events.id;


--
-- Name: cc_queue_events_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_queue_events_list AS
 SELECT qe.id,
    call_center.cc_get_lookup((qe.schema_id)::bigint, s.name) AS schema,
    qe.event,
    qe.enabled,
    qe.queue_id,
    qe.schema_id
   FROM (call_center.cc_queue_events qe
     LEFT JOIN flow.acr_routing_scheme s ON ((s.id = qe.schema_id)));


--
-- Name: cc_queue_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_queue_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_queue_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_queue_id_seq OWNED BY call_center.cc_queue.id;


--
-- Name: cc_queue_statistics; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue_statistics (
    queue_id bigint NOT NULL,
    member_count integer DEFAULT 0 NOT NULL,
    member_waiting integer DEFAULT 0 NOT NULL,
    bucket_id bigint
)
WITH (fillfactor='20', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


--
-- Name: cc_queue_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_queue_list AS
 SELECT q.id,
    q.strategy,
    q.enabled,
    q.payload,
    q.priority,
    q.updated_at,
    q.name,
    q.variables,
    q.domain_id,
    q.type,
    q.created_at,
    call_center.cc_get_lookup(uc.id, (uc.name)::character varying) AS created_by,
    call_center.cc_get_lookup(u.id, (u.name)::character varying) AS updated_by,
    call_center.cc_get_lookup((c.id)::bigint, c.name) AS calendar,
    call_center.cc_get_lookup(cl.id, cl.name) AS dnc_list,
    call_center.cc_get_lookup(ct.id, ct.name) AS team,
    call_center.cc_get_lookup((q.ringtone_id)::bigint, mf.name) AS ringtone,
    q.description,
    call_center.cc_get_lookup(s.id, s.name) AS schema,
    call_center.cc_get_lookup(ds.id, ds.name) AS do_schema,
    call_center.cc_get_lookup(afs.id, afs.name) AS after_schema,
    call_center.cc_get_lookup(fs.id, fs.name) AS form_schema,
    COALESCE(ss.member_count, (0)::bigint) AS count,
        CASE
            WHEN (q.type = ANY (ARRAY[1, 6])) THEN COALESCE(act.cnt_w, (0)::bigint)
            ELSE COALESCE(ss.member_waiting, (0)::bigint)
        END AS waiting,
    COALESCE(act.cnt, (0)::bigint) AS active,
    q.sticky_agent,
    q.processing,
    q.processing_sec,
    q.processing_renewal_sec,
    jsonb_build_object('enabled', q.processing, 'form_schema', call_center.cc_get_lookup(fs.id, fs.name), 'sec', q.processing_sec, 'renewal_sec', q.processing_renewal_sec) AS task_processing,
    call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
    q.team_id,
    q.tags
   FROM (((((((((((((call_center.cc_queue q
     LEFT JOIN flow.calendar c ON ((q.calendar_id = c.id)))
     LEFT JOIN directory.wbt_auth au ON ((au.id = q.grantee_id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = q.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = q.updated_by)))
     LEFT JOIN flow.acr_routing_scheme s ON ((q.schema_id = s.id)))
     LEFT JOIN flow.acr_routing_scheme ds ON ((q.do_schema_id = ds.id)))
     LEFT JOIN flow.acr_routing_scheme afs ON ((q.after_schema_id = afs.id)))
     LEFT JOIN flow.acr_routing_scheme fs ON ((q.form_schema_id = fs.id)))
     LEFT JOIN call_center.cc_list cl ON ((q.dnc_list_id = cl.id)))
     LEFT JOIN call_center.cc_team ct ON ((q.team_id = ct.id)))
     LEFT JOIN storage.media_files mf ON ((q.ringtone_id = mf.id)))
     LEFT JOIN LATERAL ( SELECT sum(s_1.member_waiting) AS member_waiting,
            sum(s_1.member_count) AS member_count
           FROM call_center.cc_queue_statistics s_1
          WHERE (s_1.queue_id = q.id)) ss ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt,
            count(*) FILTER (WHERE (a.agent_id IS NULL)) AS cnt_w
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL) AND ((a.state)::text <> 'leaving'::text))) act ON (true));


--
-- Name: cc_queue_report_general; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_queue_report_general AS
SELECT
    NULL::jsonb AS queue,
    NULL::jsonb AS team,
    NULL::bigint AS waiting,
    NULL::bigint AS processed,
    NULL::bigint AS cnt,
    NULL::bigint AS calls,
    NULL::bigint AS abandoned,
    NULL::double precision AS bill_sec,
    NULL::double precision AS avg_wrap_sec,
    NULL::double precision AS avg_awt_sec,
    NULL::double precision AS max_awt_sec,
    NULL::double precision AS avg_asa_sec,
    NULL::double precision AS avg_aht_sec,
    NULL::integer AS queue_id,
    NULL::bigint AS team_id;


--
-- Name: cc_queue_resource; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue_resource (
    id bigint NOT NULL,
    queue_id bigint NOT NULL,
    resource_group_id bigint NOT NULL
);


--
-- Name: cc_queue_resource_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_queue_resource_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_queue_resource_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_queue_resource_id_seq OWNED BY call_center.cc_outbound_resource.id;


--
-- Name: cc_queue_resource_id_seq1; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_queue_resource_id_seq1
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_queue_resource_id_seq1; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_queue_resource_id_seq1 OWNED BY call_center.cc_queue_resource.id;


--
-- Name: cc_queue_resource_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_queue_resource_view AS
 SELECT q.id,
    q.queue_id,
    call_center.cc_get_lookup(g.id, ((g.name)::text)::character varying) AS resource_group,
    call_center.cc_get_lookup((c.id)::bigint, ((c.name)::text)::character varying) AS communication,
    g.name AS resource_group_name,
    g.domain_id
   FROM ((call_center.cc_queue_resource q
     LEFT JOIN call_center.cc_outbound_resource_group g ON ((q.resource_group_id = g.id)))
     LEFT JOIN call_center.cc_communication c ON ((c.id = g.communication_id)));


--
-- Name: cc_queue_skill_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_queue_skill_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_queue_skill_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_queue_skill_id_seq OWNED BY call_center.cc_queue_skill.id;


--
-- Name: cc_queue_skill_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_queue_skill_list AS
 SELECT s.id,
    call_center.cc_get_lookup((cs.id)::bigint, cs.name) AS skill,
    ( SELECT jsonb_agg(call_center.cc_get_lookup(b.id, (b.name)::character varying)) AS jsonb_agg
           FROM call_center.cc_bucket b
          WHERE (b.id = ANY (s.bucket_ids))) AS buckets,
    s.lvl,
    s.min_capacity,
    s.max_capacity,
    s.enabled,
    s.bucket_ids,
    s.queue_id,
    s.skill_id,
    cq.domain_id
   FROM ((call_center.cc_queue_skill s
     JOIN call_center.cc_queue cq ON ((cq.id = s.queue_id)))
     JOIN call_center.cc_skill cs ON ((s.skill_id = cs.id)));


--
-- Name: cc_queue_skill_statistics; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue_skill_statistics (
    queue_id integer NOT NULL,
    skill_id integer NOT NULL,
    member_count integer DEFAULT 0 NOT NULL,
    member_waiting integer DEFAULT 0 NOT NULL
);


--
-- Name: cc_quick_reply; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_quick_reply (
    id bigint NOT NULL,
    name text NOT NULL,
    text text NOT NULL,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    created_by bigint NOT NULL,
    updated_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    updated_by bigint NOT NULL,
    article bigint,
    domain_id bigint NOT NULL,
    teams bigint[],
    queues integer[]
);


--
-- Name: cc_quick_reply_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_quick_reply_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_quick_reply_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_quick_reply_id_seq OWNED BY call_center.cc_quick_reply.id;


--
-- Name: cc_quick_reply_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_quick_reply_list AS
 SELECT a.domain_id,
    a.id,
    a.text,
    ( SELECT jsonb_agg(call_center.cc_get_lookup((q.id)::bigint, q.name)) AS jsonb_agg
           FROM call_center.cc_queue q
          WHERE (q.id = ANY (a.queues))) AS queues,
    a.queues AS queue_ids,
    a.teams AS team_ids,
    ( SELECT jsonb_agg(call_center.cc_get_lookup(t.id, t.name)) AS jsonb_agg
           FROM call_center.cc_team t
          WHERE (t.id = ANY (a.teams))) AS teams,
    a.name,
    a.created_at,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
    a.updated_at,
    call_center.cc_get_lookup(uu.id, (COALESCE(uu.name, (uu.username)::text))::character varying) AS updated_by
   FROM ((call_center.cc_quick_reply a
     LEFT JOIN directory.wbt_user uc ON ((uc.id = a.created_by)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = a.updated_by)));


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


--
-- Name: cc_skill_in_agent_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_skill_in_agent_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_skill_in_agent_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_skill_in_agent_id_seq OWNED BY call_center.cc_skill_in_agent.id;


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
    COALESCE(((uu.name)::character varying)::name, (uu.username COLLATE "default")) AS agent_name
   FROM ((((((call_center.cc_skill_in_agent sa
     LEFT JOIN call_center.cc_agent ca ON ((sa.agent_id = ca.id)))
     LEFT JOIN call_center.cc_team t ON ((t.id = ca.team_id)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = ca.user_id)))
     LEFT JOIN call_center.cc_skill cs ON ((sa.skill_id = cs.id)))
     LEFT JOIN directory.wbt_user c ON ((c.id = sa.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = sa.updated_by)));


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


--
-- Name: cc_skils_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_skils_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_skils_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_skils_id_seq OWNED BY call_center.cc_skill.id;


--
-- Name: cc_sys_queue_distribute_resources; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_sys_queue_distribute_resources AS
SELECT
    NULL::bigint AS queue_id,
    NULL::call_center.cc_sys_distribute_type[] AS types,
    NULL::call_center.cc_sys_distribute_resource[] AS resources,
    NULL::smallint[] AS ran;


--
-- Name: cc_team_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_team_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL,
    object bigint NOT NULL
);


--
-- Name: cc_team_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_team_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_team_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_team_acl_id_seq OWNED BY call_center.cc_team_acl.id;


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


--
-- Name: cc_team_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_team_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_team_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_team_id_seq OWNED BY call_center.cc_team.id;


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
    call_center.cc_get_lookup((fc.id)::bigint, (fc.name)::character varying) AS forecast_calculation,
    t.screen_control
   FROM (call_center.cc_team t
     LEFT JOIN wfm.forecast_calculation fc ON ((fc.id = t.forecast_calculation_id)));


--
-- Name: cc_team_trigger; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_team_trigger (
    id integer NOT NULL,
    team_id integer NOT NULL,
    name character varying NOT NULL,
    description character varying,
    enabled boolean DEFAULT false NOT NULL,
    schema_id integer NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by bigint
);


--
-- Name: cc_team_trigger_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_team_trigger_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_team_trigger_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_team_trigger_id_seq OWNED BY call_center.cc_team_trigger.id;


--
-- Name: cc_team_trigger_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_team_trigger_list AS
 SELECT qt.id,
    call_center.cc_get_lookup((qt.schema_id)::bigint, s.name) AS schema,
    qt.name,
    qt.description,
    qt.enabled,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
    qt.created_at,
    call_center.cc_get_lookup(uu.id, (COALESCE(uu.name, (uu.username)::text))::character varying) AS updated_by,
    qt.team_id,
    qt.schema_id
   FROM (((call_center.cc_team_trigger qt
     LEFT JOIN flow.acr_routing_scheme s ON ((s.id = qt.schema_id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = qt.created_by)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = qt.updated_by)));


--
-- Name: cc_trigger; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_trigger (
    id integer NOT NULL,
    domain_id bigint NOT NULL,
    name character varying NOT NULL,
    enabled boolean DEFAULT false NOT NULL,
    type character varying DEFAULT 'cron'::character varying NOT NULL,
    schema_id integer NOT NULL,
    variables jsonb,
    description text,
    expression character varying NOT NULL,
    timezone_id integer,
    created_by bigint,
    updated_by bigint,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    timeout_sec integer DEFAULT 0 NOT NULL,
    schedule_at timestamp without time zone DEFAULT (now())::timestamp without time zone,
    object text DEFAULT ''::text,
    event text DEFAULT ''::text
);


--
-- Name: cc_trigger_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_trigger_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint,
    subject bigint NOT NULL,
    access smallint DEFAULT 0 NOT NULL,
    object bigint NOT NULL
);


--
-- Name: cc_trigger_acl_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_trigger_acl_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_trigger_acl_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_trigger_acl_id_seq OWNED BY call_center.cc_trigger_acl.id;


--
-- Name: cc_trigger_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_trigger_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_trigger_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_trigger_id_seq OWNED BY call_center.cc_trigger.id;


--
-- Name: cc_trigger_job; Type: TABLE; Schema: call_center; Owner: -
--

CREATE UNLOGGED TABLE call_center.cc_trigger_job (
    id bigint NOT NULL,
    trigger_id integer NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    started_at timestamp with time zone,
    stopped_at timestamp with time zone,
    parameters jsonb,
    error text,
    result jsonb,
    node_id character varying,
    domain_id bigint
);


--
-- Name: cc_trigger_job_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_trigger_job_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_trigger_job_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_trigger_job_id_seq OWNED BY call_center.cc_trigger_job.id;


--
-- Name: cc_trigger_job_log; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_trigger_job_log (
    id bigint,
    trigger_id integer NOT NULL,
    state integer,
    created_at timestamp with time zone,
    started_at timestamp with time zone NOT NULL,
    stopped_at timestamp with time zone,
    parameters jsonb,
    error text,
    result jsonb,
    node_id character varying,
    domain_id bigint NOT NULL
);


--
-- Name: cc_trigger_job_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_trigger_job_list AS
 SELECT j.id,
    j.domain_id,
    call_center.cc_get_lookup((t.id)::bigint, t.name) AS trigger,
    j.state,
    j.created_at,
    j.started_at,
    j.stopped_at,
    j.parameters,
    j.error,
    j.result,
    j.trigger_id
   FROM (call_center.cc_trigger_job j
     LEFT JOIN call_center.cc_trigger t ON ((t.id = j.trigger_id)))
UNION ALL
 SELECT j.id,
    j.domain_id,
    call_center.cc_get_lookup((t.id)::bigint, t.name) AS trigger,
    j.state,
    j.created_at,
    j.started_at,
    j.stopped_at,
    j.parameters,
    j.error,
    j.result,
    j.trigger_id
   FROM (call_center.cc_trigger_job_log j
     LEFT JOIN call_center.cc_trigger t ON ((t.id = j.trigger_id)));


--
-- Name: cc_trigger_job_log_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_trigger_job_log_list AS
 SELECT j.id,
    j.domain_id,
    call_center.cc_get_lookup((t.id)::bigint, t.name) AS trigger,
    j.state,
    j.created_at,
    j.started_at,
    j.stopped_at,
    j.parameters,
    j.error,
    j.result
   FROM (call_center.cc_trigger_job_log j
     LEFT JOIN call_center.cc_trigger t ON ((t.id = j.trigger_id)));


--
-- Name: cc_trigger_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_trigger_list AS
 SELECT t.domain_id,
    t.schema_id,
    t.timezone_id,
    t.id,
    t.name,
    t.enabled,
    t.type,
    call_center.cc_get_lookup(s.id, s.name) AS schema,
    COALESCE(t.variables, '{}'::jsonb) AS variables,
    t.description,
    t.expression,
    call_center.cc_get_lookup((tz.id)::bigint, tz.name) AS timezone,
    t.timeout_sec AS timeout,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
    call_center.cc_get_lookup(uu.id, (COALESCE(uu.name, (uu.username)::text))::character varying) AS updated_by,
    t.created_at,
    t.updated_at,
    t.object,
    t.event
   FROM ((((call_center.cc_trigger t
     LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.schema_id)))
     LEFT JOIN flow.calendar_timezones tz ON ((tz.id = t.timezone_id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = t.created_by)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = t.updated_by)));


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
-- Name: socket_session; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.socket_session (
    id text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    user_agent text,
    user_id bigint,
    ip text,
    app_id text NOT NULL,
    domain_id bigint NOT NULL,
    ver text DEFAULT ''::text NOT NULL,
    application_name text DEFAULT ''::text NOT NULL
);


--
-- Name: socket_session_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.socket_session_view AS
 SELECT s.id,
    s.created_at,
    s.updated_at,
    (EXTRACT(epoch FROM (now() - s.created_at)))::bigint AS duration,
    (EXTRACT(epoch FROM (now() - s.updated_at)))::bigint AS pong,
    call_center.cc_get_lookup(wu.id, (COALESCE(wu.name, (wu.username)::text))::character varying) AS "user",
    s.user_agent,
    s.ip,
    s.application_name,
    s.ver,
    s.user_id,
    s.domain_id
   FROM (call_center.socket_session s
     LEFT JOIN directory.wbt_user wu ON ((s.user_id = wu.id)));


--
-- Name: systemc_settings_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.systemc_settings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: systemc_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.systemc_settings_id_seq OWNED BY call_center.system_settings.id;


--
-- Name: cc_agent id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_id_seq'::regclass);


--
-- Name: cc_agent_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_acl_id_seq'::regclass);


--
-- Name: cc_agent_state_history id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_state_history ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_history_id_seq'::regclass);


--
-- Name: cc_agent_status_log id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_status_log ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_status_log_id_seq'::regclass);


--
-- Name: cc_audit_form id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form ALTER COLUMN id SET DEFAULT nextval('call_center.cc_audit_form_id_seq'::regclass);


--
-- Name: cc_audit_form_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_form_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_audit_form_acl_id_seq'::regclass);


--
-- Name: cc_audit_rate id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate ALTER COLUMN id SET DEFAULT nextval('call_center.cc_audit_rate_id_seq'::regclass);


--
-- Name: cc_bucket id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket ALTER COLUMN id SET DEFAULT nextval('call_center.cc_bucket_id_seq'::regclass);


--
-- Name: cc_bucket_in_queue id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_in_queue ALTER COLUMN id SET DEFAULT nextval('call_center.cc_bucket_in_queue_id_seq'::regclass);


--
-- Name: cc_calls_annotation id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_annotation ALTER COLUMN id SET DEFAULT nextval('call_center.cc_call_annotation_id_seq'::regclass);


--
-- Name: cc_calls_transcribe id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_transcribe ALTER COLUMN id SET DEFAULT nextval('call_center.cc_calls_transcribe_id_seq'::regclass);


--
-- Name: cc_cluster id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_cluster ALTER COLUMN id SET DEFAULT nextval('call_center.cc_cluster_id_seq'::regclass);


--
-- Name: cc_communication id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_communication ALTER COLUMN id SET DEFAULT nextval('call_center.cc_communication_id_seq'::regclass);


--
-- Name: cc_email id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email ALTER COLUMN id SET DEFAULT nextval('call_center.cc_email_id_seq'::regclass);


--
-- Name: cc_email_profile id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email_profile ALTER COLUMN id SET DEFAULT nextval('call_center.cc_email_profiles_id_seq'::regclass);


--
-- Name: cc_list id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list ALTER COLUMN id SET DEFAULT nextval('call_center.cc_call_list_id_seq'::regclass);


--
-- Name: cc_list_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_list_acl_id_seq'::regclass);


--
-- Name: cc_list_communications id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_communications ALTER COLUMN id SET DEFAULT nextval('call_center.cc_list_communications_id_seq'::regclass);


--
-- Name: cc_member id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member ALTER COLUMN id SET DEFAULT nextval('call_center.cc_member_id_seq'::regclass);


--
-- Name: cc_member_attempt id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt ALTER COLUMN id SET DEFAULT nextval('call_center.cc_member_attempt_id_seq'::regclass);


--
-- Name: cc_member_attempt_transferred id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt_transferred ALTER COLUMN id SET DEFAULT nextval('call_center.cc_attempt_transferred_id_seq'::regclass);


--
-- Name: cc_member_messages id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_messages ALTER COLUMN id SET DEFAULT nextval('call_center.cc_member_messages_id_seq'::regclass);


--
-- Name: cc_notification id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_notification ALTER COLUMN id SET DEFAULT nextval('call_center.cc_notification_id_seq'::regclass);


--
-- Name: cc_outbound_resource id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_resource_id_seq'::regclass);


--
-- Name: cc_outbound_resource_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_outbound_resource_acl_id_seq'::regclass);


--
-- Name: cc_outbound_resource_display id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_display ALTER COLUMN id SET DEFAULT nextval('call_center.cc_outbound_resource_display_id_seq'::regclass);


--
-- Name: cc_outbound_resource_group id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group ALTER COLUMN id SET DEFAULT nextval('call_center.cc_outbound_resource_group_id_seq'::regclass);


--
-- Name: cc_outbound_resource_group_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_outbound_resource_group_acl_id_seq'::regclass);


--
-- Name: cc_outbound_resource_in_group id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_in_group ALTER COLUMN id SET DEFAULT nextval('call_center.cc_outbound_resource_in_group_id_seq'::regclass);


--
-- Name: cc_pause_cause id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause ALTER COLUMN id SET DEFAULT nextval('call_center.cc_pause_cause_id_seq'::regclass);


--
-- Name: cc_preset_query id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_preset_query ALTER COLUMN id SET DEFAULT nextval('call_center.cc_preset_query_id_seq'::regclass);


--
-- Name: cc_queue id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_id_seq'::regclass);


--
-- Name: cc_queue_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_acl_id_seq'::regclass);


--
-- Name: cc_queue_events id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_events ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_events_id_seq'::regclass);


--
-- Name: cc_queue_resource id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_resource ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_resource_id_seq1'::regclass);


--
-- Name: cc_queue_skill id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_skill ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_skill_id_seq'::regclass);


--
-- Name: cc_quick_reply id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_quick_reply ALTER COLUMN id SET DEFAULT nextval('call_center.cc_quick_reply_id_seq'::regclass);


--
-- Name: cc_skill id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill ALTER COLUMN id SET DEFAULT nextval('call_center.cc_skils_id_seq'::regclass);


--
-- Name: cc_skill_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_skill_acl_id_seq'::regclass);


--
-- Name: cc_skill_in_agent id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_in_agent ALTER COLUMN id SET DEFAULT nextval('call_center.cc_skill_in_agent_id_seq'::regclass);


--
-- Name: cc_team id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team ALTER COLUMN id SET DEFAULT nextval('call_center.cc_team_id_seq'::regclass);


--
-- Name: cc_team_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_team_acl_id_seq'::regclass);


--
-- Name: cc_team_events id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_events ALTER COLUMN id SET DEFAULT nextval('call_center.cc_team_events_id_seq'::regclass);


--
-- Name: cc_team_trigger id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_trigger ALTER COLUMN id SET DEFAULT nextval('call_center.cc_team_trigger_id_seq'::regclass);


--
-- Name: cc_trigger id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger ALTER COLUMN id SET DEFAULT nextval('call_center.cc_trigger_id_seq'::regclass);


--
-- Name: cc_trigger_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_trigger_acl_id_seq'::regclass);


--
-- Name: cc_trigger_job id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_job ALTER COLUMN id SET DEFAULT nextval('call_center.cc_trigger_job_id_seq'::regclass);


--
-- Name: system_settings id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.system_settings ALTER COLUMN id SET DEFAULT nextval('call_center.systemc_settings_id_seq'::regclass);


--
-- Name: cc_agent_acl cc_agent_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_pk PRIMARY KEY (id);


--
-- Name: cc_agent_channel cc_agent_channel_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_channel
    ADD CONSTRAINT cc_agent_channel_pk PRIMARY KEY (agent_id, channel);


--
-- Name: cc_agent cc_agent_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_pkey PRIMARY KEY (id);


--
-- Name: cc_agent_state_history cc_agent_status_history_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_state_history
    ADD CONSTRAINT cc_agent_status_history_pk PRIMARY KEY (id);


--
-- Name: cc_agent_status_log cc_agent_status_log_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_status_log
    ADD CONSTRAINT cc_agent_status_log_pk PRIMARY KEY (agent_id, joined_at);


--
-- Name: cc_pause_cause cc_agent_status_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause
    ADD CONSTRAINT cc_agent_status_pk PRIMARY KEY (id);


--
-- Name: cc_member_attempt_transferred cc_attempt_transferred_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt_transferred
    ADD CONSTRAINT cc_attempt_transferred_pk PRIMARY KEY (id);


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
-- Name: cc_audit_rate cc_audit_rate_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate
    ADD CONSTRAINT cc_audit_rate_pk PRIMARY KEY (id);


--
-- Name: cc_bucket_in_queue cc_bucket_in_queue_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_in_queue
    ADD CONSTRAINT cc_bucket_in_queue_pk PRIMARY KEY (id);


--
-- Name: cc_bucket cc_bucket_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket
    ADD CONSTRAINT cc_bucket_pk PRIMARY KEY (id);


--
-- Name: cc_calls_annotation cc_call_annotation_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_annotation
    ADD CONSTRAINT cc_call_annotation_pk PRIMARY KEY (id);


--
-- Name: cc_list cc_call_list_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list
    ADD CONSTRAINT cc_call_list_pk PRIMARY KEY (id);


--
-- Name: cc_calls_history cc_calls_history_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_history
    ADD CONSTRAINT cc_calls_history_pk PRIMARY KEY (id, domain_id);


--
-- Name: cc_calls cc_calls_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls
    ADD CONSTRAINT cc_calls_pk UNIQUE (id);


--
-- Name: cc_calls_transcribe cc_calls_transcribe_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_transcribe
    ADD CONSTRAINT cc_calls_transcribe_pk PRIMARY KEY (id);


--
-- Name: cc_cluster cc_cluster_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_cluster
    ADD CONSTRAINT cc_cluster_pkey PRIMARY KEY (id);


--
-- Name: cc_communication cc_communication_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_communication
    ADD CONSTRAINT cc_communication_pkey PRIMARY KEY (id);


--
-- Name: cc_email cc_email_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email
    ADD CONSTRAINT cc_email_pk PRIMARY KEY (id);


--
-- Name: cc_email_profile cc_email_profiles_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email_profile
    ADD CONSTRAINT cc_email_profiles_pk PRIMARY KEY (id);


--
-- Name: cc_list_acl cc_list_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_pk PRIMARY KEY (id);


--
-- Name: cc_list_communications cc_list_communications_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_communications
    ADD CONSTRAINT cc_list_communications_pk PRIMARY KEY (id);


--
-- Name: cc_list_statistics cc_list_statistics_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_statistics
    ADD CONSTRAINT cc_list_statistics_pk UNIQUE (list_id);


--
-- Name: cc_member_attempt_history cc_member_attempt_history_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt_history
    ADD CONSTRAINT cc_member_attempt_history_pk PRIMARY KEY (id);


--
-- Name: cc_member_attempt cc_member_attempt_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt
    ADD CONSTRAINT cc_member_attempt_pk PRIMARY KEY (id);


--
-- Name: cc_member_messages cc_member_messages_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_messages
    ADD CONSTRAINT cc_member_messages_pk PRIMARY KEY (id);


--
-- Name: cc_member cc_member_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_pkey PRIMARY KEY (id);


--
-- Name: cc_notification cc_notification_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_notification
    ADD CONSTRAINT cc_notification_pk PRIMARY KEY (id);


--
-- Name: cc_outbound_resource_acl cc_outbound_resource_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_acl
    ADD CONSTRAINT cc_outbound_resource_acl_pk PRIMARY KEY (id);


--
-- Name: cc_outbound_resource_display cc_outbound_resource_display_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_display
    ADD CONSTRAINT cc_outbound_resource_display_pk PRIMARY KEY (id);


--
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_pk PRIMARY KEY (id);


--
-- Name: cc_outbound_resource_group cc_outbound_resource_group_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group
    ADD CONSTRAINT cc_outbound_resource_group_pk PRIMARY KEY (id);


--
-- Name: cc_outbound_resource_in_group cc_outbound_resource_in_group_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_in_group
    ADD CONSTRAINT cc_outbound_resource_in_group_pk PRIMARY KEY (id);


--
-- Name: cc_preset_query cc_preset_query_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_preset_query
    ADD CONSTRAINT cc_preset_query_pk PRIMARY KEY (id);


--
-- Name: cc_preset_query cc_preset_query_user_id_section_name_uindex; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_preset_query
    ADD CONSTRAINT cc_preset_query_user_id_section_name_uindex UNIQUE (user_id, section, name);


--
-- Name: cc_queue_acl cc_queue_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl
    ADD CONSTRAINT cc_queue_acl_pk PRIMARY KEY (id);


--
-- Name: cc_queue_events cc_queue_events_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_events
    ADD CONSTRAINT cc_queue_events_pk PRIMARY KEY (id);


--
-- Name: cc_queue cc_queue_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_pkey PRIMARY KEY (id);


--
-- Name: cc_queue_resource cc_queue_resource_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_resource
    ADD CONSTRAINT cc_queue_resource_pk PRIMARY KEY (id);


--
-- Name: cc_outbound_resource cc_queue_resource_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource
    ADD CONSTRAINT cc_queue_resource_pkey PRIMARY KEY (id);


--
-- Name: cc_queue_skill cc_queue_skill_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_skill
    ADD CONSTRAINT cc_queue_skill_pk PRIMARY KEY (id);


--
-- Name: cc_queue_skill_statistics cc_queue_skill_statistics_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_skill_statistics
    ADD CONSTRAINT cc_queue_skill_statistics_pk PRIMARY KEY (queue_id, skill_id);


--
-- Name: cc_queue_statistics cc_queue_statistics_pk_queue_id_bucket_id_skill_id; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_statistics
    ADD CONSTRAINT cc_queue_statistics_pk_queue_id_bucket_id_skill_id UNIQUE (queue_id, bucket_id);


--
-- Name: cc_quick_reply cc_quick_reply_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_quick_reply
    ADD CONSTRAINT cc_quick_reply_pk PRIMARY KEY (id);


--
-- Name: cc_skill_acl cc_skill_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_acl
    ADD CONSTRAINT cc_skill_acl_pk PRIMARY KEY (id);


--
-- Name: cc_skill_in_agent cc_skill_in_agent_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_in_agent
    ADD CONSTRAINT cc_skill_in_agent_pkey PRIMARY KEY (id);


--
-- Name: cc_skill cc_skils_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill
    ADD CONSTRAINT cc_skils_pkey PRIMARY KEY (id);


--
-- Name: cc_team_acl cc_team_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl
    ADD CONSTRAINT cc_team_acl_pk PRIMARY KEY (id);


--
-- Name: cc_team_events cc_team_events_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_events
    ADD CONSTRAINT cc_team_events_pk PRIMARY KEY (id);


--
-- Name: cc_team cc_team_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_pk PRIMARY KEY (id);


--
-- Name: cc_team_trigger cc_team_trigger_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_trigger
    ADD CONSTRAINT cc_team_trigger_pkey PRIMARY KEY (id);


--
-- Name: cc_trigger_acl cc_trigger_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_pk PRIMARY KEY (id);


--
-- Name: cc_trigger_job cc_trigger_job_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_job
    ADD CONSTRAINT cc_trigger_job_pk PRIMARY KEY (id);


--
-- Name: cc_trigger cc_trigger_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger
    ADD CONSTRAINT cc_trigger_pk PRIMARY KEY (id);


--
-- Name: system_settings systemc_settings_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.system_settings
    ADD CONSTRAINT systemc_settings_pk PRIMARY KEY (id);


--
-- Name: cc_agent_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_acl_grantor_idx ON call_center.cc_agent_acl USING btree (grantor);


--
-- Name: cc_agent_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_acl_object_subject_udx ON call_center.cc_agent_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_agent_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_acl_subject_object_udx ON call_center.cc_agent_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_agent_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_created_by_index ON call_center.cc_agent USING btree (created_by);


--
-- Name: cc_agent_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_domain_id_index ON call_center.cc_agent USING btree (domain_id);


--
-- Name: cc_agent_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_domain_udx ON call_center.cc_agent USING btree (id, domain_id);


--
-- Name: cc_agent_state_history_dev_g; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_state_history_dev_g ON call_center.cc_agent_state_history USING btree (agent_id, joined_at DESC) INCLUDE (state, payload) WHERE ((channel IS NULL) AND ((state)::text = ANY (ARRAY[('pause'::character varying)::text, ('online'::character varying)::text, ('offline'::character varying)::text])));


--
-- Name: cc_agent_state_history_joined_at_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_state_history_joined_at_agent_id_index ON call_center.cc_agent_state_history USING btree (channel, joined_at DESC, agent_id, state DESC) INCLUDE (duration);


--
-- Name: cc_agent_state_history_joined_at_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_state_history_joined_at_idx ON call_center.cc_agent_state_history USING btree (joined_at DESC, agent_id DESC) INCLUDE (state, duration);

ALTER TABLE call_center.cc_agent_state_history CLUSTER ON cc_agent_state_history_joined_at_idx;


--
-- Name: cc_agent_status_distribute_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_status_distribute_index ON call_center.cc_agent USING btree (status) INCLUDE (user_id, id);


--
-- Name: cc_agent_status_log_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_status_log_agent_id_index ON call_center.cc_agent_status_log USING btree (agent_id);


--
-- Name: cc_agent_status_log_joined_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_status_log_joined_at_index ON call_center.cc_agent_status_log USING btree (joined_at DESC);


--
-- Name: cc_agent_today_pause_cause_agent_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_pause_cause_agent_uidx ON call_center.cc_agent_today_pause_cause USING btree (id, today, cause);


--
-- Name: cc_agent_today_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_uidx ON call_center.cc_agent_today_stats USING btree (agent_id);


--
-- Name: cc_agent_today_stats_usr_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_usr_uidx ON call_center.cc_agent_today_stats USING btree (user_id);


--
-- Name: cc_agent_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_updated_by_index ON call_center.cc_agent USING btree (updated_by);


--
-- Name: cc_agent_user_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_user_id_uindex ON call_center.cc_agent USING btree (user_id);


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
-- Name: cc_audit_rate_call_created_at; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_audit_rate_call_created_at ON call_center.cc_audit_rate USING btree (call_created_at);


--
-- Name: cc_audit_rate_call_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_audit_rate_call_id_uindex ON call_center.cc_audit_rate USING btree (call_id);


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
-- Name: cc_bucket_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_bucket_acl_grantor_idx ON call_center.cc_bucket_acl USING btree (grantor);


--
-- Name: cc_bucket_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_bucket_acl_object_subject_udx ON call_center.cc_bucket_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_bucket_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_bucket_acl_subject_object_udx ON call_center.cc_bucket_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_bucket_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_bucket_created_by_index ON call_center.cc_bucket USING btree (created_by);


--
-- Name: cc_bucket_domain_id_name_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_bucket_domain_id_name_index ON call_center.cc_bucket USING btree (domain_id, name);


--
-- Name: cc_bucket_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_bucket_domain_udx ON call_center.cc_bucket USING btree (id, domain_id);


--
-- Name: cc_bucket_in_queue_bucket_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_bucket_in_queue_bucket_id_index ON call_center.cc_bucket_in_queue USING btree (bucket_id);


--
-- Name: cc_bucket_in_queue_queue_id_bucket_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_bucket_in_queue_queue_id_bucket_id_uindex ON call_center.cc_bucket_in_queue USING btree (queue_id, bucket_id);


--
-- Name: cc_bucket_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_bucket_updated_by_index ON call_center.cc_bucket USING btree (updated_by);


--
-- Name: cc_calls_annotation_call_id_note_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_annotation_call_id_note_index ON call_center.cc_calls_annotation USING btree (call_id, note);


--
-- Name: cc_calls_history_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_agent_id_index ON call_center.cc_calls_history USING btree (agent_id);


--
-- Name: cc_calls_history_agent_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_agent_ids_index ON call_center.cc_calls_history USING gin (agent_ids gin__int_ops) WHERE (agent_ids IS NOT NULL);


--
-- Name: cc_calls_history_amd_result; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_amd_result ON call_center.cc_calls_history USING btree (amd_result) WHERE (amd_result IS NOT NULL);


--
-- Name: cc_calls_history_attempt_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_attempt_id_index ON call_center.cc_calls_history USING btree (attempt_id DESC NULLS LAST);


--
-- Name: cc_calls_history_contact_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_contact_id_index ON call_center.cc_calls_history USING btree (contact_id);


--
-- Name: cc_calls_history_destination_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_destination_idx ON call_center.cc_calls_history USING gin (domain_id, destination gin_trgm_ops);


--
-- Name: cc_calls_history_dev_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_dev_idx ON call_center.cc_calls_history USING btree (hangup_at DESC, parent_id);


--
-- Name: cc_calls_history_direction_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_direction_index ON call_center.cc_calls_history USING btree (direction);


--
-- Name: cc_calls_history_domain_id_created_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_domain_id_created_at_index ON call_center.cc_calls_history USING btree (domain_id, created_at DESC);

ALTER TABLE call_center.cc_calls_history CLUSTER ON cc_calls_history_domain_id_created_at_index;


--
-- Name: cc_calls_history_domain_id_store_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_domain_id_store_at_index ON call_center.cc_calls_history USING btree (domain_id, stored_at DESC);


--
-- Name: cc_calls_history_from_number_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_from_number_idx ON call_center.cc_calls_history USING gin (domain_id, from_number gin_trgm_ops);


--
-- Name: cc_calls_history_gateway_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_gateway_id_index ON call_center.cc_calls_history USING btree (gateway_id) WHERE (gateway_id IS NOT NULL);


--
-- Name: cc_calls_history_gateway_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_gateway_ids_index ON call_center.cc_calls_history USING gin (((gateway_ids)::integer[]) gin__int_ops) WHERE (gateway_ids IS NOT NULL);


--
-- Name: cc_calls_history_grantee_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_grantee_id_index ON call_center.cc_calls_history USING btree (grantee_id);


--
-- Name: cc_calls_history_mat_view_agent; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_mat_view_agent ON call_center.cc_calls_history USING btree (user_id, domain_id, created_at);


--
-- Name: cc_calls_history_member_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_member_id_index ON call_center.cc_calls_history USING btree (member_id);


--
-- Name: cc_calls_history_parent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_parent_id_index ON call_center.cc_calls_history USING btree (parent_id);


--
-- Name: cc_calls_history_payload_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_payload_idx ON call_center.cc_calls_history USING gin (domain_id, payload jsonb_path_ops) WHERE (payload IS NOT NULL);


--
-- Name: cc_calls_history_queue_id_dom; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_queue_id_dom ON call_center.cc_calls_history USING btree (domain_id, created_at, user_id, queue_id);


--
-- Name: cc_calls_history_queue_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_queue_id_index ON call_center.cc_calls_history USING btree (queue_id);


--
-- Name: cc_calls_history_queue_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_queue_ids_index ON call_center.cc_calls_history USING gin (queue_ids gin__int_ops) WHERE (queue_ids IS NOT NULL);


--
-- Name: cc_calls_history_sn_ops_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_sn_ops_idx ON call_center.cc_calls_history USING gin (COALESCE(search_number, call_center.cc_array_to_string((ARRAY[destination, from_number, to_number])::text[], '|'::text)) gin_trgm_ops);


--
-- Name: cc_calls_history_sn_ops_idx2; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_sn_ops_idx2 ON call_center.cc_calls_history USING gin (COALESCE(search_number, (((((destination)::text || '|'::text) || (from_number)::text) || '|'::text) || (to_number)::text)) gin_trgm_ops);


--
-- Name: cc_calls_history_team_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_team_id_index ON call_center.cc_calls_history USING btree (team_id);


--
-- Name: cc_calls_history_team_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_team_ids_index ON call_center.cc_calls_history USING gin (team_ids gin__int_ops) WHERE (team_ids IS NOT NULL);


--
-- Name: cc_calls_history_to_number_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_to_number_idx ON call_center.cc_calls_history USING gin (domain_id, to_number gin_trgm_ops);


--
-- Name: cc_calls_history_transfer_from_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_transfer_from_index ON call_center.cc_calls_history USING btree (transfer_from) WHERE (transfer_from IS NOT NULL);


--
-- Name: cc_calls_history_transfer_to_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_transfer_to_index ON call_center.cc_calls_history USING btree (transfer_to) WHERE (transfer_to IS NOT NULL);


--
-- Name: cc_calls_history_user_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_user_id_index ON call_center.cc_calls_history USING btree (user_id);


--
-- Name: cc_calls_history_user_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_user_ids_index ON call_center.cc_calls_history USING gin (((user_ids)::integer[]) gin__int_ops) WHERE (user_ids IS NOT NULL);


--
-- Name: cc_calls_history_user_ids_index3; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_user_ids_index3 ON call_center.cc_calls_history USING gin (created_at, ((user_ids)::integer[]));


--
-- Name: cc_calls_transcribe_call_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_transcribe_call_id_index ON call_center.cc_calls_transcribe USING btree (call_id);


--
-- Name: cc_calls_transcribe_created_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_transcribe_created_at_index ON call_center.cc_calls_transcribe USING btree (created_at DESC);


--
-- Name: cc_calls_transcribe_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_calls_transcribe_id_uindex ON call_center.cc_calls_transcribe USING btree (id);


--
-- Name: cc_cluster_node_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_cluster_node_name_uindex ON call_center.cc_cluster USING btree (node_name);


--
-- Name: cc_communication_domain_id_code_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_communication_domain_id_code_uindex ON call_center.cc_communication USING btree (domain_id, code);


--
-- Name: cc_communication_fkey; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_communication_fkey ON call_center.cc_communication USING btree (id, domain_id);


--
-- Name: cc_distribute_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_distribute_stats_uidx ON call_center.cc_distribute_stats USING btree (queue_id, bucket_id);


--
-- Name: cc_email_contact_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_contact_ids_index ON call_center.cc_email USING gin (contact_ids) WHERE (contact_ids IS NOT NULL);


--
-- Name: cc_email_in_reply_to_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_in_reply_to_index ON call_center.cc_email USING btree (in_reply_to) WHERE (in_reply_to IS NOT NULL);


--
-- Name: cc_email_message_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_message_id_index ON call_center.cc_email USING btree (message_id);


--
-- Name: cc_email_owner_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_owner_id_index ON call_center.cc_email USING btree (owner_id);


--
-- Name: cc_email_profile_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_profile_domain_id_index ON call_center.cc_email_profile USING btree (domain_id);


--
-- Name: cc_inbound_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_inbound_stats_uidx ON call_center.cc_inbound_stats USING btree (queue_id, bucket_id);


--
-- Name: cc_list_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_list_acl_grantor_idx ON call_center.cc_list_acl USING btree (grantor);


--
-- Name: cc_list_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_list_acl_object_subject_udx ON call_center.cc_list_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_list_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_list_acl_subject_object_udx ON call_center.cc_list_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_list_communications_expire_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_list_communications_expire_at_index ON call_center.cc_list_communications USING btree (expire_at) WHERE (expire_at IS NOT NULL);


--
-- Name: cc_list_communications_list_id_number_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_list_communications_list_id_number_uindex ON call_center.cc_list_communications USING btree (list_id, number);


--
-- Name: cc_list_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_list_created_by_index ON call_center.cc_list USING btree (created_by);


--
-- Name: cc_list_domain_id_name_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_list_domain_id_name_index ON call_center.cc_list USING btree (domain_id, name);


--
-- Name: cc_list_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_list_domain_udx ON call_center.cc_list USING btree (id, domain_id);


--
-- Name: cc_list_statistics_list_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_list_statistics_list_id_uindex ON call_center.cc_list_statistics USING btree (list_id);


--
-- Name: cc_list_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_list_updated_by_index ON call_center.cc_list USING btree (updated_by);


--
-- Name: cc_member_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_agent_id_index ON call_center.cc_member USING btree (agent_id);


--
-- Name: cc_member_appointments_queue_id_ready; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_appointments_queue_id_ready ON call_center.cc_member USING btree (queue_id, COALESCE(ready_at, created_at)) WHERE (stop_at IS NULL);


--
-- Name: cc_member_attempt_history_agent_call_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_agent_call_id_index ON call_center.cc_member_attempt_history USING btree (agent_call_id);


--
-- Name: cc_member_attempt_history_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_agent_id_index ON call_center.cc_member_attempt_history USING btree (agent_id);


--
-- Name: cc_member_attempt_history_descript_s; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_descript_s ON call_center.cc_member_attempt_history USING btree (id, description) WHERE (description IS NOT NULL);


--
-- Name: cc_member_attempt_history_domain_id_joined_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_domain_id_joined_at_index ON call_center.cc_member_attempt_history USING btree (domain_id, joined_at DESC);


--
-- Name: cc_member_attempt_history_domain_id_queue_id_joined_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_domain_id_queue_id_joined_at_index ON call_center.cc_member_attempt_history USING btree (domain_id, queue_id, joined_at DESC);


--
-- Name: cc_member_attempt_history_joined_at_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_joined_at_agent_id_index ON call_center.cc_member_attempt_history USING btree (joined_at DESC, agent_id);


--
-- Name: cc_member_attempt_history_mat_view_agent; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_mat_view_agent ON call_center.cc_member_attempt_history USING btree (agent_id, domain_id, joined_at, channel);


--
-- Name: cc_member_attempt_history_mat_view_agent2; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_mat_view_agent2 ON call_center.cc_member_attempt_history USING btree (agent_id, domain_id, leaving_at) INCLUDE (reporting_at, bridged_at, leaving_at, channel) WHERE (((channel)::text = ANY (ARRAY['chat'::text, 'task'::text])) AND (bridged_at IS NOT NULL));


--
-- Name: cc_member_attempt_history_member_call_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_member_call_id_index ON call_center.cc_member_attempt_history USING btree (member_call_id);


--
-- Name: cc_member_attempt_history_member_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_member_id_index ON call_center.cc_member_attempt_history USING btree (member_id);


--
-- Name: cc_member_attempt_history_member_id_index_drop; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_member_id_index_drop ON call_center.cc_member_attempt_history USING btree (member_id) WHERE (member_id IS NOT NULL);


--
-- Name: cc_member_attempt_history_offered_agent_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_offered_agent_ids_index ON call_center.cc_member_attempt_history USING gin (offered_agent_ids gin__int_ops) WHERE (offered_agent_ids IS NOT NULL);


--
-- Name: cc_member_attempt_history_parent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_parent_id_index ON call_center.cc_member_attempt_history USING btree (parent_id) WHERE (parent_id IS NOT NULL);


--
-- Name: cc_member_attempt_history_queue_id_leaving_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_queue_id_leaving_at_index ON call_center.cc_member_attempt_history USING btree (queue_id, leaving_at DESC);


--
-- Name: cc_member_attempt_member_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_member_id_index ON call_center.cc_member_attempt USING btree (member_id);


--
-- Name: cc_member_attempt_queue_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_queue_id_index ON call_center.cc_member_attempt USING btree (queue_id);


--
-- Name: cc_member_dis_fifo; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_dis_fifo ON call_center.cc_member USING btree (queue_id, bucket_id, skill_id, agent_id, priority DESC, ready_at, id) INCLUDE (sys_offset_id, sys_destinations, expire_at, search_destinations) WHERE (stop_at IS NULL);


--
-- Name: cc_member_dis_fifo_desc; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_dis_fifo_desc ON call_center.cc_member USING btree (queue_id, bucket_id, skill_id, agent_id, priority DESC, ready_at DESC NULLS LAST, id) INCLUDE (sys_offset_id, sys_destinations, expire_at, search_destinations) WHERE (stop_at IS NULL);


--
-- Name: cc_member_dis_lifo; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_dis_lifo ON call_center.cc_member USING btree (queue_id, bucket_id, skill_id, agent_id, priority DESC, ready_at, id DESC) INCLUDE (sys_offset_id, sys_destinations, expire_at, search_destinations) WHERE (stop_at IS NULL);


--
-- Name: cc_member_dis_lifo_desc; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_dis_lifo_desc ON call_center.cc_member USING btree (queue_id, bucket_id, skill_id, agent_id, priority DESC, ready_at DESC NULLS LAST, id DESC) INCLUDE (sys_offset_id, sys_destinations, expire_at, search_destinations) WHERE (stop_at IS NULL);


--
-- Name: cc_member_dis_strict_fifo_asc; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_dis_strict_fifo_asc ON call_center.cc_member USING btree (queue_id, bucket_id, skill_id, agent_id, attempts, priority DESC, ready_at, id) INCLUDE (sys_offset_id, sys_destinations, expire_at, search_destinations) WHERE (stop_at IS NULL);


--
-- Name: cc_member_dis_strict_fifo_asc2; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_dis_strict_fifo_asc2 ON call_center.cc_member USING btree (queue_id, attempts, priority DESC, ready_at DESC, id) INCLUDE (sys_offset_id, sys_destinations, search_destinations) WHERE ((stop_at IS NULL) AND (bucket_id IS NULL) AND (skill_id IS NULL) AND (agent_id IS NULL));


--
-- Name: cc_member_distribute_check_sys_offset_id; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_distribute_check_sys_offset_id ON call_center.cc_member USING btree (queue_id, bucket_id, sys_offset_id);


--
-- Name: cc_member_domain_id_search_destinations_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_domain_id_search_destinations_index ON call_center.cc_member USING gin (domain_id, search_destinations);


--
-- Name: cc_member_expire; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_expire ON call_center.cc_member USING btree (expire_at) WHERE ((expire_at IS NOT NULL) AND (stop_at IS NULL));


--
-- Name: cc_member_messages_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_member_messages_id_uindex ON call_center.cc_member_messages USING btree (id);


--
-- Name: cc_member_queue_id_created_at; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_queue_id_created_at ON call_center.cc_member USING btree (queue_id, created_at DESC);


--
-- Name: cc_member_queue_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_queue_id_index ON call_center.cc_member USING btree (queue_id);


--
-- Name: cc_member_reset_by_queue; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_reset_by_queue ON call_center.cc_member USING btree (domain_id, queue_id) INCLUDE (id) WHERE ((stop_at IS NOT NULL) AND ((stop_cause)::text <> ALL ('{success,expired,cancel,terminate,no_communications}'::text[])));


--
-- Name: cc_member_search_destination_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_search_destination_idx ON call_center.cc_member USING gin (domain_id, communications jsonb_path_ops);


--
-- Name: cc_member_variable_message_id; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_variable_message_id ON call_center.cc_member USING btree (((variables ->> 'message_id'::text))) WHERE ((variables ->> 'message_id'::text) IS NOT NULL);


--
-- Name: cc_member_variables_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_variables_idx ON call_center.cc_member USING gin (variables jsonb_path_ops);


--
-- Name: cc_outbound_resource_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_acl_grantor_idx ON call_center.cc_outbound_resource_acl USING btree (grantor);


--
-- Name: cc_outbound_resource_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_acl_object_subject_udx ON call_center.cc_outbound_resource_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_outbound_resource_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_acl_subject_object_udx ON call_center.cc_outbound_resource_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_outbound_resource_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_created_by_index ON call_center.cc_outbound_resource USING btree (created_by);


--
-- Name: cc_outbound_resource_display_resource_id_display_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_display_resource_id_display_uindex ON call_center.cc_outbound_resource_display USING btree (resource_id, display);


--
-- Name: cc_outbound_resource_display_resource_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_display_resource_id_index ON call_center.cc_outbound_resource_display USING btree (resource_id);


--
-- Name: cc_outbound_resource_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_domain_id_index ON call_center.cc_outbound_resource USING btree (domain_id);


--
-- Name: cc_outbound_resource_domain_id_name_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_domain_id_name_index ON call_center.cc_outbound_resource USING btree (domain_id, name);


--
-- Name: cc_outbound_resource_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_domain_udx ON call_center.cc_outbound_resource USING btree (id, domain_id);


--
-- Name: cc_outbound_resource_gateway_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_gateway_id_index ON call_center.cc_outbound_resource USING btree (gateway_id);


--
-- Name: cc_outbound_resource_group_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_group_acl_grantor_idx ON call_center.cc_outbound_resource_group_acl USING btree (grantor);


--
-- Name: cc_outbound_resource_group_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_group_acl_object_subject_udx ON call_center.cc_outbound_resource_group_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_outbound_resource_group_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_group_acl_subject_object_udx ON call_center.cc_outbound_resource_group_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_outbound_resource_group_communication_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_group_communication_id_index ON call_center.cc_outbound_resource_group USING btree (communication_id);


--
-- Name: cc_outbound_resource_group_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_group_created_by_index ON call_center.cc_outbound_resource_group USING btree (created_by);


--
-- Name: cc_outbound_resource_group_distr_res_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_group_distr_res_idx ON call_center.cc_outbound_resource_group USING btree (id, domain_id) INCLUDE (name);


--
-- Name: cc_outbound_resource_group_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_group_domain_id_index ON call_center.cc_outbound_resource_group USING btree (domain_id);


--
-- Name: cc_outbound_resource_group_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_group_domain_id_name_uindex ON call_center.cc_outbound_resource_group USING btree (domain_id, name);


--
-- Name: cc_outbound_resource_group_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_group_domain_udx ON call_center.cc_outbound_resource_group USING btree (id, domain_id);


--
-- Name: cc_outbound_resource_group_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_group_updated_by_index ON call_center.cc_outbound_resource_group USING btree (updated_by);


--
-- Name: cc_outbound_resource_in_group_group_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_in_group_group_id_index ON call_center.cc_outbound_resource_in_group USING btree (group_id);


--
-- Name: cc_outbound_resource_in_group_reserve_resource_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_in_group_reserve_resource_id_index ON call_center.cc_outbound_resource_in_group USING btree (reserve_resource_id);


--
-- Name: cc_outbound_resource_in_group_resource_id_group_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_in_group_resource_id_group_id_uindex ON call_center.cc_outbound_resource_in_group USING btree (resource_id, group_id);


--
-- Name: cc_outbound_resource_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_updated_by_index ON call_center.cc_outbound_resource USING btree (updated_by);


--
-- Name: cc_pause_cause_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_pause_cause_domain_id_name_uindex ON call_center.cc_pause_cause USING btree (domain_id, name);


--
-- Name: cc_pause_cause_domain_id_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_pause_cause_domain_id_udx ON call_center.cc_pause_cause USING btree (id, domain_id);


--
-- Name: cc_queue_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_acl_grantor_idx ON call_center.cc_queue_acl USING btree (grantor);


--
-- Name: cc_queue_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_acl_object_subject_udx ON call_center.cc_queue_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_queue_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_acl_subject_object_udx ON call_center.cc_queue_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_queue_distribute_res_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_distribute_res_idx ON call_center.cc_queue USING btree (domain_id, priority DESC) INCLUDE (id, name, calendar_id, type) WHERE (enabled IS TRUE);


--
-- Name: cc_queue_domain_id_name_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_domain_id_name_index ON call_center.cc_queue USING btree (domain_id, name);


--
-- Name: cc_queue_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_domain_udx ON call_center.cc_queue USING btree (id, domain_id);


--
-- Name: cc_queue_enabled_priority_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_enabled_priority_index ON call_center.cc_queue USING btree (enabled, priority DESC);


--
-- Name: cc_queue_events_queue_id_event_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_events_queue_id_event_uindex ON call_center.cc_queue_events USING btree (queue_id, event) WHERE enabled;


--
-- Name: cc_queue_events_queue_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_events_queue_id_index ON call_center.cc_queue_events USING btree (queue_id);


--
-- Name: cc_queue_events_schema_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_events_schema_id_index ON call_center.cc_queue_events USING btree (schema_id);


--
-- Name: cc_queue_resource_queue_id_resource_group_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_resource_queue_id_resource_group_id_uindex ON call_center.cc_queue_resource USING btree (queue_id, resource_group_id);


--
-- Name: cc_queue_resource_resource_group_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_resource_resource_group_id_index ON call_center.cc_queue_resource USING btree (resource_group_id);


--
-- Name: cc_queue_skill_lvl_queue_id_skill_id_bucket_ids_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_skill_lvl_queue_id_skill_id_bucket_ids_uindex ON call_center.cc_queue_skill USING btree (lvl, queue_id, skill_id, bucket_ids);


--
-- Name: cc_queue_skill_queue_id_skill_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_skill_queue_id_skill_id_index ON call_center.cc_queue_skill USING btree (queue_id) INCLUDE (skill_id, min_capacity, max_capacity) WHERE enabled;


--
-- Name: cc_queue_skill_skill_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_skill_skill_id_index ON call_center.cc_queue_skill USING btree (skill_id);


--
-- Name: cc_queue_statistics_queue_id_bucket_id_skill_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_statistics_queue_id_bucket_id_skill_id_uindex ON call_center.cc_queue_statistics USING btree (queue_id, COALESCE(bucket_id, (0)::bigint));


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
-- Name: cc_skill_domain_id_name_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_domain_id_name_index ON call_center.cc_skill USING btree (domain_id, name);


--
-- Name: cc_skill_domain_id_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_skill_domain_id_udx ON call_center.cc_skill USING btree (id, domain_id);


--
-- Name: cc_skill_in_agent_agent_id_capacity_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_in_agent_agent_id_capacity_index ON call_center.cc_skill_in_agent USING btree (agent_id, capacity);


--
-- Name: cc_skill_in_agent_agent_id_skill_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_skill_in_agent_agent_id_skill_id_uindex ON call_center.cc_skill_in_agent USING btree (agent_id, skill_id);


--
-- Name: cc_skill_in_agent_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_in_agent_created_by_index ON call_center.cc_skill_in_agent USING btree (created_by);


--
-- Name: cc_skill_in_agent_skill_id_agent_id_capacity_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_skill_in_agent_skill_id_agent_id_capacity_uindex ON call_center.cc_skill_in_agent USING btree (skill_id, capacity DESC, agent_id);


--
-- Name: cc_skill_in_agent_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_in_agent_updated_by_index ON call_center.cc_skill_in_agent USING btree (updated_by);


--
-- Name: cc_skill_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_updated_by_index ON call_center.cc_skill USING btree (updated_by);


--
-- Name: cc_stat_agent_awt_dev; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_stat_agent_awt_dev ON call_center.cc_member_attempt_history USING btree (leaving_at DESC, agent_id, queue_id, bucket_id) INCLUDE (bridged_at, joined_at, reporting_at) WHERE ((agent_id IS NOT NULL) AND (bridged_at IS NOT NULL));


--
-- Name: cc_team_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_acl_grantor_idx ON call_center.cc_team_acl USING btree (grantor);


--
-- Name: cc_team_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_acl_object_subject_udx ON call_center.cc_team_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_team_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_acl_subject_object_udx ON call_center.cc_team_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_team_admin_ids_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_admin_ids_index ON call_center.cc_team USING gin (admin_ids gin__int_ops);


--
-- Name: cc_team_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_created_by_index ON call_center.cc_team USING btree (created_by);


--
-- Name: cc_team_domain_id_name_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_domain_id_name_index ON call_center.cc_team USING btree (domain_id, name);


--
-- Name: cc_team_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_domain_udx ON call_center.cc_team USING btree (id, domain_id);


--
-- Name: cc_team_events_team_id_schema_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_events_team_id_schema_id_uindex ON call_center.cc_team_events USING btree (team_id, schema_id);


--
-- Name: cc_team_trigger_schema_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_trigger_schema_id_index ON call_center.cc_team_trigger USING btree (schema_id);


--
-- Name: cc_team_trigger_team_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_trigger_team_id_name_uindex ON call_center.cc_team_trigger USING btree (team_id, name);


--
-- Name: cc_team_trigger_team_id_schema_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_trigger_team_id_schema_id_uindex ON call_center.cc_team_trigger USING btree (team_id, schema_id);


--
-- Name: cc_team_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_updated_by_index ON call_center.cc_team USING btree (updated_by);


--
-- Name: cc_trigger_acl_grantor_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_trigger_acl_grantor_idx ON call_center.cc_trigger_acl USING btree (grantor);


--
-- Name: cc_trigger_acl_object_subject_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_trigger_acl_object_subject_udx ON call_center.cc_trigger_acl USING btree (object, subject) INCLUDE (access);


--
-- Name: cc_trigger_acl_subject_object_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_trigger_acl_subject_object_udx ON call_center.cc_trigger_acl USING btree (subject, object) INCLUDE (access);


--
-- Name: cc_trigger_id_domain_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_trigger_id_domain_id_uindex ON call_center.cc_trigger USING btree (id, domain_id);


--
-- Name: cc_trigger_job_log_trigger_id_started_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_trigger_job_log_trigger_id_started_at_index ON call_center.cc_trigger_job_log USING btree (trigger_id, started_at DESC);


--
-- Name: socket_session_app_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX socket_session_app_id_index ON call_center.socket_session USING btree (app_id);


--
-- Name: socket_session_user_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX socket_session_user_id_index ON call_center.socket_session USING btree (user_id);


--
-- Name: system_settings_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX system_settings_domain_id_name_uindex ON call_center.system_settings USING btree (domain_id, name) INCLUDE (value);


--
-- Name: cc_calls_history_domain_created_user_ids_st; Type: STATISTICS; Schema: call_center; Owner: -
--

CREATE STATISTICS call_center.cc_calls_history_domain_created_user_ids_st ON domain_id, created_at, user_ids FROM call_center.cc_calls_history;


--
-- Name: cc_calls_history_user_id_st; Type: STATISTICS; Schema: call_center; Owner: -
--

CREATE STATISTICS call_center.cc_calls_history_user_id_st ON domain_id, user_id, created_at FROM call_center.cc_calls_history;


--
-- Name: cc_calls_history_user_ids_st; Type: STATISTICS; Schema: call_center; Owner: -
--

CREATE STATISTICS call_center.cc_calls_history_user_ids_st ON domain_id, user_ids FROM call_center.cc_calls_history;


--
-- Name: cc_agent_in_queue_view _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_agent_in_queue_view AS
 SELECT q.queue,
    q.priority,
    q.type,
    q.strategy,
    q.enabled,
    q.count_members,
    q.waiting_members,
    q.active_members,
    q.queue_id,
    q.queue_name,
    q.team_id,
    q.domain_id,
    q.agent_id,
    jsonb_build_object('online', COALESCE(array_length(a.agent_on_ids, 1), 0), 'pause', COALESCE(array_length(a.agent_p_ids, 1), 0), 'offline', COALESCE(array_length(a.agent_off_ids, 1), 0), 'free', COALESCE(array_length(a.free, 1), 0), 'total', COALESCE(array_length(a.total, 1), 0), 'allow_pause',
        CASE
            WHEN (q.min_online_agents > 0) THEN GREATEST(((COALESCE(array_length(a.agent_p_ids, 1), 0) + COALESCE(array_length(a.agent_on_ids, 1), 0)) - q.min_online_agents), 0)
            ELSE NULL::integer
        END) AS agents,
    q.max_member_limit
   FROM (( SELECT call_center.cc_get_lookup((q_1.id)::bigint, q_1.name) AS queue,
            q_1.priority,
            q_1.type,
            q_1.strategy,
            q_1.enabled,
            COALESCE(((q_1.payload -> 'min_online_agents'::text))::integer, 0) AS min_online_agents,
            COALESCE(((q_1.payload -> 'max_member_limit'::text))::integer, 0) AS max_member_limit,
            COALESCE(sum(cqs.member_count), (0)::bigint) AS count_members,
                CASE
                    WHEN (q_1.type = ANY (ARRAY[1, 6])) THEN ( SELECT count(*) AS count
                       FROM call_center.cc_member_attempt a_1_1
                      WHERE ((a_1_1.queue_id = q_1.id) AND ((a_1_1.state)::text = ANY (ARRAY[('wait_agent'::character varying)::text, ('offering'::character varying)::text])) AND (a_1_1.leaving_at IS NULL)))
                    ELSE COALESCE(sum(cqs.member_waiting), (0)::bigint)
                END AS waiting_members,
            ( SELECT count(*) AS count
                   FROM call_center.cc_member_attempt a_1_1
                  WHERE (a_1_1.queue_id = q_1.id)) AS active_members,
            q_1.id AS queue_id,
            q_1.name AS queue_name,
            q_1.team_id,
            a_1.domain_id,
            a_1.id AS agent_id,
                CASE
                    WHEN ((q_1.type >= 0) AND (q_1.type <= 5)) THEN 'call'::text
                    WHEN (q_1.type = 6) THEN 'chat'::text
                    ELSE 'task'::text
                END AS chan_name
           FROM ((call_center.cc_agent a_1
             JOIN call_center.cc_queue q_1 ON ((q_1.domain_id = a_1.domain_id)))
             LEFT JOIN call_center.cc_queue_statistics cqs ON ((q_1.id = cqs.queue_id)))
          WHERE (((q_1.team_id IS NULL) OR (a_1.team_id = q_1.team_id)) AND (EXISTS ( SELECT qs.queue_id
                   FROM (call_center.cc_queue_skill qs
                     JOIN call_center.cc_skill_in_agent csia ON ((csia.skill_id = qs.skill_id)))
                  WHERE (qs.enabled AND csia.enabled AND (csia.agent_id = a_1.id) AND (qs.queue_id = q_1.id) AND (csia.capacity >= qs.min_capacity) AND (csia.capacity <= qs.max_capacity)))))
          GROUP BY a_1.id, q_1.id, q_1.priority) q
     LEFT JOIN LATERAL ( SELECT DISTINCT array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = 'online'::text)) AS agent_on_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = 'offline'::text)) AS agent_off_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = ANY (ARRAY[('pause'::character varying)::text, ('break_out'::character varying)::text]))) AS agent_p_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND ((ac.state)::text = 'waiting'::text))) AS free,
            array_agg(DISTINCT a_1.id) AS total
           FROM (((call_center.cc_agent a_1
             JOIN call_center.cc_agent_channel ac ON (((ac.agent_id = a_1.id) AND ((ac.channel)::text = q.chan_name))))
             JOIN call_center.cc_queue_skill qs ON (((qs.queue_id = q.queue_id) AND qs.enabled)))
             JOIN call_center.cc_skill_in_agent sia ON (((sia.agent_id = a_1.id) AND sia.enabled)))
          WHERE ((a_1.domain_id = q.domain_id) AND ((q.team_id IS NULL) OR (a_1.team_id = q.team_id)) AND (qs.skill_id = sia.skill_id) AND (sia.capacity >= qs.min_capacity) AND (sia.capacity <= qs.max_capacity))
          GROUP BY ROLLUP(q.queue_id)) a ON (true));


--
-- Name: cc_distribute_stage_1 _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_distribute_stage_1 AS
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
            COALESCE((q_1.payload ->> 'resource_strategy'::text), ''::text) AS rs,
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
            queues.rs,
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
          GROUP BY c.id, queues.id, queues.rs, queues.recall_calendar, tz.offset_id
        ), resources AS MATERIALIZED (
         SELECT l_1.queue_id,
            array_agg(ROW(cor.communication_id, (cor.id)::bigint, ((l_1.l & (l2.x)::integer[]))::smallint[], (cor.resource_group_id)::integer)::call_center.cc_sys_distribute_type ORDER BY
                CASE
                    WHEN (l_1.rs = 'priority-based'::text) THEN cor.priority
                    ELSE NULL::integer
                END, (random())) AS types,
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
-- Name: cc_sys_queue_distribute_resources _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_sys_queue_distribute_resources AS
 WITH res AS (
         SELECT cqr.queue_id,
            corg.communication_id,
            cor.id,
            cor."limit",
            call_center.cc_outbound_resource_timing(corg."time") AS t,
            cor.patterns
           FROM (((call_center.cc_queue_resource cqr
             JOIN call_center.cc_outbound_resource_group corg ON ((cqr.resource_group_id = corg.id)))
             JOIN call_center.cc_outbound_resource_in_group corig ON ((corg.id = corig.group_id)))
             JOIN call_center.cc_outbound_resource cor ON ((corig.resource_id = cor.id)))
          WHERE (cor.enabled AND (NOT cor.reserve))
          GROUP BY cqr.queue_id, corg.communication_id, corg."time", cor.id, cor."limit"
        )
 SELECT res.queue_id,
    array_agg(DISTINCT ROW(res.communication_id, (res.id)::bigint, res.t, 0)::call_center.cc_sys_distribute_type) AS types,
    array_agg(DISTINCT ROW((res.id)::bigint, ((res."limit" - ac.count))::integer, res.patterns)::call_center.cc_sys_distribute_resource) AS resources,
    array_agg(DISTINCT f.f) AS ran
   FROM res,
    (LATERAL ( SELECT count(*) AS count
           FROM call_center.cc_member_attempt a
          WHERE (a.resource_id = res.id)) ac
     JOIN LATERAL ( SELECT f_1.f
           FROM unnest(res.t) f_1(f)) f ON (true))
  WHERE ((res."limit" - ac.count) > 0)
  GROUP BY res.queue_id;


--
-- Name: cc_agent cc_agent_changed_sc_tg_ui; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_agent_changed_sc_tg_ui BEFORE INSERT OR UPDATE ON call_center.cc_agent FOR EACH ROW EXECUTE FUNCTION call_center.cc_agent_screen_control_tg();


--
-- Name: cc_agent cc_agent_init_channel_ins; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_agent_init_channel_ins AFTER INSERT ON call_center.cc_agent FOR EACH ROW EXECUTE FUNCTION call_center.cc_agent_init_channel();


--
-- Name: cc_agent cc_agent_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_agent_set_rbac_acl AFTER INSERT ON call_center.cc_agent FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_agent');


--
-- Name: cc_audit_form cc_audit_form_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_audit_form_set_rbac_acl AFTER INSERT ON call_center.cc_audit_form FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_audit_form_acl');


--
-- Name: cc_calls cc_calls_set_timing_trigger_updated; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_calls_set_timing_trigger_updated BEFORE INSERT OR UPDATE ON call_center.cc_calls FOR EACH ROW EXECUTE FUNCTION call_center.cc_calls_set_timing();


--
-- Name: cc_communication cc_communication_set_def_tg; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_communication_set_def_tg BEFORE INSERT OR UPDATE ON call_center.cc_communication FOR EACH ROW WHEN (new."default") EXECUTE FUNCTION call_center.cc_communication_set_def();


--
-- Name: cc_list cc_list_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_list_set_rbac_acl AFTER INSERT ON call_center.cc_list FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_list');


--
-- Name: cc_member cc_member_set_sys_destinations_insert; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_set_sys_destinations_insert BEFORE INSERT ON call_center.cc_member FOR EACH ROW EXECUTE FUNCTION call_center.cc_member_set_sys_destinations_tg();


--
-- Name: cc_member cc_member_set_sys_destinations_update; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_set_sys_destinations_update BEFORE UPDATE ON call_center.cc_member FOR EACH ROW WHEN ((new.communications <> old.communications)) EXECUTE FUNCTION call_center.cc_member_set_sys_destinations_tg();


--
-- Name: cc_member cc_member_statistic_skill_trigger_deleted; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_statistic_skill_trigger_deleted AFTER DELETE ON call_center.cc_member REFERENCING OLD TABLE AS deleted FOR EACH STATEMENT EXECUTE FUNCTION call_center.cc_member_statistic_skill_trigger_deleted();


--
-- Name: cc_member cc_member_statistic_skill_trigger_inserted; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_statistic_skill_trigger_inserted AFTER INSERT ON call_center.cc_member REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE FUNCTION call_center.cc_member_statistic_skill_trigger_inserted();


--
-- Name: cc_member cc_member_statistic_skill_trigger_updated; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_statistic_skill_trigger_updated AFTER UPDATE ON call_center.cc_member REFERENCING OLD TABLE AS old_data NEW TABLE AS new_data FOR EACH STATEMENT EXECUTE FUNCTION call_center.cc_member_statistic_skill_trigger_updated();


--
-- Name: cc_member cc_member_statistic_trigger_deleted; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_statistic_trigger_deleted AFTER DELETE ON call_center.cc_member REFERENCING OLD TABLE AS deleted FOR EACH STATEMENT EXECUTE FUNCTION call_center.cc_member_statistic_trigger_deleted();


--
-- Name: cc_member cc_member_statistic_trigger_inserted; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_statistic_trigger_inserted AFTER INSERT ON call_center.cc_member REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE FUNCTION call_center.cc_member_statistic_trigger_inserted();


--
-- Name: cc_member cc_member_statistic_trigger_updated; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_statistic_trigger_updated AFTER UPDATE ON call_center.cc_member REFERENCING OLD TABLE AS old_data NEW TABLE AS new_data FOR EACH STATEMENT EXECUTE FUNCTION call_center.cc_member_statistic_trigger_updated();


--
-- Name: cc_member cc_member_sys_offset_id_trigger_inserted; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_sys_offset_id_trigger_inserted BEFORE INSERT ON call_center.cc_member FOR EACH ROW EXECUTE FUNCTION call_center.cc_member_sys_offset_id_trigger_inserted();


--
-- Name: cc_member cc_member_sys_offset_id_trigger_update; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_sys_offset_id_trigger_update BEFORE UPDATE ON call_center.cc_member FOR EACH ROW WHEN ((new.timezone_id <> old.timezone_id)) EXECUTE FUNCTION call_center.cc_member_sys_offset_id_trigger_update();


--
-- Name: cc_outbound_resource_display cc_outbound_resource_display_changed_iud; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_outbound_resource_display_changed_iud AFTER INSERT OR DELETE OR UPDATE ON call_center.cc_outbound_resource_display FOR EACH ROW EXECUTE FUNCTION call_center.cc_outbound_resource_display_changed();


--
-- Name: cc_outbound_resource_group cc_outbound_resource_group_resource_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_outbound_resource_group_resource_set_rbac_acl AFTER INSERT ON call_center.cc_outbound_resource_group FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_resource_group');


--
-- Name: cc_outbound_resource cc_outbound_resource_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_outbound_resource_set_rbac_acl AFTER INSERT ON call_center.cc_outbound_resource FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_resource');


--
-- Name: cc_queue_events cc_queue_events_changed; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_queue_events_changed AFTER INSERT OR DELETE OR UPDATE ON call_center.cc_queue_events FOR EACH ROW EXECUTE FUNCTION call_center.cc_queue_event_changed_tg();


--
-- Name: cc_queue cc_queue_resource_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_queue_resource_set_rbac_acl AFTER INSERT ON call_center.cc_queue FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_queue');


--
-- Name: cc_skill cc_skill_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_skill_set_rbac_acl AFTER INSERT ON call_center.cc_skill FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_skill');


--
-- Name: cc_team cc_team_changed_tg_u; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_team_changed_tg_u AFTER UPDATE ON call_center.cc_team FOR EACH ROW WHEN ((new.screen_control IS DISTINCT FROM old.screen_control)) EXECUTE FUNCTION call_center.cc_team_changed_tg();


--
-- Name: cc_team_events cc_team_events_changed; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_team_events_changed AFTER INSERT OR DELETE OR UPDATE ON call_center.cc_team_events FOR EACH ROW EXECUTE FUNCTION call_center.cc_team_event_changed_tg();


--
-- Name: cc_team cc_team_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_team_set_rbac_acl AFTER INSERT ON call_center.cc_team FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_team');


--
-- Name: cc_trigger cc_trigger_ins_upd_tg; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_trigger_ins_upd_tg BEFORE INSERT OR UPDATE ON call_center.cc_trigger FOR EACH ROW EXECUTE FUNCTION call_center.cc_trigger_ins_upd();


--
-- Name: cc_trigger cc_trigger_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_trigger_set_rbac_acl AFTER INSERT ON call_center.cc_trigger FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_trigger');


--
-- Name: cc_list_communications tg_cc_list_statistics_deleted; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER tg_cc_list_statistics_deleted AFTER DELETE ON call_center.cc_list_communications REFERENCING OLD TABLE AS deleted FOR EACH STATEMENT EXECUTE FUNCTION call_center.cc_list_statistics_trigger_deleted();


--
-- Name: cc_list_communications tg_cc_list_statistics_inserted; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER tg_cc_list_statistics_inserted AFTER INSERT ON call_center.cc_list_communications REFERENCING NEW TABLE AS inserted FOR EACH STATEMENT EXECUTE FUNCTION call_center.cc_list_statistics_trigger_inserted();


--
-- Name: cc_agent tg_cc_set_agent_change_status_i; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER tg_cc_set_agent_change_status_i AFTER INSERT ON call_center.cc_agent FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_agent_change_status();


--
-- Name: cc_agent tg_cc_set_agent_change_status_u; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER tg_cc_set_agent_change_status_u AFTER UPDATE ON call_center.cc_agent FOR EACH ROW WHEN ((((old.status)::text <> (new.status)::text) OR ((old.status_payload)::text <> (new.status_payload)::text))) EXECUTE FUNCTION call_center.cc_set_agent_change_status();


--
-- Name: cc_agent_channel tg_cc_set_agent_channel_change_status_u; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER tg_cc_set_agent_channel_change_status_u BEFORE UPDATE ON call_center.cc_agent_channel FOR EACH ROW WHEN ((((old.state)::text <> (new.state)::text) OR (old.online <> new.online))) EXECUTE FUNCTION call_center.cc_set_agent_channel_change_status();


--
-- Name: cc_agent_acl cc_agent_acl_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_cc_agent_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_acl cc_agent_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_agent_acl cc_agent_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_acl cc_agent_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_agent_acl cc_agent_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_agent(id, domain_id) ON DELETE CASCADE;


--
-- Name: cc_agent_acl cc_agent_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_agent cc_agent_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_cc_team_id_fk FOREIGN KEY (team_id) REFERENCES call_center.cc_team(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: cc_agent_channel cc_agent_channels_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_channel
    ADD CONSTRAINT cc_agent_channels_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent cc_agent_media_files_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_media_files_id_fk FOREIGN KEY (greeting_media_id) REFERENCES storage.media_files(id);


--
-- Name: cc_agent cc_agent_region_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_region_id_fk FOREIGN KEY (region_id) REFERENCES flow.region(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: cc_agent_state_history cc_agent_status_history_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_state_history
    ADD CONSTRAINT cc_agent_status_history_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_status_log cc_agent_status_log_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_status_log
    ADD CONSTRAINT cc_agent_status_log_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON DELETE CASCADE;


--
-- Name: cc_pause_cause cc_agent_status_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause
    ADD CONSTRAINT cc_agent_status_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_pause_cause cc_agent_status_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause
    ADD CONSTRAINT cc_agent_status_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_pause_cause cc_agent_status_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause
    ADD CONSTRAINT cc_agent_status_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_agent cc_agent_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_agent cc_agent_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_wbt_user_id_fk FOREIGN KEY (user_id) REFERENCES directory.wbt_user(id);


--
-- Name: cc_agent cc_agent_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_wbt_user_id_fk_2 FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_agent cc_agent_wbt_user_id_fk_3; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_wbt_user_id_fk_3 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


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


--
-- Name: cc_audit_rate cc_audit_rate_cc_audit_form_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_audit_rate
    ADD CONSTRAINT cc_audit_rate_cc_audit_form_id_fk FOREIGN KEY (form_id) REFERENCES call_center.cc_audit_form(id) ON DELETE CASCADE;


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


--
-- Name: cc_bucket_acl cc_bucket_acl_cc_bucket_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_acl
    ADD CONSTRAINT cc_bucket_acl_cc_bucket_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_bucket(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_bucket_acl cc_bucket_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_acl
    ADD CONSTRAINT cc_bucket_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_bucket_acl cc_bucket_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_acl
    ADD CONSTRAINT cc_bucket_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_bucket_acl cc_bucket_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_acl
    ADD CONSTRAINT cc_bucket_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_bucket_acl cc_bucket_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_acl
    ADD CONSTRAINT cc_bucket_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_bucket(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_bucket_acl cc_bucket_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_acl
    ADD CONSTRAINT cc_bucket_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_bucket_in_queue cc_bucket_in_queue_cc_bucket_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_in_queue
    ADD CONSTRAINT cc_bucket_in_queue_cc_bucket_id_fk FOREIGN KEY (bucket_id) REFERENCES call_center.cc_bucket(id);


--
-- Name: cc_bucket_in_queue cc_bucket_in_queue_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_in_queue
    ADD CONSTRAINT cc_bucket_in_queue_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_bucket cc_bucket_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket
    ADD CONSTRAINT cc_bucket_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_bucket cc_bucket_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket
    ADD CONSTRAINT cc_bucket_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_bucket cc_bucket_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket
    ADD CONSTRAINT cc_bucket_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_calls_annotation cc_calls_annotation_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_annotation
    ADD CONSTRAINT cc_calls_annotation_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_calls_annotation cc_calls_annotation_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_annotation
    ADD CONSTRAINT cc_calls_annotation_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_calls cc_calls_wbt_auth_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls
    ADD CONSTRAINT cc_calls_wbt_auth_id_fk FOREIGN KEY (grantee_id) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_communication cc_communication_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_communication
    ADD CONSTRAINT cc_communication_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_email cc_email_cc_email_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email
    ADD CONSTRAINT cc_email_cc_email_id_fk FOREIGN KEY (parent_id) REFERENCES call_center.cc_email(id);


--
-- Name: cc_email cc_email_cc_email_profiles_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email
    ADD CONSTRAINT cc_email_cc_email_profiles_id_fk FOREIGN KEY (profile_id) REFERENCES call_center.cc_email_profile(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_email_profile cc_email_profile_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email_profile
    ADD CONSTRAINT cc_email_profile_acr_routing_scheme_id_fk FOREIGN KEY (flow_id) REFERENCES flow.acr_routing_scheme(id);


--
-- Name: cc_email_profile cc_email_profile_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email_profile
    ADD CONSTRAINT cc_email_profile_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_email_profile cc_email_profile_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email_profile
    ADD CONSTRAINT cc_email_profile_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_email_profile cc_email_profile_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email_profile
    ADD CONSTRAINT cc_email_profile_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_email cc_email_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email
    ADD CONSTRAINT cc_email_wbt_user_id_fk FOREIGN KEY (owner_id) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_list_acl cc_list_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_list_acl cc_list_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_list_acl cc_list_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_list_acl cc_list_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_list(id, domain_id) ON DELETE CASCADE;


--
-- Name: cc_list_acl cc_list_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_list_communications cc_list_communications_cc_list_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_communications
    ADD CONSTRAINT cc_list_communications_cc_list_id_fk FOREIGN KEY (list_id) REFERENCES call_center.cc_list(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_list_statistics cc_list_statistics_cc_list_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_statistics
    ADD CONSTRAINT cc_list_statistics_cc_list_id_fk FOREIGN KEY (list_id) REFERENCES call_center.cc_list(id) ON UPDATE CASCADE ON DELETE CASCADE DEFERRABLE;


--
-- Name: cc_list cc_list_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list
    ADD CONSTRAINT cc_list_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_list cc_list_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list
    ADD CONSTRAINT cc_list_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_list cc_list_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list
    ADD CONSTRAINT cc_list_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_member_attempt cc_member_attempt_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt
    ADD CONSTRAINT cc_member_attempt_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id);


--
-- Name: cc_member_attempt cc_member_attempt_cc_bucket_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt
    ADD CONSTRAINT cc_member_attempt_cc_bucket_id_fk FOREIGN KEY (bucket_id) REFERENCES call_center.cc_bucket(id);


--
-- Name: cc_member_attempt cc_member_attempt_cc_member_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt
    ADD CONSTRAINT cc_member_attempt_cc_member_id_fk FOREIGN KEY (member_id) REFERENCES call_center.cc_member(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_member_attempt cc_member_attempt_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt
    ADD CONSTRAINT cc_member_attempt_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id);


--
-- Name: cc_member cc_member_calendar_timezones_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_calendar_timezones_id_fk FOREIGN KEY (timezone_id) REFERENCES flow.calendar_timezones(id);


--
-- Name: cc_member cc_member_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_member cc_member_cc_bucket_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_cc_bucket_id_fk FOREIGN KEY (bucket_id) REFERENCES call_center.cc_bucket(id);


--
-- Name: cc_member cc_member_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_member cc_member_cc_skill_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_cc_skill_id_fk FOREIGN KEY (skill_id) REFERENCES call_center.cc_skill(id);


--
-- Name: cc_member_messages cc_member_messages_cc_member_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_messages
    ADD CONSTRAINT cc_member_messages_cc_member_id_fk FOREIGN KEY (member_id) REFERENCES call_center.cc_member(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_acl cc_outbound_resource_acl_cc_outbound_resource_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_acl
    ADD CONSTRAINT cc_outbound_resource_acl_cc_outbound_resource_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_outbound_resource(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_acl cc_outbound_resource_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_acl
    ADD CONSTRAINT cc_outbound_resource_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_acl cc_outbound_resource_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_acl
    ADD CONSTRAINT cc_outbound_resource_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_outbound_resource_acl cc_outbound_resource_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_acl
    ADD CONSTRAINT cc_outbound_resource_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_outbound_resource_acl cc_outbound_resource_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_acl
    ADD CONSTRAINT cc_outbound_resource_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_outbound_resource(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_outbound_resource_acl cc_outbound_resource_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_acl
    ADD CONSTRAINT cc_outbound_resource_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_outbound_resource cc_outbound_resource_cc_email_profile_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource
    ADD CONSTRAINT cc_outbound_resource_cc_email_profile_id_fk FOREIGN KEY (email_profile_id) REFERENCES call_center.cc_email_profile(id);


--
-- Name: cc_outbound_resource_display cc_outbound_resource_display_cc_outbound_resource_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_display
    ADD CONSTRAINT cc_outbound_resource_display_cc_outbound_resource_id_fk FOREIGN KEY (resource_id) REFERENCES call_center.cc_outbound_resource(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_cc_outbound_resource_group_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_cc_outbound_resource_group_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_outbound_resource_group(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_outbound_resource_group(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_group cc_outbound_resource_group_cc_communication_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group
    ADD CONSTRAINT cc_outbound_resource_group_cc_communication_id_fk FOREIGN KEY (communication_id) REFERENCES call_center.cc_communication(id);


--
-- Name: cc_outbound_resource_group cc_outbound_resource_group_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group
    ADD CONSTRAINT cc_outbound_resource_group_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_outbound_resource_group cc_outbound_resource_group_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group
    ADD CONSTRAINT cc_outbound_resource_group_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_outbound_resource_group cc_outbound_resource_group_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group
    ADD CONSTRAINT cc_outbound_resource_group_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_outbound_resource_in_group cc_outbound_resource_in_group_cc_outbound_resource_group_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_in_group
    ADD CONSTRAINT cc_outbound_resource_in_group_cc_outbound_resource_group_id_fk FOREIGN KEY (group_id) REFERENCES call_center.cc_outbound_resource_group(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_in_group cc_outbound_resource_in_group_cc_outbound_resource_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_in_group
    ADD CONSTRAINT cc_outbound_resource_in_group_cc_outbound_resource_id_fk FOREIGN KEY (resource_id) REFERENCES call_center.cc_outbound_resource(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_in_group cc_outbound_resource_in_group_cc_outbound_resource_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_in_group
    ADD CONSTRAINT cc_outbound_resource_in_group_cc_outbound_resource_id_fk_2 FOREIGN KEY (reserve_resource_id) REFERENCES call_center.cc_outbound_resource(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_outbound_resource cc_outbound_resource_sip_gateway_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource
    ADD CONSTRAINT cc_outbound_resource_sip_gateway_id_fk FOREIGN KEY (gateway_id) REFERENCES directory.sip_gateway(id);


--
-- Name: cc_outbound_resource cc_outbound_resource_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource
    ADD CONSTRAINT cc_outbound_resource_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_outbound_resource cc_outbound_resource_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource
    ADD CONSTRAINT cc_outbound_resource_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_outbound_resource cc_outbound_resource_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource
    ADD CONSTRAINT cc_outbound_resource_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_preset_query cc_preset_query_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_preset_query
    ADD CONSTRAINT cc_preset_query_wbt_user_id_fk FOREIGN KEY (user_id) REFERENCES directory.wbt_user(id) ON DELETE CASCADE;


--
-- Name: cc_queue_acl cc_queue_acl_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl
    ADD CONSTRAINT cc_queue_acl_cc_queue_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue_acl cc_queue_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl
    ADD CONSTRAINT cc_queue_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_queue_acl cc_queue_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl
    ADD CONSTRAINT cc_queue_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_queue_acl cc_queue_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl
    ADD CONSTRAINT cc_queue_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_queue_acl cc_queue_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl
    ADD CONSTRAINT cc_queue_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_queue(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_queue_acl cc_queue_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl
    ADD CONSTRAINT cc_queue_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_queue cc_queue_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: cc_queue cc_queue_acr_routing_scheme_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_acr_routing_scheme_id_fk_2 FOREIGN KEY (after_schema_id) REFERENCES flow.acr_routing_scheme(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: cc_queue cc_queue_acr_routing_scheme_id_fk_3; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_acr_routing_scheme_id_fk_3 FOREIGN KEY (do_schema_id) REFERENCES flow.acr_routing_scheme(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: cc_queue cc_queue_acr_routing_scheme_id_fk_4; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_acr_routing_scheme_id_fk_4 FOREIGN KEY (form_schema_id) REFERENCES flow.acr_routing_scheme(id);


--
-- Name: cc_queue cc_queue_calendar_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_calendar_id_fk FOREIGN KEY (calendar_id) REFERENCES flow.calendar(id);


--
-- Name: cc_queue cc_queue_cc_list_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_cc_list_id_fk FOREIGN KEY (dnc_list_id) REFERENCES call_center.cc_list(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_queue cc_queue_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_cc_team_id_fk FOREIGN KEY (team_id) REFERENCES call_center.cc_team(id);


--
-- Name: cc_queue_events cc_queue_events_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_events
    ADD CONSTRAINT cc_queue_events_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: cc_queue_events cc_queue_events_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_events
    ADD CONSTRAINT cc_queue_events_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue cc_queue_media_files_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_media_files_id_fk FOREIGN KEY (ringtone_id) REFERENCES storage.media_files(id);


--
-- Name: cc_queue_resource cc_queue_resource_cc_outbound_resource_group_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_resource
    ADD CONSTRAINT cc_queue_resource_cc_outbound_resource_group_id_fk FOREIGN KEY (resource_group_id) REFERENCES call_center.cc_outbound_resource_group(id);


--
-- Name: cc_queue_resource cc_queue_resource_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_resource
    ADD CONSTRAINT cc_queue_resource_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue_resource cc_queue_resource_cc_queue_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_resource
    ADD CONSTRAINT cc_queue_resource_cc_queue_id_fk_2 FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue_skill cc_queue_skill_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_skill
    ADD CONSTRAINT cc_queue_skill_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue_skill cc_queue_skill_cc_skill_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_skill
    ADD CONSTRAINT cc_queue_skill_cc_skill_id_fk FOREIGN KEY (skill_id) REFERENCES call_center.cc_skill(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: cc_queue_skill_statistics cc_queue_skill_statistics_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_skill_statistics
    ADD CONSTRAINT cc_queue_skill_statistics_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue_skill_statistics cc_queue_skill_statistics_cc_skill_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_skill_statistics
    ADD CONSTRAINT cc_queue_skill_statistics_cc_skill_id_fk FOREIGN KEY (skill_id) REFERENCES call_center.cc_skill(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue_statistics cc_queue_statistics_cc_bucket_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_statistics
    ADD CONSTRAINT cc_queue_statistics_cc_bucket_id_fk FOREIGN KEY (bucket_id) REFERENCES call_center.cc_bucket(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue_statistics cc_queue_statistics_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_statistics
    ADD CONSTRAINT cc_queue_statistics_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_queue cc_queue_wbt_auth_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_wbt_auth_id_fk FOREIGN KEY (grantee_id) REFERENCES directory.wbt_auth(id);


--
-- Name: cc_queue cc_queue_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_queue cc_queue_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_queue cc_queue_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_quick_reply cc_quick_reply_article_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_quick_reply
    ADD CONSTRAINT cc_quick_reply_article_fk FOREIGN KEY (article) REFERENCES knowledge_base.article(id) ON DELETE SET NULL;


--
-- Name: cc_quick_reply cc_quick_reply_wbt_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_quick_reply
    ADD CONSTRAINT cc_quick_reply_wbt_domain_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


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
-- Name: cc_skill_in_agent cc_skill_in_agent_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_in_agent
    ADD CONSTRAINT cc_skill_in_agent_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_skill_in_agent cc_skill_in_agent_cc_skils_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_in_agent
    ADD CONSTRAINT cc_skill_in_agent_cc_skils_id_fk FOREIGN KEY (skill_id) REFERENCES call_center.cc_skill(id);


--
-- Name: cc_skill_in_agent cc_skill_in_agent_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_in_agent
    ADD CONSTRAINT cc_skill_in_agent_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_skill_in_agent cc_skill_in_agent_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_in_agent
    ADD CONSTRAINT cc_skill_in_agent_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON DELETE SET NULL;


--
-- Name: cc_skill cc_skill_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill
    ADD CONSTRAINT cc_skill_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


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


--
-- Name: cc_team_acl cc_team_acl_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl
    ADD CONSTRAINT cc_team_acl_cc_team_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_team(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_team_acl cc_team_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl
    ADD CONSTRAINT cc_team_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_team_acl cc_team_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl
    ADD CONSTRAINT cc_team_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_team_acl cc_team_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl
    ADD CONSTRAINT cc_team_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_team_acl cc_team_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl
    ADD CONSTRAINT cc_team_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_team(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_team_acl cc_team_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl
    ADD CONSTRAINT cc_team_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


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


--
-- Name: cc_team cc_team_forecast_calculation_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_forecast_calculation_id_fk FOREIGN KEY (forecast_calculation_id) REFERENCES wfm.forecast_calculation(id) ON DELETE SET NULL;


--
-- Name: cc_team_trigger cc_team_trigger_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_trigger
    ADD CONSTRAINT cc_team_trigger_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id) ON DELETE CASCADE;


--
-- Name: cc_team_trigger cc_team_trigger_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_trigger
    ADD CONSTRAINT cc_team_trigger_cc_team_id_fk FOREIGN KEY (team_id) REFERENCES call_center.cc_team(id) ON DELETE CASCADE;


--
-- Name: cc_team cc_team_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_team cc_team_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_wbt_user_id_fk FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_team cc_team_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_wbt_user_id_fk_2 FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_trigger_acl cc_trigger_acl_cc_trigger_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_cc_trigger_id_fk FOREIGN KEY (object) REFERENCES call_center.cc_trigger(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_trigger_acl cc_trigger_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_trigger_acl cc_trigger_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_trigger_acl cc_trigger_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_trigger_acl cc_trigger_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_trigger(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_trigger_acl cc_trigger_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_acl
    ADD CONSTRAINT cc_trigger_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_trigger cc_trigger_acr_routing_scheme_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger
    ADD CONSTRAINT cc_trigger_acr_routing_scheme_id_fk FOREIGN KEY (schema_id) REFERENCES flow.acr_routing_scheme(id);


--
-- Name: cc_trigger cc_trigger_calendar_timezones_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger
    ADD CONSTRAINT cc_trigger_calendar_timezones_id_fk FOREIGN KEY (timezone_id) REFERENCES flow.calendar_timezones(id);


--
-- Name: cc_trigger_job cc_trigger_job_cc_trigger_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_job
    ADD CONSTRAINT cc_trigger_job_cc_trigger_id_fk FOREIGN KEY (trigger_id) REFERENCES call_center.cc_trigger(id);


--
-- Name: cc_trigger_job_log cc_trigger_job_log_cc_trigger_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger_job_log
    ADD CONSTRAINT cc_trigger_job_log_cc_trigger_id_fk FOREIGN KEY (trigger_id) REFERENCES call_center.cc_trigger(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_trigger cc_trigger_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_trigger
    ADD CONSTRAINT cc_trigger_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: socket_session socket_session_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.socket_session
    ADD CONSTRAINT socket_session_wbt_user_id_fk FOREIGN KEY (user_id) REFERENCES directory.wbt_user(id);


--
-- Name: system_settings systemc_settings_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.system_settings
    ADD CONSTRAINT systemc_settings_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: SCHEMA call_center; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA call_center TO grafana;


--
-- Name: TABLE cc_calls; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_calls TO grafana;


--
-- Name: TABLE cc_queue; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue TO grafana;


--
-- Name: TABLE cc_agent; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent TO grafana;


--
-- Name: TABLE cc_agent_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_acl TO grafana;


--
-- Name: SEQUENCE cc_agent_acl_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_agent_acl_id_seq TO grafana;


--
-- Name: TABLE cc_agent_channel; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_channel TO grafana;


--
-- Name: TABLE cc_agent_state_history; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_state_history TO grafana;


--
-- Name: SEQUENCE cc_agent_history_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_agent_history_id_seq TO grafana;


--
-- Name: SEQUENCE cc_agent_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_agent_id_seq TO grafana;


--
-- Name: TABLE cc_agent_in_queue_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_in_queue_view TO grafana;


--
-- Name: TABLE cc_agent_with_user; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_with_user TO grafana;


--
-- Name: TABLE cc_skill; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_skill TO grafana;


--
-- Name: TABLE cc_skill_in_agent; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_skill_in_agent TO grafana;


--
-- Name: TABLE cc_team; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_team TO grafana;


--
-- Name: TABLE cc_agent_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_list TO grafana;


--
-- Name: TABLE cc_agent_status_log; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_status_log TO grafana;


--
-- Name: TABLE cc_audit_rate; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_audit_rate TO grafana;


--
-- Name: TABLE cc_calls_history; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_calls_history TO grafana;


--
-- Name: TABLE cc_member_attempt_history; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_member_attempt_history TO grafana;


--
-- Name: TABLE cc_agent_today_stats; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_today_stats TO grafana;


--
-- Name: TABLE cc_agent_waiting; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_agent_waiting TO grafana;


--
-- Name: TABLE cc_member_attempt_transferred; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_member_attempt_transferred TO grafana;


--
-- Name: SEQUENCE cc_attempt_transferred_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_attempt_transferred_id_seq TO grafana;


--
-- Name: TABLE cc_audit_form; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_audit_form TO grafana;


--
-- Name: TABLE cc_audit_form_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_audit_form_acl TO grafana;


--
-- Name: SEQUENCE cc_audit_form_acl_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_audit_form_acl_id_seq TO grafana;


--
-- Name: SEQUENCE cc_audit_form_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_audit_form_id_seq TO grafana;


--
-- Name: TABLE cc_audit_form_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_audit_form_view TO grafana;


--
-- Name: SEQUENCE cc_audit_rate_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_audit_rate_id_seq TO grafana;


--
-- Name: TABLE cc_audit_rate_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_audit_rate_view TO grafana;


--
-- Name: TABLE cc_bucket; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_bucket TO grafana;


--
-- Name: TABLE cc_bucket_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_bucket_acl TO grafana;


--
-- Name: SEQUENCE cc_bucket_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_bucket_id_seq TO grafana;


--
-- Name: TABLE cc_bucket_in_queue; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_bucket_in_queue TO grafana;


--
-- Name: SEQUENCE cc_bucket_in_queue_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_bucket_in_queue_id_seq TO grafana;


--
-- Name: TABLE cc_bucket_in_queue_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_bucket_in_queue_view TO grafana;


--
-- Name: TABLE cc_bucket_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_bucket_view TO grafana;


--
-- Name: TABLE cc_member; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_member TO grafana;


--
-- Name: TABLE cc_member_attempt; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_member_attempt TO grafana;


--
-- Name: TABLE cc_call_active_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_call_active_list TO grafana;


--
-- Name: TABLE cc_calls_annotation; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_calls_annotation TO grafana;


--
-- Name: SEQUENCE cc_call_annotation_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_call_annotation_id_seq TO grafana;


--
-- Name: TABLE cc_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_list TO grafana;


--
-- Name: SEQUENCE cc_call_list_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_call_list_id_seq TO grafana;


--
-- Name: TABLE cc_calls_history_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_calls_history_list TO grafana;


--
-- Name: TABLE cc_calls_transcribe; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_calls_transcribe TO grafana;


--
-- Name: SEQUENCE cc_calls_transcribe_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_calls_transcribe_id_seq TO grafana;


--
-- Name: TABLE cc_cluster; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_cluster TO grafana;


--
-- Name: SEQUENCE cc_cluster_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_cluster_id_seq TO grafana;


--
-- Name: TABLE cc_communication; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_communication TO grafana;


--
-- Name: SEQUENCE cc_communication_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_communication_id_seq TO grafana;


--
-- Name: TABLE cc_communication_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_communication_list TO grafana;


--
-- Name: TABLE cc_distribute_stage_1; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_distribute_stage_1 TO grafana;


--
-- Name: TABLE system_settings; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.system_settings TO grafana;


--
-- Name: TABLE cc_distribute_stats; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_distribute_stats TO grafana;


--
-- Name: TABLE cc_email; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_email TO grafana;


--
-- Name: SEQUENCE cc_email_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_email_id_seq TO grafana;


--
-- Name: TABLE cc_email_profile; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_email_profile TO grafana;


--
-- Name: TABLE cc_email_profile_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_email_profile_list TO grafana;


--
-- Name: SEQUENCE cc_email_profiles_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_email_profiles_id_seq TO grafana;


--
-- Name: TABLE cc_list_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_list_acl TO grafana;


--
-- Name: SEQUENCE cc_list_acl_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_list_acl_id_seq TO grafana;


--
-- Name: TABLE cc_list_communications; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_list_communications TO grafana;


--
-- Name: SEQUENCE cc_list_communications_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_list_communications_id_seq TO grafana;


--
-- Name: TABLE cc_list_communications_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_list_communications_view TO grafana;


--
-- Name: TABLE cc_list_statistics; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_list_statistics TO grafana;


--
-- Name: TABLE cc_list_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_list_view TO grafana;


--
-- Name: TABLE cc_queue_skill; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_skill TO grafana;


--
-- Name: TABLE cc_manual_queue_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_manual_queue_list TO grafana;


--
-- Name: SEQUENCE cc_member_attempt_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_member_attempt_id_seq TO grafana;


--
-- Name: SEQUENCE cc_member_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_member_id_seq TO grafana;


--
-- Name: TABLE cc_member_messages; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_member_messages TO grafana;


--
-- Name: SEQUENCE cc_member_messages_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_member_messages_id_seq TO grafana;


--
-- Name: TABLE cc_outbound_resource; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource TO grafana;


--
-- Name: TABLE cc_member_view_attempt; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_member_view_attempt TO grafana;


--
-- Name: TABLE cc_member_view_attempt_history; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_member_view_attempt_history TO grafana;


--
-- Name: TABLE cc_notification; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_notification TO grafana;


--
-- Name: SEQUENCE cc_notification_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_notification_id_seq TO grafana;


--
-- Name: TABLE cc_outbound_resource_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_acl TO grafana;


--
-- Name: SEQUENCE cc_outbound_resource_acl_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_outbound_resource_acl_id_seq TO grafana;


--
-- Name: TABLE cc_outbound_resource_display; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_display TO grafana;


--
-- Name: SEQUENCE cc_outbound_resource_display_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_outbound_resource_display_id_seq TO grafana;


--
-- Name: TABLE cc_outbound_resource_display_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_display_view TO grafana;


--
-- Name: TABLE cc_outbound_resource_group; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_group TO grafana;


--
-- Name: TABLE cc_outbound_resource_group_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_group_acl TO grafana;


--
-- Name: SEQUENCE cc_outbound_resource_group_acl_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_outbound_resource_group_acl_id_seq TO grafana;


--
-- Name: SEQUENCE cc_outbound_resource_group_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_outbound_resource_group_id_seq TO grafana;


--
-- Name: TABLE cc_outbound_resource_group_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_group_view TO grafana;


--
-- Name: TABLE cc_outbound_resource_in_group; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_in_group TO grafana;


--
-- Name: SEQUENCE cc_outbound_resource_in_group_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_outbound_resource_in_group_id_seq TO grafana;


--
-- Name: TABLE cc_outbound_resource_in_group_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_in_group_view TO grafana;


--
-- Name: TABLE cc_outbound_resource_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_outbound_resource_view TO grafana;


--
-- Name: TABLE cc_pause_cause; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_pause_cause TO grafana;


--
-- Name: SEQUENCE cc_pause_cause_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_pause_cause_id_seq TO grafana;


--
-- Name: TABLE cc_pause_cause_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_pause_cause_list TO grafana;


--
-- Name: TABLE cc_preset_query; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_preset_query TO grafana;


--
-- Name: SEQUENCE cc_preset_query_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_preset_query_id_seq TO grafana;


--
-- Name: TABLE cc_preset_query_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_preset_query_list TO grafana;


--
-- Name: TABLE cc_queue_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_acl TO grafana;


--
-- Name: SEQUENCE cc_queue_acl_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_queue_acl_id_seq TO grafana;


--
-- Name: TABLE cc_queue_events; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_events TO grafana;


--
-- Name: SEQUENCE cc_queue_events_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_queue_events_id_seq TO grafana;


--
-- Name: TABLE cc_queue_events_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_events_list TO grafana;


--
-- Name: SEQUENCE cc_queue_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_queue_id_seq TO grafana;


--
-- Name: TABLE cc_queue_statistics; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_statistics TO grafana;


--
-- Name: TABLE cc_queue_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_list TO grafana;


--
-- Name: TABLE cc_queue_report_general; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_report_general TO grafana;


--
-- Name: TABLE cc_queue_resource; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_resource TO grafana;


--
-- Name: SEQUENCE cc_queue_resource_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_queue_resource_id_seq TO grafana;


--
-- Name: SEQUENCE cc_queue_resource_id_seq1; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_queue_resource_id_seq1 TO grafana;


--
-- Name: TABLE cc_queue_resource_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_resource_view TO grafana;


--
-- Name: SEQUENCE cc_queue_skill_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_queue_skill_id_seq TO grafana;


--
-- Name: TABLE cc_queue_skill_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_skill_list TO grafana;


--
-- Name: TABLE cc_queue_skill_statistics; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_queue_skill_statistics TO grafana;


--
-- Name: TABLE cc_quick_reply; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_quick_reply TO grafana;


--
-- Name: TABLE cc_quick_reply_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_quick_reply_list TO grafana;


--
-- Name: TABLE cc_skill_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_skill_acl TO grafana;


--
-- Name: SEQUENCE cc_skill_in_agent_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_skill_in_agent_id_seq TO grafana;


--
-- Name: TABLE cc_skill_in_agent_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_skill_in_agent_view TO grafana;


--
-- Name: TABLE cc_skill_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_skill_view TO grafana;


--
-- Name: SEQUENCE cc_skils_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_skils_id_seq TO grafana;


--
-- Name: TABLE cc_sys_queue_distribute_resources; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_sys_queue_distribute_resources TO grafana;


--
-- Name: TABLE cc_team_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_team_acl TO grafana;


--
-- Name: SEQUENCE cc_team_acl_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_team_acl_id_seq TO grafana;


--
-- Name: TABLE cc_team_events; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_team_events TO grafana;


--
-- Name: SEQUENCE cc_team_events_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_team_events_id_seq TO grafana;


--
-- Name: TABLE cc_team_events_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_team_events_list TO grafana;


--
-- Name: SEQUENCE cc_team_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_team_id_seq TO grafana;


--
-- Name: TABLE cc_team_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_team_list TO grafana;


--
-- Name: TABLE cc_team_trigger; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_team_trigger TO grafana;


--
-- Name: TABLE cc_team_trigger_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_team_trigger_list TO grafana;


--
-- Name: TABLE cc_trigger; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_trigger TO grafana;


--
-- Name: TABLE cc_trigger_acl; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_trigger_acl TO grafana;


--
-- Name: SEQUENCE cc_trigger_acl_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_trigger_acl_id_seq TO grafana;


--
-- Name: SEQUENCE cc_trigger_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_trigger_id_seq TO grafana;


--
-- Name: TABLE cc_trigger_job; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_trigger_job TO grafana;


--
-- Name: SEQUENCE cc_trigger_job_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.cc_trigger_job_id_seq TO grafana;


--
-- Name: TABLE cc_trigger_job_log; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_trigger_job_log TO grafana;


--
-- Name: TABLE cc_trigger_job_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_trigger_job_list TO grafana;


--
-- Name: TABLE cc_trigger_job_log_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_trigger_job_log_list TO grafana;


--
-- Name: TABLE cc_trigger_list; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_trigger_list TO grafana;


--
-- Name: TABLE cc_user_status_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.cc_user_status_view TO grafana;


--
-- Name: TABLE socket_session; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.socket_session TO grafana;


--
-- Name: TABLE socket_session_view; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON TABLE call_center.socket_session_view TO grafana;


--
-- Name: SEQUENCE systemc_settings_id_seq; Type: ACL; Schema: call_center; Owner: -
--

GRANT SELECT ON SEQUENCE call_center.systemc_settings_id_seq TO grafana;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: call_center; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE opensips IN SCHEMA call_center GRANT SELECT ON TABLES  TO grafana;


--
-- PostgreSQL database dump complete
--

\unrestrict QhqtLyw2KO5Nc7kUO4ltxqUKmJbta5jx0KHp2gaPEekw2gJhTWwDfOVtdmqaF4N

