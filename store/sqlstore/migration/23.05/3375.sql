
drop VIEW call_center.cc_calls_history_list;
CREATE VIEW call_center.cc_calls_history_list AS
SELECT c.id,
       c.app_id,
       'call'::character varying AS type,
       c.parent_id,
       c.transfer_from,
       CASE
           WHEN ((c.parent_id IS NOT NULL) AND (c.transfer_to IS NULL) AND ((c.id)::text <> (lega.bridged_id)::text)) THEN lega.bridged_id
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
       f.files,
       call_center.cc_get_lookup((cq.id)::bigint, cq.name) AS queue,
       call_center.cc_get_lookup((cm.id)::bigint, cm.name) AS member,
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
                 WHERE ((c.parent_id IS NULL) AND ((hp.parent_id)::text = (c.id)::text)))) AS has_children,
       (COALESCE(regexp_replace((cma.description)::text, '^[\r\n\t ]*|[\r\n\t ]*$'::text, ''::text, 'g'::text), (''::character varying)::text))::character varying AS agent_description,
       c.grantee_id,
       holds.res AS hold,
       c.gateway_ids,
       c.user_ids,
       c.agent_ids,
       c.queue_ids,
       c.team_ids,
       ( SELECT json_agg(row_to_json(annotations.*)) AS json_agg
         FROM ( SELECT a.id,
                       a.call_id,
                       a.created_at,
                       call_center.cc_get_lookup(cc.id, (COALESCE(cc.name, (cc.username)::text))::character varying) AS created_by,
                       a.updated_at,
                       call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS updated_by,
                       a.note,
                       a.start_sec,
                       a.end_sec
                FROM ((call_center.cc_calls_annotation a
                    LEFT JOIN directory.wbt_user cc ON ((cc.id = a.created_by)))
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
           WHEN ((c.cause)::text = 'ORIGINATOR_CANCEL'::text) THEN 'cancelled'::text
           WHEN ((c.hangup_by)::text = 'F'::text) THEN 'ended'::text
           WHEN ((c.cause)::text = 'NORMAL_CLEARING'::text) THEN
               CASE
                   WHEN ((((c.cause)::text = 'NORMAL_CLEARING'::text) AND (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'A'::text) AND (c.user_id IS NOT NULL))) OR (((c.direction)::text = 'inbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (c.bridged_at IS NOT NULL)) OR (((c.direction)::text = 'outbound'::text) AND ((c.hangup_by)::text = 'B'::text) AND (cq.type = ANY (ARRAY[4, 5, 1])) AND (c.bridged_at IS NOT NULL))) THEN 'agent_dropped'::text
                   ELSE 'client_dropped'::text
                   END
           ELSE 'error'::text
           END AS hangup_disposition,
       c.blind_transfer,
       ( SELECT jsonb_agg(json_build_object('id', j.id, 'created_at', call_center.cc_view_timestamp(j.created_at), 'action', j.action, 'file_id', j.file_id, 'state', j.state, 'error', j.error, 'updated_at', call_center.cc_view_timestamp(j.updated_at))) AS jsonb_agg
         FROM storage.file_jobs j
         WHERE (j.file_id = ANY (f.file_ids))) AS files_job,
       transcripts.data AS transcripts,
       c.talk_sec,
       call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
       ar.id AS rate_id,
       call_center.cc_get_lookup(aru.id, COALESCE((aru.name)::character varying, (aru.username)::character varying)) AS rated_user,
       call_center.cc_get_lookup(arub.id, COALESCE((arub.name)::character varying, (arub.username)::character varying)) AS rated_by,
       ar.score_optional,
       ar.score_required
FROM ((((((((((((((((call_center.cc_calls_history c
    LEFT JOIN LATERAL ( SELECT array_agg(f_1.id) AS file_ids,
                               json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at', ((c.params -> 'record_start'::text))::bigint, 'stop_at', ((c.params -> 'record_stop'::text))::bigint)) AS files
                        FROM ( SELECT f1.id,
                                      f1.size,
                                      f1.mime_type,
                                      f1.name
                               FROM storage.files f1
                               WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.id)::text))
                               UNION ALL
                               SELECT f1.id,
                                      f1.size,
                                      f1.mime_type,
                                      f1.name
                               FROM storage.files f1
                               WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) f ON (((c.answered_at IS NOT NULL) OR (c.bridged_at IS NOT NULL))))
    LEFT JOIN LATERAL ( SELECT jsonb_agg(x.hi ORDER BY (x.hi -> 'start'::text)) AS res
                        FROM ( SELECT jsonb_array_elements(chh.hold) AS hi
                               FROM call_center.cc_calls_history chh
                               WHERE (((chh.parent_id)::text = (c.id)::text) AND (chh.hold IS NOT NULL))
                               UNION
                               SELECT jsonb_array_elements(c.hold) AS jsonb_array_elements) x
                        WHERE (x.hi IS NOT NULL)) holds ON ((c.parent_id IS NULL)))
    LEFT JOIN call_center.cc_queue cq ON ((c.queue_id = cq.id)))
    LEFT JOIN call_center.cc_team ct ON ((c.team_id = ct.id)))
    LEFT JOIN call_center.cc_member cm ON ((c.member_id = cm.id)))
    LEFT JOIN call_center.cc_member_attempt_history cma ON ((cma.id = c.attempt_id)))
    LEFT JOIN call_center.cc_agent aa ON ((cma.agent_id = aa.id)))
    LEFT JOIN directory.wbt_user cag ON ((cag.id = aa.user_id)))
    LEFT JOIN directory.wbt_user u ON ((u.id = c.user_id)))
    LEFT JOIN directory.sip_gateway gw ON ((gw.id = c.gateway_id)))
    LEFT JOIN directory.wbt_auth au ON ((au.id = c.grantee_id)))
    LEFT JOIN call_center.cc_calls_history lega ON (((c.parent_id IS NOT NULL) AND ((lega.id)::text = (c.parent_id)::text))))
    LEFT JOIN LATERAL ( SELECT json_agg(json_build_object('id', tr.id, 'locale', tr.locale, 'file_id', tr.file_id, 'file', call_center.cc_get_lookup(ff.id, ff.name))) AS data
                        FROM (storage.file_transcript tr
                            LEFT JOIN storage.files ff ON ((ff.id = tr.file_id)))
                        WHERE ((tr.uuid)::text = ((c.id)::character varying(50))::text)
                        GROUP BY (tr.uuid)::text) transcripts ON (true))
    LEFT JOIN call_center.cc_audit_rate ar ON (((ar.call_id)::text = (c.id)::text)))
    LEFT JOIN directory.wbt_user aru ON ((aru.id = ar.rated_user_id)))
    LEFT JOIN directory.wbt_user arub ON ((arub.id = ar.created_by)));





drop VIEW call_center.cc_skill_in_agent_view;
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
       COALESCE(u.name, (u.username)::text) AS agent_name
FROM ((((((call_center.cc_skill_in_agent sa
    LEFT JOIN call_center.cc_agent ca ON ((sa.agent_id = ca.id)))
    LEFT JOIN call_center.cc_team t ON ((t.id = ca.team_id)))
    LEFT JOIN directory.wbt_user uu ON ((uu.id = ca.user_id)))
    LEFT JOIN call_center.cc_skill cs ON ((sa.skill_id = cs.id)))
    LEFT JOIN directory.wbt_user c ON ((c.id = sa.created_by)))
    LEFT JOIN directory.wbt_user u ON ((u.id = sa.updated_by)));


drop VIEW call_center.cc_skill_view;
--
-- Name: cc_skill_view; Type: VIEW; Schema: call_center; Owner: -
--
CREATE VIEW call_center.cc_skill_view AS
SELECT c.id,
       c.name,
       c.description,
       c.domain_id,
       ( SELECT count(DISTINCT sa.agent_id) AS count
         FROM call_center.cc_skill_in_agent sa
         WHERE ((sa.skill_id = c.id) AND sa.enabled)) AS agents
FROM call_center.cc_skill c;
