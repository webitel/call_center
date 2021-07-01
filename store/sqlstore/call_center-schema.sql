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
-- Name: cc_agent_init_channel(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_agent_init_channel() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
        insert into cc_agent_channel (agent_id, state)
        values (new.id, 'waiting');
        RETURN NEW;
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
    from cc_member_attempt a
    where a.agent_id = agent_id_ and a.state != 'leaving' and a.channel = 'call';

    if attempt_id_ notnull then
        raise exception 'agent % has task % in the status of %', agent_id_, attempt_id_, state_;
    end if;

    update cc_agent_channel c
    set state = 'waiting',
        channel = null,
        joined_at = now(),
        queue_id = null,
        timeout = null
    where c.agent_id = agent_id_ and c.state in ('wrap_time', 'missed')
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
    res_ jsonb;
begin
    update cc_agent
    set status            = 'online', -- enum added
        status_payload = null,
        on_demand = on_demand_,
--         updated_at = case when on_demand != on_demand_ then cc_view_timestamp(now()) else updated_at end,
        last_state_change = now()     -- todo rename to status
    where cc_agent.id = agent_id_;

    update cc_agent_channel c
        set  channel = case when x.x = 1 then c.channel end,
            state = case when x.x = 1 then c.state else 'waiting' end,
            online = true,
            no_answers = 0
    from cc_agent_channel c2
        left join LATERAL (
            select 1 x
            from cc_member_attempt a where a.agent_id = agent_id_
            limit 1
        ) x on true
    where c2.agent_id = agent_id_ and c.agent_id = c2.agent_id
    returning jsonb_build_object('channel', c.channel, 'joined_at', cc_view_timestamp(c.joined_at), 'state', c.state, 'no_answers', c.no_answers)
        into res_;

    return row(res_::jsonb, cc_view_timestamp(now()));
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
-- Name: cc_attempt_abandoned(bigint, integer, integer, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_abandoned(attempt_id_ bigint, _max_count integer DEFAULT 0, _next_after integer DEFAULT 0, vars_ jsonb DEFAULT NULL::jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt  cc_member_attempt%rowtype;
    member_stop_cause varchar;
begin
    update cc_member_attempt
        set leaving_at = now(),
            last_state_change = now(),
            result = 'abandoned',
            state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    if attempt.member_id notnull then
        update cc_member
        set last_hangup_at  = (extract(EPOCH from now() ) * 1000)::int8,
            last_agent      = coalesce(attempt.agent_id, last_agent),
            stop_at = case when _max_count > 0 and (attempts + 1 < _max_count)  then null else  attempt.leaving_at end,
            stop_cause = case when _max_count > 0 and (attempts + 1 < _max_count)  then null else attempt.result end,
            ready_at = now() + (_next_after || ' sec')::interval,
            -- fixme
            communications  = jsonb_set(
                    jsonb_set(communications, array[attempt.communication_idx::text, 'attempt_id']::text[], attempt_id_::text::jsonb, true)
                , array[attempt.communication_idx::text, 'last_activity_at']::text[], ((extract(EPOCH from now() ) * 1000)::int8)::text::jsonb),
            variables = case when vars_ notnull then coalesce(variables::jsonb, '{}') || vars_ else variables end,
            attempts        = attempts + 1                     --TODO
        where id = attempt.member_id
        returning stop_cause into member_stop_cause;
    end if;


    return row(attempt.last_state_change::timestamptz, member_stop_cause::varchar);
end;
$$;


--
-- Name: cc_attempt_agent_cancel(bigint, character varying, character varying, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_agent_cancel(attempt_id_ bigint, result_ character varying, agent_status_ character varying, agent_hold_sec_ integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt cc_member_attempt%rowtype;
    no_answers_ int4;
begin
    update cc_member_attempt
        set leaving_at = now(),
            result = result_,
            state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    if attempt.agent_id notnull then
        update cc_agent_channel c
        set state = agent_status_,
            joined_at = attempt.leaving_at,
            channel = case when agent_hold_sec_ > 0 then attempt.channel else null end,
            no_answers = no_answers + 1,
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where c.agent_id = attempt.agent_id
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
            no_answers = 0,
            joined_at = attempt.bridged_at,
            last_bridged_at = now()
        where  ch.agent_id = attempt.agent_id;
    end if;

    return row(attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_attempt_distribute_cancel(bigint, character varying, integer, boolean, jsonb); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_attempt_distribute_cancel(attempt_id_ bigint, description_ character varying, next_distribute_sec_ integer, stop_ boolean, vars_ jsonb)
    LANGUAGE plpgsql
    AS $$
declare
    attempt  cc_member_attempt%rowtype;
begin
    update cc_member_attempt
        set leaving_at = now(),
            description = description_,
            last_state_change = now(),
            result = 'cancel', --TODO
            state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    update cc_member
    set last_hangup_at  = (extract(EPOCH from now() ) * 1000)::int8,
        last_agent      = coalesce(attempt.agent_id, last_agent),
        variables = case when vars_ notnull  then coalesce(variables, '{}'::jsonb) || vars_ else variables end,
        ready_at = case when next_distribute_sec_ > 0 then now() + (next_distribute_sec_::text || ' sec')::interval else now() end,
        stop_at = case when stop_ is true then attempt.leaving_at end,
        stop_cause = case when stop_ is true then attempt.result end
    where id = attempt.member_id;

end;
$$;


--
-- Name: cc_attempt_end_reporting(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, integer, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_end_reporting(attempt_id_ bigint, status_ character varying, description_ character varying DEFAULT NULL::character varying, expire_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, next_offering_at_ timestamp with time zone DEFAULT NULL::timestamp with time zone, sticky_agent_id_ integer DEFAULT NULL::integer, variables_ jsonb DEFAULT NULL::jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt cc_member_attempt%rowtype;
    agent_timeout_ timestamptz;
    time_ int8 = extract(EPOCH  from now()) * 1000;
    user_id_ int8 = null;
    domain_id_ int8;
    wrap_time_ int;
    stop_cause_ varchar;
begin

    if next_offering_at_ notnull and not attempt.result in ('success', 'cancel') and next_offering_at_ < now() then
        -- todo move to application
        raise exception 'bad parameter: next distribute at';
    end if;


    update cc_member_attempt
        set state  =  'leaving',
            reporting_at = now(),
            leaving_at = case when leaving_at isnull then now() else leaving_at end,
            result = status_,
            description = description_
    where id = attempt_id_ and state != 'leaving'
    returning * into attempt;

    if attempt.id isnull then
        return null;
--         raise exception  'not found %', attempt_id_;
    end if;

    if attempt.member_id notnull then
        update cc_member
        set last_hangup_at  = time_,
            variables = case when variables_ isnull then variables else variables_ end,
            expire_at = case when expire_at_ isnull then expire_at else expire_at_ end,
            agent_id = case when sticky_agent_id_ isnull then agent_id else sticky_agent_id_ end,

            stop_at = case when not attempt.result in ('success', 'cancel') and (q._max_count > 0 and (attempts + 1 < q._max_count))  then null else  attempt.leaving_at end,
            stop_cause = case when not attempt.result in ('success', 'cancel') and (q._max_count > 0 and (attempts + 1 < q._max_count)) then null else attempt.result end,

            ready_at = case when next_offering_at_ notnull then next_offering_at_
                else now() + (q._next_after || ' sec')::interval end,

            last_agent      = coalesce(attempt.agent_id, last_agent),
            communications = jsonb_set(
                    jsonb_set(communications, array [attempt.communication_idx, 'attempt_id']::text[],
                              attempt_id_::text::jsonb, true)
                , array [attempt.communication_idx, 'last_activity_at']::text[],
                    case when next_offering_at_ isnull then '0'::text::jsonb else time_::text::jsonb end
                ),
            attempts        = attempts + 1                     --TODO
        from (
            -- fixme
            select coalesce(cast((q.payload->>'max_attempts') as int), 0) as _max_count, coalesce(cast((q.payload->>'wait_between_retries') as int), 0) as _next_after
            from cc_queue q
            where q.id = attempt.queue_id
        ) q
        where id = attempt.member_id
        returning stop_cause into stop_cause_;
    end if;

    if attempt.agent_id notnull then
        select a.user_id, a.domain_id, case when a.on_demand then null else coalesce(tm.wrap_up_time, 0) end
        into user_id_, domain_id_, wrap_time_
        from cc_agent a
            left join cc_team tm on tm.id = attempt.team_id
        where a.id = attempt.agent_id;

        if wrap_time_ > 0 or wrap_time_ isnull then
            update cc_agent_channel c
            set state = 'wrap_time',
                joined_at = now(),
                timeout = case when wrap_time_ > 0 then now() + (wrap_time_ || ' sec')::interval end,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning timeout into agent_timeout_;
        else
            update cc_agent_channel c
            set state = 'waiting',
                joined_at = now(),
                timeout = null,
                channel = null,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id),
                queue_id = null
            where (c.agent_id, c.channel) = (attempt.agent_id, attempt.channel)
            returning timeout into agent_timeout_;
        end if;
    end if;

    return row(cc_view_timestamp(now()),
        attempt.channel,
        attempt.queue_id,
        attempt.agent_call_id,
        attempt.agent_id,
        user_id_,
        domain_id_,
        cc_view_timestamp(agent_timeout_),
        stop_cause_
        );
end;
$$;


--
-- Name: cc_attempt_leaving(bigint, character varying, character varying, integer, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_leaving(attempt_id_ bigint, result_ character varying, agent_status_ character varying, agent_hold_sec_ integer, vars_ jsonb DEFAULT NULL::jsonb) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    attempt cc_member_attempt%rowtype;
    no_answers_ int;
    member_stop_cause varchar;
begin
    /*
     FIXME
     */
    update cc_member_attempt
    set leaving_at = now(),
        result = result_,
        state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    if attempt.member_id notnull then
        update cc_member m
        set last_hangup_at  = extract(EPOCH from now())::int8 * 1000,
            last_agent      = coalesce(attempt.agent_id, last_agent),

            stop_at = case when not attempt.result = 'success' and q._max_count > 0 and (attempts + 1 < q._max_count)  then null else  attempt.leaving_at end,
            stop_cause = case when not attempt.result = 'success' and q._max_count > 0 and (attempts + 1 < q._max_count)  then null else attempt.result end,
            ready_at = now() + (coalesce(q._next_after, 0) || ' sec')::interval,

            communications = jsonb_set(
                    jsonb_set(communications, array [attempt.communication_idx, 'attempt_id']::text[],
                              attempt_id_::text::jsonb, true)
                , array [attempt.communication_idx, 'last_activity_at']::text[],
                    ( (extract(EPOCH  from now()) * 1000)::int8 )::text::jsonb
                ),
            attempts        = attempts + 1,
            variables = case when vars_ notnull then coalesce(variables::jsonb, '{}') || vars_ else variables end
        from (
            -- fixme
            select cast((q.payload->>'max_attempts') as int) as _max_count, cast((q.payload->>'wait_between_retries') as int) as _next_after
            from cc_queue q
            where q.id = attempt.queue_id
        ) q
        where id = attempt.member_id
        returning stop_cause into member_stop_cause;
    end if;

    if attempt.agent_id notnull then
        update cc_agent_channel c
        set state = agent_status_,
            joined_at = now(),
            channel = case when agent_hold_sec_ > 0 or agent_status_ != 'waiting' then channel else null end,
            no_answers = case when attempt.bridged_at notnull then 0 else no_answers + 1 end,
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where c.agent_id = attempt.agent_id
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
        where c.agent_id = agent_id_
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
    AS $$
declare
    attempt cc_member_attempt%rowtype;
begin

    update cc_member_attempt
    set state             = 'offering',
        last_state_change = now(),
--         destination = dest_,
        display = displ_,
        offering_at       = now(),
        agent_id          = case when agent_id isnull and agent_id_::int notnull then agent_id_ else agent_id end,
        agent_call_id     = case
                                when agent_call_id isnull and agent_call_id_::varchar notnull then agent_call_id_
                                else agent_call_id end,
        -- todo for queue preview
        member_call_id    = case
                                when member_call_id isnull and member_call_id_ notnull then member_call_id_
                                else member_call_id end
    where id = attempt_id_
    returning * into attempt;


    if attempt.agent_id notnull then
        update cc_agent_channel ch
        set state            = attempt.state,
            joined_at        = now(),
            last_offering_at = now(),
            queue_id         = attempt.queue_id,
            channel          = attempt.channel,
            last_bucket_id   = coalesce(attempt.bucket_id, last_bucket_id)
        where (ch.agent_id) = (attempt.agent_id);
    end if;

    return row (attempt.last_state_change::timestamptz);
end;
$$;


--
-- Name: cc_attempt_timeout(bigint, integer, character varying, character varying, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_timeout(attempt_id_ bigint, hold_sec integer, result_ character varying, agent_status_ character varying, agent_hold_sec_ integer) RETURNS timestamp with time zone
    LANGUAGE plpgsql
    AS $$
declare
    attempt cc_member_attempt%rowtype;
begin
    update cc_member_attempt
        set reporting_at = now(),
            result = 'timeout',
            state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    update cc_member
    set last_hangup_at  = extract(EPOCH from now())::int8 * 1000,
        last_agent      = coalesce(attempt.agent_id, last_agent),


        stop_at = case when  q._max_count > 0 and (attempts + 1 < q._max_count)  then null else  attempt.leaving_at end,
        stop_cause = case when q._max_count > 0 and (attempts + 1 < q._max_count)  then null else attempt.result end,
        ready_at = now() + (coalesce(q._next_after, 0) || ' sec')::interval,

        communications = jsonb_set(
                jsonb_set(communications, array [attempt.communication_idx, 'attempt_id']::text[],
                          attempt_id_::text::jsonb, true)
            , array [attempt.communication_idx, 'last_activity_at']::text[],
                ( (extract(EPOCH  from now()) * 1000)::int8 )::text::jsonb
            ),
        attempts        = attempts + 1
    from (
        -- fixme
        select coalesce(cast((q.payload->>'max_attempts') as int), 0) as _max_count, coalesce(cast((q.payload->>'wait_between_retries') as int), 0) as _next_after
        from cc_queue q
        where q.id = attempt.queue_id
    ) q
    where id = attempt.member_id;

    if attempt.agent_id notnull then
        update cc_agent_channel c
        set state = agent_status_,
            joined_at = now(),
            channel = null,
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where c.agent_id = attempt.agent_id;

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
    attempt cc_member_attempt%rowtype;
        user_id_ int8 = null;
    domain_id_ int8;
    wrap_time_ int;
     agent_timeout_ timestamptz;
begin

    update cc_member_attempt
    set transferred_agent_id = agent_id,
        agent_id = to_agent_id_,
        agent_call_id = agent_sess_id_
    where id = attempt_id_
    returning * into attempt;

    insert into cc_member_attempt_transferred (from_id, to_id, from_agent_id, to_agent_id)
    values (to_attempt_id_, attempt_id_, attempt.transferred_agent_id, attempt.agent_id);

    if attempt.transferred_agent_id notnull then
        select a.user_id, a.domain_id, case when a.on_demand then null else coalesce(tm.wrap_up_time, 0) end
        into user_id_, domain_id_, wrap_time_
        from cc_agent a
            left join cc_team tm on tm.id = attempt.team_id
        where a.id = attempt.transferred_agent_id;

        if wrap_time_ > 0 or wrap_time_ isnull then
            update cc_agent_channel c
            set state = 'wrap_time',
                joined_at = now(),
                timeout = case when wrap_time_ > 0 then now() + (wrap_time_ || ' sec')::interval end,
                last_bucket_id = coalesce(attempt.bucket_id, last_bucket_id)
            where (c.agent_id, c.channel) = (attempt.transferred_agent_id, attempt.channel)
            returning timeout into agent_timeout_;
        else
            update cc_agent_channel c
            set state = 'waiting',
                joined_at = now(),
                timeout = null,
                channel = null,
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
    attempt cc_member_attempt%rowtype;
begin

    update cc_member_attempt
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
-- Name: cc_call_active_numbers(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_call_active_numbers() RETURNS SETOF character varying
    LANGUAGE plpgsql
    AS $$
declare
        c cc_calls;
BEGIN

    for c in select *
            from cc_calls cc where cc.hangup_at isnull and not cc.direction isnull
            and ( (cc.gateway_id notnull and cc.direction = 'outbound') or (cc.gateway_id notnull and cc.direction = 'inbound') )
            for update skip locked
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
    transfer_from character varying,
    transfer_to character varying,
    amd_result character varying,
    amd_duration interval,
    tags character varying[],
    region_id integer,
    grantee_id integer
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01');


--
-- Name: cc_call_get_owner_leg(call_center.cc_calls); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_call_get_owner_leg(c_ call_center.cc_calls, OUT number_ character varying, OUT name_ character varying, OUT type_ character varying, OUT id_ character varying) RETURNS record
    LANGUAGE plpgsql IMMUTABLE
    AS $$
begin
    if c_.direction = 'inbound' or (c_.direction = 'outbound' and c_.gateway_id notnull ) then
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
declare
        transfer_to_ varchar;
        transfer_from_ varchar;
begin
    update cc_calls cc
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
             from cc_calls b
                      left join cc_calls b2 on b2.id = call_id_
                      left join lateral cc_call_get_owner_leg(b2) b2o on true
             where b.id = call_bridged_id_
         ) c
    where c.id = cc.id
    returning c.transfer_to into transfer_to_;


    update cc_calls cc
    set bridged_id    = c.bridged_id,
        state         = state_,
        timestamp     = timestamp_,
        parent_id     = case
                            when cc.parent_id notnull and cc.parent_id != c.bridged_id then c.bridged_id
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
                    b2o.*
             from cc_calls b
                      left join cc_calls b2 on b2.id = call_bridged_id_
                      left join lateral cc_call_get_owner_leg(b2) b2o on true
             where b.id = call_id_
         ) c
    where c.id = cc.id
    returning cc.transfer_from into transfer_from_;

    update cc_calls set
     transfer_from =  case when id = transfer_from_ then transfer_to_ end,
     transfer_to =  case when id = transfer_to_ then transfer_from_ end
    where id in (transfer_from_, transfer_to_);

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

CREATE FUNCTION call_center.cc_confirm_agent_attempt(_agent_id bigint, _attempt_id bigint) RETURNS SETOF character varying
    LANGUAGE plpgsql
    AS $$
BEGIN
    return query update cc_member_attempt
    set result = case when id = _attempt_id then null else 'cancel' end,
        leaving_at = case when id = _attempt_id then null else now() end
    where agent_id = _agent_id and not exists(
       select 1
       from cc_member_attempt a
       where a.agent_id = _agent_id and a.leaving_at notnull and a.result = 'cancel'
       for update
    )
    returning member_call_id;
END;
$$;


--
-- Name: cc_distribute(integer); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_distribute(INOUT cnt integer)
    LANGUAGE plpgsql
    AS $$
begin
    if NOT pg_try_advisory_xact_lock(132132117) then
        raise exception 'LOCK';
    end if;

    with dis as MATERIALIZED (
        select *
        from cc_sys_distribute() x (agent_id int, queue_id int, bucket_id int, ins bool, id int8, resource_id int,
                                    resource_group_id int, comm_idx int)
    )
       , ins as (
        insert into cc_member_attempt (channel, member_id, queue_id, resource_id, agent_id, bucket_id, destination,
                                       communication_idx, member_call_id, team_id, resource_group_id, domain_id)
            select case when q.type = 7 then 'task' else 'call' end, --todo
                   dis.id,
                   dis.queue_id,
                   dis.resource_id,
                   case when q.type != 5 then dis.agent_id end,
                   dis.bucket_id,
                   x,
                   dis.comm_idx,
                   uuid_generate_v4(),
                   q.team_id,
                   dis.resource_group_id,
                   q.domain_id
            from dis
                     inner join cc_queue q on q.id = dis.queue_id
                     inner join cc_member m on m.id = dis.id
                     inner join lateral jsonb_extract_path(m.communications, (dis.comm_idx)::text) x on true
            where dis.ins
    )
    update cc_member_attempt a
    set agent_id = t.agent_id
    from (
             select dis.id, dis.agent_id
             from dis
             where not dis.ins is true
         ) t
    where t.id = a.id
      and a.agent_id isnull;

end;
$$;


--
-- Name: cc_distribute_direct_member_to_queue(character varying, bigint, integer, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint, seq integer)
    LANGUAGE plpgsql
    AS $$
declare
    _weight      int4;
    _destination jsonb;
BEGIN

    return query with attempts as (
        insert into cc_member_attempt (state, queue_id, member_id, destination, node_id, agent_id, resource_id,
                                       bucket_id, seq, team_id, domain_id)
            select 1,
                   m.queue_id,
                   m.id,
                   m.communications -> (_communication_id::int2),
                   _node_name,
                   _agent_id,
                   r.resource_id,
                   m.bucket_id,
                   m.attempts + 1,
                   q.team_id,
                   q.domain_id
            from cc_member m
                     inner join cc_queue q on q.id = m.queue_id
                     inner join lateral (
                select (t::cc_sys_distribute_type).resource_id
                from cc_sys_queue_distribute_resources r,
                     unnest(r.types) t
                where r.queue_id = m.queue_id
                  and (t::cc_sys_distribute_type).type_id =
                      (m.communications -> (_communication_id::int2) -> 'type' -> 'id')::int4
                limit 1
                ) r on true
                     inner join cc_team ct on q.team_id = ct.id
                     left join cc_outbound_resource cor on cor.id = r.resource_id
            where m.id = _member_id
              and m.communications -> (_communication_id::int2) notnull
            returning cc_member_attempt.*
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
                        a.seq::int seq
                 from attempts a
                          left join cc_member cm on a.member_id = cm.id
                          inner join cc_queue cq on a.queue_id = cq.id
                          inner join cc_team t on t.id = cq.team_id
                          left join cc_outbound_resource r on r.id = a.resource_id
                          left join cc_agent ag on ag.id = a.agent_id;

    --raise notice '%', _attempt_id;

END;
$$;


--
-- Name: cc_distribute_inbound_call_to_agent(character varying, character varying, jsonb, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer) RETURNS record
    LANGUAGE plpgsql
    AS $$
declare
    _domain_id int8;
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;

    _call record;
    _attempt record;

    _a_status varchar;
    _a_channel varchar;
BEGIN

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

  select
    a.team_id,
    t.updated_at,
    a.status,
    cac.channel,
    a.domain_id,
    a.updated_at
  from cc_agent a
      inner join cc_team t on t.id = a.team_id
      inner join cc_agent_channel cac on a.id = cac.agent_id
  where a.id = _agent_id -- check attempt
  for update
  into _team_id_,
      _team_updated_at,
      _a_status,
      _a_channel,
      _domain_id,
      _agent_updated_at
      ;

  if _call.domain_id != _domain_id then
      raise exception 'the queue on another domain';
  end if;

  if not _a_status = 'online' then
      raise exception 'agent not in online';
  end if;

  if not _a_channel isnull  then
      raise exception 'agent is busy';
  end if;


  insert into call_center.cc_member_attempt (domain_id, state, team_id, member_call_id, destination, node_id, agent_id)
  values (_domain_id, 'waiting', _team_id_, _call_id, jsonb_build_object('destination', _call.from_number),
              _node_name, _agent_id)
  returning * into _attempt;

  update cc_calls
  set team_id = _team_id_,
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
-- Name: cc_distribute_inbound_call_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
    _enabled bool;
    _q_type smallint;
    _sticky bool;
    _call record;
    _attempt record;
    _number varchar;
BEGIN
  select c.timezone_id,
           (payload->>'discard_abandoned_after')::int discard_abandoned_after,
         c.domain_id,
         q.dnc_list_id,
         q.calendar_id,
         q.updated_at,
         ct.updated_at,
         q.team_id,
         q.enabled,
         q.type,
         q.sticky_agent
  from cc_queue q
    inner join flow.calendar c on q.calendar_id = c.id
    inner join cc_team ct on q.team_id = ct.id
  where  q.id = _queue_id
  into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
      _team_updated_at, _team_id_, _enabled, _q_type, _sticky;

  if not _q_type = 1 then
      raise exception 'queue not inbound';
  end if;

  if not _enabled = true then
      raise exception 'queue disabled';
  end if;

  select *
  from cc_calls c
  where c.id = _call_id
--   for update
  into _call;

  if _call.domain_id != _domain_id then
      raise exception 'the queue on another domain';
  end if;

  if _call.id isnull or _call.direction isnull then
      raise exception 'not found call';
  ELSIF _call.direction <> 'outbound' then
      _number = _call.from_number;
  else
      _number = _call.destination;
  end if;

--   raise  exception '%', _number;


  if not exists(select accept
            from flow.calendar_check_timing(_domain_id, _calendar_id, null)
            as x (name varchar, excepted varchar, accept bool, expire bool)
            where accept and excepted is null and not expire)
  then
--       insert into cc_member_attempt(channel, queue_id, state, leaving_at, member_call_id, result)
--           values ('call', _queue_id, 'leaving', now(), _call_id, 'now_working');
      raise exception 'number % calendar not working', _number;
  end if;


  --TODO
  select clc.id
    into _list_comm_id
    from cc_list_communications clc
    where (clc.list_id = dnc_list_id_ and clc.number = _number)
  limit 1;

  if _list_comm_id notnull then
--           insert into cc_member_attempt(channel, queue_id, state, leaving_at, member_call_id, result, list_communication_id)
--           values ('call', _queue_id, 'leaving', now(), _call_id, 'banned', _list_comm_id);
          raise exception 'number % banned', _number;
  end if;

  if  _discard_abandoned_after > 0 then
      select
            case when log.result = 'abandoned' then
                 extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
            else coalesce(_priority, 0) end
        from cc_member_attempt_history log
        where log.leaving_at >= (now() -  (_discard_abandoned_after || ' sec')::interval)
            and log.queue_id = _queue_id
            and log.destination->>'destination' = _number
        order by log.leaving_at desc
        limit 1
        into _weight;
  end if;

  if _sticky_agent_id notnull and _sticky then
      if not exists(select 1
                    from cc_agent a
                    where a.id = _sticky_agent_id
                      and a.domain_id = _domain_id
                      and a.status = 'online'
                      and exists(select 1
                                 from cc_skill_in_agent sa
                                          inner join cc_queue_skill qs
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

  insert into call_center.cc_member_attempt (domain_id, state, queue_id, team_id, member_id, bucket_id, weight, member_call_id, destination, node_id, sticky_agent_id, list_communication_id)
  values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id, jsonb_build_object('destination', _number),
              _node_name, _sticky_agent_id, null)
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
      _number::varchar,
      _call.from_name::varchar,
      cc_view_timestamp(_call.answered_at)::int8,
      cc_view_timestamp(_call.bridged_at)::int8,
      cc_view_timestamp(_call.created_at)::int8
  );

END;
$$;


--
-- Name: cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
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
    _enabled bool;
    _q_type smallint;
    _attempt record;
    _con_created timestamptz;
    _con_name varchar;
    _inviter_channel_id varchar;
    _inviter_user_id varchar;
    _sticky bool;
BEGIN
  select c.timezone_id,
           (coalesce(payload->>'discard_abandoned_after', '0'))::int discard_abandoned_after,
         c.domain_id,
         q.dnc_list_id,
         q.calendar_id,
         q.updated_at,
         ct.updated_at,
         q.team_id,
         q.enabled,
         q.type,
         q.sticky_agent
  from cc_queue q
    inner join flow.calendar c on q.calendar_id = c.id
    inner join cc_team ct on q.team_id = ct.id
  where  q.id = _queue_id
  into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
      _team_updated_at, _team_id_, _enabled, _q_type, _sticky;

  if not _q_type = 6 then
      raise exception 'queue type not inbound chat';
  end if;

  if not _enabled = true then
      raise exception 'queue disabled';
  end if;

  if not exists(select accept
            from flow.calendar_check_timing(_domain_id, _calendar_id, null)
            as x (name varchar, excepted varchar, accept bool, expire bool)
            where accept and excepted is null and not expire) then
      raise exception 'conversation [%] calendar not working', _conversation_id;
  end if;

  select cli.external_id,
         c.created_at,
         c.id inviter_channel_id,
         c.user_id
  from chat.channel c
           left join chat.client cli on cli.id = c.user_id
  where c.closed_at isnull
        and c.conversation_id = _conversation_id
    and not c.internal
  into _con_name, _con_created, _inviter_channel_id, _inviter_user_id;
  --TODO
--   select clc.id
--     into _list_comm_id
--     from cc_list_communications clc
--     where (clc.list_id = dnc_list_id_ and clc.number = _call.from_number)
--   limit 1;

--   if _list_comm_id notnull then
--           insert into cc_member_attempt(channel, queue_id, state, leaving_at, member_call_id, result, list_communication_id)
--           values ('call', _queue_id, 'leaving', now(), _call_id, 'banned', _list_comm_id);
--           raise exception 'number % banned', _call.from_number;
--   end if;

  if  _discard_abandoned_after > 0 then
      select
            case when log.result = 'abandoned' then
                 extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
            else coalesce(_priority, 0) end
        from cc_member_attempt_history log
        where log.leaving_at >= (now() -  (_discard_abandoned_after || ' sec')::interval)
            and log.queue_id = _queue_id
            and log.destination->>'destination' = _con_name
        order by log.leaving_at desc
        limit 1
        into _weight;
  end if;

  if _sticky_agent_id notnull and _sticky then
      if not exists(select 1
                    from cc_agent a
                    where a.id = _sticky_agent_id
                      and a.domain_id = _domain_id
                      and a.status = 'online'
                      and exists(select 1
                                 from cc_skill_in_agent sa
                                          inner join cc_queue_skill qs
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

  insert into call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_id, bucket_id, weight, member_call_id, destination, node_id, sticky_agent_id, list_communication_id)
  values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id, jsonb_build_object('destination', _con_name),
              _node_name, _sticky_agent_id, (select clc.id
                            from cc_list_communications clc
                            where (clc.list_id = dnc_list_id_ and clc.number = _conversation_id)))
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
      cc_view_timestamp(_con_created)::int8
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
    and data_type in ('json', 'jsonb'));
end;
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
    if new.stop_cause notnull then
        new.ready_at = null;
    end if;

    if new.communications notnull and jsonb_typeof(new.communications) = 'array' then
        new.sys_destinations = (select array(select cc_destination_in(idx::int4 - 1, (x -> 'type' ->> 'id')::int4, (x ->> 'last_activity_at')::int8,  (x -> 'resource' ->> 'id')::int, (x ->> 'priority')::int)
         from jsonb_array_elements(new.communications) with ordinality as x(x, idx)
         where coalesce((x.x -> 'stopped_at')::int8, 0) = 0
         and idx > -1));

        new.search_destinations = (select array_agg( distinct x->>'destination'::varchar)
            from jsonb_array_elements(new.communications) x);

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
        set member_count   = cc_queue_skill_statistics.member_count - EXCLUDED.member_count,
            member_waiting = cc_queue_skill_statistics.member_waiting - EXCLUDED.member_waiting
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

    insert into cc_queue_statistics (bucket_id, queue_id, member_count, member_waiting)
    select t.bucket_id, t.queue_id, t.cnt, t.cntwait
    from (
             select queue_id, bucket_id, count(*) cnt, count(*) filter ( where m.stop_at isnull ) cntwait
             from deleted m
                inner join cc_queue q on q.id = m.queue_id
             group by queue_id, bucket_id
         ) t
    on conflict (queue_id, coalesce(bucket_id, 0))
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
    insert into cc_queue_statistics (queue_id, bucket_id, member_count, member_waiting)
    select t.queue_id, t.bucket_id, t.cnt, t.cntwait
    from (
             select queue_id, bucket_id, count(*) cnt, count(*) filter ( where m.stop_at isnull ) cntwait
             from inserted m
             group by queue_id, bucket_id
         ) t
    on conflict (queue_id, coalesce(bucket_id, 0))
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
    insert into cc_queue_statistics (queue_id, bucket_id, member_count, member_waiting)
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

CREATE FUNCTION call_center.cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    return query update cc_member_attempt a
        set state = 'waiting'
            ,node_id = node
            ,last_state_change = now()
            ,list_communication_id = lc.id
            ,seq = c.attempts + 1
        from (
            select c.id,
                   cq.updated_at                                   as queue_updated_at,
                   r.updated_at                                    as resource_updated_at,
                   cc_view_timestamp(gw.updated_at)             as gateway_updated_at,
                   c.destination as destination,
                   cm.variables                                    as variables,
                   cm.name                                         as member_name,
                   c.state                                         as state,
                   cqs.member_count                                as queue_cnt,
                   0                                               as queue_active_cnt,
                   cqs.member_waiting                              as queue_waiting_cnt,
                   ca.updated_at                                   as agent_updated_at,
                   tm.updated_at                                   as team_updated_at,
                   cq.dnc_list_id,
                   cm.attempts
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
            left join cc_list_communications lc on lc.list_id = c.dnc_list_id and
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
            c.resource_updated_at::bigint as resource_updated_at,
            c.gateway_updated_at::bigint as gateway_updated_at,
            c.destination,
            c.variables ,
            c.member_name,
            a.member_call_id,
            a.agent_id,
            c.agent_updated_at,
            c.team_updated_at,
            a.list_communication_id,
            a.seq;
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

  --
  if new.state = 'waiting' then
      new.queue_id := null;
  end if;

  --fixme error when agent set offline/pause in active call
  if new.joined_at - old.joined_at = interval '0' then
--       raise exception 'dev';
        return new;
  end if;

  if coalesce(new.channel, '') != coalesce(old.channel, '') then
      new.channel_changed_at = now();
  end if;

  if new.channel = 'chat' and old.channel = 'chat' then

      return new;
  end if;

  if old.channel = 'chat' then
      insert into cc_agent_state_history (agent_id, joined_at, state, channel, duration, queue_id)
      values (old.agent_id, old.channel_changed_at, 'chat', old.channel, new.channel_changed_at - old.channel_changed_at, old.queue_id);
      return new;
  end if;

  insert into cc_agent_state_history (agent_id, joined_at, state, channel, duration, queue_id)
  values (old.agent_id, old.joined_at, old.state, old.channel, new.joined_at - old.joined_at, old.queue_id);

  RETURN new;
END;
$$;


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
      set state  =  'leaving',
          leaving_at = now(),
          result = res
    where leaving_at isnull and node_id = node and state = 'idle';

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
-- Name: gin_cc_pair_test2_ops; Type: OPERATOR FAMILY; Schema: call_center; Owner: -
--

CREATE OPERATOR FAMILY call_center.gin_cc_pair_test2_ops USING gin;


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
    supervisor_id integer,
    team_id integer,
    region_id integer,
    supervisor boolean DEFAULT false NOT NULL,
    auditor_id bigint,
    CONSTRAINT cc_agent_chat_count_c CHECK ((chat_count > '-1'::integer)),
    CONSTRAINT cc_agent_progress_count_c CHECK ((progressive_count > '-1'::integer))
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
    channel character varying,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    timeout timestamp with time zone,
    max_opened integer DEFAULT 1 NOT NULL,
    no_answers integer DEFAULT 0 NOT NULL,
    queue_id integer,
    last_offering_at timestamp with time zone,
    last_bridged_at timestamp with time zone,
    last_missed_at timestamp with time zone,
    last_bucket_id integer,
    channel_changed_at timestamp with time zone DEFAULT now() NOT NULL,
    online boolean DEFAULT false NOT NULL,
    no_send_processing integer DEFAULT 0 NOT NULL
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20');


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
    queue_id integer
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
    NULL::bigint AS domain_id,
    NULL::integer AS agent_id;


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
    description character varying DEFAULT ''::character varying NOT NULL
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
    updated_by bigint NOT NULL,
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
    admin_id integer
);


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
    ch.x AS channel,
    (json_build_object('id', ct.id, 'name', COALESCE(((ct.name)::character varying)::name, ct.username)))::jsonb AS "user",
    call_center.cc_get_lookup((a.greeting_media_id)::bigint, g.name) AS greeting_media,
    a.allow_channels,
    a.chat_count,
    sup."user" AS supervisor,
    call_center.cc_get_lookup(aud.id, (COALESCE(aud.name, (aud.username)::text))::character varying) AS auditor,
    call_center.cc_get_lookup(t.id, t.name) AS team,
    call_center.cc_get_lookup((r.id)::bigint, r.name) AS region,
    a.supervisor AS is_supervisor,
    ( SELECT jsonb_agg(call_center.cc_get_lookup((sa.skill_id)::bigint, cs.name)) AS jsonb_agg
           FROM (call_center.cc_skill_in_agent sa
             JOIN call_center.cc_skill cs ON ((sa.skill_id = cs.id)))
          WHERE (sa.agent_id = a.id)) AS skills,
    a.team_id,
    a.region_id,
    a.supervisor_id,
    a.auditor_id
   FROM (((((((call_center.cc_agent a
     LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
     LEFT JOIN storage.media_files g ON ((g.id = a.greeting_media_id)))
     LEFT JOIN call_center.cc_agent_with_user sup ON ((sup.id = a.supervisor_id)))
     LEFT JOIN directory.wbt_user aud ON ((aud.id = a.auditor_id)))
     LEFT JOIN call_center.cc_team t ON ((t.id = a.team_id)))
     LEFT JOIN flow.region r ON ((r.id = a.region_id)))
     LEFT JOIN LATERAL ( SELECT json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint) AS x
           FROM call_center.cc_agent_channel c
          WHERE (c.agent_id = a.id)) ch ON (true));


--
-- Name: cc_agent_today_pause_cause; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_agent_today_pause_cause AS
 SELECT a.id,
    ((now())::date + age(now(), (timezone(t.sys_name, now()))::timestamp with time zone)) AS today,
    p.payload AS cause,
    p.d AS duration
   FROM (((call_center.cc_agent a
     LEFT JOIN flow.region r ON ((r.id = a.region_id)))
     LEFT JOIN flow.calendar_timezones t ON ((t.id = r.timezone_id)))
     LEFT JOIN LATERAL ( SELECT cc_agent_state_history.payload,
            sum(cc_agent_state_history.duration) AS d
           FROM call_center.cc_agent_state_history
          WHERE ((cc_agent_state_history.joined_at > ((now())::date + age(now(), (timezone(t.sys_name, now()))::timestamp with time zone))) AND (cc_agent_state_history.agent_id = a.id) AND ((cc_agent_state_history.state)::text = 'pause'::text) AND (cc_agent_state_history.channel IS NULL))
          GROUP BY cc_agent_state_history.payload) p ON (true))
  WHERE (p.d IS NOT NULL)
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
-- Name: cc_attempt_missed_agent; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_attempt_missed_agent (
    id bigint NOT NULL,
    attempt_id bigint NOT NULL,
    agent_id integer NOT NULL,
    offering_at timestamp with time zone NOT NULL,
    missed_at timestamp with time zone NOT NULL,
    cause character varying
);


--
-- Name: cc_attempt_missed_agent_id_seq; Type: SEQUENCE; Schema: call_center; Owner: -
--

CREATE SEQUENCE call_center.cc_attempt_missed_agent_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cc_attempt_missed_agent_id_seq; Type: SEQUENCE OWNED BY; Schema: call_center; Owner: -
--

ALTER SEQUENCE call_center.cc_attempt_missed_agent_id_seq OWNED BY call_center.cc_attempt_missed_agent.id;


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
-- Name: cc_bucket_in_queue_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_bucket_in_queue_view AS
 SELECT q.id,
    q.ratio,
    call_center.cc_get_lookup(cb.id, ((cb.name)::text)::character varying) AS bucket,
    q.queue_id,
    q.bucket_id,
    cb.domain_id,
    cb.name AS bucket_name
   FROM (call_center.cc_bucket_in_queue q
     LEFT JOIN call_center.cc_bucket cb ON ((q.bucket_id = cb.id)));


--
-- Name: cc_bucket_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_bucket_view AS
 SELECT b.id,
    b.name,
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
    communications jsonb NOT NULL,
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
    sys_destinations call_center.cc_destination[],
    CONSTRAINT cc_member_bucket_skill_check CHECK ((NOT ((bucket_id IS NOT NULL) AND (skill_id IS NOT NULL))))
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_vacuum_scale_factor='0.01', autovacuum_analyze_scale_factor='0.05', autovacuum_vacuum_cost_delay='20', autovacuum_enabled='1', autovacuum_analyze_threshold='2000');
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
    transferred_attempt_id bigint
)
WITH (fillfactor='20', log_autovacuum_min_duration='0', autovacuum_analyze_scale_factor='0.05', autovacuum_enabled='1', autovacuum_vacuum_cost_delay='20', autovacuum_vacuum_threshold='100', autovacuum_vacuum_scale_factor='0.01');


--
-- Name: TABLE cc_member_attempt; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON TABLE call_center.cc_member_attempt IS 'todo';


--
-- Name: COLUMN cc_member_attempt.communication_idx; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON COLUMN call_center.cc_member_attempt.communication_idx IS 'fixme';


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
    updated_at bigint DEFAULT ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint NOT NULL,
    name character varying NOT NULL,
    variables jsonb DEFAULT '{}'::jsonb NOT NULL,
    domain_id bigint NOT NULL,
    dnc_list_id bigint,
    type smallint DEFAULT 1 NOT NULL,
    team_id bigint,
    created_at bigint NOT NULL,
    created_by bigint NOT NULL,
    updated_by bigint NOT NULL,
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
    recall_calendar boolean DEFAULT false
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
    sup."user" AS supervisor,
    aa.supervisor_id,
    c.grantee_id
   FROM (((((((((call_center.cc_calls c
     LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
     LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
     LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
     LEFT JOIN call_center.cc_member_attempt cma ON ((cma.id = c.attempt_id)))
     LEFT JOIN call_center.cc_agent_with_user ca ON ((cma.agent_id = ca.id)))
     LEFT JOIN call_center.cc_agent aa ON ((aa.user_id = c.user_id)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
     LEFT JOIN call_center.cc_agent_with_user sup ON ((sup.id = aa.supervisor_id)))
  WHERE ((c.hangup_at IS NULL) AND (c.direction IS NOT NULL));


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
    amd_duration interval,
    grantee_id bigint
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
    result character varying(25) NOT NULL,
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
    answered_at timestamp with time zone
);


--
-- Name: COLUMN cc_member_attempt_history.result; Type: COMMENT; Schema: call_center; Owner: -
--

COMMENT ON COLUMN call_center.cc_member_attempt_history.result IS 'fixme';


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
    cag."user" AS agent,
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
    cma.description AS agent_description,
    c.grantee_id
   FROM ((((((((call_center.cc_calls_history c
     LEFT JOIN LATERAL ( SELECT json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type)) AS files
           FROM ( SELECT f1.id,
                    f1.size,
                    f1.mime_type,
                    f1.name
                   FROM storage.files f1
                  WHERE ((f1.domain_id = c.domain_id) AND ((f1.uuid)::text = (c.id)::text))
                UNION ALL
                 SELECT f1.id,
                    f1.size,
                    f1.mime_type,
                    f1.name
                   FROM storage.files f1
                  WHERE ((f1.domain_id = c.domain_id) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) f ON (((c.answered_at IS NOT NULL) OR (c.bridged_at IS NOT NULL))))
     LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
     LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
     LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
     LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
     LEFT JOIN call_center.cc_agent_with_user cag ON ((cma.agent_id = cag.id)))
     LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
     LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)));


--
-- Name: cc_calls_transcribe; Type: TABLE; Schema: call_center; Owner: -
--

CREATE TABLE call_center.cc_calls_transcribe (
    id bigint NOT NULL,
    call_id character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    transcribe character varying
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
-- Name: cc_communication_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_communication_view AS
 SELECT c.id,
    c.name,
    c.code,
    c.description,
    c.type,
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
    NULL::boolean AS wait_between_retries_desc;


--
-- Name: cc_distribute_stats; Type: MATERIALIZED VIEW; Schema: call_center; Owner: -
--

CREATE MATERIALIZED VIEW call_center.cc_distribute_stats AS
 SELECT att.queue_id,
    att.bucket_id,
    count(*) AS cnt,
    count(*) FILTER (WHERE (att.bridged_at IS NULL)) AS nbr_cnt,
    count(*) FILTER (WHERE (att.bridged_at IS NOT NULL)) AS br_cnt,
    COALESCE(date_part('epoch'::text, avg((att.answered_at - att.joined_at)) FILTER (WHERE (att.answered_at IS NOT NULL))), (0)::double precision) AS distr_t,
    count(*) FILTER (WHERE ((att.bridged_at IS NULL) AND (att.answered_at IS NOT NULL))) AS predict_abandoned_cnt,
    GREATEST(
        CASE
            WHEN (count(*) FILTER (WHERE (att.bridged_at IS NOT NULL)) > 0) THEN ((count(*))::double precision / (count(*) FILTER (WHERE (att.bridged_at IS NOT NULL)))::double precision)
            ELSE (1)::double precision
        END, (1)::double precision) AS connect_rate
   FROM call_center.cc_member_attempt_history att
  WHERE (att.joined_at > (now() - '01:00:00'::interval))
  GROUP BY att.queue_id, att.bucket_id
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
-- Name: cc_list_communications_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_list_communications_view AS
 SELECT i.id,
    i.number,
    i.description,
    i.list_id,
    cl.domain_id
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
    last_error_at bigint DEFAULT 0,
    created_at bigint NOT NULL,
    created_by bigint NOT NULL,
    updated_by bigint NOT NULL,
    error_ids character varying(50)[] DEFAULT '{}'::character varying[],
    gateway_id bigint,
    email_profile_id integer,
    payload jsonb
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
    t.joined_at AS joined_at_timestamp
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
     LEFT JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
     LEFT JOIN call_center.cc_member cm ON ((t.member_id = cm.id)))
     LEFT JOIN call_center.cc_agent a ON ((t.agent_id = a.id)))
     LEFT JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (u.dc = a.domain_id))))
     LEFT JOIN call_center.cc_outbound_resource r ON ((r.id = t.resource_id)))
     LEFT JOIN call_center.cc_bucket cb ON ((cb.id = t.bucket_id)))
     LEFT JOIN call_center.cc_list l ON ((l.id = t.list_communication_id)));


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
-- Name: cc_outbound_resource_in_group_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_outbound_resource_in_group_view AS
 SELECT s.id,
    s.group_id,
    call_center.cc_get_lookup((cor.id)::bigint, cor.name) AS resource,
    s.resource_id,
    cor.name AS resource_name,
    cor.domain_id
   FROM ((call_center.cc_outbound_resource_in_group s
     LEFT JOIN call_center.cc_outbound_resource cor ON ((s.resource_id = cor.id)))
     LEFT JOIN call_center.cc_outbound_resource_group corg ON ((s.group_id = corg.id)));


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
    s.gateway_id
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
    created_by bigint NOT NULL,
    updated_by bigint NOT NULL,
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
    COALESCE(ss.member_count, (0)::bigint) AS count,
    COALESCE(ss.member_waiting, (0)::bigint) AS waiting,
    COALESCE(act.cnt, (0)::bigint) AS active,
    q.sticky_agent,
    q.processing,
    q.processing_sec,
    q.processing_renewal_sec
   FROM (((((((((((call_center.cc_queue q
     JOIN flow.calendar c ON ((q.calendar_id = c.id)))
     LEFT JOIN directory.wbt_user uc ON ((uc.id = q.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = q.updated_by)))
     LEFT JOIN flow.acr_routing_scheme s ON ((q.schema_id = s.id)))
     LEFT JOIN flow.acr_routing_scheme ds ON ((q.do_schema_id = ds.id)))
     LEFT JOIN flow.acr_routing_scheme afs ON ((q.after_schema_id = afs.id)))
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
-- Name: cc_queue_resource_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_queue_resource_view AS
 SELECT q.id,
    q.queue_id,
    call_center.cc_get_lookup(g.id, ((g.name)::text)::character varying) AS resource_group,
    g.name AS resource_group_name,
    g.domain_id
   FROM (call_center.cc_queue_resource q
     LEFT JOIN call_center.cc_outbound_resource_group g ON ((q.resource_group_id = g.id)));


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
    sa.capacity,
    sa.enabled,
    ca.domain_id,
    sa.skill_id,
    cs.name AS skill_name,
    sa.agent_id,
    COALESCE(u.name, (u.username)::text) AS agent_name
   FROM (((((call_center.cc_skill_in_agent sa
     LEFT JOIN call_center.cc_agent ca ON ((sa.agent_id = ca.id)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = ca.user_id)))
     LEFT JOIN call_center.cc_skill cs ON ((sa.skill_id = cs.id)))
     LEFT JOIN directory.wbt_user c ON ((c.id = sa.created_by)))
     LEFT JOIN directory.wbt_user u ON ((u.id = sa.updated_by)));


--
-- Name: cc_skill_view; Type: VIEW; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_skill_view AS
 SELECT c.id,
    c.name,
    c.description,
    c.domain_id
   FROM call_center.cc_skill c;


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
    array_agg(DISTINCT ROW(res.communication_id, (res.id)::bigint, res.t, 0)::call_center.cc_sys_distribute_type) AS types,
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
    adm."user" AS admin,
    t.domain_id,
    t.admin_id
   FROM (call_center.cc_team t
     LEFT JOIN call_center.cc_agent_with_user adm ON ((adm.id = t.admin_id)));


--
-- Name: cc_agent id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_id_seq'::regclass);


--
-- Name: cc_agent_acl id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_acl ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_acl_id_seq'::regclass);


--
-- Name: cc_agent_attempt id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_attempt ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_attempt_id_seq'::regclass);


--
-- Name: cc_agent_state_history id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_state_history ALTER COLUMN id SET DEFAULT nextval('call_center.cc_agent_history_id_seq'::regclass);


--
-- Name: cc_attempt_missed_agent id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_attempt_missed_agent ALTER COLUMN id SET DEFAULT nextval('call_center.cc_attempt_missed_agent_id_seq'::regclass);


--
-- Name: cc_bucket id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket ALTER COLUMN id SET DEFAULT nextval('call_center.cc_bucket_id_seq'::regclass);


--
-- Name: cc_bucket_in_queue id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_bucket_in_queue ALTER COLUMN id SET DEFAULT nextval('call_center.cc_bucket_in_queue_id_seq'::regclass);


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
-- Name: cc_skill id; Type: DEFAULT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_skill ALTER COLUMN id SET DEFAULT nextval('call_center.cc_skils_id_seq'::regclass);


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
-- Name: cc_agent_channel cc_agent_channel_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent_channel
    ADD CONSTRAINT cc_agent_channel_pk PRIMARY KEY (agent_id);


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
-- Name: cc_pause_cause cc_agent_status_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause
    ADD CONSTRAINT cc_agent_status_pk PRIMARY KEY (id);


--
-- Name: cc_attempt_missed_agent cc_attempt_missed_agent_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_attempt_missed_agent
    ADD CONSTRAINT cc_attempt_missed_agent_pk PRIMARY KEY (id);


--
-- Name: cc_member_attempt_transferred cc_attempt_transferred_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member_attempt_transferred
    ADD CONSTRAINT cc_attempt_transferred_pk PRIMARY KEY (id);


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
-- Name: cc_team cc_team_pk; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_pk PRIMARY KEY (id);


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
-- Name: cc_agent_attempt_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_attempt_id_uindex ON call_center.cc_agent_attempt USING btree (id);


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
-- Name: cc_agent_today_pause_cause_agent_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_today_pause_cause_agent_idx ON call_center.cc_agent_today_pause_cause USING btree (id);


--
-- Name: cc_agent_updated_by_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_agent_updated_by_index ON call_center.cc_agent USING btree (updated_by);


--
-- Name: cc_agent_user_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_user_id_uindex ON call_center.cc_agent USING btree (user_id);


--
-- Name: cc_attempt_missed_agent_id_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_attempt_missed_agent_id_uindex ON call_center.cc_attempt_missed_agent USING btree (id);


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
-- Name: cc_list_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_list_domain_id_name_uindex ON call_center.cc_list USING btree (domain_id, name);


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
-- Name: cc_member_attempt_history_domain_id_queue_id_joined_at_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_domain_id_queue_id_joined_at_index ON call_center.cc_member_attempt_history USING btree (domain_id, queue_id, joined_at DESC);


--
-- Name: cc_member_attempt_history_joined_at_agent_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_attempt_history_joined_at_agent_id_index ON call_center.cc_member_attempt_history USING btree (joined_at DESC, agent_id);


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
-- Name: cc_member_queue_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_queue_id_index ON call_center.cc_member USING btree (queue_id);


--
-- Name: cc_member_search_destination_idx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_member_search_destination_idx ON call_center.cc_member USING gin (domain_id, communications jsonb_path_ops);


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
-- Name: cc_outbound_resource_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_outbound_resource_domain_id_name_uindex ON call_center.cc_outbound_resource USING btree (domain_id, name);


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
-- Name: cc_queue_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_domain_id_name_uindex ON call_center.cc_queue USING btree (domain_id, name);


--
-- Name: cc_queue_domain_udx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_queue_domain_udx ON call_center.cc_queue USING btree (id, domain_id);


--
-- Name: cc_queue_enabled_priority_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_queue_enabled_priority_index ON call_center.cc_queue USING btree (enabled, priority DESC);


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
-- Name: cc_skill_domain_id_name_uindex; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_skill_domain_id_name_uindex ON call_center.cc_skill USING btree (domain_id, name);


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
-- Name: cc_team_admin_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX cc_team_admin_id_index ON call_center.cc_team USING btree (admin_id);


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
-- Name: cc_agent_in_queue_view _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_agent_in_queue_view AS
 SELECT call_center.cc_get_lookup((q.id)::bigint, q.name) AS queue,
    q.priority,
    q.type,
    q.strategy,
    q.enabled,
    COALESCE(sum(cqs.member_count), (0)::bigint) AS count_members,
    COALESCE(
        CASE
            WHEN (q.type = 1) THEN ( SELECT count(*) AS count
               FROM call_center.cc_member_attempt a1
              WHERE ((a1.queue_id = q.id) AND (a1.bridged_at IS NULL)))
            ELSE ( SELECT count(1) AS count
               FROM call_center.cc_member m
              WHERE ((m.stop_at IS NULL) AND (m.queue_id = q.id) AND ((m.ready_at IS NULL) OR (m.ready_at < now())) AND ((m.expire_at IS NULL) OR (m.expire_at > now()))))
        END, (0)::bigint) AS waiting_members,
    ( SELECT count(*) AS count
           FROM call_center.cc_member_attempt a_1
          WHERE (a_1.queue_id = q.id)) AS active_members,
    q.id AS queue_id,
    q.name AS queue_name,
    a.domain_id,
    a.id AS agent_id
   FROM ((call_center.cc_agent a
     JOIN call_center.cc_queue q ON ((q.team_id = a.team_id)))
     LEFT JOIN call_center.cc_queue_statistics cqs ON ((q.id = cqs.queue_id)))
  WHERE (EXISTS ( SELECT qs.queue_id
           FROM (call_center.cc_queue_skill qs
             JOIN call_center.cc_skill_in_agent csia ON ((csia.skill_id = qs.skill_id)))
          WHERE (qs.enabled AND csia.enabled AND (csia.agent_id = a.id) AND (qs.queue_id = q.id) AND (csia.capacity >= qs.min_capacity) AND (csia.capacity <= qs.max_capacity))))
  GROUP BY a.id, q.id, q.priority;


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
                    WHEN q_1.sticky_agent THEN COALESCE(((q_1.payload -> 'sticky_agent_sec'::text))::integer, 30)
                    ELSE NULL::integer
                END AS sticky_agent_sec,
                CASE
                    WHEN ((q_1.strategy)::text = 'lifo'::text) THEN 1
                    ELSE 0
                END AS strategy,
            q_1.priority,
            q_1.team_id,
            ((q_1.payload -> 'max_calls'::text))::integer AS lim,
            ((q_1.payload -> 'wait_between_retries_desc'::text))::boolean AS wait_between_retries_desc,
            array_agg(ROW((m.bucket_id)::integer, (m.member_waiting)::integer, m.op)::call_center.cc_sys_distribute_bucket ORDER BY cbiq.ratio DESC NULLS LAST, m.bucket_id) AS buckets,
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
          WHERE ((m.member_waiting > 0) AND q_1.enabled AND (q_1.type > 0) AND (m.pos = 1))
          GROUP BY q_1.domain_id, q_1.id, q_1.calendar_id, q_1.type, m.op
         LIMIT 1024
        ), calend AS MATERIALIZED (
         SELECT c.id AS calendar_id,
            queues.id AS queue_id,
                CASE
                    WHEN (queues.recall_calendar AND (NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id))))) THEN ((array_agg(DISTINCT o1.id))::integer[] + (tz.offset_id)::integer)
                    ELSE (array_agg(DISTINCT o1.id))::integer[]
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
         SELECT cqr.queue_id,
            array_agg(DISTINCT ROW(corg.communication_id, (cor.id)::bigint, ((l_1.l & (l2.x)::integer[]))::smallint[], (corg.id)::integer)::call_center.cc_sys_distribute_type) AS types,
            array_agg(DISTINCT ROW((cor.id)::bigint, ((cor."limit" - used.cnt))::integer)::call_center.cc_sys_distribute_resource) AS resources,
            call_center.cc_array_merge_agg((l_1.l & (l2.x)::integer[])) AS offset_ids
           FROM ((((((call_center.cc_queue_resource cqr
             JOIN call_center.cc_outbound_resource_group corg ON ((cqr.resource_group_id = corg.id)))
             JOIN call_center.cc_outbound_resource_in_group corig ON ((corg.id = corig.group_id)))
             JOIN call_center.cc_outbound_resource cor ON ((corig.resource_id = cor.id)))
             JOIN calend l_1 ON ((l_1.queue_id = cqr.queue_id)))
             JOIN LATERAL ( WITH times AS (
                         SELECT ((e.value -> 'start_time_of_day'::text))::integer AS start,
                            ((e.value -> 'end_time_of_day'::text))::integer AS "end"
                           FROM jsonb_array_elements(corg."time") e(value)
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
          WHERE (cor.enabled AND (NOT cor.reserve) AND ((cor."limit" - used.cnt) > 0))
          GROUP BY cqr.queue_id
        )
 SELECT q.id,
    q.type,
    (q.strategy)::smallint AS strategy,
    q.team_id,
    q.buckets,
    r.types,
    r.resources,
        CASE
            WHEN (q.type = 7) THEN calend.l
            ELSE r.offset_ids
        END AS offset_ids,
    ((q.lim - COALESCE(l.usage, (0)::bigint)))::integer AS lim,
    q.domain_id,
    q.priority,
    q.sticky_agent,
    q.sticky_agent_sec,
    calend.recall_calendar,
    q.wait_between_retries_desc
   FROM (((queues q
     LEFT JOIN calend ON ((calend.queue_id = q.id)))
     LEFT JOIN resources r ON ((q.op AND (r.queue_id = q.id))))
     LEFT JOIN LATERAL ( SELECT count(*) AS usage
           FROM call_center.cc_member_attempt a
          WHERE (a.queue_id = q.id)) l ON ((q.lim > 0)))
  WHERE ((q.type = ANY (ARRAY[1, 6, 7])) OR ((q.type = 5) AND (NOT q.op)) OR (q.op AND (q.type = ANY (ARRAY[2, 3, 4, 5])) AND (r.* IS NOT NULL)));


--
-- Name: cc_agent cc_agent_init_channel_ins; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_agent_init_channel_ins AFTER INSERT ON call_center.cc_agent FOR EACH ROW EXECUTE FUNCTION call_center.cc_agent_init_channel();


--
-- Name: cc_agent cc_agent_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_agent_set_rbac_acl AFTER INSERT ON call_center.cc_agent FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_agent');


--
-- Name: cc_calls cc_calls_set_timing_trigger_updated; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_calls_set_timing_trigger_updated BEFORE INSERT OR UPDATE ON call_center.cc_calls FOR EACH ROW EXECUTE FUNCTION call_center.cc_calls_set_timing();


--
-- Name: cc_list cc_list_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_list_set_rbac_acl AFTER INSERT ON call_center.cc_list FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_list');


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
-- Name: cc_team cc_team_set_rbac_acl; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_team_set_rbac_acl AFTER INSERT ON call_center.cc_team FOR EACH ROW EXECUTE FUNCTION call_center.tg_obj_default_rbac('cc_team');


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
-- Name: cc_agent cc_agent_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_cc_agent_id_fk FOREIGN KEY (supervisor_id) REFERENCES call_center.cc_agent(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


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
-- Name: cc_pause_cause cc_agent_status_wbt_domain_dc_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause
    ADD CONSTRAINT cc_agent_status_wbt_domain_dc_fk FOREIGN KEY (domain_id) REFERENCES directory.wbt_domain(dc) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: cc_pause_cause cc_agent_status_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause
    ADD CONSTRAINT cc_agent_status_wbt_user_id_fk FOREIGN KEY (created_by) REFERENCES directory.wbt_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


--
-- Name: cc_pause_cause cc_agent_status_wbt_user_id_fk_2; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_pause_cause
    ADD CONSTRAINT cc_agent_status_wbt_user_id_fk_2 FOREIGN KEY (updated_by) REFERENCES directory.wbt_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


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
-- Name: cc_agent cc_agent_wbt_user_id_fk_4; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_agent
    ADD CONSTRAINT cc_agent_wbt_user_id_fk_4 FOREIGN KEY (auditor_id) REFERENCES directory.wbt_user(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


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
-- Name: cc_calls cc_calls_cc_member_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_calls
    ADD CONSTRAINT cc_calls_cc_member_id_fk FOREIGN KEY (member_id) REFERENCES call_center.cc_member(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


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
-- Name: cc_member cc_member_calendar_timezones_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_calendar_timezones_id_fk FOREIGN KEY (timezone_id) REFERENCES flow.calendar_timezones(id);


--
-- Name: cc_member cc_member_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_member
    ADD CONSTRAINT cc_member_cc_agent_id_fk FOREIGN KEY (agent_id) REFERENCES call_center.cc_agent(id);


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
-- Name: cc_team cc_team_cc_agent_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_team
    ADD CONSTRAINT cc_team_cc_agent_id_fk FOREIGN KEY (admin_id) REFERENCES call_center.cc_agent(id) ON UPDATE RESTRICT ON DELETE RESTRICT;


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

