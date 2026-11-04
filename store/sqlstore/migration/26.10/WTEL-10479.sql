CREATE OR REPLACE VIEW call_center.cc_member_view_attempt_history AS
SELECT t.id,
       t.joined_at,
       t.offering_at,
       t.bridged_at,
       t.reporting_at,
       t.leaving_at,
       t.channel,
       call_center.cc_get_lookup((t.queue_id)::bigint, cq.name) AS queue,
       call_center.cc_get_lookup(t.member_id, cm.name) AS member,
       t.member_call_id,
       COALESCE(cm.variables, '{}'::jsonb) AS variables,
       call_center.cc_get_lookup((t.agent_id)::bigint, (COALESCE(u.name, (u.username)::text))::character varying) AS agent,
       ( SELECT jsonb_agg(ofa."user") AS jsonb_agg
         FROM call_center.cc_agent_with_user ofa
         WHERE (ofa.id = ANY (t.offered_agent_ids))) AS offered_agents,
       t.agent_call_id,
       t.weight AS "position",
       call_center.cc_get_lookup((t.resource_id)::bigint, r.name) AS resource,
       call_center.cc_get_lookup(t.bucket_id, (cb.name)::character varying) AS bucket,
       call_center.cc_get_lookup(t.list_communication_id, l.name) AS list,
       COALESCE(t.display, ''::character varying) AS display,
       t.destination,
       t.result,
       t.domain_id,
       t.queue_id,
       t.bucket_id,
       t.member_id,
       t.agent_id,
       t.seq AS attempts,
       c.amd_result,
       t.offered_agent_ids,
       (EXTRACT(epoch FROM (COALESCE(t.reporting_at, t.leaving_at) - t.joined_at)))::bigint AS duration
FROM ((((((((call_center.cc_member_attempt_history t
    LEFT JOIN call_center.cc_queue cq ON ((t.queue_id = cq.id)))
    LEFT JOIN call_center.cc_member cm ON ((t.member_id = cm.id)))
    LEFT JOIN call_center.cc_agent a ON ((t.agent_id = a.id)))
    LEFT JOIN directory.wbt_user u ON (((u.id = a.user_id) AND (u.dc = a.domain_id))))
    LEFT JOIN call_center.cc_outbound_resource r ON ((r.id = t.resource_id)))
    LEFT JOIN call_center.cc_bucket cb ON ((cb.id = t.bucket_id)))
    LEFT JOIN call_center.cc_list l ON ((l.id = t.list_communication_id)))
    LEFT JOIN call_center.cc_calls_history c ON (((c.domain_id = t.domain_id) AND (c.id = (t.member_call_id)::uuid))));
