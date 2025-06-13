
--
-- Name: cc_agent_init_channel(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_agent_init_channel() RETURNS trigger
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
-- Name: cc_distribute_inbound_call_to_agent(character varying, character varying, jsonb, integer, jsonb); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer, q_params jsonb DEFAULT NULL::jsonb) RETURNS record
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


ALTER TABLE call_center.cc_audit_rate
    ADD COLUMN if not exists select_yes_count bigint DEFAULT 0,
    ADD COLUMN if not exists critical_count bigint DEFAULT 0;



DROP  MATERIALIZED VIEW call_center.cc_agent_today_stats;
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
    LEFT JOIN attempts cht ON (((cht.agent_id = a.id) AND ((chc.channel)::text = 'task'::text))))
    LEFT JOIN rate ON ((rate.user_id = a.user_id)))
WITH NO DATA;


DROP VIEW call_center.cc_audit_form_view;
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


DROP VIEW call_center.cc_audit_rate_view;
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

--
-- Name: cc_sys_queue_distribute_resources _RETURN; Type: RULE; Schema: call_center; Owner: -
--

CREATE VIEW call_center.cc_sys_queue_distribute_resources AS
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

DROP VIEW call_center.cc_agent_in_queue_view;
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


DROP VIEW call_center.cc_queue_report_general;
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
-- Name: cc_agent_today_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_uidx ON call_center.cc_agent_today_stats USING btree (agent_id);


--
-- Name: cc_agent_today_stats_usr_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_usr_uidx ON call_center.cc_agent_today_stats USING btree (user_id);


insert into call_center.cc_agent_channel (agent_id, channel, state)
select a.id, 'out_call', 'waiting'
from call_center.cc_agent a
where not exists(select 1 from call_center.cc_agent_channel c where c.agent_id = a.id
                                                                and c.channel = 'out_call');

REFRESH MATERIALIZED VIEW call_center.cc_agent_today_stats;


alter table storage.file_policies add column encrypt boolean DEFAULT false;


DROP VIEW storage.file_policies_view;
--
-- Name: file_policies_view; Type: VIEW; Schema: storage; Owner: -
--

CREATE VIEW storage.file_policies_view AS
SELECT p.id,
       p.domain_id,
       p.created_at,
       storage.get_lookup(c.id, (COALESCE(c.name, (c.username)::text))::character varying) AS created_by,
       p.updated_at,
       storage.get_lookup(u.id, (COALESCE(u.name, (u.username)::text))::character varying) AS updated_by,
       p.enabled,
       p.name,
       p.description,
       p.channels,
       p.mime_types,
       p.speed_download,
       p.speed_upload,
       p.max_upload_size,
       p.retention_days,
       p.encrypt,
       row_number() OVER (PARTITION BY p.domain_id ORDER BY p."position" DESC) AS "position"
FROM ((storage.file_policies p
    LEFT JOIN directory.wbt_user c ON ((c.id = p.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = p.updated_by)));


