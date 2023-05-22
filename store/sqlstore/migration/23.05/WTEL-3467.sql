drop materialized view if exists call_center.cc_distribute_stats;
drop view if exists  call_center.cc_member_view_attempt_history;
drop view if exists  call_center.cc_calls_history_list;
drop materialized view if exists  call_center.cc_agent_today_stats;

drop  view call_center.cc_call_active_list ;
drop procedure call_center.cc_call_set_bridged;

ALTER TABLE call_center.cc_calls_history ALTER COLUMN id type uuid USING id::uuid;
ALTER TABLE call_center.cc_calls_history ALTER COLUMN parent_id type uuid USING parent_id::uuid;
ALTER TABLE call_center.cc_calls_history ALTER COLUMN bridged_id type uuid USING bridged_id::uuid;
ALTER TABLE call_center.cc_calls_history ALTER COLUMN transfer_from type uuid USING transfer_from::uuid;
ALTER TABLE call_center.cc_calls_history ALTER COLUMN transfer_to type uuid USING transfer_to::uuid;

ALTER TABLE call_center.cc_calls ALTER COLUMN id type uuid USING id::uuid;
ALTER TABLE call_center.cc_calls ALTER COLUMN parent_id type uuid USING parent_id::uuid;
ALTER TABLE call_center.cc_calls ALTER COLUMN bridged_id type uuid USING bridged_id::uuid;
ALTER TABLE call_center.cc_calls ALTER COLUMN transfer_from type uuid USING transfer_from::uuid;
ALTER TABLE call_center.cc_calls ALTER COLUMN transfer_to type uuid USING transfer_to::uuid;


create materialized view call_center.cc_distribute_stats as
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
       s.over_dial,
       s.abandoned_rate,
       s.hit_rate,
       s.agents,
       s.aggent_ids
FROM call_center.cc_queue q
         LEFT JOIN LATERAL ( SELECT CASE
                                        WHEN ((q.payload -> 'amd'::text) -> 'allow_not_sure'::text)::boolean IS TRUE
                                            THEN ARRAY ['HUMAN'::text, 'NOTSURE'::text]
                                        ELSE ARRAY ['HUMAN'::text]
                                        END AS arr) amd ON true
         JOIN LATERAL ( SELECT att.queue_id,
                               att.bucket_id,
                               min(att.joined_at)                                                                     AS start_stat,
                               max(att.joined_at)                                                                     AS stop_stat,
                               count(*)                                                                               AS call_attempts,
                               COALESCE(avg(date_part('epoch'::text,
                                                      COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))
                                        FILTER (WHERE att.bridged_at IS NOT NULL),
                                        0::double precision)                                                          AS avg_handle,
                               COALESCE(avg(DISTINCT round(date_part('epoch'::text,
                                                                     COALESCE(att.reporting_at, att.leaving_at) -
                                                                     att.offering_at))::real)
                                        FILTER (WHERE att.bridged_at IS NOT NULL),
                                        0::double precision)                                                          AS med_handle,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL),
                                        0::double precision)                                                          AS avg_member_answer,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL AND ch.bridged_at IS NULL),
                                        0::double precision)                                                          AS avg_member_answer_not_bridged,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL AND ch.bridged_at IS NOT NULL),
                                        0::double precision)                                                          AS avg_member_answer_bridged,
                               COALESCE(max(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL),
                                        0::double precision)                                                          AS max_member_answer,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)                   AS connected_calls,
                               count(*) FILTER (WHERE att.bridged_at IS NOT NULL)                                     AS bridged_calls,
                               count(*)
                               FILTER (WHERE ch.answered_at IS NOT NULL AND att.bridged_at IS NULL AND amd_res.human) AS abandoned_calls,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)::double precision /
                               count(*)::double precision                                                             AS connection_rate,
                               CASE
                                   WHEN (count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)::double precision /
                                         count(*)::double precision) > 0::double precision THEN 1::double precision /
                                                                                                (count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)::double precision /
                                                                                                 count(*)::double precision)
                                   ELSE (count(*) / GREATEST(count(DISTINCT att.agent_id), 1::bigint) - 1)::double precision
                                   END                                                                                AS over_dial,
                               COALESCE((count(*)
                                         FILTER (WHERE ch.answered_at IS NOT NULL AND att.bridged_at IS NULL AND amd_res.human)::double precision -
                                         COALESCE((q.payload -> 'abandon_rate_adjustment'::text)::integer,
                                                  0)::double precision) /
                                        NULLIF(count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human),
                                               0)::double precision * 100::double precision,
                                        0::double precision)                                                          AS abandoned_rate,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND amd_res.human)::double precision /
                               count(*)::double precision                                                             AS hit_rate,
                               count(DISTINCT att.agent_id)                                                           AS agents,
                               array_agg(DISTINCT att.agent_id)
                               FILTER (WHERE att.agent_id IS NOT NULL)                                                AS aggent_ids
                        FROM call_center.cc_member_attempt_history att
                                 LEFT JOIN call_center.cc_calls_history ch
                                           ON ch.domain_id = att.domain_id AND ch.id::uuid = att.member_call_id::uuid
                                 LEFT JOIN LATERAL ( SELECT ch.amd_result IS NULL AND ch.amd_ai_positive IS NULL OR
                                                            (ch.amd_result::text = ANY (amd.arr)) OR
                                                            ch.amd_ai_positive IS TRUE AS human) amd_res ON true
                        WHERE att.channel::text = 'call'::text
                          AND att.joined_at > (now() - ((COALESCE((q.payload -> 'statistic_time'::text)::integer, 60) ||
                                                         ' min'::text)::interval))
                          AND att.queue_id = q.id
                          AND att.domain_id = q.domain_id
                        GROUP BY att.queue_id, att.bucket_id) s ON s.queue_id IS NOT NULL
WHERE q.type = 5
  AND q.enabled;

create unique index cc_distribute_stats_uidx
    on call_center.cc_distribute_stats (queue_id, bucket_id);

refresh materialized view call_center.cc_distribute_stats;


create view call_center.cc_member_view_attempt_history
            (id, joined_at, offering_at, bridged_at, reporting_at, leaving_at, channel, queue, member, member_call_id,
             variables, agent, agent_call_id, position, resource, bucket, list, display, destination, result, domain_id,
             queue_id, bucket_id, member_id, agent_id, attempts, amd_result)
as
SELECT t.id,
       t.joined_at,
       t.offering_at,
       t.bridged_at,
       t.reporting_at,
       t.leaving_at,
       t.channel,
       call_center.cc_get_lookup(t.queue_id::bigint, cq.name)                                               AS queue,
       call_center.cc_get_lookup(t.member_id, cm.name)                                                      AS member,
       t.member_call_id,
       COALESCE(cm.variables, '{}'::jsonb)                                                                  AS variables,
       call_center.cc_get_lookup(t.agent_id::bigint, COALESCE(u.name, u.username::text)::character varying) AS agent,
       t.agent_call_id,
       t.weight                                                                                             AS "position",
       call_center.cc_get_lookup(t.resource_id::bigint, r.name)                                             AS resource,
       call_center.cc_get_lookup(t.bucket_id, cb.name::character varying)                                   AS bucket,
       call_center.cc_get_lookup(t.list_communication_id, l.name)                                           AS list,
       COALESCE(t.display, ''::character varying)                                                           AS display,
       t.destination,
       t.result,
       t.domain_id,
       t.queue_id,
       t.bucket_id,
       t.member_id,
       t.agent_id,
       t.seq                                                                                                AS attempts,
       c.amd_result
FROM call_center.cc_member_attempt_history t
         LEFT JOIN call_center.cc_queue cq ON t.queue_id = cq.id
         LEFT JOIN call_center.cc_member cm ON t.member_id = cm.id
         LEFT JOIN call_center.cc_agent a ON t.agent_id = a.id
         LEFT JOIN directory.wbt_user u ON u.id = a.user_id AND u.dc = a.domain_id
         LEFT JOIN call_center.cc_outbound_resource r ON r.id = t.resource_id
         LEFT JOIN call_center.cc_bucket cb ON cb.id = t.bucket_id
         LEFT JOIN call_center.cc_list l ON l.id = t.list_communication_id
         LEFT JOIN call_center.cc_calls_history c ON c.domain_id = t.domain_id AND c.id::text = t.member_call_id::text;


create or replace view call_center.cc_calls_history_list
as
SELECT c.id,
       c.app_id,
       'call'::character varying                                                                                    AS type,
       c.parent_id,
       c.transfer_from,
       CASE
           WHEN c.parent_id IS NOT NULL AND c.transfer_to IS NULL AND c.id::text <> lega.bridged_id::text
               THEN lega.bridged_id
           ELSE c.transfer_to
           END                                                                                                      AS transfer_to,
       call_center.cc_get_lookup(u.id,
                                 COALESCE(u.name, u.username::text)::character varying)                             AS "user",
       CASE
           WHEN cq.type = ANY (ARRAY [4, 5]) THEN cag.extension
           ELSE u.extension
           END                                                                                                      AS extension,
       call_center.cc_get_lookup(gw.id, gw.name)                                                                    AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number',
                         COALESCE(c.from_number, ''::character varying), 'id',
                         COALESCE(c.from_id, ''::character varying), 'name',
                         COALESCE(c.from_name, ''::character varying))                                              AS "from",
       json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number',
                         COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying),
                         'name',
                         COALESCE(c.to_name, ''::character varying))                                                AS "to",
       c.payload                                                                                                    AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       c.stored_at,
       COALESCE(c.hangup_by, ''::character varying)                                                                 AS hangup_by,
       c.cause,
       date_part('epoch'::text, c.hangup_at - c.created_at)::bigint                                                 AS duration,
       COALESCE(c.hold_sec, 0)                                                                                      AS hold_sec,
       COALESCE(
               CASE
                   WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.answered_at - c.created_at)::bigint
                   ELSE date_part('epoch'::text, c.hangup_at - c.created_at)::bigint
                   END,
               0::bigint)                                                                                           AS wait_sec,
       CASE
           WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.hangup_at - c.answered_at)::bigint
           ELSE 0::bigint
           END                                                                                                      AS bill_sec,
       c.sip_code,
       f.files,
       call_center.cc_get_lookup(cq.id::bigint, cq.name)                                                            AS queue,
       call_center.cc_get_lookup(cm.id::bigint, cm.name)                                                            AS member,
       call_center.cc_get_lookup(ct.id, ct.name)                                                                    AS team,
       call_center.cc_get_lookup(aa.id::bigint,
                                 COALESCE(cag.username, cag.name::name)::character varying)                         AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at                                                                                               AS queue_bridged_at,
       CASE
           WHEN cma.bridged_at IS NOT NULL THEN date_part('epoch'::text, cma.bridged_at - cma.joined_at)::integer
           ELSE date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer
           END                                                                                                      AS queue_wait_sec,
       date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer                                            AS queue_duration_sec,
       cma.result,
       CASE
           WHEN cma.reporting_at IS NOT NULL THEN date_part('epoch'::text, cma.reporting_at - cma.leaving_at)::integer
           ELSE 0
           END                                                                                                      AS reporting_sec,
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
       (EXISTS(SELECT 1
               FROM call_center.cc_calls_history hp
               WHERE c.parent_id IS NULL
                 AND hp.parent_id::uuid = c.id::uuid))                                                              AS has_children,
       COALESCE(regexp_replace(cma.description::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text),
                ''::character varying::text)::character varying                                                     AS agent_description,
       c.grantee_id,
       holds.res                                                                                                    AS hold,
       c.gateway_ids,
       c.user_ids,
       c.agent_ids,
       c.queue_ids,
       c.team_ids,
       (SELECT json_agg(row_to_json(annotations.*)) AS json_agg
        FROM (SELECT a.id,
                     a.call_id,
                     a.created_at,
                     call_center.cc_get_lookup(cc.id,
                                               COALESCE(cc.name, cc.username::text)::character varying)        AS created_by,
                     a.updated_at,
                     call_center.cc_get_lookup(uc.id,
                                               COALESCE(uc.name, uc.username::text)::character varying)        AS updated_by,
                     a.note,
                     a.start_sec,
                     a.end_sec
              FROM call_center.cc_calls_annotation a
                       LEFT JOIN directory.wbt_user cc ON cc.id = a.created_by
                       LEFT JOIN directory.wbt_user uc ON uc.id = a.updated_by
              WHERE a.call_id::text = c.id::text
              ORDER BY a.created_at DESC) annotations)                                                              AS annotations,
       COALESCE(c.amd_result, c.amd_ai_result)                                                                      AS amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       c.amd_ai_positive,
       cq.type                                                                                                      AS queue_type,
       CASE
           WHEN c.parent_id IS NOT NULL THEN ''::text
           WHEN c.cause::text = ANY (ARRAY ['USER_BUSY'::character varying::text, 'NO_ANSWER'::character varying::text])
               THEN 'not_answered'::text
           WHEN c.cause::text = 'ORIGINATOR_CANCEL'::text OR c.cause::text = 'LOSE_RACE'::text AND cq.type = 4
               THEN 'cancelled'::text
           WHEN c.hangup_by::text = 'F'::text THEN 'ended'::text
           WHEN c.cause::text = 'NORMAL_CLEARING'::text THEN
               CASE
                   WHEN c.cause::text = 'NORMAL_CLEARING'::text AND c.direction::text = 'outbound'::text AND
                        c.hangup_by::text = 'A'::text AND c.user_id IS NOT NULL OR
                        c.direction::text = 'inbound'::text AND c.hangup_by::text = 'B'::text AND
                        c.bridged_at IS NOT NULL OR
                        c.direction::text = 'outbound'::text AND c.hangup_by::text = 'B'::text AND
                        (cq.type = ANY (ARRAY [4, 5, 1])) AND c.bridged_at IS NOT NULL THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END                                                                                                      AS hangup_disposition,
       c.blind_transfer,
       (SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at),
                                           'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error,
                                           'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
        FROM storage.file_jobs j
        WHERE j.file_id = ANY (f.file_ids))                                                                         AS files_job,
       transcripts.data                                                                                             AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, au.name::character varying)                                                 AS grantee,
       ar.id                                                                                                        AS rate_id,
       call_center.cc_get_lookup(aru.id, COALESCE(aru.name::character varying,
                                                  aru.username::character varying))                                 AS rated_user,
       call_center.cc_get_lookup(arub.id, COALESCE(arub.name::character varying,
                                                   arub.username::character varying))                               AS rated_by,
       ar.score_optional,
       ar.score_required
FROM call_center.cc_calls_history c
         LEFT JOIN LATERAL ( SELECT array_agg(f_1.id)                                                       AS file_ids,
                                    json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size,
                                                                'mime_type', f_1.mime_type, 'start_at',
                                                                (c.params -> 'record_start'::text)::bigint, 'stop_at',
                                                                (c.params -> 'record_stop'::text)::bigint)) AS files
                             FROM (SELECT f1.id,
                                          f1.size,
                                          f1.mime_type,
                                          f1.name
                                   FROM storage.files f1
                                   WHERE f1.domain_id = c.domain_id
                                     AND NOT f1.removed IS TRUE
                                     AND f1.uuid::text = c.id::text
                                   UNION ALL
                                   SELECT f1.id,
                                          f1.size,
                                          f1.mime_type,
                                          f1.name
                                   FROM storage.files f1
                                   WHERE f1.domain_id = c.domain_id
                                     AND NOT f1.removed IS TRUE
                                     AND f1.uuid::text = c.parent_id::text) f_1) f
                   ON c.answered_at IS NOT NULL OR c.bridged_at IS NOT NULL
         LEFT JOIN LATERAL ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
                             FROM (SELECT jsonb_array_elements(chh.hold) AS hi
                                   FROM call_center.cc_calls_history chh
                                   WHERE chh.parent_id::uuid = c.id::uuid
                                     AND chh.hold IS NOT NULL
                                   UNION
                                   SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
                             WHERE x.hi IS NOT NULL) holds ON c.parent_id IS NULL
         LEFT JOIN call_center.cc_queue cq ON c.queue_id = cq.id
         LEFT JOIN call_center.cc_team ct ON c.team_id = ct.id
         LEFT JOIN call_center.cc_member cm ON c.member_id = cm.id
         LEFT JOIN call_center.cc_member_attempt_history cma ON cma.id = c.attempt_id
         LEFT JOIN call_center.cc_agent aa ON cma.agent_id = aa.id
         LEFT JOIN directory.wbt_user cag ON cag.id = aa.user_id
         LEFT JOIN directory.wbt_user u ON u.id = c.user_id
         LEFT JOIN directory.sip_gateway gw ON gw.id = c.gateway_id
         LEFT JOIN directory.wbt_auth au ON au.id = c.grantee_id
         LEFT JOIN call_center.cc_calls_history lega ON c.parent_id IS NOT NULL AND lega.id::uuid = c.parent_id::uuid
         LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id,
                                                               'file',
                                                               call_center.cc_get_lookup(ff.id, ff.name))) AS data
                             FROM storage.file_transcript tr
                                      LEFT JOIN storage.files ff ON ff.id = tr.file_id
                             WHERE tr.uuid::text = c.id::text
                             GROUP BY (tr.uuid::text)) transcripts ON true
         LEFT JOIN call_center.cc_audit_rate ar ON ar.call_id::text = c.id::text
         LEFT JOIN directory.wbt_user aru ON aru.id = ar.rated_user_id
         LEFT JOIN directory.wbt_user arub ON arub.id = ar.created_by;



create materialized view call_center.cc_agent_today_stats as
WITH agents AS MATERIALIZED (SELECT a_1.id,
                                    a_1.user_id,
                                    CASE
                                        WHEN a_1.last_state_change < d."from"::timestamp with time zone
                                            THEN d."from"::timestamp with time zone
                                        WHEN a_1.last_state_change < d."to" THEN a_1.last_state_change
                                        ELSE a_1.last_state_change
                                        END                                          AS cur_state_change,
                                    a_1.status,
                                    a_1.status_payload,
                                    a_1.last_state_change,
                                    lasts.last_at::timestamp with time zone          AS last_at,
                                    lasts.state                                      AS last_state,
                                    lasts.status_payload                             AS last_payload,
                                    COALESCE(top.top_at, a_1.last_state_change)      AS top_at,
                                    COALESCE(top.state, a_1.status)                  AS top_state,
                                    COALESCE(top.status_payload, a_1.status_payload) AS top_payload,
                                    d."from",
                                    d."to",
                                    a_1.domain_id,
                                    COALESCE(t.sys_name, 'UTC'::text)                AS tz_name
                             FROM call_center.cc_agent a_1
                                      LEFT JOIN flow.region r ON r.id = a_1.region_id
                                      LEFT JOIN flow.calendar_timezones t ON t.id = r.timezone_id
                                      LEFT JOIN LATERAL ( SELECT now()                                                                                           AS "to",
                                                                 now()::date + age(now(),
                                                                                   timezone(COALESCE(t.sys_name, 'UTC'::text), now())::timestamp with time zone) AS "from") d
                                                ON true
                                      LEFT JOIN LATERAL ( SELECT aa.state,
                                                                 d."from"   AS last_at,
                                                                 aa.payload AS status_payload
                                                          FROM call_center.cc_agent_state_history aa
                                                          WHERE aa.agent_id = a_1.id
                                                            AND aa.channel IS NULL
                                                            AND (aa.state::text = ANY
                                                                 (ARRAY ['pause'::character varying::text, 'online'::character varying::text, 'offline'::character varying::text]))
                                                            AND aa.joined_at < d."from"::timestamp with time zone
                                                          ORDER BY aa.joined_at DESC
                                                          LIMIT 1) lasts ON a_1.last_state_change > d."from"
                                      LEFT JOIN LATERAL ( SELECT a2.state,
                                                                 d."to"     AS top_at,
                                                                 a2.payload AS status_payload
                                                          FROM call_center.cc_agent_state_history a2
                                                          WHERE a2.agent_id = a_1.id
                                                            AND a2.channel IS NULL
                                                            AND (a2.state::text = ANY
                                                                 (ARRAY ['pause'::character varying::text, 'online'::character varying::text, 'offline'::character varying::text]))
                                                            AND a2.joined_at > d."to"
                                                          ORDER BY a2.joined_at
                                                          LIMIT 1) top ON true),
     d AS MATERIALIZED (SELECT x.agent_id,
                               x.joined_at,
                               x.state,
                               x.payload
                        FROM (SELECT a_1.agent_id,
                                     a_1.joined_at,
                                     a_1.state,
                                     a_1.payload
                              FROM call_center.cc_agent_state_history a_1,
                                   agents
                              WHERE a_1.agent_id = agents.id
                                AND a_1.joined_at >= agents."from"
                                AND a_1.joined_at <= agents."to"
                                AND a_1.channel IS NULL
                                AND (a_1.state::text = ANY
                                     (ARRAY ['pause'::character varying::text, 'online'::character varying::text, 'offline'::character varying::text]))
                              UNION
                              SELECT agents.id,
                                     agents.cur_state_change,
                                     agents.status,
                                     agents.status_payload
                              FROM agents
                              WHERE 1 = 1) x
                        ORDER BY x.joined_at DESC),
     s AS MATERIALIZED (SELECT d.agent_id,
                               d.joined_at,
                               d.state,
                               d.payload,
                               COALESCE(lag(d.joined_at) OVER (PARTITION BY d.agent_id ORDER BY d.joined_at DESC),
                                        now()) - d.joined_at AS dur
                        FROM d
                        ORDER BY d.joined_at DESC),
     eff AS (SELECT h.agent_id,
                    sum(COALESCE(h.reporting_at, h.leaving_at) - h.bridged_at)
                    FILTER (WHERE h.bridged_at IS NOT NULL)                                                                          AS aht,
                    sum(h.reporting_at - h.leaving_at - ((q.processing_sec || 's'::text)::interval))
                    FILTER (WHERE h.reporting_at IS NOT NULL AND q.processing AND (h.reporting_at - h.leaving_at) >
                                                                                  (((q.processing_sec + 1) || 's'::text)::interval)) AS tpause
             FROM agents
                      JOIN call_center.cc_member_attempt_history h ON h.agent_id = agents.id
                      LEFT JOIN call_center.cc_queue q ON q.id = h.queue_id
             WHERE h.domain_id = agents.domain_id
               AND h.joined_at >= agents."from"::timestamp with time zone
               AND h.joined_at <= agents."to"
               AND h.channel::text = 'call'::text
             GROUP BY h.agent_id),
     chats AS (SELECT cma.agent_id,
                      count(*) FILTER (WHERE cma.bridged_at IS NOT NULL) AS chat_accepts,
                      avg(EXTRACT(epoch FROM COALESCE(cma.reporting_at, cma.leaving_at) - cma.bridged_at))
                      FILTER (WHERE cma.bridged_at IS NOT NULL)::bigint  AS chat_aht
               FROM agents
                        JOIN call_center.cc_member_attempt_history cma ON cma.agent_id = agents.id
               WHERE cma.joined_at >= agents."from"::timestamp with time zone
                 AND cma.joined_at <= agents."to"
                 AND cma.domain_id = agents.domain_id
                 AND cma.bridged_at IS NOT NULL
                 AND cma.channel::text = 'chat'::text
               GROUP BY cma.agent_id),
     calls AS (SELECT h.user_id,
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text)                                                                               AS all_inb,
                      count(*) FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                          AS handled,
                      count(*)
                      FILTER (WHERE h.direction::text = 'inbound'::text AND h.bridged_at IS NOT NULL)                                                           AS inbound_bridged,
                      count(*)
                      FILTER (WHERE cq.type = 1 AND h.bridged_at IS NOT NULL AND h.parent_id IS NOT NULL)                                                       AS "inbound queue",
                      count(*)
                      FILTER (WHERE h.direction::text = 'inbound'::text AND h.queue_id IS NULL)                                                                 AS "direct inbound",
                      count(*)
                      FILTER (WHERE h.parent_id IS NOT NULL AND h.bridged_at IS NOT NULL AND h.queue_id IS NULL AND
                                    pc.user_id IS NOT NULL)                                                                                                     AS internal_inb,
                      count(*) FILTER (WHERE (h.direction::text = 'inbound'::text OR cq.type = 3) AND
                                             h.bridged_at IS NULL)                                                                                              AS missed,
                      count(*) FILTER (WHERE h.direction::text = 'inbound'::text AND h.bridged_at IS NULL AND
                                             h.queue_id IS NOT NULL AND (h.cause::text = ANY
                                                                         (ARRAY ['NO_ANSWER'::character varying::text, 'USER_BUSY'::character varying::text]))) AS abandoned,
                      count(*)
                      FILTER (WHERE (cq.type = ANY (ARRAY [0::smallint, 3::smallint, 4::smallint, 5::smallint])) AND
                                    h.bridged_at IS NOT NULL)                                                                                                   AS outbound_queue,
                      count(*) FILTER (WHERE h.parent_id IS NULL AND h.direction::text = 'outbound'::text AND
                                             h.queue_id IS NULL)                                                                                                AS "direct outboud",
                      sum(h.hangup_at - h.created_at)
                      FILTER (WHERE h.direction::text = 'outbound'::text AND h.queue_id IS NULL)                                                                AS direct_out_dur,
                      avg(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL AND h.direction::text = 'inbound'::text AND
                                    h.parent_id IS NOT NULL)                                                                                                    AS "avg bill inbound",
                      avg(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL AND h.direction::text = 'outbound'::text)                                                          AS "avg bill outbound",
                      sum(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                                   AS "sum bill",
                      avg(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                                   AS avg_talk,
                      sum((h.hold_sec || ' sec'::text)::interval)                                                                                               AS "sum hold",
                      avg((h.hold_sec || ' sec'::text)::interval)
                      FILTER (WHERE h.hold_sec > 0)                                                                                                             AS avg_hold,
                      sum(COALESCE(h.answered_at, h.bridged_at, h.hangup_at) - h.created_at)                                                                    AS "Call initiation",
                      sum(h.hangup_at - h.bridged_at)
                      FILTER (WHERE h.bridged_at IS NOT NULL)                                                                                                   AS "Talk time",
                      sum(cc.reporting_at - cc.leaving_at)
                      FILTER (WHERE cc.reporting_at IS NOT NULL)                                                                                                AS "Post call"
               FROM agents
                        JOIN call_center.cc_calls_history h ON h.user_id = agents.user_id
                        LEFT JOIN call_center.cc_queue cq ON h.queue_id = cq.id
                        LEFT JOIN call_center.cc_member_attempt_history cc ON cc.agent_call_id::text = h.id::text
                        LEFT JOIN call_center.cc_calls_history pc ON pc.id::uuid = h.parent_id::uuid
               WHERE h.domain_id = agents.domain_id
                 AND h.created_at >= agents."from"::timestamp with time zone
                 AND h.created_at <= agents."to"
               GROUP BY h.user_id),
     stats AS MATERIALIZED (SELECT s.agent_id,
                                   min(s.joined_at) FILTER (WHERE s.state::text = ANY
                                                                  (ARRAY ['online'::character varying::text, 'pause'::character varying::text])) AS login,
                                   max(s.joined_at) FILTER (WHERE s.state::text = 'offline'::text)                                               AS logout,
                                   sum(s.dur) FILTER (WHERE s.state::text = ANY
                                                            (ARRAY ['online'::character varying::text, 'pause'::character varying::text]))       AS online,
                                   sum(s.dur) FILTER (WHERE s.state::text = 'pause'::text)                                                       AS pause,
                                   sum(s.dur)
                                   FILTER (WHERE s.state::text = 'pause'::text AND s.payload::text = 'Навчання'::text)                           AS study,
                                   sum(s.dur)
                                   FILTER (WHERE s.state::text = 'pause'::text AND s.payload::text = 'Нарада'::text)                             AS conference,
                                   sum(s.dur)
                                   FILTER (WHERE s.state::text = 'pause'::text AND s.payload::text = 'Обід'::text)                               AS lunch,
                                   sum(s.dur) FILTER (WHERE s.state::text = 'pause'::text AND s.payload::text =
                                                                                              'Технічна перерва'::text)                          AS tech
                            FROM s
                                     LEFT JOIN agents ON agents.id = s.agent_id
                                     LEFT JOIN eff eff_1 ON eff_1.agent_id = s.agent_id
                                     LEFT JOIN calls ON calls.user_id = agents.user_id
                            GROUP BY s.agent_id),
     rate AS (SELECT a_1.user_id,
                     count(*)               AS count,
                     avg(ar.score_required) AS score_required_avg,
                     sum(ar.score_required) AS score_required_sum,
                     avg(ar.score_optional) AS score_optional_avg,
                     sum(ar.score_optional) AS score_optional_sum
              FROM agents a_1
                       JOIN call_center.cc_audit_rate ar ON ar.rated_user_id = a_1.user_id
              WHERE ar.created_at >=
                    (date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) AT TIME ZONE a_1.tz_name)
                AND ar.created_at <= ((date_trunc('month'::text, (now() AT TIME ZONE a_1.tz_name)) + '1 mon'::interval -
                                       '1 day 00:00:01'::interval) AT TIME ZONE a_1.tz_name)
              GROUP BY a_1.user_id)
SELECT a.id                                                        AS agent_id,
       a.domain_id,
       COALESCE(c.missed, 0::bigint)                               AS call_missed,
       COALESCE(c.abandoned, 0::bigint)                            AS call_abandoned,
       COALESCE(c.inbound_bridged, 0::bigint)                      AS call_inbound,
       COALESCE(c.handled, 0::bigint)                              AS call_handled,
       COALESCE(EXTRACT(epoch FROM c.avg_talk)::bigint, 0::bigint) AS avg_talk_sec,
       COALESCE(EXTRACT(epoch FROM c.avg_hold)::bigint, 0::bigint) AS avg_hold_sec,
       LEAST(round(COALESCE(
                           CASE
                               WHEN stats.online > '00:00:00'::interval AND
                                    EXTRACT(epoch FROM stats.online - COALESCE(stats.lunch, '00:00:00'::interval)) > 0::numeric
                                   THEN (COALESCE(EXTRACT(epoch FROM c."Call initiation"), 0::numeric) +
                                         COALESCE(EXTRACT(epoch FROM c."Talk time"), 0::numeric) +
                                         COALESCE(EXTRACT(epoch FROM c."Post call"), 0::numeric) -
                                         COALESCE(EXTRACT(epoch FROM eff.tpause), 0::numeric) +
                                         EXTRACT(epoch FROM COALESCE(stats.study, '00:00:00'::interval)) +
                                         EXTRACT(epoch FROM COALESCE(stats.conference, '00:00:00'::interval))) /
                                        EXTRACT(epoch FROM stats.online - COALESCE(stats.lunch, '00:00:00'::interval)) *
                                        100::numeric
                               ELSE 0::numeric
                               END, 0::numeric), 2), 100::numeric) AS occupancy,
       round(COALESCE(
                     CASE
                         WHEN stats.online > '00:00:00'::interval THEN
                                     EXTRACT(epoch FROM stats.online - COALESCE(stats.pause, '00:00:00'::interval)) /
                                     EXTRACT(epoch FROM stats.online) * 100::numeric
                         ELSE 0::numeric
                         END, 0::numeric), 2)                      AS utilization,
       COALESCE(ch.chat_aht, 0::bigint)                            AS chat_aht,
       COALESCE(ch.chat_accepts, 0::bigint)                        AS chat_accepts,
       COALESCE(rate.count, 0::bigint)                             AS score_count,
       COALESCE(rate.score_optional_avg, 0::numeric)               AS score_optional_avg,
       COALESCE(rate.score_optional_sum, 0::bigint::numeric)       AS score_optional_sum,
       COALESCE(rate.score_required_avg, 0::numeric)               AS score_required_avg,
       COALESCE(rate.score_required_sum, 0::bigint::numeric)       AS score_required_sum
FROM agents a
         LEFT JOIN call_center.cc_agent_with_user u ON u.id = a.id
         LEFT JOIN stats ON stats.agent_id = a.id
         LEFT JOIN eff ON eff.agent_id = a.id
         LEFT JOIN calls c ON c.user_id = a.user_id
         LEFT JOIN chats ch ON ch.agent_id = a.id
         LEFT JOIN rate ON rate.user_id = a.user_id;


create unique index cc_agent_today_stats_uidx
    on call_center.cc_agent_today_stats (agent_id);

refresh materialized view call_center.cc_agent_today_stats;


create view call_center.cc_call_active_list
as
SELECT c.id,
       c.app_id,
       c.state,
       c."timestamp",
       'call'::character varying                                                              AS type,
       c.parent_id,
       call_center.cc_get_lookup(u.id, COALESCE(u.name, u.username::text)::character varying) AS "user",
       u.extension,
       call_center.cc_get_lookup(gw.id, gw.name)                                              AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number',
                         COALESCE(c.from_number, ''::character varying), 'id',
                         COALESCE(c.from_id, ''::character varying), 'name',
                         COALESCE(c.from_name, ''::character varying))                        AS "from",
       CASE
           WHEN c.to_number::text <> ''::text THEN json_build_object('type', COALESCE(c.to_type, ''::character varying),
                                                                     'number',
                                                                     COALESCE(c.to_number, ''::character varying), 'id',
                                                                     COALESCE(c.to_id, ''::character varying), 'name',
                                                                     COALESCE(c.to_name, ''::character varying))
           ELSE NULL::json
           END                                                                                AS "to",
       CASE
           WHEN c.payload IS NULL THEN '{}'::jsonb
           ELSE c.payload
           END                                                                                AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       date_part('epoch'::text, now() - c.created_at)::bigint                                 AS duration,
       COALESCE(c.hold_sec, 0)                                                                AS hold_sec,
       COALESCE(
               CASE
                   WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.answered_at - c.created_at)::bigint
                   ELSE date_part('epoch'::text, now() - c.created_at)::bigint
                   END, 0::bigint)                                                            AS wait_sec,
       CASE
           WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, now() - c.answered_at)::bigint
           ELSE 0::bigint
           END                                                                                AS bill_sec,
       call_center.cc_get_lookup(cq.id::bigint, cq.name)                                      AS queue,
       call_center.cc_get_lookup(cm.id::bigint, cm.name)                                      AS member,
       call_center.cc_get_lookup(ct.id, ct.name)                                              AS team,
       ca."user"                                                                              AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at                                                                         AS queue_bridged_at,
       CASE
           WHEN cma.bridged_at IS NOT NULL THEN date_part('epoch'::text, cma.bridged_at - cma.joined_at)::integer
           ELSE date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer
           END                                                                                AS queue_wait_sec,
       date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer                      AS queue_duration_sec,
       cma.result,
       CASE
           WHEN cma.reporting_at IS NOT NULL THEN date_part('epoch'::text, cma.reporting_at - now())::integer
           ELSE 0
           END                                                                                AS reporting_sec,
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
       (SELECT jsonb_agg(sag."user") AS jsonb_agg
        FROM call_center.cc_agent_with_user sag
        WHERE sag.id = ANY (aa.supervisor_ids))                                               AS supervisor,
       aa.supervisor_ids,
       c.grantee_id,
       c.hold,
       c.blind_transfer
FROM call_center.cc_calls c
         LEFT JOIN call_center.cc_queue cq ON c.queue_id = cq.id
         LEFT JOIN call_center.cc_team ct ON c.team_id = ct.id
         LEFT JOIN call_center.cc_member cm ON c.member_id = cm.id
         LEFT JOIN call_center.cc_member_attempt cma ON cma.id = c.attempt_id
         LEFT JOIN call_center.cc_agent_with_user ca ON cma.agent_id = ca.id
         LEFT JOIN call_center.cc_agent aa ON aa.user_id = c.user_id
         LEFT JOIN directory.wbt_user u ON u.id = c.user_id
         LEFT JOIN directory.sip_gateway gw ON gw.id = c.gateway_id
WHERE c.hangup_at IS NULL
  AND c.direction IS NOT NULL;


create procedure call_center.cc_call_set_bridged(IN call_id_ uuid, IN state_ character varying, IN timestamp_ timestamp with time zone, IN app_id_ character varying, IN domain_id_ bigint, IN call_bridged_id_ uuid)
    language plpgsql
as
$$
declare
        transfer_to_ uuid;
        transfer_from_ uuid;
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
    returning c.transfer_to into transfer_to_;


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



create or replace function call_center.cc_distribute_inbound_call_to_agent(_node_name character varying, _call_id character varying, variables_ jsonb, _agent_id integer DEFAULT NULL::integer) returns record
    language plpgsql
as
$$
declare
    _domain_id int8;
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;

    _call record;
    _attempt record;

    _a_status varchar;
    _a_channel varchar;
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
  ELSIF _call.direction <> 'outbound' then
      _number = _call.from_number;
  else
      _number = _call.destination;
  end if;

  select
    a.team_id,
    t.updated_at,
    a.status,
    cac.channel,
    a.domain_id,
    (a.updated_at - extract(epoch from u.updated_at))::int8,
    exists (select 1 from call_center.cc_calls c where c.user_id = a.user_id and c.queue_id isnull and c.hangup_at isnull ) busy_ext
  from call_center.cc_agent a
      inner join call_center.cc_team t on t.id = a.team_id
      inner join call_center.cc_agent_channel cac on a.id = cac.agent_id
      inner join directory.wbt_user u on u.id = a.user_id
  where a.id = _agent_id -- check attempt
    and length(coalesce(u.extension, '')) > 0
  for update
  into _team_id_,
      _team_updated_at,
      _a_status,
      _a_channel,
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

  if not _a_channel isnull  then
      raise exception 'agent is busy';
  end if;

  if _busy_ext then
      raise exception 'agent has external call';
  end if;


  insert into call_center.cc_member_attempt (domain_id, state, team_id, member_call_id, destination, node_id, agent_id, parent_id)
  values (_domain_id, 'waiting', _team_id_, _call_id, jsonb_build_object('destination', _number),
              _node_name, _agent_id, _call.attempt_id)
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


create or replace function call_center.cc_distribute_inbound_call_to_queue(_node_name character varying, _queue_id bigint, _call_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) returns record
    language plpgsql
as
$$
declare
_timezone_id             int4;
    _discard_abandoned_after int4;
    _weight                  int4;
    dnc_list_id_
int4;
    _domain_id               int8;
    _calendar_id             int4;
    _queue_updated_at        int8;
    _team_updated_at         int8;
    _team_id_                int;
    _list_comm_id            int8;
    _enabled                 bool;
    _q_type                  smallint;
    _sticky                  bool;
    _call                    record;
    _attempt                 record;
    _number                  varchar;
    _max_waiting_size        int;
    _grantee_id              int8;
BEGIN
select c.timezone_id,
       (payload ->> 'discard_abandoned_after')::int discard_abandoned_after,
        c.domain_id,
       q.dnc_list_id,
       q.calendar_id,
       q.updated_at,
       ct.updated_at,
       q.team_id,
       q.enabled,
       q.type,
       q.sticky_agent,
       (payload ->> 'max_waiting_size')::int        max_size,
        q.grantee_id
from call_center.cc_queue q
         inner join flow.calendar c on q.calendar_id = c.id
         left join call_center.cc_team ct on q.team_id = ct.id
where q.id = _queue_id
    into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
        _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _grantee_id;

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
else
        _number = _call.destination;
end if;

--   raise  exception '%', _number;


    if
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
                        and a.status = 'online'
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
                                           parent_id)
values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id,
        jsonb_build_object('destination', _number),
        _node_name, _sticky_agent_id, null, _call.attempt_id)
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


vacuum analyze call_center.cc_calls_history;
vacuum full call_center.cc_calls;
