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
-- Name: cc_communication_t; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.cc_communication_t AS (
	number character varying(50),
	priority integer,
	state integer,
	routing_ids integer[]
);


--
-- Name: cc_communication_type_in_member; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.cc_communication_type_in_member AS (
	id integer,
	type_id integer,
	last_activity bigint
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
-- Name: cc_type; Type: TYPE; Schema: call_center; Owner: -
--

CREATE TYPE call_center.cc_type AS ENUM (
    'inbound',
    'ivr',
    'preview',
    'progressive',
    'predictive'
);


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
    from cc_member_attempt a
    where a.agent_id = agent_id_ and a.state != 'leaving' and a.channel = 'call';

    if attempt_id_ notnull then
        raise exception 'agent % has task % in the status of %', agent_id_, attempt_id_, state_;
    end if;

    update cc_agent_channel c
    set state = 'waiting',
        joined_at = now(),
        queue_id = null,
        timeout = null
    where (c.agent_id, c.channel) = (agent_id_, channel_) and c.state in ('wrap_time', 'missed')
    returning joined_at into joined_at_;

    return row(joined_at_);
end;
$$;


--
-- Name: cc_agent_set_login(integer, character varying[], boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_agent_set_login(agent_id_ integer, channels_ character varying[], on_demand_ boolean DEFAULT false) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    res_ jsonb;
begin
    update cc_agent
    set status            = 'online', -- enum added
        status_payload = null,
        on_demand = on_demand_,
        updated_at = cc_view_timestamp(now()), -- todo
        last_state_change = now()     -- todo rename to status
    where cc_agent.id = agent_id_;

    with c as (
        insert into cc_agent_channel (agent_id, channel, state, online)
            select a.id, x, 'waiting', coalesce((channels_::varchar[]) && array [x]::varchar[], true)
            from cc_agent a,
                 unnest((a.allow_channels)::varchar[]) x -- TODO global var
            where a.id = agent_id_
            on conflict (agent_id, channel) do update
                set online = excluded.online,
                    no_answers = 0,
                    timeout = case when excluded.state = 'waiting' then null else excluded.timeout end,
--                     joined_at = case when excluded.state = 'waiting' then now() else excluded.timeout end,
                    state = case
                                when
                                    (exists(select 1 from cc_member_attempt at where at.agent_id = excluded.agent_id))
                                    then cc_agent_channel.state
                                else excluded.state end
            returning *
    )
    select json_agg(json_build_object('channel', c.channel, 'online', c.online, 'state', c.state, 'joined_at',
                                      (date_part('epoch'::text, c.joined_at) * 1000::double precision)::bigint)) AS x
    into res_
    from c;


    return row(res_, cc_view_timestamp(now()));
end;
$$;


--
-- Name: cc_agent_state_timeout(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_agent_state_timeout() RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
    declare rec record;
        curr_time int8 = cc_view_timestamp(now());
begin
        for rec in select curr_time, a.agent_id, ca.updated_at as agent_updated_at, ca.status
        from cc_member_attempt a
            inner join cc_queue cq on a.queue_id = cq.id
            inner join cc_team ct on cq.team_id = ct.id
            inner join lateral cc_attempt_leaving(a.id, cq.sec_between_retries, 'ABANDONED'::varchar) x on true
            inner join cc_agent ca on a.agent_id = ca.id
        where a.state_str = 'reporting'  and (not ct.post_processing or a.leaving_at < now() - (ct.post_processing_timeout || ' sec')::interval)
        loop
            return next rec;
        end loop;


        for rec in with u as (
        update cc_agent a
        set state = a.status,
            state_timeout = null,
            attempt_id = null,
            active_queue_id = null,
            last_state_change = now()
        where a.state_timeout < now()
        returning curr_time, a.id, a.updated_at, a.state
        )
        select *
        from u
        loop
            return next rec;
        end loop;
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
-- Name: cc_attempt_abandoned(bigint, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_abandoned(attempt_id_ bigint, _max_count integer DEFAULT 0) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt  cc_member_attempt%rowtype;
begin
    update cc_member_attempt
        set leaving_at = now(),
            last_state_change = now(),
            result = 'abandoned', --TODO
            state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    update cc_member
    set last_hangup_at  = extract(EPOCH from now())::int8, -- todo delete me
        last_attempt_id = attempt_id_,
        last_agent      = coalesce(attempt.agent_id, last_agent),
        stop_at = extract(EPOCH from now())::int8, -- del me
        stop_cause = attempt.result,
        -- fixme
        communications  = jsonb_set(
                jsonb_set(communications, '{0,attempt_id}'::text[], attempt_id_::text::jsonb, true)
            , '{0,last_activity_at}'::text[], (extract(EPOCH from now())::int8)::text::jsonb),
        attempts        = attempts + 1                     --TODO
    where id = attempt.member_id;


    return row(attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_attempt_bridged(bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_bridged(attempt_id_ bigint) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt cc_member_attempt%rowtype;
begin

    update cc_member_attempt
    set state = 'bridged',
        bridged_at = now(),
        last_state_change = now()
    where id = attempt_id_
    returning * into attempt;


    if attempt.agent_id notnull then
        update cc_agent_channel ch
        set state = attempt.state,
            joined_at = now(),
            no_answers = 0,
            last_bridged_at = now()
        where  (ch.agent_id, ch.channel) = (attempt.agent_id, attempt.channel);
    end if;

    return row(attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_attempt_end_reporting(bigint, character varying, character varying, bigint, bigint, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ bigint DEFAULT NULL::bigint, next_offering_at_ bigint DEFAULT NULL::bigint, variables_ jsonb DEFAULT NULL::jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt cc_member_attempt%rowtype;
    agent_timeout_ timestamptz;
    time_ int8 = extract(EPOCH  from now()) * 1000;
    user_id_ int8 = null;
    domain_id_ int8;
begin
    update cc_member_attempt
        set state  =  'leaving',
            reporting_at = now(),
            leaving_at = case when leaving_at isnull then now() else leaving_at end,
            result = status_,
            description = description_
    where id = attempt_id_ and state != 'leaving'
    returning * into attempt;

    if attempt.id isnull then
        raise exception  'not found %', attempt_id_;
    end if;

    update cc_member
    set last_hangup_at  = time_, -- todo delete me
        last_attempt_id = attempt_id_,
        variables = case when variables_ isnull then variables else variables_ end,
        expire_at = case when expire_at_ isnull then expire_at else expire_at_ end,
        min_offering_at = case when next_offering_at_ isnull then min_offering_at else next_offering_at_ end,
        last_agent      = coalesce(attempt.agent_id, last_agent),
--         stop_at         = case when status_ isnull then null else (extract(EPOCH from now()) * 1000)::int8 end, --TODO
        stop_cause      = status_,
        communications = jsonb_set(
                jsonb_set(communications, array [attempt.communication_idx, 'attempt_id']::text[],
                          attempt_id_::text::jsonb, true)
            , array [attempt.communication_idx, 'last_activity_at']::text[],
                time_::text::jsonb
            ),
        attempts        = attempts + 1                     --TODO
    where id = attempt.member_id;

    if attempt.agent_id notnull then
        select a.user_id, a.domain_id
        into user_id_, domain_id_
        from cc_agent a
        where a.id = attempt.agent_id;

        update cc_agent_channel c
        set state = 'waiting',
            joined_at = now(),
            queue_id = null
        where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
        returning timeout into agent_timeout_;
    end if;

    return row(cc_view_timestamp(now()), attempt.channel, attempt.queue_id, attempt.agent_call_id, attempt.agent_id, user_id_, domain_id_, cc_view_timestamp(agent_timeout_));
end;
$$;


--
-- Name: cc_attempt_leaving(bigint, integer, character varying, character varying, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_leaving(attempt_id_ bigint, hold_sec integer, result_ character varying, agent_status_ character varying, agent_hold_sec_ integer) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
declare
    agent_id_  int;
    member_id_ int8;
    queue_id_ int;
    channel_ varchar;
begin
    update cc_member_attempt
        set leaving_at = now(),
            result = result_,
            state = 'leaving'
    where id = attempt_id_
    returning queue_id, agent_id, member_id, channel into queue_id_, agent_id_, member_id_, channel_;

    update cc_member
    set last_hangup_at  = extract(EPOCH from now())::int8 * 1000, -- todo delete me
        last_attempt_id = attempt_id_,
        last_agent      = coalesce(agent_id_, last_agent),
        ready_at        = now() + (hold_sec || ' sec')::interval,
        stop_at = case when result_ = 'success' then extract(EPOCH from now())::int8 * 1000 else stop_at end,
        pause_at = case when result_ = 'success' then now() else pause_at end,
        communications  = jsonb_set(
                jsonb_set(communications, '{0,attempt_id}'::text[], attempt_id_::text::jsonb, true)
            , '{0,last_activity_at}'::text[], (extract(EPOCH from now())::int8)::text::jsonb),
        attempts        = attempts + 1                     --TODO
    where id = member_id_;

    if agent_id_ notnull then
        update cc_agent_channel c
        set state = agent_status_,
            joined_at = now(),
            no_answers = no_answers + 1,
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where (c.agent_id, c.channel) = (agent_id_, channel_);

    end if;

    return now();
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
    update cc_member_attempt  n
    set state = 'wait_agent',
        last_state_change = now(),
        agent_id = null ,
        agent_call_id = null
    from cc_member_attempt a
    where a.id = n.id and a.id = attempt_id_
    returning n.last_state_change, a.agent_id, n.channel into last_state_change_, agent_id_, channel_;

    if agent_id_ notnull then
        update cc_agent_channel c
        set state = 'missed',
            joined_at = last_state_change_,
            timeout  = now() + (agent_hold_::varchar || ' sec')::interval,
            no_answers = (no_answers + 1),
            last_missed_at = now()
        where (c.agent_id, c.channel) = (agent_id_, channel_)
        returning no_answers into no_answers_;
    end if;

    return row(last_state_change_, no_answers_);
end;
$$;


--
-- Name: cc_attempt_offering(bigint, integer, character varying, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_offering(attempt_id_ bigint, agent_id_ integer, agent_call_id_ character varying, member_call_id_ character varying) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt cc_member_attempt%rowtype;
begin

    update cc_member_attempt
    set state = 'offering',
        last_state_change = now(),
        offering_at = coalesce(offering_at, now()),
        agent_id = case when agent_id isnull and agent_id_::int notnull then agent_id_ else agent_id end,
        agent_call_id = case when agent_call_id isnull  and agent_call_id_::varchar notnull then agent_call_id_ else agent_call_id end,
        -- todo for queue preview
        member_call_id = case when member_call_id isnull  and member_call_id_ notnull then member_call_id_ else member_call_id end
    where id = attempt_id_
    returning * into attempt;


    if attempt.agent_id notnull then
        update cc_agent_channel ch
        set state = attempt.state,
            joined_at = now(),
            last_offering_at = now(),
            queue_id = attempt.queue_id
        where  (ch.agent_id, ch.channel) = (attempt.agent_id, attempt.channel);
    end if;

    return row(attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_attempt_timeout(bigint, integer, character varying, character varying, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_timeout(attempt_id_ bigint, hold_sec integer, result_ character varying, agent_status_ character varying, agent_hold_sec_ integer) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
declare
    agent_id_  int;
    member_id_ int8;
    queue_id_ int;
    channel_ varchar;
begin
    update cc_member_attempt
        set reporting_at = now(),
            result = 'timeout',
            state = 'leaving'
    where id = attempt_id_
    returning queue_id, agent_id, member_id, channel into queue_id_, agent_id_, member_id_, channel_;

    update cc_member
    set last_hangup_at  = extract(EPOCH from now())::int8 * 1000, -- todo delete me
        last_attempt_id = attempt_id_,
        last_agent      = coalesce(agent_id_, last_agent),
        ready_at        = now() + (hold_sec || ' sec')::interval,
        stop_at = case when result_ = 'success' then extract(EPOCH from now())::int8 * 1000 else stop_at end,
        pause_at = case when result_ = 'success' then now() else pause_at end,
        communications  = jsonb_set(
                jsonb_set(communications, '{0,attempt_id}'::text[], attempt_id_::text::jsonb, true)
            , '{0,last_activity_at}'::text[], (extract(EPOCH from now())::int8)::text::jsonb),
        attempts        = attempts + 1                     --TODO
    where id = member_id_;

    if agent_id_ notnull then
        update cc_agent_channel c
        set state = agent_status_,
            joined_at = now(),
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where (c.agent_id, c.channel) = (agent_id_, channel_);

    end if;

    return now();
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cc_calls; Type: TABLE; Schema: call_center; Owner: -
--

CREATE UNLOGGED TABLE call_center.cc_calls (
    id character varying NOT NULL,
    direction character varying,
    destination character varying,
    parent_id character varying,
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
    bridged_id character varying,
    user_id integer,
    gateway_id integer,
    queue_id integer,
    agent_id integer,
    team_id integer,
    attempt_id integer,
    member_id bigint,
    type character varying DEFAULT 'call'::character varying,
    "timestamp" timestamp with time zone,
    answered_at timestamp with time zone,
    bridged_at timestamp with time zone,
    hangup_at timestamp with time zone,
    created_at timestamp with time zone,
    hangup_by character varying,
    transfer_from character varying,
    transfer_to character varying,
    amd_result character varying,
    amd_duration interval
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


--
-- Name: cc_call_get_owner_leg(call_center.cc_calls); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_call_get_owner_leg(c_ call_center.cc_calls, OUT number_ character varying, OUT name_ character varying, OUT type_ character varying, OUT id_ character varying) RETURNS record
    LANGUAGE plpgsql IMMUTABLE
    AS $$
begin
    if c_.direction = 'inbound' then
        number_ := c_.to_number;
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
-- Name: cc_call_set_bridged(character varying, character varying, timestamp with time zone, character varying, bigint, character varying); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_call_set_bridged(call_id_ character varying, state_ character varying, timestamp_ timestamp with time zone, app_id_ character varying, domain_id_ bigint, call_bridged_id_ character varying)
    LANGUAGE plpgsql
    AS $$
begin
    update cc_calls cc
        set bridged_id = c.bridged_id,
            state = state_,
            timestamp = timestamp_,
            to_number = case when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                then c.number_ else to_number end,
            to_name = case when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                then c.name_ else to_name end,
            to_type = case when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                then c.type_ else to_type end,
            to_id = case when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                then c.id_ else to_id end
        from (
            select b.id,
                   b2.id parent_id,
                   b2.id bridged_id,
                   b2o.*
            from cc_calls b
                left join cc_calls b2 on b2.id = call_id_
                left join lateral cc_call_get_owner_leg(b2) b2o on true
        where b.id = call_bridged_id_
    ) c
    where c.id = cc.id;


    update cc_calls cc
        set bridged_id = c.bridged_id,
            state = state_,
            timestamp = timestamp_,
            parent_id = case when cc.parent_id notnull and cc.parent_id != c.bridged_id then c.bridged_id else cc.parent_id end,
            transfer_from = case when cc.parent_id notnull and cc.parent_id != c.bridged_id then cc.parent_id else cc.transfer_from end,
            to_number = case when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                then c.number_ else to_number end,
            to_name = case when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                then c.name_ else to_name end,
            to_type = case when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                then c.type_ else to_type end,
            to_id = case when (cc.direction = 'inbound' and cc.parent_id isnull) or (cc.direction = 'outbound')
                then c.id_ else to_id end
        from (
                select b.id,
                       b2.id parent_id,
                       b2.id bridged_id,
                       b2o.*
                from cc_calls b
                    left join cc_calls b2 on b2.id = call_bridged_id_
                    left join lateral cc_call_get_owner_leg(b2) b2o on true
            where b.id = call_id_
        ) c
    where c.id = cc.id;

end;
$$;


--
-- Name: cc_calls_set_timing(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_calls_set_timing() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    if new.state = 'active' then
        if new.answered_at isnull then
            new.answered_at = new.timestamp;

            if new.direction = 'inbound' and new.parent_id notnull and new.bridged_at isnull then
                new.bridged_at = new.answered_at;
            end if;

        else if old.state = 'hold' then
            new.hold_sec =  coalesce(old.hold_sec, 0) + extract ('epoch' from new.timestamp - old.timestamp)::double precision;

--             if new.parent_id notnull then
--                 update cc_calls set hold_sec  = hold_sec + new.hold_sec  where id = new.parent_id;
--             end if;
        end if;

        end if;
    else if (new.state = 'bridge' ) then
        new.bridged_at = coalesce(new.bridged_at, new.timestamp);
    else if new.state = 'hangup' then
        new.hangup_at = new.timestamp;
    end if;
    end if;
    end if;

    RETURN new;
END
$$;


--
-- Name: cc_confirm_agent_attempt(bigint, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_confirm_agent_attempt(_agent_id bigint, _attempt_id bigint) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare cnt int;
BEGIN
    update cc_member_attempt
    set result = case id when _attempt_id then null else 'ABANDONED' end
    where agent_id = _agent_id and not exists(
       select 1
       from cc_member_attempt a
       where a.agent_id = _agent_id and a.result notnull
       for update
    );
    get diagnostics cnt = row_count;
    return cnt::int;
END;
$$;


--
-- Name: cc_distribute_direct_member_to_queue(character varying, bigint, integer, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint)
    LANGUAGE plpgsql
    AS $_$
declare
    _weight int4;
    _destination jsonb;
BEGIN

  return query with attempts as (
      insert into cc_member_attempt (state, queue_id, member_id, destination, node_id, agent_id, resource_id, bucket_id)
        select 1, m.queue_id, m.id, x, _node_name, _agent_id, r.resource_id, m.bucket_id
        from cc_member m
            inner join lateral jsonb_path_query_first(communications, '$[*] ? (@.id == $id)', vars => jsonb_build_object('id', _communication_id)) x on x notnull
            inner join cc_queue q on q.id = m.queue_id
            inner join lateral (
                select (t::cc_sys_distribute_type).resource_id
                from cc_sys_queue_distribute_resources r,
                     unnest(r.types) t
                where r.queue_id = m.queue_id and (t::cc_sys_distribute_type).type_id = (x->'type'->'id')::int4
                limit 1
            ) r on true
            inner join cc_team ct on q.team_id = ct.id
            left join cc_outbound_resource cor on cor.id = r.resource_id
        where m.id = _member_id
      returning cc_member_attempt.*
  )
  select a.id,
         a.member_id,
         null::varchar    result,
         a.queue_id,
         cq.updated_at as queue_updated_at,
         0::integer       queue_count,
         0::integer       queue_active_count,
         0::integer       queue_waiting_count,
         a.resource_id::integer    resource_id,
         r.updated_at::bigint     resource_updated_at,
         null::bigint     gateway_updated_at,
         a.destination    destination,
         cm.variables,
         cm.name,
         null::varchar,
         a.agent_id::bigint     agent_id,
         ag.updated_at::bigint     agent_updated_at,
         t.updated_at::bigint     team_updated_at
  from attempts a
           left join cc_member cm on a.member_id = cm.id
           inner join cc_queue cq on a.queue_id = cq.id
           inner join cc_team t on t.id = cq.team_id
           left join cc_outbound_resource r on r.id = a.resource_id
           left join cc_agent ag on ag.id = a.agent_id;

  --raise notice '%', _attempt_id;

END;
$_$;


--
-- Name: cc_distribute_inbound_call_to_queue(character varying, bigint, character varying, jsonb, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, _priority integer DEFAULT 0) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    _timezone_id int4;
    _discard_abandoned_after int4;
    _weight int4;
    dnc_list_id_ int4;
    _domain_id int8;
    _calendar_id int4;
    _queue_updated_at int8;
    _team_updated_at int8;
    _team_id_ int;
    _list_comm_id int8;

    _call record;
    _attempt record;
BEGIN
  select c.timezone_id,
           (payload->>'discard_abandoned_after')::int discard_abandoned_after,
         c.domain_id,
         q.dnc_list_id,
         q.calendar_id,
         q.updated_at,
         ct.updated_at,
         q.team_id
  from cc_queue q
    inner join flow.calendar c on q.calendar_id = c.id
    inner join cc_team ct on q.team_id = ct.id
  where  q.id = _queue_id
  into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
      _team_updated_at, _team_id_;

  select *
  from cc_calls c
  where c.id = _call_id
--   for update
  into _call;

  if _call.id isnull or _call.direction isnull then
--       insert into cc_member_attempt(channel, queue_id, state, leaving_at, member_call_id, result)
--           values ('call', _queue_id, 'leaving', now(), _call_id, 'abandoned');
      raise exception 'not found call';
  end if;


  if not exists(select accept
            from flow.calendar_check_timing(_domain_id, _calendar_id, null)
            as x (name varchar, excepted varchar, accept bool, expire bool)
            where accept and excepted is null and not expire)
  then
--       insert into cc_member_attempt(channel, queue_id, state, leaving_at, member_call_id, result)
--           values ('call', _queue_id, 'leaving', now(), _call_id, 'now_working');
      raise exception 'number % calendar not working', _call.from_number;
  end if;


  --TODO
  select clc.id
    into _list_comm_id
    from cc_list_communications clc
    where (clc.list_id = dnc_list_id_ and clc.number = _call.from_number)
  limit 1;

  if _list_comm_id notnull then
--           insert into cc_member_attempt(channel, queue_id, state, leaving_at, member_call_id, result, list_communication_id)
--           values ('call', _queue_id, 'leaving', now(), _call_id, 'banned', _list_comm_id);
          raise exception 'number % banned', _call.from_number;
  end if;

  if  _discard_abandoned_after > 0 then
      select
            case when log.result = 'abandoned' then
                 extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
            else coalesce(_priority, 0) end
        from cc_member_attempt_history log
        where log.leaving_at >= (now() -  (_discard_abandoned_after || ' sec')::interval)
            and log.queue_id = _queue_id
            and log.destination->>'destination' = _call.from_number
        order by log.leaving_at desc
        limit 1
        into _weight;
  end if;

  insert into call_center.cc_member_attempt (state, queue_id, member_id, weight, member_call_id, destination, node_id, list_communication_id)
  values ('waiting', _queue_id, null, coalesce(_weight, _priority), _call_id, jsonb_build_object('destination', _call.from_number),
              _node_name, (select clc.id
                            from cc_list_communications clc
                            where (clc.list_id = dnc_list_id_ and clc.number = _call.from_number)))
  returning * into _attempt;

  update cc_calls
  set queue_id  = _attempt.queue_id,
      team_id = _team_id_,
      attempt_id = _attempt.id,
      payload = variables_
  where id = _call_id
  returning * into _call;

  if _call.id isnull or _call.direction isnull then
--       insert into cc_member_attempt(channel, queue_id, state, leaving_at, result, member_call_id)
--       values ('call', _queue_id, 'leaving', now(), 'abandoned', _call_id);
      raise exception 'not found call';
  end if;

  return row(
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
      cc_view_timestamp(_call.timestamp)::int8,
      _call.app_id::varchar,
      _call.from_number::varchar,
      _call.from_name::varchar,
      cc_view_timestamp(_call.answered_at)::int8,
      cc_view_timestamp(_call.bridged_at)::int8,
      cc_view_timestamp(_call.created_at)::int8
  );

END;
$$;


--
-- Name: cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, character varying, character varying, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, _number character varying, _name character varying, _priority integer DEFAULT 0) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint)
    LANGUAGE plpgsql
    AS $_$
declare
    _attempt_id               bigint = null;
    _member_id                bigint;
    _timezone_id              int4;
    _abandoned_resume_allowed bool;
    _discard_abandoned_after  int4;
    _weight                   int4;
    _destination              jsonb;
    _domain_id                int8;
BEGIN

    select m.id,
           jsonb_path_query_first(communications, '$[*] ? (@.destination == $destination)',
                                  vars => jsonb_build_object('destination', _number))
    from cc_member m
    where m.queue_id = _queue_id
      and m.communications @> (jsonb_build_array(jsonb_build_object('destination', _number)))::jsonb
      and not exists(select 1 from cc_member_attempt a where a.member_id = m.id for update skip locked)
    limit 1
    into _member_id, _destination;

    select c.timezone_id,
           (payload ->> 'abandoned_resume_allowed')::bool abandoned_resume_allowed,
           (payload ->> 'discard_abandoned_after')::int   discard_abandoned_after,
           c.domain_id
    from cc_queue q
             inner join flow.calendar c on q.calendar_id = c.id
    where q.id = _queue_id
    into _timezone_id, _abandoned_resume_allowed, _discard_abandoned_after, _domain_id;


    if _abandoned_resume_allowed is true and _discard_abandoned_after > 0 then
        select (case
                    when log.result = 'ABANDONED'
                        then ((((extract(EPOCH from now()) * 1000)::int8 - log.hangup_at) / 1000)) +
                             coalesce(_priority, 0)
                    else null end)::int
        from cc_member_attempt_log log
        where log.created_at >= (now() - (_discard_abandoned_after || ' sec')::interval)
          and log.member_id = _member_id
        order by log.created_at desc
        limit 1
        into _weight;
    end if;


    if _member_id isnull then
        _destination = jsonb_build_object('destination', _number);

        insert into cc_member(domain_id, queue_id, name, priority, timezone_id, communications)
        select _domain_id, _queue_id, _name, _priority, coalesce(_timezone_id, 344), (jsonb_build_array(_destination))::jsonb
        returning cc_member.id into _member_id;
    end if;

    return query with attempts as (
        insert into cc_member_attempt (state, queue_id, member_id, weight, member_call_id, destination, node_id,
                                       channel)
            values (1, _queue_id, _member_id, coalesce(_weight, _priority), _call_id, _destination, _node_name, 'chat')
            returning *
    )
                 select a.id,
                        a.member_id,
                        null::varchar         result,
                        a.queue_id,
                        cq.updated_at as      queue_updated_at,
                        0::integer            queue_count,
                        0::integer            queue_active_count,
                        0::integer            queue_waiting_count,
                        null::integer         resource_id,
                        null::bigint          resource_updated_at,
                        null::bigint          gateway_updated_at,
                        a.destination         destination,
                        cm.variables,
                        cm.name,
                        a.member_call_id,
                        null::bigint          agent_id,
                        null::bigint          agent_updated_at,
                        ct.updated_at::bigint team_updated_at
                 from attempts a
                          left join cc_member cm on a.member_id = cm.id
                          inner join cc_queue cq on a.queue_id = cq.id
                          left join cc_team ct on cq.team_id = ct.id
                          left join cc_list_communications lc
                                    on lc.list_id = cq.dnc_list_id and lc.number = a.destination ->> 'destination';

    --raise notice '%', _attempt_id;

END;
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
-- Name: cc_list_statistics_trigger_deleted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_list_statistics_trigger_deleted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

    insert into cc_list_statistics (list_id, count)
    select l.list_id, l.cnt
    from (
             select l.list_id, count(*) cnt
             from deleted l
                inner join cc_list li on li.id = l.list_id
             group by l.list_id
         ) l
    on conflict (list_id)
        do update
        set count = cc_list_statistics.count - EXCLUDED.count ;

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
    insert into cc_list_statistics (list_id, count)
    select l.list_id, l.cnt
    from (
             select l.list_id, count(*) cnt
             from inserted l
             group by l.list_id
         ) l
    on conflict (list_id)
        do update
        set count = EXCLUDED.count + cc_list_statistics.count;
    RETURN NULL;
END
$$;


--
-- Name: cc_member_attempt_dev_tgf(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_attempt_dev_tgf() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

        if old.result isnull then
            raise exception 'not allow';
        end if;

        RETURN NULL;
    END;
$$;


--
-- Name: cc_member_attempt_log_day_f(integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_attempt_log_day_f(queue_id integer, bucket_id integer) RETURNS integer
    LANGUAGE sql IMMUTABLE STRICT
    AS $_$
    SELECT sum(l.count)::int4 AS cnt
     FROM call_center.cc_member_attempt_log_day l
     WHERE $2 IS NOT NULL and l.queue_id = $1::int
       AND l.bucket_id = $2::int4
$_$;


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
    AS $_$select (select json_agg(x)
                from (
                         select x ->> 'destination'                destination,
                                cc_get_lookup(c.id, c.name)       as type,
                                (x -> 'priority')::int          as priority,
                                (x -> 'state')::int             as state,
                                x -> 'description'              as description,
                                (x -> 'last_activity_at')::int8 as last_activity_at,
                                (x -> 'attempts')::int          as attempts,
                                x ->> 'last_cause'              as last_cause,
                                cc_get_lookup(r.id, r.name)       as resource,
                                x ->> 'display'                 as display
                         from jsonb_array_elements($1) x
                                  left join cc_communication c on c.id = (x -> 'type' -> 'id')::int
                                  left join cc_outbound_resource r on r.id = (x -> 'resource' -> 'id')::int
                     ) x)::jsonb$_$;


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
    if new.communications notnull and jsonb_typeof(new.communications) = 'array' then
        new.sys_destinations = (select array(select cc_destination_in(idx::int4, (x -> 'type' ->> 'id')::int4, (x ->> 'last_activity_at')::int8,  (x -> 'resource' ->> 'id')::int, (x ->> 'priority')::int)
         from jsonb_array_elements(new.communications) with ordinality as x(x, idx)
         where coalesce((x.x -> 'stopped_at')::int8, 0) = 0
         and idx > -1));

    else
        new.sys_destinations = null;
    end if;

    return new;
END
$$;


--
-- Name: cc_member_statistic_trigger(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN NULL;
END;
$$;


--
-- Name: cc_member_statistic_trigger_deleted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_trigger_deleted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare cnt int;
BEGIN

    insert into cc_queue_statistics (bucket_id, skill_id, queue_id, member_count, member_waiting)
    select t.bucket_id, skill_id, t.queue_id, t.cnt, t.cntwait
    from (
             select queue_id, bucket_id, skill_id, count(*) cnt, count(*) filter ( where m.stop_at = 0 ) cntwait
             from deleted m
                inner join cc_queue q on q.id = m.queue_id
             group by queue_id, bucket_id, skill_id
         ) t
    on conflict (queue_id, coalesce(bucket_id, 0), coalesce(skill_id, 0))
        do update
        set member_count   = cc_queue_statistics.member_count - EXCLUDED.member_count,
            member_waiting = cc_queue_statistics.member_waiting - EXCLUDED.member_waiting;

    RETURN NULL;
END
$$;


--
-- Name: cc_member_statistic_trigger_inserted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_trigger_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    insert into cc_queue_statistics (queue_id, bucket_id, skill_id, member_count, member_waiting)
    select t.queue_id, t.bucket_id, t.skill_id, t.cnt, t.cntwait
    from (
             select queue_id, bucket_id, skill_id, count(*) cnt, count(*) filter ( where m.stop_at = 0 ) cntwait
             from inserted m
             group by queue_id, bucket_id, skill_id
         ) t
    on conflict (queue_id, coalesce(bucket_id, 0), coalesce(skill_id, 0))
        do update
        set member_count   = EXCLUDED.member_count + cc_queue_statistics.member_count,
            member_waiting = EXCLUDED.member_waiting + cc_queue_statistics.member_waiting;


    --    raise notice '% % %', TG_TABLE_NAME, TG_OP, (select count(*) from inserted );
--    PERFORM pg_notify(TG_TABLE_NAME, TG_OP);
    RETURN NULL;
END
$$;


--
-- Name: cc_member_statistic_trigger_updated(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_statistic_trigger_updated() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    insert into cc_queue_statistics (queue_id, bucket_id, skill_id, member_count, member_waiting)
    select t.queue_id, t.bucket_id, t.skill_id, t.cnt, t.cntwait
    from (
        select queue_id, bucket_id, skill_id, sum(cnt) cnt, sum(cntwait) cntwait
        from (
             select m.queue_id,
                    m.bucket_id,
                    m.skill_id,
                    -1 * count(*) cnt,
                    -1 * count(*) filter ( where m.stop_at = 0 ) cntwait
             from old_data m
             group by m.queue_id, m.bucket_id, m.skill_id

             union all
            select m.queue_id,
                    m.bucket_id   bucket_id ,
                    m.skill_id   skill_id ,
                    count(*) cnt,
                    count(*) filter ( where m.stop_at = 0 ) cntwait
             from new_data m
             group by m.queue_id, m.bucket_id, m.skill_id
        ) o
        group by queue_id, bucket_id, skill_id
    ) t
    --where t.cntwait != 0
    on conflict (queue_id, coalesce(bucket_id, 0), coalesce(skill_id, 0)) do update
        set member_waiting = excluded.member_waiting + cc_queue_statistics.member_waiting,
            member_count = excluded.member_count + cc_queue_statistics.member_count;

   RETURN NULL;
END
$$;


--
-- Name: cc_member_sys_offset_id_trigger_inserted(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_member_sys_offset_id_trigger_inserted() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
declare res int4[];
BEGIN
    if new.timezone_id isnull or new.timezone_id = 0 then
        res = cc_queue_default_timezone_offset_id(new.queue_id);
        new.timezone_id = res[1];
        new.sys_offset_id = res[2];
    else
        new.sys_offset_id = cc_timezone_offset_id(new.timezone_id);
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
    new.sys_offset_id = cc_timezone_offset_id(new.timezone_id);

    if new.timezone_id isnull or new.sys_offset_id isnull then
        raise exception 'not found timezone';
    end if;

    RETURN new;
END
$$;


--
-- Name: cc_msg_create_conversation(character varying, character varying, character varying, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_msg_create_conversation(key_ character varying, title_ character varying, name_ character varying, body_ jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$
    declare conversation_id_ int8;
    channel_id_ varchar;
    posted_at_ timestamptz;
begin
    insert into cc_msg_conversation (title, domain_id)
    values (title_, (select p.domain_id
			from cc_msg_profiles p
			where p.secret_key = key_))
    returning id into conversation_id_;

    insert into cc_msg_participants (name, conversation_id)
    values (name_, conversation_id_)
    returning channel_id into channel_id_;

    insert into cc_msg_post(conversation_id, body, posted_by)
    values (conversation_id_, body_, name_)
    returning posted_at into posted_at_;

    return row(posted_at_, conversation_id_, channel_id_::text);
end;
$$;


--
-- Name: cc_msg_history(uuid, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_msg_history(channel_id_ uuid, limit_ integer, offset_ integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
    declare conversation_id_ int8;
begin
    select o.conversation_id
    into conversation_id_
    from cc_msg_participants o
        inner join cc_msg_conversation cmc on o.conversation_id = cmc.id
    where o.channel_id = channel_id_ and cmc.closed_at isnull;

    if conversation_id_ isnull then
        raise exception 'not found'; -- todo
    end if;

    return query select msg.posted_by, (extract(epoch from msg.posted_at) * 1000)::int8 posted_at, msg.body
    from cc_msg_post msg
    where msg.conversation_id = conversation_id_
    order by msg.posted_at desc
    limit limit_
    offset offset_;
end;
$$;


--
-- Name: cc_msg_post(uuid, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_msg_post(channel_id_ uuid, body_ jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$
    declare last_ timestamptz;
        posted_by_ varchar;
begin
    update cc_msg_participants n
        set activity_at  = now()
    from cc_msg_participants o
    where n.channel_id = channel_id_ and n.channel_id = o.channel_id
    returning o.activity_at into last_;

    insert into cc_msg_post (body, conversation_id, posted_by)
    select body_, p.conversation_id, p.name
    from cc_msg_participants p
    where p.channel_id = channel_id_
    returning posted_by into posted_by_;

    return row( (extract(epoch from now()) )::int8 , posted_by_, body_ );

end;
$$;


--
-- Name: cc_msg_unread(uuid, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_msg_unread(channel_id_ uuid, limit_ integer) RETURNS SETOF record
    LANGUAGE plpgsql
    AS $$
    declare activity_at_ timestamptz;
        conversation_id_ int8;
begin
    update cc_msg_participants n
        set activity_at  = now()
    from cc_msg_participants o
        inner join cc_msg_conversation cmc on o.conversation_id = cmc.id
    where n.channel_id = channel_id_ and n.channel_id = o.channel_id and cmc.closed_at isnull
    returning o.conversation_id, o.activity_at into conversation_id_, activity_at_;

    if conversation_id_ isnull then
        raise exception 'not found'; -- todo
    end if;

    return query select msg.posted_by, (extract(epoch from msg.posted_at) * 1000)::int8 posted_at, msg.body
    from cc_msg_post msg
    where msg.conversation_id = conversation_id_
        and msg.posted_at > activity_at_
    order by msg.posted_at desc
    limit limit_;
end;
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
    from cc_queue q
        inner join flow.calendar c on c.id = q.calendar_id
        inner join flow.calendar_timezones z on z.id = c.timezone_id
    where q.id = $1;
$_$;


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

  update cc_outbound_resource
  set last_error_id = _error_id,
      last_error_at = ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint,
    successively_errors = case when successively_errors + 1 >= max_successively_errors then 0 else successively_errors + 1 end,
    enabled = case when successively_errors + 1 >= max_successively_errors then false else enabled end
  where id = _id and "enabled" is true
  returning successively_errors >= max_successively_errors, successively_errors into _stopped, _successively_errors
  ;

  if _stopped is true then
    update cc_outbound_resource o
    set reserve = false,
        successively_errors = 0
    from (
      select id
      from cc_outbound_resource r
      where r.enabled is true
        and r.reserve is true
--         and exists(
--           select *
--           from cc_resource_in_routing crir
--           where crir.routing_id = _routing_id
--             and crir.resource_id = r.id
--         )
      order by case when _strategy = 'top_down' then r.last_error_at else null end asc,
               case _strategy
                 when 'by_limit' then r."limit"
                 when 'random' then random()
               else null
               end desc
      limit 1
    ) r
    where r.id = o.id
    returning o.id::bigint into _un_reserved_id;
  end if;

  select _successively_errors::smallint, _stopped::boolean, _un_reserved_id::bigint into _res;
  return _res;
END;
$$;


--
-- Name: cc_set_active_members(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    return query update cc_member_attempt a
        set state = 'waiting'
            ,node_id = node
            ,last_state_change = now()
            ,list_communication_id = lc.id
        from (
            select c.id,
                   cq.updated_at                      as queue_updated_at,
                   r.updated_at                       as resource_updated_at,
                   0                      as gateway_updated_at, --fixme!!!
                   c.destination                      as destination,
                   cm.variables                       as variables,
                   cm.name                            as member_name,
                   c.state                            as state,
                   cq.sec_locate_agent,
                   cqs.member_count                   as queue_cnt,
                   0                                  as queue_active_cnt,
                   cqs.member_waiting                 as queue_waiting_cnt,
                   ca.updated_at                      as agent_updated_at,
                   tm.updated_at                      as team_updated_at,
                   cq.dnc_list_id
            from cc_member_attempt c
                     inner join cc_member cm on c.member_id = cm.id
                     inner join cc_queue cq on cm.queue_id = cq.id
                     left join cc_team tm on tm.id = cq.team_id
                     left join cc_outbound_resource r on r.id = c.resource_id
                     left join directory.sip_gateway gw on gw.id = r.gateway_id
                     left join cc_agent ca on c.agent_id = ca.id
                     left join cc_queue_statistics cqs on cq.id = cqs.queue_id
            where c.state = 'idle'
              and c.leaving_at isnull
            order by cq.priority desc, c.weight desc
                for update of c skip locked
        ) c
        left join cc_list_communications lc on lc.list_id = c.dnc_list_id and lc.number = c.destination->>'destination'
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
            c.resource_updated_at::bigint as resource_updated_at,
            c.gateway_updated_at::bigint as gateway_updated_at,
            c.destination,
            c.variables ,
            c.member_name,
            a.member_call_id,
            a.agent_id,
            c.agent_updated_at,
            c.team_updated_at,
            a.list_communication_id;
END;
$$;


--
-- Name: cc_set_agent_change_status(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_set_agent_change_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- FIXME
    if TG_OP = 'INSERT' then
        return new;
    end if;
    insert into cc_agent_state_history (agent_id, joined_at, state, duration, payload)
    values (old.id, old.last_state_change, old.status,  new.last_state_change - old.last_state_change, old.status_payload);
--     update cc_agent_channel
--     set online = case when new.status = 'online' then true else false end
--     where cc_agent_channel.agent_id = new.id;
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

  if new.state = 'waiting' then
      new.queue_id := null;
  end if;

  insert into cc_agent_state_history (agent_id, joined_at, state, channel, duration, queue_id)
  values (old.agent_id, old.joined_at, old.state, old.channel, new.joined_at - old.joined_at, old.queue_id);

  RETURN new;
END;
$$;


--
-- Name: cc_set_rbac_rec(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_set_rbac_rec() RETURNS trigger
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


--
-- Name: cc_team_agents_by_bucket(character varying, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_team_agents_by_bucket(ch_ character varying, team_id_ integer, bucket_id integer) RETURNS integer[]
    LANGUAGE plpgsql
    AS $_$
declare res int4[];
begin
    select array_agg(a.id order by b.lvl asc, a.last_state_change)
    into res
    from cc_agent_channel cac
             inner join cc_agent a on a.id = cac.agent_id
             inner join cc_sys_agent_group_team_bucket b on b.agent_id = cac.agent_id
    where (cac.agent_id, cac.channel) = (a.id, $1) and cac.state = 'waiting' and cac.timeout isnull
      and a.status = 'online'
      and b.team_id = $2::int4
      and not exists(select 1 from cc_member_attempt att where att.agent_id = cac.agent_id)
      and case when $3 isnull then true else b.bucket_id = $3 end ;

    return res;
end;
$_$;


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
-- Name: cc_un_reserve_members_with_resources(character varying, character varying); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_un_reserve_members_with_resources(node character varying, res character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    count integer;
BEGIN
    update cc_member_attempt
      set state  = -1,
          hangup_at = ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint,
          result = res
    where hangup_at = 0 and node_id = node and state = 0;

    get diagnostics count = row_count;
    return count;
END;
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
-- Name: test_sp(integer); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.test_sp(INOUT cnt integer)
    LANGUAGE plpgsql
    AS $$
begin
    if NOT pg_try_advisory_xact_lock(13213211) then
        raise notice 'LOCK';
        return;
    end if;


    with dis as (
        select q.domain_id,
               row_number() over (partition by q.domain_id order by q.priority desc, csdqbs.bucket_id nulls last) pos,
               q.id,
               q.team_id,

               q.calendar_id,
               q.type,
               csdqbs.bucket_id,
               q.sec_between_retries,
               case
                   when q.type in  (1, 6) then (select count(*) --fixme
                                         from cc_member_attempt a
                                         where a.queue_id = q.id
                                           and (a.state = 'wait_agent')
                                           and a.agent_id isnull)
                   else csdqbs.member_waiting end                                                                 member_waiting
        from cc_queue q
                 left join cc_sys_distribute_queue_bucket_seg csdqbs on q.id = csdqbs.queue_id and q.type in (1,2,3,4,5) -- FIXME
        where q.enabled
          and (q.type in (1, 6) or csdqbs.member_waiting > 0)
    )
            ,
         res as (
             select dis.*, r.resources, r.types, r.ran
             from dis
                      left join cc_sys_queue_distribute_resources r on r.queue_id = dis.id and dis.type != 1
             where dis.member_waiting > 0
               and (dis.type in (1, 6) or r.queue_id notnull)
         ),
         ag as (
             --FIXME channel in C
             select t.*, cc_team_agents_by_bucket('call',t.team_id::int, t.bucket_id::int) agents
             from (
                      select res.team_id, res.bucket_id
                      from res
                      where res.team_id notnull
                      group by res.team_id, res.bucket_id
                  ) t
         )
    , cc_distribute_member_tmp as (
        select x.*, t.bucket_id, t.id as queue_id, case when t.type in (1, 6) then 'u' else 'i' end op,
             case when t.type in ( 6) then 'chat' else 'call' end channel, t.domain_id
        from (
                 select res.*,
                        ag.agents,
                        row (res.id, res.bucket_id, res.type, (extract(epoch  from now()) * 1000)::int8 - (res.sec_between_retries * 1000)
                            , res.ran, 100, res.member_waiting, 1)::cc_sys_distribute_request req
                 from res
                          left join ag on res.type > 0 and res.team_id = ag.team_id and
                                          coalesce(res.bucket_id, 0) = coalesce(ag.bucket_id, 0)
                 order by res.pos
             ) t,
             lateral cc_test_recursion(
                     t.req,
                     t.agents,
                     t.resources,
                     t.types
                 ) x (id bigint, destination_idx int4, resource_id int4, agent_id int4)
    )
    , ins as (
        insert into cc_member_attempt(channel, member_id, queue_id, resource_id, agent_id, bucket_id, destination, communication_idx)
        select t.channel,
               t.id,
               t.queue_id,
               t.resource_id,
               t.agent_id,
               t.bucket_id,
               json_build_object('id', x->'id', 'destination', x->'destination',
        'priority', x->'priority',
        'type', json_build_object('id', x->'type'->'id', 'name', comm.name)) as destination,
               t.destination_idx - 1
        from cc_distribute_member_tmp t
            inner join cc_member cm on t.id = cm.id
            inner join lateral jsonb_extract_path(cm.communications, (t.destination_idx - 1)::text) x on true
            left join cc_communication comm on comm.id = (x->'type'->'id')::int
        where t.op = 'i'
    )
    update cc_member_attempt a
    set agent_id = t.agent_id
    from (
             select t.id, t.agent_id
             from cc_distribute_member_tmp t
             where t.op = 'u'
         ) t
    where t.id = a.id
      and a.agent_id isnull;

end;
$$;


--
-- Name: gin_cc_pair_test2_ops; Type: OPERATOR FAMILY; Schema: call_center; Owner: -
--

CREATE OPERATOR FAMILY call_center.gin_cc_pair_test2_ops USING gin;


--
-- Name: cc_agent_activity; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_activity (
    id integer NOT NULL,
    agent_id integer NOT NULL,
    last_bridge_start_at bigint DEFAULT 0 NOT NULL,
    last_bridge_end_at bigint DEFAULT 0 NOT NULL,
    last_offering_call_at bigint DEFAULT 0,
    calls_abandoned integer DEFAULT 0 NOT NULL,
    calls_answered integer DEFAULT 0 NOT NULL,
    sum_talking_of_day bigint DEFAULT 0 NOT NULL,
    sum_pause_of_day bigint DEFAULT 0 NOT NULL,
    successively_no_answers smallint DEFAULT 0 NOT NULL,
    last_answer_at bigint DEFAULT 0 NOT NULL,
    sum_idle_of_day bigint DEFAULT 0 NOT NULL
);


--
-- Name: agent_statistic_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.agent_statistic_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agent_statistic_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.agent_statistic_id_seq OWNED BY call_center.cc_agent_activity.id;


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
    successively_no_answers integer DEFAULT 0 NOT NULL,
    created_at bigint,
    created_by bigint,
    updated_by bigint,
    status_payload character varying,
    progressive_count integer DEFAULT 1,
    last_state_change timestamp with time zone DEFAULT now() NOT NULL,
    on_demand boolean DEFAULT false NOT NULL,
    allow_channels character varying[] DEFAULT '{call}'::character varying[] NOT NULL
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


--
-- Name: cc_agent_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint NOT NULL,
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
-- Name: cc_agent_attempt; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_attempt (
    id bigint NOT NULL,
    queue_id bigint NOT NULL,
    agent_id bigint,
    attempt_id bigint NOT NULL
);


--
-- Name: cc_agent_attempt_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_agent_attempt_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_agent_attempt_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_agent_attempt_id_seq OWNED BY call_center.cc_agent_attempt.id;


--
-- Name: cc_agent_channel; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_channel (
    agent_id integer NOT NULL,
    state character varying NOT NULL,
    channel character varying NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    timeout timestamp with time zone,
    online boolean DEFAULT true NOT NULL,
    max_opened integer DEFAULT 1 NOT NULL,
    no_answers integer DEFAULT 0 NOT NULL,
    queue_id integer,
    last_offering_at timestamp with time zone,
    last_bridged_at timestamp with time zone,
    last_missed_at timestamp with time zone
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


--
-- Name: cc_agent_missed_attempt; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_missed_attempt (
    id bigint NOT NULL,
    attempt_id bigint NOT NULL,
    agent_id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    call_id character varying
);


--
-- Name: cc_member_attempt; Type: TABLE; Schema: call_center; Owner: -
--

CREATE UNLOGGED TABLE call_center.cc_member_attempt (
    id bigint NOT NULL,
    queue_id integer NOT NULL,
    member_id bigint,
    weight integer DEFAULT 0 NOT NULL,
    resource_id integer,
    node_id character varying(20),
    result character varying(200),
    agent_id integer,
    bucket_id bigint,
    destination jsonb,
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
    conversation_id bigint
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


--
-- Name: TABLE cc_member_attempt; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON TABLE call_center.cc_member_attempt IS 'todo';


--
-- Name: COLUMN cc_member_attempt.communication_idx; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON COLUMN call_center.cc_member_attempt.communication_idx IS 'fixme';


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
-- Name: cc_member_attempt_log; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_member_attempt_log (
    id bigint DEFAULT nextval('call_center.cc_member_attempt_id_seq'::regclass) NOT NULL,
    queue_id bigint NOT NULL,
    state integer DEFAULT 0 NOT NULL,
    member_id bigint NOT NULL,
    weight integer DEFAULT 0 NOT NULL,
    hangup_at bigint DEFAULT 0 NOT NULL,
    bridged_at bigint DEFAULT 0 NOT NULL,
    resource_id integer,
    leg_a_id character varying(36),
    leg_b_id character varying(36),
    node_id character varying(20),
    result character varying(200),
    originate_at bigint DEFAULT 0 NOT NULL,
    answered_at bigint DEFAULT 0 NOT NULL,
    logs jsonb,
    agent_id bigint,
    bucket_id bigint,
    created_at timestamp without time zone NOT NULL,
    success boolean DEFAULT false NOT NULL
);
ALTER TABLE ONLY call_center.cc_member_attempt_log ALTER COLUMN created_at SET STATISTICS 1000;


--
-- Name: cc_agent_daily_calls_mat; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_agent_daily_calls_mat AS
 SELECT a.id,
    COALESCE(calls.success_calls, (0)::bigint) AS success_calls,
    COALESCE(calls.max_data, (CURRENT_DATE)::timestamp without time zone) AS max_success_call_time,
    COALESCE(missed.cnt, (0)::bigint) AS missed_calls,
    COALESCE(missed.max_data, (CURRENT_DATE)::timestamp without time zone) AS max_missed_call_time
   FROM ((call_center.cc_agent a
     LEFT JOIN ( SELECT l.agent_id,
            count(*) AS success_calls,
            max(l.created_at) AS max_data
           FROM call_center.cc_member_attempt_log l
          WHERE ((l.created_at > CURRENT_DATE) AND (l.agent_id IS NOT NULL))
          GROUP BY l.agent_id) calls ON ((calls.agent_id = a.id)))
     LEFT JOIN ( SELECT m.agent_id,
            count(*) AS cnt,
            max(m.created_at) AS max_data
           FROM call_center.cc_agent_missed_attempt m
          WHERE (m.created_at > CURRENT_DATE)
          GROUP BY m.agent_id) missed ON ((missed.agent_id = a.id)))
  WITH NO DATA;


--
-- Name: cc_agent_daily_calls; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_agent_daily_calls AS
 SELECT a.id AS agent_id,
    (a.success_calls + n.cnt) AS success_calls,
    (a.missed_calls + m.cnt) AS missed_calls
   FROM ((call_center.cc_agent_daily_calls_mat a
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt
           FROM call_center.cc_member_attempt_log l
          WHERE ((l.created_at > a.max_success_call_time) AND (l.agent_id = a.id))) n ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt
           FROM call_center.cc_agent_missed_attempt l
          WHERE ((l.created_at > a.max_missed_call_time) AND (l.agent_id = a.id))) m ON (true));


--
-- Name: cc_agent_state_history; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_state_history (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    state character varying(20) NOT NULL,
    queue_id integer,
    attempt_id bigint,
    channel character varying,
    duration interval DEFAULT '00:00:00'::interval NOT NULL,
    payload character varying
);


--
-- Name: cc_agent_daily_state_activity_mat; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_agent_daily_state_activity_mat AS
 SELECT h.agent_id,
    h.queue_id,
    h.state,
    sum((h2.joined_at - h.joined_at)) AS t,
    max(h.joined_at) AS last_activity
   FROM (call_center.cc_agent_state_history h
     JOIN LATERAL ( SELECT h2_1.id,
            h2_1.agent_id,
            h2_1.joined_at,
            h2_1.state,
            h2_1.payload,
            h2_1.queue_id
           FROM call_center.cc_agent_state_history h2_1
          WHERE ((h2_1.agent_id = h.agent_id) AND (h2_1.joined_at > h.joined_at))
          ORDER BY h2_1.joined_at
         LIMIT 1) h2 ON (true))
  WHERE (h.joined_at > CURRENT_DATE)
  GROUP BY h.agent_id, h.queue_id, h.state
  WITH NO DATA;


--
-- Name: cc_agent_end_state_day_5min; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_agent_end_state_day_5min AS
 SELECT s.trunc_5_minute,
    s.state,
    s.agent_id,
    sum(s.t) AS state_time
   FROM ( SELECT h.agent_id,
            h.state,
            sum((h2.joined_at - h.joined_at)) AS t,
            (date_trunc('minute'::text, h.joined_at) - ((((date_part('minute'::text, h.joined_at))::integer % 5))::double precision * '00:01:00'::interval)) AS trunc_5_minute
           FROM ((call_center.cc_agent_state_history h
             LEFT JOIN LATERAL ( SELECT h2_1.id,
                    h2_1.agent_id,
                    h2_1.joined_at,
                    h2_1.state,
                    h2_1.payload
                   FROM call_center.cc_agent_state_history h2_1
                  WHERE ((h2_1.agent_id = h.agent_id) AND (h2_1.joined_at > h.joined_at))
                  ORDER BY h2_1.joined_at
                 LIMIT 1) h2 ON (true))
             JOIN call_center.cc_agent ca ON ((h.agent_id = ca.id)))
          WHERE ((h.joined_at > CURRENT_DATE) AND (h2.joined_at IS NOT NULL))
          GROUP BY h.agent_id, h.state, ca.id, (date_trunc('minute'::text, h.joined_at) - ((((date_part('minute'::text, h.joined_at))::integer % 5))::double precision * '00:01:00'::interval))) s
  WHERE ((s.state)::text <> 'logged_out'::text)
  GROUP BY s.agent_id, s.state, s.trunc_5_minute
  WITH NO DATA;


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
-- Name: cc_agent_in_team; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_agent_in_team (
    id integer NOT NULL,
    team_id integer NOT NULL,
    agent_id integer,
    skill_id integer,
    lvl integer DEFAULT 0 NOT NULL,
    min_capacity smallint DEFAULT 0 NOT NULL,
    max_capacity smallint DEFAULT 100 NOT NULL,
    bucket_ids bigint[]
);


--
-- Name: cc_agent_in_team_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_agent_in_team_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_agent_in_team_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_agent_in_team_id_seq OWNED BY call_center.cc_agent_in_team.id;


--
-- Name: cc_agent_last_2hour_calls_mat; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_agent_last_2hour_calls_mat AS
 SELECT a.id,
    COALESCE(calls.success_calls, (0)::bigint) AS success_calls,
    COALESCE((calls.max_data)::timestamp with time zone, (now() - '02:00:00'::interval)) AS max_success_call_time,
    COALESCE(missed.cnt, (0)::bigint) AS missed_calls,
    COALESCE((missed.max_data)::timestamp with time zone, (now() - '02:00:00'::interval)) AS max_missed_call_time
   FROM ((call_center.cc_agent a
     LEFT JOIN ( SELECT l.agent_id,
            count(*) AS success_calls,
            max(l.created_at) AS max_data
           FROM call_center.cc_member_attempt_log l
          WHERE ((l.created_at > (now() - '02:00:00'::interval)) AND (l.agent_id IS NOT NULL))
          GROUP BY l.agent_id) calls ON ((calls.agent_id = a.id)))
     LEFT JOIN ( SELECT m.agent_id,
            count(*) AS cnt,
            max(m.created_at) AS max_data
           FROM call_center.cc_agent_missed_attempt m
          WHERE (m.created_at > (now() - '02:00:00'::interval))
          GROUP BY m.agent_id) missed ON ((missed.agent_id = a.id)))
  WITH NO DATA;


--
-- Name: cc_agent_last_2hour_calls; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_agent_last_2hour_calls AS
 SELECT a.id AS agent_id,
    (a.success_calls + n.cnt) AS success_calls,
    (a.missed_calls + m.cnt) AS missed_calls
   FROM ((call_center.cc_agent_last_2hour_calls_mat a
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt
           FROM call_center.cc_member_attempt_log l
          WHERE ((l.created_at > a.max_success_call_time) AND (l.agent_id = a.id))) n ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt
           FROM call_center.cc_agent_missed_attempt l
          WHERE ((l.created_at > a.max_missed_call_time) AND (l.agent_id = a.id))) m ON (true));


--
-- Name: cc_agent_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_agent_list AS
 SELECT a.domain_id,
    a.id,
    (COALESCE(((ct.name)::character varying)::name, ct.username))::character varying AS name,
    a.status,
    a.description,
    ((date_part('epoch'::text, a.last_state_change) * (1000)::double precision))::bigint AS last_status_change,
    (date_part('epoch'::text, (now() - a.last_state_change)))::bigint AS status_duration,
    a.progressive_count,
    ch.x AS channels,
    (json_build_object('id', ct.id, 'name', COALESCE(((ct.name)::character varying)::name, ct.username)))::jsonb AS "user"
   FROM ((call_center.cc_agent a
     LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
     LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('channel', c.channel, 'online', c.online, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint)) AS x
           FROM call_center.cc_agent_channel c
          WHERE (c.agent_id = a.id)) ch ON (true));


--
-- Name: cc_agent_missed_attempt_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_agent_missed_attempt_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_agent_missed_attempt_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_agent_missed_attempt_id_seq OWNED BY call_center.cc_agent_missed_attempt.id;


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
    grantor bigint NOT NULL
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
    bucket_id integer NOT NULL
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
-- Name: cc_member; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_member (
    id integer NOT NULL,
    queue_id integer NOT NULL,
    priority smallint DEFAULT 0 NOT NULL,
    expire_at bigint,
    variables jsonb DEFAULT '{}'::jsonb,
    name character varying(50) DEFAULT ''::character varying NOT NULL,
    stop_cause character varying(50),
    stop_at bigint DEFAULT 0 NOT NULL,
    last_hangup_at bigint DEFAULT 0 NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    agent_id bigint,
    communications jsonb NOT NULL,
    bucket_id bigint,
    timezone_id integer,
    last_agent integer,
    sys_offset_id smallint,
    min_offering_at bigint DEFAULT 0 NOT NULL,
    created_at bigint DEFAULT ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint,
    domain_id bigint NOT NULL,
    skill_id integer,
    ready_at timestamp with time zone DEFAULT now() NOT NULL,
    last_attempt_id bigint,
    sys_destinations call_center.cc_destination[],
    pause_at timestamp with time zone
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_vacuum_cost_delay='20', autovacuum_enabled='1', autovacuum_analyze_threshold='2000');
ALTER TABLE ONLY call_center.cc_member ALTER COLUMN communications SET STATISTICS 100;


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
    result character varying(25) NOT NULL,
    agent_id integer,
    bucket_id bigint,
    destination jsonb,
    display character varying(50),
    description character varying,
    list_communication_id bigint,
    joined_at timestamp with time zone,
    leaving_at timestamp with time zone,
    agent_call_id character varying,
    member_call_id character varying,
    offering_at timestamp with time zone,
    reporting_at timestamp with time zone,
    bridged_at timestamp with time zone,
    channel character varying,
    domain_id bigint NOT NULL
);


--
-- Name: COLUMN cc_member_attempt_history.result; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON COLUMN call_center.cc_member_attempt_history.result IS 'fixme';


--
-- Name: cc_queue; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue (
    id integer NOT NULL,
    strategy character varying(20) NOT NULL,
    enabled boolean NOT NULL,
    payload jsonb,
    calendar_id integer NOT NULL,
    priority integer DEFAULT 0 NOT NULL,
    max_calls integer DEFAULT 0 NOT NULL,
    sec_between_retries integer DEFAULT 10 NOT NULL,
    updated_at bigint DEFAULT ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint NOT NULL,
    name character varying(50) NOT NULL,
    max_of_retry smallint DEFAULT 0 NOT NULL,
    variables jsonb DEFAULT '{}'::jsonb NOT NULL,
    timeout integer DEFAULT 60 NOT NULL,
    domain_id bigint NOT NULL,
    dnc_list_id bigint,
    sec_locate_agent integer DEFAULT 5 NOT NULL,
    type smallint DEFAULT 1 NOT NULL,
    team_id bigint,
    created_at bigint NOT NULL,
    created_by bigint NOT NULL,
    updated_by bigint NOT NULL,
    schema_id integer,
    callback_timeout integer DEFAULT 0 NOT NULL,
    description character varying DEFAULT ''::character varying,
    ringtone_id integer,
    distribute_schema_id integer
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
    busy_delay_time smallint DEFAULT 0 NOT NULL,
    no_answer_delay_time smallint DEFAULT 0 NOT NULL,
    call_timeout smallint DEFAULT 0 NOT NULL,
    updated_at bigint DEFAULT 0 NOT NULL,
    created_at bigint,
    created_by bigint,
    updated_by bigint,
    post_processing boolean DEFAULT false NOT NULL
);


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
    json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number', COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying), 'name', COALESCE(c.to_name, ''::character varying)) AS "to",
        CASE
            WHEN (c.payload IS NULL) THEN '{}'::jsonb
            ELSE c.payload
        END AS variables,
    c.created_at,
    c.answered_at,
    c.bridged_at,
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
    call_center.cc_get_lookup((ca.id)::bigint, ca.name) AS agent,
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
    c.team_id,
    c.user_id,
    c.queue_id,
    c.member_id,
    c.attempt_id,
    c.domain_id,
    c.gateway_id,
    c.from_number,
    c.to_number,
    cma.display
   FROM (((((((call_center.cc_calls c
     LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
     LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
     LEFT JOIN call_center.cc_agent_list ca ON ((c.agent_id = ca.id)))
     LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
     LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)));


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
    created_by bigint NOT NULL,
    updated_at bigint NOT NULL,
    updated_by bigint NOT NULL
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
-- Name: cc_calls_all_a; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_calls_all_a AS
 WITH RECURSIVE a AS (
         SELECT c_1.id,
            c_1.parent_id,
            '+'::text AS c,
            row_number() OVER (ORDER BY c_1.created_at DESC) AS rn
           FROM call_center.cc_calls c_1
          WHERE (c_1.parent_id IS NULL)
        UNION ALL
         SELECT c2.id,
            c2.parent_id,
            ' '::text AS text,
            a_1.rn
           FROM (call_center.cc_calls c2
             JOIN a a_1 ON (((c2.parent_id)::text = (a_1.id)::text)))
        )
 SELECT a.rn,
    a.c,
    call_center.cc_view_timestamp(c.created_at) AS created_at,
    c.state,
    c.direction,
    c.destination,
    to_char((now() - c.created_at), 'MM:SS'::text) AS duration,
    c.from_name,
    c.from_number,
    c.to_name,
    c.to_number,
        CASE cch.direction
            WHEN 'inbound'::text THEN cch.to_name
            ELSE cch.from_name
        END AS br
   FROM ((a
     JOIN call_center.cc_calls c ON (((c.id)::text = (a.id)::text)))
     LEFT JOIN call_center.cc_calls cch ON (((c.bridged_id)::text = (cch.id)::text)))
  ORDER BY a.rn, a.c DESC;


--
-- Name: cc_calls_history; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_calls_history (
    id character varying NOT NULL,
    direction character varying,
    destination character varying,
    parent_id character varying,
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
    bridged_id character varying,
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
    transfer_from character varying,
    transfer_to character varying,
    amd_result character varying,
    amd_duration interval
);


--
-- Name: cc_calls_history_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_calls_history_list AS
 SELECT c.id,
    c.app_id,
    'call'::character varying AS type,
    c.parent_id,
    c.transfer_from,
    c.transfer_to,
    call_center.cc_get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS "user",
    u.extension,
    call_center.cc_get_lookup(gw.id, gw.name) AS gateway,
    c.direction,
    c.destination,
    json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number', COALESCE(c.from_number, ''::character varying), 'id', COALESCE(c.from_id, ''::character varying), 'name', COALESCE(c.from_name, ''::character varying)) AS "from",
    json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number', COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying), 'name', COALESCE(c.to_name, ''::character varying)) AS "to",
        CASE
            WHEN (c.payload IS NULL) THEN '{}'::jsonb
            ELSE c.payload
        END AS variables,
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
    call_center.cc_get_lookup((ca.id)::bigint, ca.name) AS agent,
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
          WHERE ((c.parent_id IS NULL) AND ((hp.parent_id)::text = (c.id)::text)))) AS has_children
   FROM ((((((((call_center.cc_calls_history c
     LEFT JOIN LATERAL ( SELECT json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type)) AS files
           FROM storage.files f_1
          WHERE ((f_1.domain_id = c.domain_id) AND ((f_1.uuid)::text = (c.id)::text))) f ON (true))
     LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
     LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
     LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
     LEFT JOIN call_center.cc_member_attempt_history cma ON (((cma.member_call_id)::text = (c.id)::text)))
     LEFT JOIN call_center.cc_agent_list ca ON ((cma.agent_id = ca.id)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)));


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
    code character varying(10) NOT NULL,
    type character varying(5),
    domain_id bigint,
    description character varying(200) DEFAULT ''::character varying
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
-- Name: cc_email; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_email (
    id bigint NOT NULL,
    "from" character varying[] NOT NULL,
    "to" character varying[],
    profile_id integer NOT NULL,
    subject character varying,
    cc character varying[],
    body bytea,
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
    flow_id integer
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
    host character varying,
    mailbox character varying,
    imap_port integer,
    smtp_port integer,
    login character varying,
    password character varying,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by bigint NOT NULL,
    updated_by bigint NOT NULL
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
    t.name,
    t.host,
    t.login,
    t.mailbox,
    t.smtp_port,
    t.imap_port,
    call_center.cc_get_lookup((t.flow_id)::bigint, s.name) AS schema,
    t.description,
    t.enabled
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
-- Name: cc_list_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_list_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    object bigint NOT NULL,
    grantor bigint NOT NULL,
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
    number character varying(25) NOT NULL,
    id bigint NOT NULL,
    description text
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
-- Name: cc_list_statistics; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_list_statistics (
    list_id integer NOT NULL,
    count integer DEFAULT 0 NOT NULL
);


--
-- Name: cc_member_attempt_log_day_5min; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_member_attempt_log_day_5min AS
 SELECT l.queue_id,
    l.bucket_id,
    (date_trunc('minute'::text, l.created_at) - ((((date_part('minute'::text, l.created_at))::integer % 5))::double precision * '00:01:00'::interval)) AS trunc_5_minute,
    count(*) AS count,
    count(*) FILTER (WHERE ((l.result)::text = 'SUCCESS'::text)) AS success_count,
    max(l.created_at) AS max,
    avg(((l.hangup_at - l.bridged_at) / 1000)) FILTER (WHERE (l.bridged_at > 0)) AS avg_bill_sec
   FROM call_center.cc_member_attempt_log l
  WHERE (date(l.created_at) = date(now()))
  GROUP BY l.queue_id, l.bucket_id, (date_trunc('minute'::text, l.created_at) - ((((date_part('minute'::text, l.created_at))::integer % 5))::double precision * '00:01:00'::interval))
  ORDER BY (date_trunc('minute'::text, l.created_at) - ((((date_part('minute'::text, l.created_at))::integer % 5))::double precision * '00:01:00'::interval))
  WITH NO DATA;


--
-- Name: cc_member_attempt_log_day; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_member_attempt_log_day AS
 SELECT t.queue_id,
    t.bucket_id,
    (t.count + (COALESCE(g.count, (0)::bigint))::numeric) AS count,
    (t.success_count + (COALESCE(g.success_count, (0)::bigint))::numeric) AS success_count,
    (COALESCE(t.avg_bill_sec, (0)::numeric) + COALESCE(g.avg_bill_sec, (0)::numeric)) AS avg_bill_sec
   FROM (( SELECT q.queue_id,
            q.bucket_id,
            sum(q.count) AS count,
            sum(q.success_count) AS success_count,
            max(q.max) AS max,
            avg(q.avg_bill_sec) AS avg_bill_sec
           FROM call_center.cc_member_attempt_log_day_5min q
          GROUP BY q.queue_id, q.bucket_id) t
     LEFT JOIN LATERAL ( SELECT l.queue_id,
            l.bucket_id,
            count(*) AS count,
            count(*) FILTER (WHERE ((l.result)::text = 'SUCCESSFUL'::text)) AS success_count,
            max(l.created_at) AS max,
            avg(((l.hangup_at - l.bridged_at) / 1000)) FILTER (WHERE (l.bridged_at > 0)) AS avg_bill_sec
           FROM call_center.cc_member_attempt_log l
          WHERE ((l.created_at > (CURRENT_DATE - '1 day'::interval)) AND (l.created_at > t.max) AND (COALESCE(l.bucket_id, (0)::bigint) = COALESCE(t.bucket_id, (0)::bigint)) AND (l.queue_id = t.queue_id))
          GROUP BY l.queue_id, l.bucket_id
          ORDER BY l.queue_id, COALESCE(l.bucket_id, (0)::bigint)) g ON (true));


--
-- Name: cc_member_attempt_log_day_tmp; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_member_attempt_log_day_tmp (
    id bigint,
    queue_id bigint,
    state integer,
    member_id bigint,
    weight integer,
    hangup_at bigint,
    bridged_at bigint,
    resource_id integer,
    leg_a_id character varying(36),
    leg_b_id character varying(36),
    node_id character varying(20),
    result character varying(200),
    originate_at bigint,
    answered_at bigint,
    logs jsonb,
    agent_id bigint,
    bucket_id bigint,
    created_at timestamp without time zone,
    success boolean
);


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
    last_error_at bigint DEFAULT 0,
    created_at bigint NOT NULL,
    created_by bigint NOT NULL,
    updated_by bigint NOT NULL,
    error_ids character varying(50)[] DEFAULT '{}'::character varying[],
    gateway_id bigint,
    email_profile_id integer
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
    cq.domain_id,
    t.queue_id,
    t.bucket_id,
    t.member_id,
    t.agent_id,
    t.joined_at AS joined_at_timestamp
   FROM (((((((call_center.cc_member_attempt t
     JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
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
    t.agent_id
   FROM (((((((call_center.cc_member_attempt_history t
     JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
     LEFT JOIN call_center.cc_member cm ON ((t.member_id = cm.id)))
     LEFT JOIN call_center.cc_agent a ON ((t.agent_id = a.id)))
     LEFT JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (u.dc = a.domain_id))))
     LEFT JOIN call_center.cc_outbound_resource r ON ((r.id = t.resource_id)))
     LEFT JOIN call_center.cc_bucket cb ON ((cb.id = t.bucket_id)))
     LEFT JOIN call_center.cc_list l ON ((l.id = t.list_communication_id)));


--
-- Name: cc_msg_attachment; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_msg_attachment (
    id bigint NOT NULL,
    post_id bigint NOT NULL,
    file_name character varying NOT NULL,
    file_type character varying NOT NULL
);


--
-- Name: cc_msg_attachment_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_msg_attachment_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_msg_attachment_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_msg_attachment_id_seq OWNED BY call_center.cc_msg_attachment.id;


--
-- Name: cc_msg_conversation; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_msg_conversation (
    title character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    domain_id bigint NOT NULL,
    id bigint NOT NULL,
    closed_at timestamp with time zone,
    activity_at timestamp without time zone DEFAULT now() NOT NULL,
    profile_id integer NOT NULL,
    variables jsonb,
    closed_by bigint
);


--
-- Name: cc_msg_conversation_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_msg_conversation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_msg_conversation_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_msg_conversation_id_seq OWNED BY call_center.cc_msg_conversation.id;


--
-- Name: cc_msg_conversation_profile_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_msg_conversation_profile_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_msg_conversation_profile_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_msg_conversation_profile_id_seq OWNED BY call_center.cc_msg_conversation.profile_id;


--
-- Name: cc_msg_participants; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_msg_participants (
    id bigint NOT NULL,
    type_id integer DEFAULT 0 NOT NULL,
    name character varying,
    conversation_id bigint NOT NULL,
    channel_id uuid DEFAULT uuid_generate_v4() NOT NULL,
    activity_at timestamp with time zone DEFAULT now() NOT NULL,
    attempt_id bigint
);


--
-- Name: COLUMN cc_msg_participants.type_id; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON COLUMN call_center.cc_msg_participants.type_id IS 'group/single';


--
-- Name: cc_msg_participants_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_msg_participants_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_msg_participants_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_msg_participants_id_seq OWNED BY call_center.cc_msg_participants.id;


--
-- Name: cc_msg_post; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_msg_post (
    id bigint NOT NULL,
    posted_at timestamp with time zone DEFAULT now() NOT NULL,
    posted_by character varying,
    body jsonb NOT NULL,
    conversation_id bigint NOT NULL,
    schema_idx integer DEFAULT 0 NOT NULL,
    participant_id bigint
);


--
-- Name: cc_msg_post_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_msg_post_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_msg_post_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_msg_post_id_seq OWNED BY call_center.cc_msg_post.id;


--
-- Name: cc_msg_profiles; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_msg_profiles (
    id bigint NOT NULL,
    secret_key character varying NOT NULL,
    domain_id bigint NOT NULL,
    schema_id integer,
    conversation_max_time integer DEFAULT 360 NOT NULL
);


--
-- Name: cc_msg_profiles_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_msg_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_msg_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_msg_profiles_id_seq OWNED BY call_center.cc_msg_profiles.id;


--
-- Name: cc_outbound_resource_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint NOT NULL,
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
    created_by bigint NOT NULL,
    updated_at bigint NOT NULL,
    updated_by bigint NOT NULL,
    "time" jsonb
);


--
-- Name: cc_outbound_resource_group_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource_group_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint NOT NULL,
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
-- Name: cc_outbound_resource_in_group; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_outbound_resource_in_group (
    id bigint NOT NULL,
    resource_id bigint NOT NULL,
    group_id bigint NOT NULL
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
-- Name: cc_queue_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_queue_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint NOT NULL,
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
    bucket_id bigint,
    skill_id integer
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


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
    q.timeout,
    q.domain_id,
    q.sec_locate_agent,
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
    COALESCE(ss.member_count, (0)::bigint) AS count,
    COALESCE(ss.member_waiting, (0)::bigint) AS waiting,
    COALESCE(act.cnt, (0)::bigint) AS active
   FROM (((((((((call_center.cc_queue q
     JOIN flow.calendar c ON ((q.calendar_id = c.id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = q.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = q.updated_by)))
     LEFT JOIN flow.acr_routing_scheme s ON ((q.schema_id = s.id)))
     LEFT JOIN call_center.cc_list cl ON ((q.dnc_list_id = cl.id)))
     LEFT JOIN call_center.cc_team ct ON ((q.team_id = ct.id)))
     LEFT JOIN storage.media_files mf ON ((q.ringtone_id = mf.id)))
     LEFT JOIN LATERAL ( SELECT sum(s_1.member_waiting) AS member_waiting,
            sum(s_1.member_count) AS member_count
           FROM call_center.cc_queue_statistics s_1
          WHERE (s_1.queue_id = q.id)) ss ON (true))
     LEFT JOIN LATERAL ( SELECT count(*) AS cnt
           FROM call_center.cc_member_attempt a
          WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL))) act ON (true));


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
-- Name: cc_skill; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_skill (
    id integer NOT NULL,
    name character varying(20) NOT NULL,
    domain_id bigint NOT NULL,
    description character varying(100) DEFAULT ''::character varying NOT NULL
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
    created_by bigint NOT NULL,
    updated_at bigint NOT NULL,
    updated_by bigint NOT NULL
);


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
-- Name: cc_supervisor_in_team; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_supervisor_in_team (
    id bigint NOT NULL,
    agent_id bigint NOT NULL,
    team_id bigint NOT NULL
);


--
-- Name: cc_supervisor_in_team_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_supervisor_in_team_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_supervisor_in_team_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_supervisor_in_team_id_seq OWNED BY call_center.cc_supervisor_in_team.id;


--
-- Name: cc_sys_agent_group_team_bucket; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_sys_agent_group_team_bucket AS
 WITH ag AS (
         SELECT s.team_id,
            s.bucket_id,
            s.agent_id,
            max(s.lvl) AS lvl,
            max(s.capacity) AS capacity
           FROM ( SELECT aq.team_id,
                    x.x AS bucket_id,
                    sa.agent_id,
                    aq.lvl,
                    sa.capacity
                   FROM ((call_center.cc_agent_in_team aq
                     JOIN call_center.cc_skill_in_agent sa ON ((sa.skill_id = aq.skill_id)))
                     LEFT JOIN LATERAL unnest(aq.bucket_ids) x(x) ON (true))
                  WHERE ((aq.skill_id IS NOT NULL) AND (sa.capacity >= aq.min_capacity) AND (sa.capacity <= aq.max_capacity))
                UNION
                 SELECT aq.team_id,
                    x.x AS bucket_id,
                    aq.agent_id,
                    aq.lvl,
                    0
                   FROM (call_center.cc_agent_in_team aq
                     LEFT JOIN LATERAL unnest(aq.bucket_ids) x(x) ON (true))
                  WHERE (aq.agent_id IS NOT NULL)) s
          GROUP BY s.team_id, s.bucket_id, s.agent_id
        )
 SELECT row_number() OVER (PARTITION BY ag.team_id, ag.bucket_id ORDER BY ag.lvl DESC, ag.capacity DESC, a.last_state_change) AS pos,
    ag.team_id,
    ag.bucket_id,
    ag.agent_id,
    ag.lvl,
    ag.capacity
   FROM (ag
     JOIN call_center.cc_agent a ON ((a.id = ag.agent_id)));


--
-- Name: cc_sys_distribute_queue_bucket_seg; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_sys_distribute_queue_bucket_seg AS
 SELECT s.queue_id,
    s.bucket_id,
    (s.member_waiting)::integer AS member_waiting,
        CASE
            WHEN ((s.bucket_id IS NULL) OR (s.member_waiting < 2)) THEN s.member_waiting
            ELSE (((ceil((((s.member_count * cbiq.ratio) / 100))::double precision))::integer - log.log))::bigint
        END AS lim,
    cbiq.ratio
   FROM ((( SELECT s_1.queue_id,
            s_1.bucket_id,
            sum(s_1.member_waiting) AS member_waiting,
            sum(s_1.member_count) AS member_count
           FROM call_center.cc_queue_statistics s_1
          GROUP BY s_1.queue_id, s_1.bucket_id) s
     LEFT JOIN call_center.cc_bucket_in_queue cbiq ON (((s.queue_id = cbiq.queue_id) AND (s.bucket_id = cbiq.bucket_id))))
     LEFT JOIN LATERAL call_center.cc_member_attempt_log_day_f((s.queue_id)::integer, (s.bucket_id)::integer) log(log) ON ((s.bucket_id IS NOT NULL)))
  WHERE ((s.member_waiting > 0) AND ((
        CASE
            WHEN ((s.bucket_id IS NULL) OR (s.member_waiting < 2)) THEN s.member_waiting
            ELSE (((round((((s.member_count * cbiq.ratio) / 100))::double precision))::integer - COALESCE(log.log, 0)))::bigint
        END)::numeric > (0)::numeric));


--
-- Name: cc_sys_distribute_queue; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_sys_distribute_queue AS
 SELECT q.domain_id,
    q.id,
    q.type,
    q.strategy,
    q.team_id,
    q.calendar_id,
    cqs.bucket_id,
    cqs.lim AS buckets_cnt,
    cqs.ratio
   FROM (call_center.cc_queue q
     JOIN call_center.cc_sys_distribute_queue_bucket_seg cqs ON ((q.id = cqs.queue_id)))
  WHERE (q.enabled AND (cqs.member_waiting > 0) AND (cqs.lim > 0) AND (q.type > 1))
  ORDER BY q.domain_id, q.priority DESC, cqs.ratio DESC NULLS LAST;


--
-- Name: cc_sys_queue_distribute_resources; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_sys_queue_distribute_resources AS
 WITH res AS (
         SELECT cqr.queue_id,
            corg.communication_id,
            cor.id,
            cor."limit",
            call_center.cc_outbound_resource_timing(corg."time") AS t
           FROM (((call_center.cc_queue_resource cqr
             JOIN call_center.cc_outbound_resource_group corg ON ((cqr.resource_group_id = corg.id)))
             JOIN call_center.cc_outbound_resource_in_group corig ON ((corg.id = corig.group_id)))
             JOIN call_center.cc_outbound_resource cor ON ((corig.resource_id = cor.id)))
          WHERE (cor.enabled AND (NOT cor.reserve))
          GROUP BY cqr.queue_id, corg.communication_id, corg."time", cor.id, cor."limit"
        )
 SELECT res.queue_id,
    array_agg(DISTINCT ROW(res.communication_id, (res.id)::bigint, res.t)::call_center.cc_sys_distribute_type) AS types,
    array_agg(DISTINCT ROW((res.id)::bigint, ((res."limit" - ac.count))::integer)::call_center.cc_sys_distribute_resource) AS resources,
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
-- Name: cc_team_acl; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_team_acl (
    id bigint NOT NULL,
    dc bigint NOT NULL,
    grantor bigint NOT NULL,
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
-- Name: cc_agent id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_id_seq'::regclass);


--
-- Name: cc_agent_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_acl_id_seq'::regclass);


--
-- Name: cc_agent_activity id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_activity ALTER COLUMN id SET DEFAULT nextval('call_center.agent_statistic_id_seq'::regclass);


--
-- Name: cc_agent_attempt id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_attempt ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_attempt_id_seq'::regclass);


--
-- Name: cc_agent_in_team id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_in_team ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_in_team_id_seq'::regclass);


--
-- Name: cc_agent_missed_attempt id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_missed_attempt ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_missed_attempt_id_seq'::regclass);


--
-- Name: cc_agent_state_history id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_state_history ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_history_id_seq'::regclass);


--
-- Name: cc_bucket id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket ALTER COLUMN id SET DEFAULT nextval('call_center.cc_bucket_id_seq'::regclass);


--
-- Name: cc_bucket_in_queue id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_in_queue ALTER COLUMN id SET DEFAULT nextval('call_center.cc_bucket_in_queue_id_seq'::regclass);


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
-- Name: cc_member_messages id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_messages ALTER COLUMN id SET DEFAULT nextval('call_center.cc_member_messages_id_seq'::regclass);


--
-- Name: cc_msg_attachment id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_attachment ALTER COLUMN id SET DEFAULT nextval('call_center.cc_msg_attachment_id_seq'::regclass);


--
-- Name: cc_msg_conversation id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_conversation ALTER COLUMN id SET DEFAULT nextval('call_center.cc_msg_conversation_id_seq'::regclass);


--
-- Name: cc_msg_conversation profile_id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_conversation ALTER COLUMN profile_id SET DEFAULT nextval('call_center.cc_msg_conversation_profile_id_seq'::regclass);


--
-- Name: cc_msg_participants id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_participants ALTER COLUMN id SET DEFAULT nextval('call_center.cc_msg_participants_id_seq'::regclass);


--
-- Name: cc_msg_post id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_post ALTER COLUMN id SET DEFAULT nextval('call_center.cc_msg_post_id_seq'::regclass);


--
-- Name: cc_msg_profiles id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_profiles ALTER COLUMN id SET DEFAULT nextval('call_center.cc_msg_profiles_id_seq'::regclass);


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
-- Name: cc_queue id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_id_seq'::regclass);


--
-- Name: cc_queue_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_acl_id_seq'::regclass);


--
-- Name: cc_queue_resource id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_resource ALTER COLUMN id SET DEFAULT nextval('call_center.cc_queue_resource_id_seq1'::regclass);


--
-- Name: cc_skill id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill ALTER COLUMN id SET DEFAULT nextval('call_center.cc_skils_id_seq'::regclass);


--
-- Name: cc_skill_in_agent id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_in_agent ALTER COLUMN id SET DEFAULT nextval('call_center.cc_skill_in_agent_id_seq'::regclass);


--
-- Name: cc_supervisor_in_team id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_supervisor_in_team ALTER COLUMN id SET DEFAULT nextval('call_center.cc_supervisor_in_team_id_seq'::regclass);


--
-- Name: cc_team id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team ALTER COLUMN id SET DEFAULT nextval('call_center.cc_team_id_seq'::regclass);


--
-- Name: cc_team_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_team_acl_id_seq'::regclass);


--
-- Name: cc_agent_activity agent_statistic_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_activity
    ADD CONSTRAINT agent_statistic_pk PRIMARY KEY (id);


--
-- Name: cc_agent_acl cc_agent_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_pk PRIMARY KEY (id);


--
-- Name: cc_agent_attempt cc_agent_attempt_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_attempt
    ADD CONSTRAINT cc_agent_attempt_pk PRIMARY KEY (id);


--
-- Name: cc_agent_channel cc_agent_channels_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_channel
    ADD CONSTRAINT cc_agent_channels_pk PRIMARY KEY (agent_id, channel);


--
-- Name: cc_agent_in_team cc_agent_in_team_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_in_team
    ADD CONSTRAINT cc_agent_in_team_pk PRIMARY KEY (id);


--
-- Name: cc_agent_missed_attempt cc_agent_missed_attempt_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_missed_attempt
    ADD CONSTRAINT cc_agent_missed_attempt_pk PRIMARY KEY (id);


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
-- Name: cc_list cc_call_list_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list
    ADD CONSTRAINT cc_call_list_pk PRIMARY KEY (id);


--
-- Name: cc_calls_history cc_calls_history_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_history
    ADD CONSTRAINT cc_calls_history_pk PRIMARY KEY (domain_id, id);


--
-- Name: cc_calls cc_calls_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls
    ADD CONSTRAINT cc_calls_pk UNIQUE (id);


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
-- Name: cc_member_attempt_log cc_member_attempt_log_pkey; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt_log
    ADD CONSTRAINT cc_member_attempt_log_pkey PRIMARY KEY (id);


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
-- Name: cc_msg_attachment cc_msg_attachment_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_attachment
    ADD CONSTRAINT cc_msg_attachment_pk PRIMARY KEY (id);


--
-- Name: cc_msg_conversation cc_msg_conversation_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_conversation
    ADD CONSTRAINT cc_msg_conversation_pk PRIMARY KEY (id);


--
-- Name: cc_msg_participants cc_msg_participants_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_participants
    ADD CONSTRAINT cc_msg_participants_pk PRIMARY KEY (id);


--
-- Name: cc_msg_post cc_msg_post_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_post
    ADD CONSTRAINT cc_msg_post_pk PRIMARY KEY (id);


--
-- Name: cc_msg_profiles cc_msg_profiles_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_profiles
    ADD CONSTRAINT cc_msg_profiles_pk PRIMARY KEY (id);


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
-- Name: cc_queue_acl cc_queue_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_acl
    ADD CONSTRAINT cc_queue_acl_pk PRIMARY KEY (id);


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
-- Name: cc_queue_statistics cc_queue_statistics_pk_queue_id_bucket_id_skill_id; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue_statistics
    ADD CONSTRAINT cc_queue_statistics_pk_queue_id_bucket_id_skill_id UNIQUE (queue_id, bucket_id, skill_id);


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
-- Name: cc_supervisor_in_team cc_supervisor_in_team_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_supervisor_in_team
    ADD CONSTRAINT cc_supervisor_in_team_pk PRIMARY KEY (id);


--
-- Name: cc_team_acl cc_team_acl_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team_acl
    ADD CONSTRAINT cc_team_acl_pk PRIMARY KEY (id);


--
-- Name: cc_team cc_team_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_pk PRIMARY KEY (id);


--
-- Name: agent_statistic_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX agent_statistic_id_uindex ON call_center.cc_agent_activity USING btree (id);


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
-- Name: cc_agent_activity_agent_id_last_offering_call_at_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_activity_agent_id_last_offering_call_at_uindex ON call_center.cc_agent_activity USING btree (agent_id, last_offering_call_at);


--
-- Name: cc_agent_attempt_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_attempt_id_uindex ON call_center.cc_agent_attempt USING btree (id);


--
-- Name: cc_agent_channel_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_channel_agent_id_index ON call_center.cc_agent_channel USING btree (agent_id);


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
-- Name: cc_agent_in_team_agent_id_team_id_lvl_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_in_team_agent_id_team_id_lvl_uindex ON call_center.cc_agent_in_team USING btree (agent_id, team_id, lvl DESC);


--
-- Name: cc_agent_in_team_skill_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_in_team_skill_id_index ON call_center.cc_agent_in_team USING btree (skill_id);


--
-- Name: cc_agent_in_team_skill_id_team_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_in_team_skill_id_team_id_uindex ON call_center.cc_agent_in_team USING btree (skill_id, team_id);


--
-- Name: cc_agent_in_team_team_id_agent_id_skill_id_lvl_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_in_team_team_id_agent_id_skill_id_lvl_uindex ON call_center.cc_agent_in_team USING btree (team_id, agent_id, skill_id, lvl DESC);


--
-- Name: cc_agent_in_team_team_id_lvl_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_in_team_team_id_lvl_index ON call_center.cc_agent_in_team USING btree (team_id, lvl DESC);


--
-- Name: cc_agent_last_2hour_calls_mat_agent_id_adx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_last_2hour_calls_mat_agent_id_adx ON call_center.cc_agent_last_2hour_calls_mat USING btree (id);


--
-- Name: cc_agent_missed_attempt_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_missed_attempt_agent_id_index ON call_center.cc_agent_missed_attempt USING btree (agent_id);


--
-- Name: cc_agent_missed_attempt_attempt_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_missed_attempt_attempt_id_index ON call_center.cc_agent_missed_attempt USING btree (attempt_id);


--
-- Name: cc_agent_missed_attempt_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_missed_attempt_id_uindex ON call_center.cc_agent_missed_attempt USING btree (id);


--
-- Name: cc_agent_state_history_joined_at_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_state_history_joined_at_agent_id_index ON call_center.cc_agent_state_history USING btree (channel, joined_at DESC, agent_id, state DESC) INCLUDE (duration);


--
-- Name: cc_agent_state_history_joined_at_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_state_history_joined_at_idx ON call_center.cc_agent_state_history USING btree (joined_at DESC, agent_id DESC) INCLUDE (state, duration);


--
-- Name: cc_agent_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_updated_by_index ON call_center.cc_agent USING btree (updated_by);


--
-- Name: cc_agent_user_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_user_id_uindex ON call_center.cc_agent USING btree (user_id);


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
-- Name: cc_bucket_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_bucket_domain_id_name_uindex ON call_center.cc_bucket USING btree (domain_id, name);


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
-- Name: cc_calls_history_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_agent_id_index ON call_center.cc_calls_history USING btree (agent_id);


--
-- Name: cc_calls_history_attempt_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_attempt_id_index ON call_center.cc_calls_history USING btree (attempt_id DESC NULLS LAST);


--
-- Name: cc_calls_history_destination_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_destination_idx ON call_center.cc_calls_history USING gin (domain_id, destination gin_trgm_ops);


--
-- Name: cc_calls_history_dev_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_dev_idx ON call_center.cc_calls_history USING btree (hangup_at DESC, parent_id);


--
-- Name: cc_calls_history_domain_id_created_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_domain_id_created_at_index ON call_center.cc_calls_history USING btree (domain_id, created_at DESC);


--
-- Name: cc_calls_history_domain_id_store_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_domain_id_store_at_index ON call_center.cc_calls_history USING btree (domain_id, stored_at DESC);


--
-- Name: cc_calls_history_from_number_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_from_number_idx ON call_center.cc_calls_history USING gin (domain_id, from_number gin_trgm_ops);


--
-- Name: cc_calls_history_member_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_member_id_index ON call_center.cc_calls_history USING btree (member_id);


--
-- Name: cc_calls_history_parent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_parent_id_index ON call_center.cc_calls_history USING btree (parent_id);


--
-- Name: cc_calls_history_queue_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_queue_id_index ON call_center.cc_calls_history USING btree (queue_id);


--
-- Name: cc_calls_history_team_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_team_id_index ON call_center.cc_calls_history USING btree (team_id);


--
-- Name: cc_calls_history_to_number_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_to_number_idx ON call_center.cc_calls_history USING gin (domain_id, to_number gin_trgm_ops);


--
-- Name: cc_calls_history_user_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_calls_history_user_id_index ON call_center.cc_calls_history USING btree (user_id);


--
-- Name: cc_cluster_node_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_cluster_node_name_uindex ON call_center.cc_cluster USING btree (node_name);


--
-- Name: cc_communication_code_domain_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_communication_code_domain_id_uindex ON call_center.cc_communication USING btree (code, domain_id);


--
-- Name: cc_communication_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_communication_domain_id_index ON call_center.cc_communication USING btree (domain_id);


--
-- Name: cc_email_profile_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_email_profile_domain_id_index ON call_center.cc_email_profile USING btree (domain_id);


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
-- Name: cc_list_communications_list_id_number_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_list_communications_list_id_number_uindex ON call_center.cc_list_communications USING btree (list_id, number);


--
-- Name: cc_list_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_list_created_by_index ON call_center.cc_list USING btree (created_by);


--
-- Name: cc_list_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_list_domain_id_index ON call_center.cc_list USING btree (domain_id);


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
-- Name: cc_member_attempt_history_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_agent_id_index ON call_center.cc_member_attempt_history USING btree (agent_id);


--
-- Name: cc_member_attempt_history_domain_id_joined_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_domain_id_joined_at_index ON call_center.cc_member_attempt_history USING btree (domain_id, joined_at DESC);


--
-- Name: cc_member_attempt_history_member_call_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_member_call_id_index ON call_center.cc_member_attempt_history USING btree (member_call_id);


--
-- Name: cc_member_attempt_history_member_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_member_id_index ON call_center.cc_member_attempt_history USING btree (member_id);


--
-- Name: cc_member_attempt_history_queue_id_leaving_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_queue_id_leaving_at_index ON call_center.cc_member_attempt_history USING btree (queue_id, leaving_at DESC);


--
-- Name: cc_member_attempt_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_member_attempt_id_uindex ON call_center.cc_member_attempt USING btree (id);


--
-- Name: cc_member_attempt_log_created_at_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_log_created_at_agent_id_index ON call_center.cc_member_attempt_log USING btree (created_at DESC, agent_id) WHERE (agent_id IS NOT NULL);


--
-- Name: cc_member_attempt_log_created_at_agent_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_member_attempt_log_created_at_agent_id_uindex ON call_center.cc_member_attempt_log USING btree (created_at DESC, agent_id);


--
-- Name: cc_member_attempt_log_created_at_queue_id_bucket_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_log_created_at_queue_id_bucket_id_index ON call_center.cc_member_attempt_log USING btree (queue_id, COALESCE(bucket_id, (0)::bigint), created_at DESC);


--
-- Name: cc_member_attempt_log_hangup_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_log_hangup_at_index ON call_center.cc_member_attempt_log USING btree (hangup_at DESC);


--
-- Name: cc_member_attempt_log_member_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_log_member_id_index ON call_center.cc_member_attempt_log USING btree (member_id);


--
-- Name: cc_member_attempt_log_queue_id_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_log_queue_id_idx ON call_center.cc_member_attempt_log USING btree (queue_id);


--
-- Name: cc_member_attempt_member_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_member_id_index ON call_center.cc_member_attempt USING btree (member_id);


--
-- Name: cc_member_attempt_queue_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_queue_id_index ON call_center.cc_member_attempt USING btree (queue_id);


--
-- Name: cc_member_dis_fifo_dev; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_dis_fifo_dev ON call_center.cc_member USING btree (queue_id, bucket_id, last_hangup_at, priority DESC) WHERE (stop_at = 0);


--
-- Name: cc_member_distribute_check_sys_offset_id; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_distribute_check_sys_offset_id ON call_center.cc_member USING btree (queue_id, bucket_id, sys_offset_id);


--
-- Name: cc_member_messages_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_member_messages_id_uindex ON call_center.cc_member_messages USING btree (id);


--
-- Name: cc_member_queue_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_queue_id_index ON call_center.cc_member USING btree (queue_id);


--
-- Name: cc_member_search_destination_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_search_destination_idx ON call_center.cc_member USING gin (domain_id, communications jsonb_path_ops);


--
-- Name: cc_member_sens_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_sens_idx ON call_center.cc_member USING btree (queue_id, bucket_id, skill_id) WHERE (stop_at = 0);


--
-- Name: cc_msg_conversation_activity_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_msg_conversation_activity_at_index ON call_center.cc_msg_conversation USING btree (activity_at DESC);


--
-- Name: cc_msg_conversation_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_msg_conversation_domain_id_index ON call_center.cc_msg_conversation USING btree (domain_id);


--
-- Name: cc_msg_participants_channel_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_msg_participants_channel_id_uindex ON call_center.cc_msg_participants USING btree (channel_id);


--
-- Name: cc_msg_participants_conversation_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_msg_participants_conversation_id_index ON call_center.cc_msg_participants USING btree (conversation_id);


--
-- Name: cc_msg_post_conversation_id_posted_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_msg_post_conversation_id_posted_at_index ON call_center.cc_msg_post USING btree (conversation_id, posted_at DESC);


--
-- Name: cc_msg_profiles_secret_key_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_msg_profiles_secret_key_uindex ON call_center.cc_msg_profiles USING btree (secret_key);


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
-- Name: cc_outbound_resource_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_domain_udx ON call_center.cc_outbound_resource USING btree (id, domain_id);


--
-- Name: cc_outbound_resource_gateway_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_gateway_id_uindex ON call_center.cc_outbound_resource USING btree (gateway_id);


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
-- Name: cc_outbound_resource_in_group_resource_id_group_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_in_group_resource_id_group_id_uindex ON call_center.cc_outbound_resource_in_group USING btree (resource_id, group_id);


--
-- Name: cc_outbound_resource_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_outbound_resource_updated_by_index ON call_center.cc_outbound_resource USING btree (updated_by);


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
-- Name: cc_queue_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_domain_udx ON call_center.cc_queue USING btree (id, domain_id);


--
-- Name: cc_queue_enabled_priority_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_enabled_priority_index ON call_center.cc_queue USING btree (enabled, priority DESC);


--
-- Name: cc_queue_id_priority_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_id_priority_uindex ON call_center.cc_queue USING btree (priority, sec_locate_agent, updated_at);


--
-- Name: cc_queue_resource_queue_id_resource_group_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_resource_queue_id_resource_group_id_uindex ON call_center.cc_queue_resource USING btree (queue_id, resource_group_id);


--
-- Name: cc_queue_resource_resource_group_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_resource_resource_group_id_index ON call_center.cc_queue_resource USING btree (resource_group_id);


--
-- Name: cc_queue_statistics_queue_id_bucket_id_skill_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_statistics_queue_id_bucket_id_skill_id_uindex ON call_center.cc_queue_statistics USING btree (queue_id, COALESCE(bucket_id, (0)::bigint), COALESCE(skill_id, 0));


--
-- Name: cc_skill_domain_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_domain_id_index ON call_center.cc_skill USING btree (domain_id);


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

CREATE UNIQUE INDEX cc_skill_in_agent_skill_id_agent_id_capacity_uindex ON call_center.cc_skill_in_agent USING btree (skill_id, agent_id, capacity DESC);


--
-- Name: cc_skill_in_agent_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_skill_in_agent_updated_by_index ON call_center.cc_skill_in_agent USING btree (updated_by);


--
-- Name: cc_supervisor_in_team_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_supervisor_in_team_agent_id_index ON call_center.cc_supervisor_in_team USING btree (agent_id);


--
-- Name: cc_supervisor_in_team_team_id_agent_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_supervisor_in_team_team_id_agent_id_uindex ON call_center.cc_supervisor_in_team USING btree (team_id, agent_id);


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
-- Name: cc_team_created_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_created_by_index ON call_center.cc_team USING btree (created_by);


--
-- Name: cc_team_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_domain_id_name_uindex ON call_center.cc_team USING btree (domain_id, name);


--
-- Name: cc_team_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_team_domain_udx ON call_center.cc_team USING btree (id, domain_id);


--
-- Name: cc_team_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_updated_by_index ON call_center.cc_team USING btree (updated_by);


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
-- Name: cc_agent cc_agent_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_agent_set_rbac_acl AFTER INSERT ON call_center.cc_agent FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_rbac_rec('cc_agent_acl');


--
-- Name: cc_bucket cc_bucket_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_bucket_set_rbac_acl AFTER INSERT ON call_center.cc_bucket FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_rbac_rec('cc_bucket_acl');


--
-- Name: cc_calls cc_calls_set_timing_trigger_updated; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_calls_set_timing_trigger_updated BEFORE INSERT OR UPDATE ON call_center.cc_calls FOR EACH ROW EXECUTE FUNCTION call_center.cc_calls_set_timing();


--
-- Name: cc_list cc_list_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_list_set_rbac_acl AFTER INSERT ON call_center.cc_list FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_rbac_rec('cc_list_acl');


--
-- Name: cc_member_attempt cc_member_attempt_dev_tg; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_attempt_dev_tg AFTER DELETE ON call_center.cc_member_attempt FOR EACH ROW EXECUTE FUNCTION call_center.cc_member_attempt_dev_tgf();


--
-- Name: cc_member cc_member_set_sys_destinations_insert; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_set_sys_destinations_insert BEFORE INSERT ON call_center.cc_member FOR EACH ROW EXECUTE FUNCTION call_center.cc_member_set_sys_destinations_tg();


--
-- Name: cc_member cc_member_set_sys_destinations_update; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_member_set_sys_destinations_update BEFORE UPDATE ON call_center.cc_member FOR EACH ROW WHEN ((new.communications <> old.communications)) EXECUTE FUNCTION call_center.cc_member_set_sys_destinations_tg();


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
-- Name: cc_outbound_resource_group cc_outbound_resource_group_resource_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_outbound_resource_group_resource_set_rbac_acl AFTER INSERT ON call_center.cc_outbound_resource_group FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_rbac_rec('cc_outbound_resource_group_acl');


--
-- Name: cc_outbound_resource cc_outbound_resource_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_outbound_resource_set_rbac_acl AFTER INSERT ON call_center.cc_outbound_resource FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_rbac_rec('cc_outbound_resource_acl');


--
-- Name: cc_queue cc_queue_resource_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_queue_resource_set_rbac_acl AFTER INSERT ON call_center.cc_queue FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_rbac_rec('cc_queue_acl');


--
-- Name: cc_team cc_team_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_team_set_rbac_acl AFTER INSERT ON call_center.cc_team FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_rbac_rec('cc_team_acl');


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
-- Name: cc_agent_channel tg_cc_set_agent_channel_change_status_i; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER tg_cc_set_agent_channel_change_status_i AFTER INSERT ON call_center.cc_agent_channel FOR EACH ROW EXECUTE FUNCTION call_center.cc_set_agent_channel_change_status();


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
    ADD CONSTRAINT cc_agent_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


--
-- Name: cc_agent_acl cc_agent_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_agent_acl cc_agent_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_agent(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


--
-- Name: cc_agent_acl cc_agent_acl_subject_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl
    ADD CONSTRAINT cc_agent_acl_subject_fk FOREIGN KEY (subject, dc) REFERENCES directory.wbt_auth(id, dc) ON DELETE CASCADE;


--
-- Name: cc_agent_attempt cc_agent_attempt_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_attempt
    ADD CONSTRAINT cc_agent_attempt_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_channel cc_agent_channels_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_channel
    ADD CONSTRAINT cc_agent_channels_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_in_team cc_agent_in_team_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_in_team
    ADD CONSTRAINT cc_agent_in_team_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_in_team cc_agent_in_team_cc_skils_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_in_team
    ADD CONSTRAINT cc_agent_in_team_cc_skils_id_fk FOREIGN KEY (skill_id) REFERENCES call_center.cc_skill(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_in_team cc_agent_in_team_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_in_team
    ADD CONSTRAINT cc_agent_in_team_cc_team_id_fk FOREIGN KEY (team_id) REFERENCES call_center.cc_team(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_activity cc_agent_statistic_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_activity
    ADD CONSTRAINT cc_agent_statistic_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_agent_state_history cc_agent_status_history_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_state_history
    ADD CONSTRAINT cc_agent_status_history_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
    ADD CONSTRAINT cc_agent_wbt_user_id_fk_2 FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_agent cc_agent_wbt_user_id_fk_3; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_wbt_user_id_fk_3 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


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
    ADD CONSTRAINT cc_bucket_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


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
    ADD CONSTRAINT cc_bucket_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_bucket cc_bucket_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket
    ADD CONSTRAINT cc_bucket_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_calls_history cc_calls_history_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_history
    ADD CONSTRAINT cc_calls_history_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_calls_history cc_calls_history_cc_member_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_history
    ADD CONSTRAINT cc_calls_history_cc_member_id_fk FOREIGN KEY (member_id) REFERENCES call_center.cc_member(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_calls_history cc_calls_history_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_history
    ADD CONSTRAINT cc_calls_history_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE SET NULL ON DELETE SET NULL;


--
-- Name: cc_calls_history cc_calls_history_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls_history
    ADD CONSTRAINT cc_calls_history_cc_team_id_fk FOREIGN KEY (team_id) REFERENCES call_center.cc_team(id) ON UPDATE SET NULL ON DELETE SET NULL;


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
    ADD CONSTRAINT cc_email_cc_email_profiles_id_fk FOREIGN KEY (profile_id) REFERENCES call_center.cc_email_profile(id);


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
    ADD CONSTRAINT cc_email_profile_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_email_profile cc_email_profile_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_email_profile
    ADD CONSTRAINT cc_email_profile_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_list_acl cc_list_acl_domain_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_domain_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON DELETE CASCADE;


--
-- Name: cc_list_acl cc_list_acl_grantor_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


--
-- Name: cc_list_acl cc_list_acl_grantor_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_grantor_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_auth(id) ON DELETE SET NULL;


--
-- Name: cc_list_acl cc_list_acl_object_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list_acl
    ADD CONSTRAINT cc_list_acl_object_fk FOREIGN KEY (object, dc) REFERENCES call_center.cc_list(id, domain_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;


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
    ADD CONSTRAINT cc_list_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_list cc_list_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_list
    ADD CONSTRAINT cc_list_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


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
    ADD CONSTRAINT cc_member_attempt_cc_member_id_fk FOREIGN KEY (member_id) REFERENCES call_center.cc_member(id);


--
-- Name: cc_member_attempt cc_member_attempt_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt
    ADD CONSTRAINT cc_member_attempt_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id);


--
-- Name: cc_member_attempt_history cc_member_attempt_history_cc_member_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt_history
    ADD CONSTRAINT cc_member_attempt_history_cc_member_id_fk FOREIGN KEY (member_id) REFERENCES call_center.cc_member(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_member_attempt_log cc_member_attempt_log_cc_member_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt_log
    ADD CONSTRAINT cc_member_attempt_log_cc_member_id_fk FOREIGN KEY (member_id) REFERENCES call_center.cc_member(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_member_attempt_log cc_member_attempt_log_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt_log
    ADD CONSTRAINT cc_member_attempt_log_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_member cc_member_calendar_timezones_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_calendar_timezones_id_fk FOREIGN KEY (timezone_id) REFERENCES flow.calendar_timezones(id);


--
-- Name: cc_member cc_member_cc_queue_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_cc_queue_id_fk FOREIGN KEY (queue_id) REFERENCES call_center.cc_queue(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_member_messages cc_member_messages_cc_member_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_messages
    ADD CONSTRAINT cc_member_messages_cc_member_id_fk FOREIGN KEY (member_id) REFERENCES call_center.cc_member(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_msg_attachment cc_msg_attachment_cc_msg_post_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_attachment
    ADD CONSTRAINT cc_msg_attachment_cc_msg_post_id_fk FOREIGN KEY (post_id) REFERENCES call_center.cc_msg_post(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_msg_conversation cc_msg_conversation_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_conversation
    ADD CONSTRAINT cc_msg_conversation_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_msg_participants cc_msg_participants_cc_msg_conversation_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_participants
    ADD CONSTRAINT cc_msg_participants_cc_msg_conversation_id_fk FOREIGN KEY (conversation_id) REFERENCES call_center.cc_msg_conversation(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_msg_post cc_msg_post_cc_msg_conversation_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_msg_post
    ADD CONSTRAINT cc_msg_post_cc_msg_conversation_id_fk FOREIGN KEY (conversation_id) REFERENCES call_center.cc_msg_conversation(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
    ADD CONSTRAINT cc_outbound_resource_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


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
    ADD CONSTRAINT cc_outbound_resource_group_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


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
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_wbt_domain_dc_fk FOREIGN KEY (dc) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_outbound_resource_group_acl cc_outbound_resource_group_acl_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group_acl
    ADD CONSTRAINT cc_outbound_resource_group_acl_wbt_user_id_fk FOREIGN KEY (grantor) REFERENCES directory.wbt_user(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
    ADD CONSTRAINT cc_outbound_resource_group_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_outbound_resource_group cc_outbound_resource_group_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource_group
    ADD CONSTRAINT cc_outbound_resource_group_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


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
    ADD CONSTRAINT cc_outbound_resource_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_outbound_resource cc_outbound_resource_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_outbound_resource
    ADD CONSTRAINT cc_outbound_resource_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


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
    ADD CONSTRAINT cc_queue_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


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
-- Name: cc_queue cc_queue_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_queue cc_queue_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_queue cc_queue_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_queue
    ADD CONSTRAINT cc_queue_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


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
    ADD CONSTRAINT cc_skill_in_agent_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_skill_in_agent cc_skill_in_agent_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill_in_agent
    ADD CONSTRAINT cc_skill_in_agent_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_skill cc_skill_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill
    ADD CONSTRAINT cc_skill_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_supervisor_in_team cc_supervisor_in_team_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_supervisor_in_team
    ADD CONSTRAINT cc_supervisor_in_team_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id);


--
-- Name: cc_supervisor_in_team cc_supervisor_in_team_cc_team_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_supervisor_in_team
    ADD CONSTRAINT cc_supervisor_in_team_cc_team_id_fk FOREIGN KEY (team_id) REFERENCES call_center.cc_team(id) ON UPDATE CASCADE ON DELETE CASCADE;


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
    ADD CONSTRAINT cc_team_acl_grantor_fk FOREIGN KEY (grantor, dc) REFERENCES directory.wbt_auth(id, dc);


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
-- Name: cc_team cc_team_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc);


--
-- Name: cc_team cc_team_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_wbt_user_id_fk FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id);


--
-- Name: cc_team cc_team_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_wbt_user_id_fk_2 FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id);


--
-- PostgreSQL database dump complete
--

