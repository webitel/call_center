

create or replace view call_center.cc_distribute_stage_1
            (id, type, strategy, team_id, buckets, types, resources, offset_ids, lim, domain_id, priority, sticky_agent,
             sticky_agent_sec, recall_calendar, wait_between_retries_desc, strict_circuit)
as
WITH queues AS MATERIALIZED (SELECT q_1.domain_id,
                                    q_1.id,
                                    q_1.calendar_id,
                                    q_1.type,
                                    q_1.sticky_agent,
                                    q_1.recall_calendar,
                                    CASE
                                        WHEN q_1.sticky_agent
                                            THEN COALESCE((q_1.payload -> 'sticky_agent_sec'::text)::integer, 30)
                                        ELSE NULL::integer
                                        END                                                                                  AS sticky_agent_sec,
                                    CASE
                                        WHEN q_1.strategy::text = 'lifo'::text THEN 1
                                        WHEN q_1.strategy::text = 'strict_fifo'::text THEN 2
                                        ELSE 0
                                        END                                                                                  AS strategy,
                                    q_1.priority,
                                    q_1.team_id,
                                    (q_1.payload -> 'max_calls'::text)::integer                                              AS lim,
                                    (q_1.payload -> 'wait_between_retries_desc'::text)::boolean                              AS wait_between_retries_desc,
                                    COALESCE((q_1.payload -> 'strict_circuit'::text)::boolean, false)                        AS strict_circuit,
                                    array_agg(
                                            ROW (m.bucket_id::integer, m.member_waiting::integer, m.op)::call_center.cc_sys_distribute_bucket
                                            ORDER BY cbiq.priority DESC NULLS LAST, cbiq.ratio DESC NULLS LAST, m.bucket_id) AS buckets,
                                    m.op
                             FROM (WITH mem AS MATERIALIZED (SELECT a.queue_id,
                                                                    a.bucket_id,
                                                                    count(*) AS member_waiting,
                                                                    false    AS op
                                                             FROM call_center.cc_member_attempt a
                                                             WHERE a.bridged_at IS NULL
                                                               AND a.leaving_at IS NULL
                                                               AND a.state::text = 'wait_agent'::text
                                                             GROUP BY a.queue_id, a.bucket_id
                                                             UNION ALL
                                                             SELECT q_2.queue_id,
                                                                    q_2.bucket_id,
                                                                    q_2.member_waiting,
                                                                    true AS op
                                                             FROM call_center.cc_queue_statistics q_2
                                                             WHERE q_2.member_waiting > 0)
                                   SELECT rank() OVER (PARTITION BY mem.queue_id ORDER BY mem.op) AS pos,
                                          mem.queue_id,
                                          mem.bucket_id,
                                          mem.member_waiting,
                                          mem.op
                                   FROM mem) m
                                      JOIN call_center.cc_queue q_1 ON q_1.id = m.queue_id
                                      LEFT JOIN call_center.cc_bucket_in_queue cbiq
                                                ON cbiq.queue_id = m.queue_id AND cbiq.bucket_id = m.bucket_id
                             WHERE m.member_waiting > 0
                               AND q_1.enabled
                               AND q_1.type > 0
                               AND m.pos = 1
                               AND (cbiq.bucket_id IS NULL OR NOT cbiq.disabled)
                             GROUP BY q_1.domain_id, q_1.id, q_1.calendar_id, q_1.type, m.op
                             LIMIT 1024),
     calend AS MATERIALIZED (SELECT c.id                                                                            AS calendar_id,
                                    queues.id                                                                       AS queue_id,
                                    CASE
                                        WHEN queues.recall_calendar AND
                                             NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id)))
                                            THEN array_agg(DISTINCT o1.id)::integer[] + tz.offset_id::integer
                                        ELSE array_agg(DISTINCT o1.id)::integer[]
                                        END                                                                         AS l,
                                    queues.recall_calendar AND
                                    NOT (tz.offset_id = ANY (array_agg(DISTINCT o1.id)))                            AS recall_calendar
                             FROM flow.calendar c
                                      LEFT JOIN flow.calendar_timezones tz ON tz.id = c.timezone_id
                                      JOIN queues ON queues.calendar_id = c.id
                                      JOIN LATERAL unnest(c.accepts) a(disabled, day, start_time_of_day, end_time_of_day)
                                           ON true
                                      JOIN flow.calendar_timezone_offsets o1 ON (a.day + 1) =
                                                                                date_part('isodow'::text, timezone(o1.names[1], now()))::integer AND
                                                                                (to_char(timezone(o1.names[1], now()), 'SSSS'::text)::integer /
                                                                                 60) >= a.start_time_of_day AND
                                                                                (to_char(timezone(o1.names[1], now()), 'SSSS'::text)::integer /
                                                                                 60) <= a.end_time_of_day
                             WHERE NOT a.disabled IS TRUE
                               and not exists(
                                     select 1
                                     from unnest(c.excepts) as x
                                     where not x.disabled is true
                                       and case
                                               when x.repeat is true then
                                                       to_char((current_timestamp AT TIME ZONE tz.sys_name)::date, 'MM-DD') =
                                                       to_char((to_timestamp(x.date / 1000) at time zone tz.sys_name)::date, 'MM-DD')
                                               else
                                                       (current_timestamp AT TIME ZONE tz.sys_name)::date =
                                                       (to_timestamp(x.date / 1000) at time zone tz.sys_name)::date
                                         end
                                 )
                             GROUP BY c.id, queues.id, queues.recall_calendar, tz.offset_id),
     resources AS MATERIALIZED (SELECT l_1.queue_id,
                                       array_agg(ROW (cor.communication_id, cor.id::bigint, (l_1.l & l2.x::integer[])::smallint[], cor.resource_group_id::integer)::call_center.cc_sys_distribute_type) AS types,
                                       array_agg(ROW (cor.id::bigint, (cor."limit" - used.cnt)::integer, cor.patterns)::call_center.cc_sys_distribute_resource)                                         AS resources,
                                       call_center.cc_array_merge_agg(l_1.l & l2.x::integer[])                                                                                                          AS offset_ids
                                FROM calend l_1
                                         JOIN (SELECT corg.queue_id,
                                                      corg.priority,
                                                      corg.resource_group_id,
                                                      corg.communication_id,
                                                      corg."time",
                                                      (corg.cor).id                      AS id,
                                                      (corg.cor)."limit"                 AS "limit",
                                                      (corg.cor).enabled                 AS enabled,
                                                      (corg.cor).updated_at              AS updated_at,
                                                      (corg.cor).rps                     AS rps,
                                                      (corg.cor).domain_id               AS domain_id,
                                                      (corg.cor).reserve                 AS reserve,
                                                      (corg.cor).variables               AS variables,
                                                      (corg.cor).number                  AS number,
                                                      (corg.cor).max_successively_errors AS max_successively_errors,
                                                      (corg.cor).name                    AS name,
                                                      (corg.cor).last_error_id           AS last_error_id,
                                                      (corg.cor).successively_errors     AS successively_errors,
                                                      (corg.cor).created_at              AS created_at,
                                                      (corg.cor).created_by              AS created_by,
                                                      (corg.cor).updated_by              AS updated_by,
                                                      (corg.cor).error_ids               AS error_ids,
                                                      (corg.cor).gateway_id              AS gateway_id,
                                                      (corg.cor).email_profile_id        AS email_profile_id,
                                                      (corg.cor).payload                 AS payload,
                                                      (corg.cor).description             AS description,
                                                      (corg.cor).patterns                AS patterns,
                                                      (corg.cor).failure_dial_delay      AS failure_dial_delay,
                                                      (corg.cor).last_error_at           AS last_error_at
                                               FROM calend calend_1
                                                        JOIN (SELECT DISTINCT cqr.queue_id,
                                                                              corig.priority,
                                                                              corg_1.id AS resource_group_id,
                                                                              corg_1.communication_id,
                                                                              corg_1."time",
                                                                              CASE
                                                                                  WHEN cor_1.enabled AND gw.enable
                                                                                      THEN ROW (cor_1.id, cor_1."limit", cor_1.enabled, cor_1.updated_at, cor_1.rps, cor_1.domain_id, cor_1.reserve, cor_1.variables, cor_1.number, cor_1.max_successively_errors, cor_1.name, cor_1.last_error_id, cor_1.successively_errors, cor_1.created_at, cor_1.created_by, cor_1.updated_by, cor_1.error_ids, cor_1.gateway_id, cor_1.email_profile_id, cor_1.payload, cor_1.description, cor_1.patterns, cor_1.failure_dial_delay, cor_1.last_error_at, NULL::jsonb)::call_center.cc_outbound_resource
                                                                                  WHEN cor2.enabled AND gw2.enable
                                                                                      THEN ROW (cor2.id, cor2."limit", cor2.enabled, cor2.updated_at, cor2.rps, cor2.domain_id, cor2.reserve, cor2.variables, cor2.number, cor2.max_successively_errors, cor2.name, cor2.last_error_id, cor2.successively_errors, cor2.created_at, cor2.created_by, cor2.updated_by, cor2.error_ids, cor2.gateway_id, cor2.email_profile_id, cor2.payload, cor2.description, cor2.patterns, cor2.failure_dial_delay, cor2.last_error_at, NULL::jsonb)::call_center.cc_outbound_resource
                                                                                  ELSE NULL::call_center.cc_outbound_resource
                                                                                  END   AS cor
                                                              FROM call_center.cc_queue_resource cqr
                                                                       JOIN call_center.cc_outbound_resource_group corg_1
                                                                            ON cqr.resource_group_id = corg_1.id
                                                                       JOIN call_center.cc_outbound_resource_in_group corig
                                                                            ON corg_1.id = corig.group_id
                                                                       JOIN call_center.cc_outbound_resource cor_1
                                                                            ON cor_1.id = corig.resource_id::integer
                                                                       JOIN directory.sip_gateway gw ON gw.id = cor_1.gateway_id
                                                                       LEFT JOIN call_center.cc_outbound_resource cor2
                                                                                 ON cor2.id = corig.reserve_resource_id AND cor2.enabled
                                                                       LEFT JOIN directory.sip_gateway gw2 ON gw2.id = cor2.gateway_id AND cor2.enabled
                                                              WHERE CASE
                                                                        WHEN cor_1.enabled AND gw.enable THEN cor_1.id
                                                                        WHEN cor2.enabled AND gw2.enable THEN cor2.id
                                                                        ELSE NULL::integer
                                                                        END IS NOT NULL
                                                              ORDER BY cqr.queue_id, corig.priority DESC) corg
                                                             ON corg.queue_id = calend_1.queue_id) cor
                                              ON cor.queue_id = l_1.queue_id
                                         JOIN LATERAL ( WITH times
                                                                 AS (SELECT (e.value -> 'start_time_of_day'::text)::integer AS start,
                                                                            (e.value -> 'end_time_of_day'::text)::integer   AS "end"
                                                                     FROM jsonb_array_elements(cor."time") e(value))
                                                        SELECT array_agg(DISTINCT t.id) AS x
                                                        FROM flow.calendar_timezone_offsets t,
                                                             times,
                                                             LATERAL ( SELECT timezone(t.names[1], CURRENT_TIMESTAMP) AS t) with_timezone
                                                        WHERE (to_char(with_timezone.t, 'SSSS'::text)::integer / 60) >=
                                                              times.start
                                                          AND (to_char(with_timezone.t, 'SSSS'::text)::integer / 60) <=
                                                              times."end") l2 ON l2.* IS NOT NULL
                                         LEFT JOIN LATERAL ( SELECT count(*) AS cnt
                                                             FROM (SELECT 1 AS cnt
                                                                   FROM call_center.cc_member_attempt c_1
                                                                   WHERE c_1.resource_id = cor.id
                                                                     AND (c_1.state::text <> ALL
                                                                          (ARRAY ['leaving'::character varying::text, 'processing'::character varying::text]))) c) used
                                                   ON true
                                WHERE cor.enabled
                                  AND (cor.last_error_at IS NULL OR cor.last_error_at <=
                                                                    (now() - ((cor.failure_dial_delay || ' s'::text)::interval)))
                                  AND (cor."limit" - used.cnt) > 0
                                GROUP BY l_1.queue_id)
SELECT q.id,
       q.type,
       q.strategy::smallint AS strategy,
       q.team_id,
       q.buckets,
       r.types,
       r.resources,
       CASE
           WHEN q.type = ANY ('{7,8}'::smallint[]) THEN calend.l
           ELSE r.offset_ids
           END              AS offset_ids,
       CASE
           WHEN q.lim = '-1'::integer THEN NULL::integer
           ELSE GREATEST((q.lim - COALESCE(l.usage, 0::bigint))::integer, 0)
           END              AS lim,
       q.domain_id,
       q.priority,
       q.sticky_agent,
       q.sticky_agent_sec,
       calend.recall_calendar,
       q.wait_between_retries_desc,
       q.strict_circuit
FROM queues q
         LEFT JOIN calend ON calend.queue_id = q.id
         LEFT JOIN resources r ON q.op AND r.queue_id = q.id
         LEFT JOIN LATERAL ( SELECT count(*) AS usage
                             FROM call_center.cc_member_attempt a
                             WHERE a.queue_id = q.id
                               AND a.state::text <> 'leaving'::text) l ON q.lim > 0
WHERE (q.type = ANY (ARRAY [1, 6, 7]))
   OR q.type = 8 AND GREATEST((q.lim - COALESCE(l.usage, 0::bigint))::integer, 0) > 0
   OR q.type = 5 AND NOT q.op
   OR q.op AND (q.type = ANY (ARRAY [2, 3, 4, 5])) AND r.* IS NOT NULL;


CREATE or replace FUNCTION call_center.cc_attempt_timeout(attempt_id_ bigint, hold_sec integer, result_ character varying, agent_status_ character varying, agent_hold_sec_ integer) RETURNS timestamp with time zone
    LANGUAGE plpgsql
AS $$
declare
    attempt call_center.cc_member_attempt%rowtype;
begin
    update call_center.cc_member_attempt
    set reporting_at = now(),
        result = 'timeout',
        state = 'leaving'
    where id = attempt_id_
    returning * into attempt;

    update call_center.cc_member
    set last_hangup_at  = extract(EPOCH from now())::int8 * 1000,
        last_agent      = coalesce(attempt.agent_id, last_agent),


        stop_at = case when stop_at notnull or (q._max_count > 0 and (attempts + 1 < q._max_count))
                           then stop_at else  attempt.leaving_at end,
        stop_cause = case when stop_cause notnull or (q._max_count > 0 and (attempts + 1 < q._max_count))
                              then stop_cause else attempt.result end,
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
             from call_center.cc_queue q
             where q.id = attempt.queue_id
         ) q
    where id = attempt.member_id;

    if attempt.agent_id notnull then
        update call_center.cc_agent_channel c
        set state = agent_status_,
            joined_at = now(),
            channel = case when c.channel = any('{chat,task}') and (select count(1)
                                                                    from call_center.cc_member_attempt aa
                                                                    where aa.agent_id = attempt.agent_id and aa.id != attempt.id and aa.state != 'leaving') > 0
                               then c.channel else null end,
            timeout = case when agent_hold_sec_ > 0 then (now() + (agent_hold_sec_::varchar || ' sec')::interval) else null end
        where c.agent_id = attempt.agent_id;

    end if;

    return now();
end;
$$;



alter table call_center.cc_calls
    drop column if exists amd_ml_result;
alter table call_center.cc_calls
    drop column if exists amd_ml_logs;

alter table call_center.cc_calls_history
    drop column if exists amd_ml_result;
alter table call_center.cc_calls_history
    drop column if exists amd_ml_logs;

alter table call_center.cc_calls
    add amd_ai_result varchar;
alter table call_center.cc_calls
    add amd_ai_logs varchar[];


alter table call_center.cc_calls_history
    add amd_ai_result varchar;
alter table call_center.cc_calls_history
    add amd_ai_logs varchar[];


drop view call_center.cc_calls_history_list;
create view call_center.cc_calls_history_list
as
SELECT c.id,
       c.app_id,
       'call'::character varying                                                                           AS type,
       c.parent_id,
       c.transfer_from,
       CASE
           WHEN c.parent_id IS NOT NULL AND c.transfer_to IS NULL AND c.id::text <> lega.bridged_id::text
               THEN lega.bridged_id
           ELSE c.transfer_to
           END                                                                                             AS transfer_to,
       call_center.cc_get_lookup(u.id, COALESCE(u.name, u.username::text)::character varying)              AS "user",
       CASE
           WHEN cq.type = ANY (ARRAY [4, 5]) THEN cag.extension
           ELSE u.extension
           END                                                                                             AS extension,
       call_center.cc_get_lookup(gw.id, gw.name)                                                           AS gateway,
       c.direction,
       c.destination,
       json_build_object('type', COALESCE(c.from_type, ''::character varying), 'number',
                         COALESCE(c.from_number, ''::character varying), 'id',
                         COALESCE(c.from_id, ''::character varying), 'name',
                         COALESCE(c.from_name, ''::character varying))                                     AS "from",
       json_build_object('type', COALESCE(c.to_type, ''::character varying), 'number',
                         COALESCE(c.to_number, ''::character varying), 'id', COALESCE(c.to_id, ''::character varying),
                         'name', COALESCE(c.to_name, ''::character varying))                               AS "to",
       c.payload                                                                                           AS variables,
       c.created_at,
       c.answered_at,
       c.bridged_at,
       c.hangup_at,
       c.stored_at,
       COALESCE(c.hangup_by, ''::character varying)                                                        AS hangup_by,
       c.cause,
       date_part('epoch'::text, c.hangup_at - c.created_at)::bigint                                        AS duration,
       COALESCE(c.hold_sec, 0)                                                                             AS hold_sec,
       COALESCE(
               CASE
                   WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.answered_at - c.created_at)::bigint
                   ELSE date_part('epoch'::text, c.hangup_at - c.created_at)::bigint
                   END, 0::bigint)                                                                         AS wait_sec,
       CASE
           WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.hangup_at - c.answered_at)::bigint
           ELSE 0::bigint
           END                                                                                             AS bill_sec,
       c.sip_code,
       f.files,
       call_center.cc_get_lookup(cq.id::bigint, cq.name)                                                   AS queue,
       call_center.cc_get_lookup(cm.id::bigint, cm.name)                                                   AS member,
       call_center.cc_get_lookup(ct.id, ct.name)                                                           AS team,
       call_center.cc_get_lookup(aa.id::bigint, COALESCE(cag.username, cag.name::name)::character varying) AS agent,
       cma.joined_at,
       cma.leaving_at,
       cma.reporting_at,
       cma.bridged_at                                                                                      AS queue_bridged_at,
       CASE
           WHEN cma.bridged_at IS NOT NULL THEN date_part('epoch'::text, cma.bridged_at - cma.joined_at)::integer
           ELSE date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer
           END                                                                                             AS queue_wait_sec,
       date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer                                   AS queue_duration_sec,
       cma.result,
       CASE
           WHEN cma.reporting_at IS NOT NULL THEN date_part('epoch'::text, cma.reporting_at - cma.leaving_at)::integer
           ELSE 0
           END                                                                                             AS reporting_sec,
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
                 AND hp.parent_id::text = c.id::text))                                                     AS has_children,
       COALESCE(regexp_replace(cma.description::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text),
                ''::character varying::text)::character varying                                            AS agent_description,
       c.grantee_id,
       holds.res                                                                                           AS hold,
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
              ORDER BY a.created_at DESC) annotations)                                                     AS annotations,
       c.amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       cq.type                                                                                             AS queue_type,
       CASE
           WHEN c.parent_id IS NOT NULL THEN ''::text
           WHEN c.cause::text = ANY (ARRAY ['USER_BUSY'::character varying::text, 'NO_ANSWER'::character varying::text])
               THEN 'not_answered'::text
           WHEN c.cause::text = 'ORIGINATOR_CANCEL'::text THEN 'cancelled'::text
           WHEN c.cause::text = 'NORMAL_CLEARING'::text THEN
               CASE
                   WHEN c.cause::text = 'NORMAL_CLEARING'::text AND
                        (c.direction::text = 'outbound'::text AND c.hangup_by::text = 'A'::text AND
                         c.user_id IS NOT NULL OR
                         c.direction::text = 'inbound'::text AND c.hangup_by::text = 'B'::text AND
                         c.bridged_at IS NOT NULL OR
                         c.direction::text = 'outbound'::text AND c.hangup_by::text = 'B'::text AND
                         (cq.type = ANY (ARRAY [4, 5])) AND c.bridged_at IS NOT NULL) THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END                                                                                             AS hangup_disposition,
       c.blind_transfer,
       (SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at),
                                           'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error,
                                           'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
        FROM storage.file_jobs j
        WHERE j.file_id = ANY (f.file_ids))                                                                AS files_job,
       transcripts.data                                                                                    AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, au.name::character varying)                                        AS grantee
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
                                   WHERE chh.parent_id::text = c.id::text
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
         LEFT JOIN call_center.cc_calls_history lega ON c.parent_id IS NOT NULL AND lega.id::text = c.parent_id::text
         LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id,
                                                               'file',
                                                               call_center.cc_get_lookup(ff.id, ff.name))) AS data
                             FROM storage.file_transcript tr
                                      LEFT JOIN storage.files ff ON ff.id = tr.file_id
                             WHERE tr.uuid::text = c.id::character varying(50)::text
                             GROUP BY (tr.uuid::text)) transcripts ON true;