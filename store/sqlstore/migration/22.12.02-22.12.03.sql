alter table call_center.cc_calls add column amd_ai_positive bool;
alter table call_center.cc_calls_history add column amd_ai_positive bool;


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
       COALESCE(c.amd_result, c.amd_ai_result)                                                             AS amd_result,
       c.amd_duration,
       c.amd_ai_result,
       c.amd_ai_logs,
       c.amd_ai_positive,
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

drop materialized view call_center.cc_distribute_stats;
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
                               min(att.joined_at)                                                                       AS start_stat,
                               max(att.joined_at)                                                                       AS stop_stat,
                               count(*)                                                                                 AS call_attempts,
                               COALESCE(avg(date_part('epoch'::text,
                                                      COALESCE(att.reporting_at, att.leaving_at) - att.offering_at))
                                        FILTER (WHERE att.bridged_at IS NOT NULL),
                                        0::double precision)                                                            AS avg_handle,
                               COALESCE(avg(DISTINCT round(date_part('epoch'::text,
                                                                     COALESCE(att.reporting_at, att.leaving_at) -
                                                                     att.offering_at))::real)
                                        FILTER (WHERE att.bridged_at IS NOT NULL),
                                        0::double precision)                                                            AS med_handle,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL),
                                        0::double precision)                                                            AS avg_member_answer,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL AND ch.bridged_at IS NULL),
                                        0::double precision)                                                            AS avg_member_answer_not_bridged,
                               COALESCE(avg(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL AND ch.bridged_at IS NOT NULL),
                                        0::double precision)                                                            AS avg_member_answer_bridged,
                               COALESCE(max(date_part('epoch'::text, ch.answered_at - att.joined_at))
                                        FILTER (WHERE ch.answered_at IS NOT NULL),
                                        0::double precision)                                                            AS max_member_answer,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND
                                                      amd_res.human) AS connected_calls,
                               count(*) FILTER (WHERE att.bridged_at IS NOT NULL)                                       AS bridged_calls,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND att.bridged_at IS NULL AND
                                                      amd_res.human) AS abandoned_calls,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND
                                                      amd_res.human)::double precision /
                               count(*)::double precision                                                               AS connection_rate,
                               CASE
                                   WHEN (count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND
                                                                amd_res.human)::double precision /
                                         count(*)::double precision) > 0::double precision THEN 1::double precision / (
                                                   count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND
                                                                          amd_res.human)::double precision /
                                                   count(*)::double precision) - 1::double precision
                                   ELSE (count(*) / GREATEST(count(DISTINCT att.agent_id), 1::bigint) - 1)::double precision
                                   END                                                                                  AS over_dial,
                               COALESCE((count(*)
                                         FILTER (WHERE ch.answered_at IS NOT NULL AND att.bridged_at IS NULL AND
                                                       amd_res.human)::double precision -
                                         COALESCE((q.payload -> 'abandon_rate_adjustment'::text)::integer,
                                                  0)::double precision) / NULLIF(count(*) FILTER (WHERE
                                       ch.answered_at IS NOT NULL AND
                                       amd_res.human),
                                                                                 0)::double precision *
                                        100::double precision,
                                        0::double precision)                                                            AS abandoned_rate,
                               count(*) FILTER (WHERE ch.answered_at IS NOT NULL AND
                                                      amd_res.human)::double precision /
                               count(*)::double precision                                                               AS hit_rate,
                               count(DISTINCT att.agent_id)                                                             AS agents,
                               array_agg(DISTINCT att.agent_id)
                               FILTER (WHERE att.agent_id IS NOT NULL)                                                  AS aggent_ids
                        FROM call_center.cc_member_attempt_history att
                                 LEFT JOIN call_center.cc_calls_history ch
                                           ON ch.domain_id = att.domain_id AND ch.id::text = att.member_call_id::text
                                 left join lateral (select (ch.amd_result IS NULL and ch.amd_ai_positive isnull ) or (ch.amd_result::text = ANY (amd.arr)) or ch.amd_ai_positive is true as human ) amd_res on true
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


CREATE or replace PROCEDURE call_center.cc_distribute(INOUT cnt integer)
    LANGUAGE plpgsql
AS $$
begin
    if NOT pg_try_advisory_xact_lock(132132117) then
        raise exception 'LOCK';
    end if;

    with dis as MATERIALIZED (
        select x.*, a.team_id
        from call_center.cc_sys_distribute() x (agent_id int, queue_id int, bucket_id int, ins bool, id int8, resource_id int,
                                                resource_group_id int, comm_idx int)
                 left join call_center.cc_agent a on a.id= x.agent_id
    )
       , ins as (
        insert into call_center.cc_member_attempt (channel, member_id, queue_id, resource_id, agent_id, bucket_id, destination,
                                                   communication_idx, member_call_id, team_id, resource_group_id, domain_id, import_id, sticky_agent_id)
            select case when q.type = 7 then 'task' else 'call' end, --todo
                   dis.id,
                   dis.queue_id,
                   dis.resource_id,
                   dis.agent_id,
                   dis.bucket_id,
                   x,
                   dis.comm_idx,
                   uuid_generate_v4(),
                   dis.team_id,
                   dis.resource_group_id,
                   q.domain_id,
                   m.import_id,
                   case when q.type = 5 and q.sticky_agent then dis.agent_id end
            from dis
                     inner join call_center.cc_queue q on q.id = dis.queue_id
                     inner join call_center.cc_member m on m.id = dis.id
                     inner join lateral jsonb_extract_path(m.communications, (dis.comm_idx)::text) x on true
            where dis.ins
    )
    update call_center.cc_member_attempt a
    set agent_id = t.agent_id,
        team_id = t.team_id
    from (
             select dis.id, dis.agent_id, dis.team_id
             from dis

             where not dis.ins is true
         ) t
    where t.id = a.id
      and a.agent_id isnull;

end;
$$;