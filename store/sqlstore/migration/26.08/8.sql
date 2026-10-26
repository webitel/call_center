CREATE OR REPLACE FUNCTION call_center.cc_agent_set_login_v2(agent_id_ integer, on_demand_ boolean DEFAULT false, p_status_id bigint DEFAULT NULL::bigint, p_status_name character varying DEFAULT NULL::character varying)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
DECLARE
    screen_control_ bool;
    res_ jsonb;
    user_id_ int8;
BEGIN
    UPDATE call_center.cc_agent a
    SET status            = 'online',
        status_payload    = NULL,
        on_demand         = on_demand_,
        last_state_change = NOW(),
        status_id         = CASE
            WHEN p_status_id IS NOT NULL THEN p_status_id
            WHEN p_status_name IS NOT NULL THEN (
                SELECT s.id
                FROM call_center.cc_online_skills s
                WHERE
                    s.domain_id = a.domain_id
                    and (
                        lower(s."name") = lower(trim(p_status_name))
                        or s.is_system is true
                    )
                order by is_system asc
                LIMIT 1
            )
            ELSE NULL
        END
    WHERE a.id = agent_id_
    RETURNING a.user_id, a.screen_control INTO user_id_, screen_control_;

    IF screen_control_ AND NOT EXISTS (
        SELECT 1
        FROM call_center.socket_session ss
        WHERE ss.user_id = user_id_
          AND ss.application_name = 'desc_track'
          AND NOW() - ss.updated_at < '65 sec'::interval
    ) THEN
        RAISE EXCEPTION 'The agent must connect via the "desc_track" client application.'
        USING
            DETAIL = 'The agent must connect via the "desc_track" client application.',
            ERRCODE = '09000';
    END IF;

    IF NOT (
        EXISTS (
            SELECT 1
            FROM directory.wbt_user_presence p
            WHERE p.user_id = user_id_
              AND p.open > 0
              AND p.status IN ('sip', 'web')
        )
        OR EXISTS (
            SELECT 1
            FROM directory.wbt_session s
            WHERE s.user_id IS NOT NULL
              AND NULLIF((s.props ->> 'pn-rpid'::text), ''::text) IS NOT NULL
              AND s.user_id = user_id_::int8
              AND s.access IS NOT NULL
              AND s.expires > NOW() AT TIME ZONE 'UTC'
        )
    ) THEN
        RAISE EXCEPTION 'not found: sip, web or pn';
    END IF;

    WITH chls AS (
        UPDATE call_center.cc_agent_channel c
        SET state = CASE WHEN x.x = 1 THEN c.state ELSE 'waiting' END,
            online = TRUE,
            no_answers = 0,
            timeout = CASE WHEN x.x = 1 THEN c.timeout ELSE NULL END
        FROM call_center.cc_agent_channel c2
        LEFT JOIN LATERAL (
            SELECT a.channel, 1 AS x
            FROM call_center.cc_member_attempt a
            WHERE a.agent_id = agent_id_
              AND a.channel = c2.channel
            LIMIT 1
        ) x ON TRUE
        WHERE c2.agent_id = agent_id_
          AND (c.agent_id, c.channel) = (c2.agent_id, c2.channel)
        RETURNING jsonb_build_object(
            'channel', c.channel,
            'joined_at', call_center.cc_view_timestamp(c.joined_at),
            'state', c.state,
            'no_answers', c.no_answers
        ) xx
    )
    SELECT jsonb_agg(chls.xx)
    INTO res_
    FROM chls;

    RETURN ROW (res_::jsonb, call_center.cc_view_timestamp(NOW()));
END;
$function$;


CREATE OR REPLACE VIEW "call_center"."cc_calls_history_list" AS
 SELECT c.id,
    c.app_id,
    'call'::character varying AS type,
    c.parent_id,
    c.transfer_from,
        CASE
            WHEN c.parent_id IS NOT NULL AND c.transfer_to IS NULL AND c.id <> cc_bridged_id(c.parent_id) THEN cc_bridged_id(c.parent_id)
            ELSE c.transfer_to
        END AS transfer_to,
    COALESCE(cc_get_lookup(u.id, COALESCE(u.name, u.username::text)::character varying), cc_get_lookup(cag.id, COALESCE(cag.name, cag.username::text)::character varying), NULL::jsonb) AS "user",
        CASE
            WHEN cq.type = ANY (ARRAY[4, 5]) THEN cag.extension
            ELSE u.extension
        END AS extension,
    cc_get_lookup(gw.id, gw.name) AS gateway,
    c.direction,
    c.destination::text AS destination,
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
    date_part('epoch'::text, c.hangup_at - c.created_at)::bigint AS duration,
    COALESCE(c.hold_sec, 0) AS hold_sec,
    COALESCE(
        CASE
            WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.answered_at - c.created_at)::bigint
            ELSE date_part('epoch'::text, c.hangup_at - c.created_at)::bigint
        END, 0::bigint) AS wait_sec,
        CASE
            WHEN c.answered_at IS NOT NULL THEN date_part('epoch'::text, c.hangup_at - c.answered_at)::bigint
            ELSE 0::bigint
        END AS bill_sec,
    c.sip_code,
    ( SELECT json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at',
                CASE
                    WHEN f_1.channel::text = 'call'::text AND NOT f_1.mime_type::text ~~ 'image%'::text THEN COALESCE(NULLIF((f_1.custom_properties ->> 'start_time'::text)::bigint, 0), NULLIF((c.params -> 'record_start'::text)::bigint, 0), NULLIF(cc_view_timestamp(c.bridged_at), 0), cc_view_timestamp(c.answered_at))
                    ELSE COALESCE(NULLIF((f_1.custom_properties ->> 'start_time'::text)::bigint, 0), f_1.created_at)
                END, 'stop_at',
                CASE
                    WHEN f_1.channel::text = 'call'::text AND NOT f_1.mime_type::text ~~ 'image%'::text THEN COALESCE(NULLIF((f_1.custom_properties ->> 'end_time'::text)::bigint, 0), NULLIF((c.params -> 'record_stop'::text)::bigint, 0), cc_view_timestamp(c.hangup_at))
                    ELSE (f_1.custom_properties ->> 'end_time'::text)::bigint
                END, 'start_record', f_1.sr, 'channel', f_1.channel)) AS files
           FROM ( SELECT f1.id,
                    f1.size,
                    f1.mime_type,
                    COALESCE(f1.view_name, f1.name) AS name,
                    f1.channel,
                    f1.custom_properties,
                    f1.created_at,
                        CASE
                            WHEN c.direction::text = 'outbound'::text AND c.user_id IS NOT NULL AND (c.queue_id IS NULL OR cq.type = 2) THEN 'operator'::text
                            ELSE 'client'::text
                        END AS sr
                   FROM storage.files f1
                  WHERE f1.domain_id = c.domain_id AND NOT f1.removed IS TRUE AND f1.uuid::text = c.id::text
                UNION ALL
                 SELECT f1.id,
                    f1.size,
                    f1.mime_type,
                    COALESCE(f1.view_name, f1.name) AS name,
                    f1.channel,
                    f1.custom_properties,
                    f1.created_at,
                    NULL::text AS sr
                   FROM storage.files f1
                  WHERE f1.domain_id = c.domain_id AND NOT f1.removed IS TRUE AND c.parent_id IS NOT NULL AND f1.uuid::text = c.parent_id::text) f_1) AS files,
    cc_get_lookup(cq.id::bigint, cq.name) AS queue,
    cc_get_lookup(c.member_id, COALESCE(cm.name, (cma.destination ->> 'name'::text)::character varying)) AS member,
    cc_get_lookup(ct.id, ct.name) AS team,
    cc_get_lookup(aa.id::bigint, COALESCE(cag.name, cag.username::text)::character varying) AS agent,
    cma.joined_at,
    cma.leaving_at,
    cma.reporting_at,
    cma.bridged_at AS queue_bridged_at,
        CASE
            WHEN cma.bridged_at IS NOT NULL THEN date_part('epoch'::text, cma.bridged_at - cma.joined_at)::integer
            ELSE date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer
        END AS queue_wait_sec,
    date_part('epoch'::text, cma.leaving_at - cma.joined_at)::integer AS queue_duration_sec,
    cma.result,
        CASE
            WHEN cma.reporting_at IS NOT NULL THEN date_part('epoch'::text, cma.reporting_at - cma.leaving_at)::integer
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
    c.from_number::text AS from_number,
    c.to_number::text AS to_number,
    c.tags,
    cma.display,
    (EXISTS ( SELECT 1
           FROM cc_calls_history hp
          WHERE (c.parent_id IS NULL OR c.blind_transfer IS NOT NULL) AND hp.parent_id = c.id AND hp.created_at > c.created_at::date)) AS has_children,
    COALESCE(regexp_replace(cma.description::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), ''::character varying::text)::character varying AS agent_description,
    c.grantee_id,
    ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
           FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                   FROM cc_calls_history chh
                  WHERE chh.parent_id = c.id AND chh.created_at > c.created_at::date AND chh.hold IS NOT NULL
                UNION
                 SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
          WHERE x.hi IS NOT NULL) AS hold,
    c.gateway_ids,
    c.user_ids,
    c.agent_ids,
    c.queue_ids,
    c.team_ids,
    ( SELECT json_agg(row_to_json(annotations.*)) AS json_agg
           FROM ( SELECT a.id,
                    a.call_id,
                    a.created_at,
                    cc_get_lookup(cc_1.id, COALESCE(cc_1.name, cc_1.username::text)::character varying) AS created_by,
                    a.updated_at,
                    cc_get_lookup(uc.id, COALESCE(uc.name, uc.username::text)::character varying) AS updated_by,
                    a.note,
                    a.start_sec,
                    a.end_sec,
                    a.file_id
                   FROM cc_calls_annotation a
                     LEFT JOIN directory.wbt_user cc_1 ON cc_1.id = a.created_by
                     LEFT JOIN directory.wbt_user uc ON uc.id = a.updated_by
                  WHERE a.call_id::text = c.id::text
                  ORDER BY a.created_at DESC) annotations) AS annotations,
    COALESCE(c.amd_result, c.amd_ai_result) AS amd_result,
    c.amd_duration,
    c.amd_ai_result,
    c.amd_ai_logs,
    c.amd_ai_positive,
    cq.type AS queue_type,
        CASE
            WHEN c.parent_id IS NOT NULL THEN ''::text
            WHEN c.cause::text = ANY (ARRAY['USER_BUSY'::character varying::text, 'NO_ANSWER'::character varying::text]) THEN 'not_answered'::text
            WHEN c.cause::text = 'ORIGINATOR_CANCEL'::text OR c.cause::text = 'NORMAL_UNSPECIFIED'::text AND c.amd_ai_result IS NOT NULL OR c.cause::text = 'LOSE_RACE'::text AND cq.type = 4 THEN 'cancelled'::text
            WHEN c.hangup_by::text = 'F'::text THEN 'ended'::text
            WHEN c.cause::text = 'NORMAL_CLEARING'::text THEN
            CASE
                WHEN c.cause::text = 'NORMAL_CLEARING'::text AND c.direction::text = 'outbound'::text AND c.hangup_by::text = 'A'::text AND c.user_id IS NOT NULL OR c.direction::text = 'inbound'::text AND c.hangup_by::text = 'B'::text AND c.bridged_at IS NOT NULL OR c.direction::text = 'outbound'::text AND c.hangup_by::text = 'B'::text AND (cq.type = ANY (ARRAY[4, 5, 1])) AND c.bridged_at IS NOT NULL THEN 'agent_dropped'::text
                ELSE 'client_dropped'::text
            END
            ELSE 'error'::text
        END AS hangup_disposition,
    c.blind_transfer,
    ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error, 'updated_at', cc_view_timestamp(j.updated_at))) AS jsonb_agg
           FROM storage.file_jobs j
          WHERE (j.file_id IN ( SELECT f_1.id
                   FROM ( SELECT f1.id
                           FROM storage.files f1
                          WHERE f1.domain_id = c.domain_id AND NOT f1.removed IS TRUE AND f1.uuid::text = c.id::text
                        UNION
                         SELECT f1.id
                           FROM storage.files f1
                          WHERE f1.domain_id = c.domain_id AND NOT f1.removed IS TRUE AND f1.uuid::text = c.parent_id::text) f_1))) AS files_job,
    ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id, 'file', cc_get_lookup(ff.id, ff.name))) AS data
           FROM storage.file_transcript tr
             LEFT JOIN storage.files ff ON ff.id = tr.file_id
          WHERE tr.uuid::text = c.id::text
          GROUP BY (tr.uuid::text)) AS transcripts,
    c.talk_sec,
    cc_get_lookup(au.id, au.name::character varying) AS grantee,
    ar.id AS rate_id,
    cc_get_lookup(aru.id, COALESCE(aru.name::character varying, aru.username::character varying)) AS rated_user,
    cc_get_lookup(arub.id, COALESCE(arub.name::character varying, arub.username::character varying)) AS rated_by,
    ar.score_optional,
    ar.score_required,
    (EXISTS ( SELECT 1
          WHERE c.answered_at IS NOT NULL AND cq.type = 2)) OR (EXISTS ( SELECT 1
           FROM cc_calls_history cr
          WHERE cr.id = c.bridged_id AND c.bridged_id IS NOT NULL AND c.blind_transfer IS NULL AND cr.blind_transfer IS NULL AND c.transfer_to IS NULL AND cr.transfer_to IS NULL AND c.transfer_from IS NULL AND cr.transfer_from IS NULL AND COALESCE(cr.user_id, c.user_id) IS NOT NULL)) AS allow_evaluation,
    cma.form_fields,
    c.bridged_id,
    cc_get_lookup(cc.id, cc.common_name::character varying) AS contact,
    c.contact_id,
    c.search_number,
    c.hide_missed,
    c.redial_id,
    c.parent_id IS NOT NULL AND (EXISTS ( SELECT 1
           FROM cc_calls_history lega
          WHERE lega.id = c.parent_id AND lega.domain_id = c.domain_id AND lega.bridged_at IS NOT NULL)) AS parent_bridged,
    ( SELECT jsonb_agg(cc_get_lookup(ash.id, ash.name)) AS jsonb_agg
           FROM flow.acr_routing_scheme ash
          WHERE ash.id = ANY (c.schema_ids)) AS schemas,
    c.schema_ids,
    c.hangup_phrase,
    c.blind_transfers,
    c.destination_name,
    c.attempt_ids,
    ( SELECT jsonb_agg(json_build_object('id', p.id, 'agent', u_1."user", 'form_fields', p.form_fields, 'reporting_at', cc_view_timestamp(p.reporting_at))) AS jsonb_agg
           FROM cc_member_attempt_history p
             LEFT JOIN cc_agent_with_user u_1 ON u_1.id = p.agent_id
          WHERE (p.id IN ( SELECT DISTINCT x.x
                   FROM unnest(c.attempt_ids || c.attempt_id) x(x))) AND p.reporting_at IS NOT NULL
         LIMIT 20) AS forms,
    ( SELECT co.id
           FROM chat.conversation co
          WHERE (co.props ->> 'wbt_meeting_id'::text) = (c.params ->> 'meeting_id'::text)
         LIMIT 1) AS conversation_id,
    c.params ->> 'meeting_id'::text AS meeting_id,
    row_to_json(ms.*) AS quality_metrics,
    COALESCE(c.params ->> 'ua'::text, ''::text) AS user_agent,
    COALESCE(cq.variables ->> 'wbt_hide_number'::text, ''::text) = 'true'::text AS hide_number
   FROM cc_calls_history c
     LEFT JOIN cc_queue cq ON c.queue_id = cq.id
     LEFT JOIN cc_member cm ON c.member_id = cm.id
     LEFT JOIN cc_member_attempt_history cma ON cma.id = c.attempt_id
     LEFT JOIN cc_agent aa ON cma.agent_id = aa.id
     LEFT JOIN directory.wbt_user cag ON cag.id = aa.user_id
     LEFT JOIN cc_team ct ON aa.team_id = ct.id
     LEFT JOIN directory.wbt_user u ON u.id = c.user_id
     LEFT JOIN directory.sip_gateway gw ON gw.id = c.gateway_id
     LEFT JOIN directory.wbt_auth au ON au.id = c.grantee_id
     LEFT JOIN cc_audit_rate ar ON ar.call_id::text = c.id::text
     LEFT JOIN directory.wbt_user aru ON aru.id = ar.rated_user_id
     LEFT JOIN directory.wbt_user arub ON arub.id = ar.created_by
     LEFT JOIN contacts.contact cc ON cc.id = c.contact_id
     LEFT JOIN cc_calls_media_stats ms ON ms.sip_id = (c.params ->> 'sip_id'::text);


     CREATE OR REPLACE VIEW "call_center"."cc_online_skills_list" AS
      SELECT p.id,
         p.domain_id,
         cc_get_lookup(uc.id, COALESCE(uc.name, uc.username::text)::character varying) AS created_by,
         p.created_at,
         cc_get_lookup(ua.id, COALESCE(ua.name, ua.username::text)::character varying) AS updated_by,
         p.updated_at,
         p.name,
         p.description,
         s.skills,
         p.is_system
        FROM cc_online_skills p
          LEFT JOIN LATERAL ( SELECT jsonb_agg(cc_get_lookup(s_1.id::bigint, s_1.name)) AS skills
                FROM cc_skills_in_online_skills si
                  JOIN cc_skill s_1 ON s_1.id = si.skill_id
               WHERE si.online_skill_id = p.id) s ON true
          LEFT JOIN directory.wbt_user uc ON uc.id = p.created_by
          LEFT JOIN directory.wbt_user ua ON ua.id = p.updated_by;

          CREATE OR REPLACE VIEW "call_center"."cc_queue_list" AS
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
              cc_get_lookup(uc.id, uc.name::character varying) AS created_by,
              cc_get_lookup(u.id, u.name::character varying) AS updated_by,
              cc_get_lookup(c.id::bigint, c.name) AS calendar,
              cc_get_lookup(cl.id, cl.name) AS dnc_list,
              cc_get_lookup(ct.id, ct.name) AS team,
              cc_get_lookup(q.ringtone_id::bigint, mf.name) AS ringtone,
              q.description,
              cc_get_lookup(s.id, s.name) AS schema,
              cc_get_lookup(ds.id, ds.name) AS do_schema,
              cc_get_lookup(afs.id, afs.name) AS after_schema,
              cc_get_lookup(fs.id, fs.name) AS form_schema,
              COALESCE(ss.member_count, 0::bigint) AS count,
                  CASE
                      WHEN q.type = ANY (ARRAY[1, 6]) THEN COALESCE(act.cnt_w, 0::bigint)
                      ELSE COALESCE(ss.member_waiting, 0::bigint)
                  END AS waiting,
              COALESCE(act.cnt, 0::bigint) AS active,
              q.sticky_agent,
              q.processing,
              q.processing_sec,
              q.processing_renewal_sec,
              jsonb_build_object('enabled', q.processing, 'form_schema', cc_get_lookup(fs.id, fs.name), 'sec', q.processing_sec, 'renewal_sec', q.processing_renewal_sec, 'processing_autosave', q.processing_autosave) AS task_processing,
              cc_get_lookup(au.id, au.name::character varying) AS grantee,
              q.team_id,
              q.tags,
              COALESCE(rg.resource_groups, '[]'::jsonb) AS resource_groups,
              COALESCE(rg.resources, '[]'::jsonb) AS resources
             FROM cc_queue q
               LEFT JOIN flow.calendar c ON q.calendar_id = c.id
               LEFT JOIN directory.wbt_auth au ON au.id = q.grantee_id
               LEFT JOIN directory.wbt_user uc ON uc.id = q.created_by
               LEFT JOIN directory.wbt_user u ON u.id = q.updated_by
               LEFT JOIN flow.acr_routing_scheme s ON q.schema_id = s.id
               LEFT JOIN flow.acr_routing_scheme ds ON q.do_schema_id = ds.id
               LEFT JOIN flow.acr_routing_scheme afs ON q.after_schema_id = afs.id
               LEFT JOIN flow.acr_routing_scheme fs ON q.form_schema_id = fs.id
               LEFT JOIN cc_list cl ON q.dnc_list_id = cl.id
               LEFT JOIN cc_team ct ON q.team_id = ct.id
               LEFT JOIN storage.media_files mf ON q.ringtone_id = mf.id
               LEFT JOIN LATERAL ( SELECT sum(s_1.member_waiting) AS member_waiting,
                      sum(s_1.member_count) AS member_count
                     FROM cc_queue_statistics s_1
                    WHERE s_1.queue_id = q.id) ss ON true
               LEFT JOIN LATERAL ( SELECT count(*) AS cnt,
                      count(*) FILTER (WHERE a.agent_id IS NULL) AS cnt_w
                     FROM cc_member_attempt a
                    WHERE a.queue_id = q.id AND a.leaving_at IS NULL AND a.state::text <> 'leaving'::text) act ON true
               LEFT JOIN LATERAL ( SELECT jsonb_agg(DISTINCT cc_get_lookup(corg.id, corg.name)) FILTER (WHERE corg.id IS NOT NULL) AS resource_groups,
                      jsonb_agg(DISTINCT cc_get_lookup(cor.id::bigint, cor.name)) FILTER (WHERE cor.id IS NOT NULL) AS resources
                     FROM cc_queue_resource cqr
                       JOIN cc_outbound_resource_group corg ON corg.id = cqr.resource_group_id
                       LEFT JOIN cc_outbound_resource_in_group corg_res ON corg_res.group_id = corg.id
                       LEFT JOIN cc_outbound_resource cor ON cor.id = corg_res.resource_id
                    WHERE cqr.queue_id = q.id) rg ON true;

               drop view if exists "call_center"."cc_agent_list";

               CREATE OR REPLACE VIEW "call_center"."cc_agent_list" AS
                SELECT a.domain_id,
                   a.id,
                   COALESCE(ct.name, ct.username::text COLLATE "default")::character varying AS name,
                   a.status,
                   a.description,
                   (date_part('epoch'::text, a.last_state_change) * 1000::double precision)::bigint AS last_status_change,
                   date_part('epoch'::text, now() - a.last_state_change)::bigint AS status_duration,
                   a.progressive_count,
                   ch.x AS channel,
                   json_build_object('id', ct.id, 'name', COALESCE(ct.name, ct.username::text))::jsonb AS "user",
                   cc_get_lookup(a.greeting_media_id::bigint, g.name) AS greeting_media,
                   a.allow_channels,
                   a.chat_count,
                   ( SELECT jsonb_agg(sag."user") AS jsonb_agg
                          FROM cc_agent_with_user sag
                         WHERE sag.id = ANY (a.supervisor_ids)) AS supervisor,
                   ( SELECT jsonb_agg(cc_get_lookup(aud.id, COALESCE(aud.name, aud.username::text)::character varying)) AS jsonb_agg
                          FROM directory.wbt_user aud
                         WHERE aud.id = ANY (a.auditor_ids)) AS auditor,
                   cc_get_lookup(t.id, t.name) AS team,
                   cc_get_lookup(r.id::bigint, r.name) AS region,
                   a.supervisor AS is_supervisor,
                   ( SELECT jsonb_agg(cc_get_lookup(sa.skill_id::bigint, cs.name)) AS jsonb_agg
                          FROM cc_skill_in_agent sa
                            JOIN cc_skill cs ON sa.skill_id = cs.id
                         WHERE sa.agent_id = a.id) AS skills,
                   a.team_id,
                   a.region_id,
                   a.supervisor_ids,
                   a.auditor_ids,
                   a.user_id,
                   ct.extension,
                   a.task_count,
                   a.screen_control,
                   t.screen_control IS FALSE AS allow_set_screen_control,
                   row_number() OVER (PARTITION BY a.domain_id ORDER BY (
                       CASE
                           WHEN a.status::text = 'online'::text THEN 0
                           WHEN a.status::text = 'pause'::text THEN 1
                           WHEN a.status::text = 'offline'::text THEN 2
                           ELSE 3
                       END), (COALESCE(ct.name, ct.username::text))) AS "position",
                   COALESCE(( SELECT array_agg(status.open) AS array_agg
                          FROM ( SELECT 'dnd'::name AS "?column?"
                                  FROM directory.wbt_user_status stt
                                 WHERE stt.user_id = a.user_id AND stt.dnd
                               UNION ALL
                               ( SELECT stt.status
                                  FROM directory.wbt_user_presence stt
                                 WHERE stt.user_id = a.user_id AND stt.status IS NOT NULL AND stt.open > 0
                                 ORDER BY stt.prior, stt.status)) status(open)), '{}'::name[]) AS user_presence_status,
                   a.extra_chat_count,
                   COALESCE(a.status_payload, os.name::character varying, ''::character varying) AS status_type
                  FROM cc_agent a
                    LEFT JOIN directory.wbt_user ct ON ct.id = a.user_id
                    LEFT JOIN storage.media_files g ON g.id = a.greeting_media_id
                    LEFT JOIN cc_team t ON t.id = a.team_id
                    LEFT JOIN flow.region r ON r.id = a.region_id
                    LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', (date_part('epoch'::text, c.joined_at) * 1000::double precision)::bigint)) AS x
                          FROM cc_agent_channel c
                         WHERE c.agent_id = a.id) ch ON true
                    LEFT JOIN cc_online_skills os ON a.status_id IS NOT NULL AND a.status_id = os.id AND os.is_system IS FALSE;

                    CREATE OR REPLACE FUNCTION call_center.cc_attempt_timeout(attempt_id_ bigint, agent_status_ character varying, agent_hold_sec_ integer, max_attempts_ integer DEFAULT 0, per_number_ boolean DEFAULT false, do_leaving_ boolean DEFAULT false)
                     RETURNS timestamp with time zone
                     LANGUAGE plpgsql
                    AS $function$
                    declare
                        attempt call_center.cc_member_attempt%rowtype;
                    begin
                        update call_center.cc_member_attempt a
                            set reporting_at = now(),
                            result = CASE
                                  WHEN a.queue_id IS NULL THEN 'timeout'
                                  WHEN max_attempts_ = 1 AND (SELECT q.prolongation_is_timeout_retry
                                                              FROM call_center.cc_queue q
                                                              WHERE q.id = a.queue_id) = false
                                      THEN 'canceled_by_timeout'
                                  ELSE 'timeout'
                              END,
                                state = 'leaving',
                                schema_processing = do_leaving_
                        where a.id = attempt_id_
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
                    $function$;
