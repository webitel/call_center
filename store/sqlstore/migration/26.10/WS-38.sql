CREATE OR REPLACE VIEW "call_center"."cc_manual_queue_list" AS
 WITH manual_queue AS MATERIALIZED (
         SELECT q.domain_id,
            q.id,
            call_center.cc_get_lookup(q.id::bigint, q.name) AS queue,
            q.priority,
            q.sticky_agent,
            q.team_id,
            COALESCE((q.payload -> 'max_wait_time'::text)::integer, 0) AS max_wait_time,
            COALESCE((q.payload -> 'sticky_agent_sec'::text)::integer, 0) AS sticky_agent_sec
           FROM call_center.cc_queue q
          where q.enabled and (q.payload->>'manual_distribution')::boolean is true
          ORDER BY q.domain_id
        ), queues AS MATERIALIZED (
         SELECT DISTINCT q.domain_id,
            q.queue,
            qs.queue_id,
            q.priority,
            bq.priority AS bucket_pri,
            q.max_wait_time,
            q.sticky_agent_sec,
            q.sticky_agent,
            b.b AS bucket_id,
            csia.agent_id,
            a.user_id,
            max(qs.lvl) AS lvl
           FROM manual_queue q
             JOIN call_center.cc_queue_skill qs ON qs.queue_id = q.id
             JOIN call_center.cc_skill_in_agent csia ON csia.skill_id = qs.skill_id
             JOIN call_center.cc_agent a ON a.id = csia.agent_id AND (q.team_id IS NULL OR q.team_id = a.team_id)
             LEFT JOIN call_center.cc_online_skills sp ON sp.id = a.status_id AND a.status::text = 'online'::text
             LEFT JOIN call_center.cc_skills_in_online_skills spp ON spp.online_skill_id = a.status_id AND spp.skill_id = qs.skill_id AND a.status::text = 'online'::text
             LEFT JOIN LATERAL unnest(qs.bucket_ids) b(b) ON true
             LEFT JOIN call_center.cc_bucket_in_queue bq ON bq.queue_id = q.id AND bq.bucket_id = b.b
          WHERE qs.enabled AND csia.enabled AND csia.capacity >= qs.min_capacity AND csia.capacity <= qs.max_capacity AND q.domain_id = a.domain_id AND a.status::text = 'online'::text AND (a.status_id IS NULL OR a.status::text <> 'online'::text OR spp.skill_id IS NOT NULL OR sp.is_system IS TRUE)
          GROUP BY q.domain_id, q.queue, qs.queue_id, q.priority, bq.priority, q.max_wait_time, q.sticky_agent_sec, q.sticky_agent, b.b, csia.agent_id, a.user_id
        ), attempts AS MATERIALIZED (
         SELECT q.domain_id,
            q.queue,
            q.queue_id,
            q.priority,
            q.bucket_pri,
            q.max_wait_time,
            q.sticky_agent_sec,
            q.sticky_agent,
            q.bucket_id,
            q.agent_id,
            q.user_id,
            q.lvl,
            a.id AS attempt_id,
            a.joined_at,
            a.member_call_id AS session_id,
            EXTRACT(epoch FROM now() - a.joined_at)::integer AS wait,
            a.destination AS communication,
            a.sticky_agent_id,
            a.channel,
            (EXTRACT(epoch FROM now() - a.joined_at) / COALESCE(NULLIF(q.max_wait_time::numeric, 0::numeric), 3600::numeric) * 100::numeric)::integer AS deadline,
            call_center.cc_get_lookup(con.id, con.common_name::character varying) AS contact
           FROM call_center.cc_member_attempt a
             JOIN queues q ON q.queue_id = a.queue_id
             left join call_center.cc_calls c on a.channel = 'call' and c.id = a.member_call_id::uuid
             left join contacts.contact con on con.id = c.contact_id
          WHERE a.domain_id = q.domain_id AND a.agent_id IS NULL AND a.state::text = 'wait_agent'::text AND a.queue_id = q.queue_id AND COALESCE(q.bucket_id, 0) = COALESCE(a.bucket_id, 0::bigint) AND (a.sticky_agent_id IS NULL OR a.sticky_agent_id = q.agent_id OR a.joined_at < (now() - ((q.sticky_agent_sec || ' sec'::text)::interval)))
         FOR UPDATE OF a SKIP LOCKED
        )
 SELECT domain_id,
    array_agg(user_id) AS users,
    array_to_json(calls[1:50]) AS calls,
    array_to_json(chats[1:100]) AS chats
   FROM ( SELECT a.domain_id,
            a.user_id,
            array_agg(jsonb_build_object('attempt_id', a.attempt_id, 'wait', a.wait, 'communication', a.communication, 'queue', a.queue, 'bucket', call_center.cc_get_lookup(b.id, b.name::text::character varying), 'deadline', a.deadline, 'session_id', a.session_id, 'contact', a.contact) ORDER BY a.lvl, a.priority DESC, a.bucket_pri DESC NULLS LAST, a.wait DESC) FILTER (WHERE a.channel::text = 'call'::text) AS calls,
            array_agg(jsonb_build_object('attempt_id', a.attempt_id, 'wait', a.wait, 'communication', a.communication, 'queue', a.queue, 'bucket', call_center.cc_get_lookup(b.id, b.name::text::character varying), 'deadline', a.deadline, 'session_id', a.session_id) ORDER BY a.lvl, a.priority DESC, a.bucket_pri DESC NULLS LAST, a.wait DESC) FILTER (WHERE a.channel::text = ANY (ARRAY['chat'::text, 'im'::text])) AS chats
           FROM attempts a
             LEFT JOIN call_center.cc_bucket b ON b.id = a.bucket_id
          GROUP BY a.domain_id, a.user_id) x
  GROUP BY domain_id, (calls[1:50]), (chats[1:100]);
