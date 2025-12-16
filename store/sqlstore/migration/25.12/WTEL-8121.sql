DROP VIEW call_center.cc_calls_history_list;
--
-- Name: cc_calls_history_list; Type: VIEW; Schema: call_center; Owner: -
--

CREATE OR REPLACE VIEW call_center.cc_calls_history_list AS
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
       ( SELECT json_agg(jsonb_build_object('id', f_1.id, 'name', f_1.name, 'size', f_1.size, 'mime_type', f_1.mime_type, 'start_at',
                                            CASE
                                              WHEN ((f_1.channel)::text = 'call'::text) THEN ((c.params -> 'record_start'::text))::bigint
                                              ELSE ((f_1.custom_properties ->> 'start_time'::text))::bigint
                                              END, 'stop_at',
                                            CASE
                                              WHEN ((f_1.channel)::text = 'call'::text) THEN ((c.params -> 'record_stop'::text))::bigint
                                              ELSE ((f_1.custom_properties ->> 'end_time'::text))::bigint
                                              END, 'start_record', f_1.sr, 'channel', f_1.channel)) AS files
         FROM ( SELECT f1.id,
                       f1.size,
                       f1.mime_type,
                       COALESCE(f1.view_name, f1.name) AS name,
                       f1.channel,
                       f1.custom_properties,
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
                       COALESCE(f1.view_name, f1.name) AS name,
                       f1.channel,
                       f1.custom_properties,
                       NULL::text AS sr
                FROM storage.files f1
                WHERE ((f1.domain_id = c.domain_id) AND (NOT (f1.removed IS TRUE)) AND (c.parent_id IS NOT NULL) AND ((f1.uuid)::text = (c.parent_id)::text))) f_1) AS files,
       call_center.cc_get_lookup((cq.id)::bigint, cq.name) AS queue,
       call_center.cc_get_lookup(c.member_id, cm.name) AS member,
       call_center.cc_get_lookup(ct.id, ct.name) AS team,
       call_center.cc_get_lookup(aa.id::bigint, COALESCE(cag.name, cag.username)::character varying) AS agent,
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
