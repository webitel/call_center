DROP MATERIALIZED VIEW call_center.cc_agent_today_stats;
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
    WHERE ((h.joined_at > now()::date - interval '1d') and (h.domain_id = agents.domain_id) AND (h.joined_at >= agents."from") AND (h.joined_at <= agents."to") AND ((h.channel)::text = 'call'::text))
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


--
-- Name: cc_agent_today_stats_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_uidx ON call_center.cc_agent_today_stats USING btree (agent_id);


--
-- Name: cc_agent_today_stats_usr_uidx; Type: INDEX; Schema: call_center; Owner: -
--

CREATE UNIQUE INDEX cc_agent_today_stats_usr_uidx ON call_center.cc_agent_today_stats USING btree (user_id);

REFRESH MATERIALIZED VIEW call_center.cc_agent_today_stats;
