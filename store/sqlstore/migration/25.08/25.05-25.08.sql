
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
-- Name: cc_agent_set_login(integer, boolean); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE OR REPLACE FUNCTION call_center.cc_agent_set_login(agent_id_ integer, on_demand_ boolean DEFAULT false) RETURNS record
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


alter table call_center.cc_calls add column destination_name text;
alter table call_center.cc_calls add column attempt_ids bigint[];



--
-- Name: cc_distribute(boolean); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE OR REPLACE PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean)
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


alter table call_center.cc_agent add column screen_control boolean DEFAULT false NOT NULL;
alter table call_center.cc_team add column screen_control boolean DEFAULT false NOT NULL;



DROP VIEW call_center.cc_agent_list;
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


alter table call_center.cc_calls_history add column destination_name text;
alter table call_center.cc_calls_history add column attempt_ids bigint[];


drop MATERIALIZED VIEW call_center.cc_agent_today_stats;
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
        WHERE h.bridged_at IS NOT NULL and ((h.leaving_at > ((now())::date - '2 days'::interval)) AND ((h.leaving_at >= a_1."from") AND (h.leaving_at <= a_1."to")) AND ((h.channel)::text = ANY (ARRAY['chat'::text, 'task'::text])) AND (h.agent_id IS NOT NULL) AND (1 = 1))
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


create unique index cc_agent_today_stats_uidx
    on call_center.cc_agent_today_stats (agent_id);

create unique index cc_agent_today_stats_usr_uidx
    on call_center.cc_agent_today_stats (user_id);

refresh materialized view call_center.cc_agent_today_stats;

alter table call_center.cc_audit_form alter column updated_by drop not null ;
alter table call_center.cc_audit_form alter column created_by drop not null ;


drop VIEW call_center.cc_calls_history_list;
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


DROP VIEW call_center.cc_quick_reply_list;

alter table call_center.cc_quick_reply
    alter column created_at type timestamptz using created_at::timestamptz;
alter table call_center.cc_quick_reply
    alter column updated_at type timestamptz using updated_at::timestamptz;

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


DROP VIEW call_center.cc_team_list;
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




DROP  INDEX IF EXISTS call_center.cc_preset_query_user_id_name_uindex;


--
-- Name: cc_preset_query cc_preset_query_user_id_section_name_uindex; Type: CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.cc_preset_query
    ADD CONSTRAINT cc_preset_query_user_id_section_name_uindex UNIQUE (user_id, section, name);


--
-- Name: socket_session_app_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX socket_session_app_id_index ON call_center.socket_session USING btree (app_id);


--
-- Name: socket_session_user_id_index; Type: INDEX; Schema: call_center; Owner: -
--

CREATE INDEX socket_session_user_id_index ON call_center.socket_session USING btree (user_id);


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


DROP VIEW call_center.cc_sys_queue_distribute_resources;
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
-- Name: cc_team cc_team_changed_tg_u; Type: TRIGGER; Schema: call_center; Owner: -
--

CREATE TRIGGER cc_team_changed_tg_u AFTER UPDATE ON call_center.cc_team FOR EACH ROW WHEN ((new.screen_control IS DISTINCT FROM old.screen_control)) EXECUTE FUNCTION call_center.cc_team_changed_tg();



--
-- Name: socket_session socket_session_wbt_user_id_fk; Type: FK CONSTRAINT; Schema: call_center; Owner: -
--

ALTER TABLE ONLY call_center.socket_session
    ADD CONSTRAINT socket_session_wbt_user_id_fk FOREIGN KEY (user_id) REFERENCES directory.wbt_user(id);


-- WEBRTC

CREATE SCHEMA webrtc_rec;


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
