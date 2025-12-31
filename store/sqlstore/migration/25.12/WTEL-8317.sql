DROP VIEW call_center.cc_queue_list;
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
       call_center.cc_get_lookup(fs.id, fs.name) AS form_schema,
       COALESCE(ss.member_count, (0)::bigint) AS count,
       CASE
         WHEN (q.type = ANY (ARRAY[1, 6])) THEN COALESCE(act.cnt_w, (0)::bigint)
         ELSE COALESCE(ss.member_waiting, (0)::bigint)
         END AS waiting,
       COALESCE(act.cnt, (0)::bigint) AS active,
       q.sticky_agent,
       q.processing,
       q.processing_sec,
       q.processing_renewal_sec,
       jsonb_build_object('enabled', q.processing, 'form_schema', call_center.cc_get_lookup(fs.id, fs.name), 'sec', q.processing_sec, 'renewal_sec', q.processing_renewal_sec) AS task_processing,
       call_center.cc_get_lookup(au.id, (au.name)::character varying) AS grantee,
       q.team_id,
       q.tags,
       COALESCE(rg.resource_groups, '[]'::jsonb) AS resource_groups,
       COALESCE(rg.resources, '[]'::jsonb) AS resources
FROM ((((((((((((((call_center.cc_queue q
  LEFT JOIN flow.calendar c ON ((q.calendar_id = c.id)))
  LEFT JOIN directory.wbt_auth au ON ((au.id = q.grantee_id)))
  LEFT JOIN directory.wbt_user uc ON ((uc.id = q.created_by)))
  LEFT JOIN directory.wbt_user u ON ((u.id = q.updated_by)))
  LEFT JOIN flow.acr_routing_scheme s ON ((q.schema_id = s.id)))
  LEFT JOIN flow.acr_routing_scheme ds ON ((q.do_schema_id = ds.id)))
  LEFT JOIN flow.acr_routing_scheme afs ON ((q.after_schema_id = afs.id)))
  LEFT JOIN flow.acr_routing_scheme fs ON ((q.form_schema_id = fs.id)))
  LEFT JOIN call_center.cc_list cl ON ((q.dnc_list_id = cl.id)))
  LEFT JOIN call_center.cc_team ct ON ((q.team_id = ct.id)))
  LEFT JOIN storage.media_files mf ON ((q.ringtone_id = mf.id)))
  LEFT JOIN LATERAL ( SELECT sum(s_1.member_waiting) AS member_waiting,
                             sum(s_1.member_count) AS member_count
                      FROM call_center.cc_queue_statistics s_1
                      WHERE (s_1.queue_id = q.id)) ss ON (true))
  LEFT JOIN LATERAL ( SELECT count(*) AS cnt,
                             count(*) FILTER (WHERE (a.agent_id IS NULL)) AS cnt_w
                      FROM call_center.cc_member_attempt a
                      WHERE ((a.queue_id = q.id) AND (a.leaving_at IS NULL) AND ((a.state)::text <> 'leaving'::text))) act ON (true))
  LEFT JOIN LATERAL ( SELECT jsonb_agg(DISTINCT call_center.cc_get_lookup(corg.id, corg.name)) FILTER (WHERE (corg.id IS NOT NULL)) AS resource_groups,
                             jsonb_agg(DISTINCT call_center.cc_get_lookup(cor.id, cor.name)) FILTER (WHERE (cor.id IS NOT NULL)) AS resources
                      FROM (((call_center.cc_queue_resource cqr
                        JOIN call_center.cc_outbound_resource_group corg ON ((corg.id = cqr.resource_group_id)))
                        LEFT JOIN call_center.cc_outbound_resource_in_group corg_res ON ((corg_res.group_id = corg.id)))
                        LEFT JOIN call_center.cc_outbound_resource cor ON ((cor.id = corg_res.resource_id)))
                      WHERE (cqr.queue_id = q.id)) rg ON (true));