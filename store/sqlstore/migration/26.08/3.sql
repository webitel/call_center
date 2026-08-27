-- View: call_center.cc_agent_in_queue_view

-- DROP VIEW call_center.cc_agent_in_queue_view;

CREATE OR REPLACE VIEW call_center.cc_agent_in_queue_view
 AS
 WITH users_with_calls AS (
          SELECT DISTINCT c.user_id
            FROM call_center.cc_calls c
           WHERE c.user_id IS NOT NULL AND (c.hangup_at IS NULL AND NOT (EXISTS ( SELECT 1
                    FROM call_center.cc_calls cc
                   WHERE cc.parent_id = c.id AND cc.hangup_at IS NOT NULL)) OR c.hangup_at IS NOT NULL AND c.attempt_id IS NOT NULL AND (EXISTS ( SELECT 1
                    FROM call_center.cc_agent_channel ch
                   WHERE ch.agent_id = c.agent_id AND (ch.channel::text = ANY (ARRAY['call'::character varying::text, 'out_call'::character varying::text])) AND ch.state::text = 'processing'::text)))
         )
  SELECT q.queue,
     q.priority,
     q.type,
     q.strategy,
     q.enabled,
     q.count_members,
     q.waiting_members,
     q.active_members,
     q.queue_id,
     q.queue_name,
     q.team_id,
     q.domain_id,
     q.agent_id,
     jsonb_build_object('online', COALESCE(array_length(a.agent_on_ids, 1), 0), 'pause', COALESCE(array_length(a.agent_p_ids, 1), 0), 'offline', COALESCE(array_length(a.agent_off_ids, 1), 0), 'free', COALESCE(array_length(a.free, 1), 0), 'total', COALESCE(array_length(a.total, 1), 0), 'allow_pause',
         CASE
             WHEN q.min_online_agents > 0 THEN GREATEST(COALESCE(array_length(a.agent_p_ids, 1), 0) + COALESCE(array_length(a.agent_on_ids, 1), 0) - q.min_online_agents, 0)
             ELSE NULL::integer
         END, 'busy', COALESCE(array_length(a.agent_b_ids, 1), 0)) AS agents,
     q.max_member_limit
    FROM ( SELECT call_center.cc_get_lookup(q_1.id::bigint, q_1.name) AS queue,
             q_1.priority,
             q_1.type,
             q_1.strategy,
             q_1.enabled,
             COALESCE((q_1.payload -> 'min_online_agents'::text)::integer, 0) AS min_online_agents,
             COALESCE((q_1.payload -> 'max_member_limit'::text)::integer, 0) AS max_member_limit,
             COALESCE(sum(cqs.member_count), 0::bigint) AS count_members,
                 CASE
                     WHEN q_1.type = ANY (ARRAY[1, 6]) THEN ( SELECT count(*) AS count
                        FROM call_center.cc_member_attempt a_1_1
                       WHERE a_1_1.queue_id = q_1.id AND (a_1_1.state::text = ANY (ARRAY['wait_agent'::character varying::text, 'offering'::character varying::text])) AND a_1_1.leaving_at IS NULL)
                     ELSE COALESCE(sum(cqs.member_waiting), 0::bigint)
                 END AS waiting_members,
             ( SELECT count(*) AS count
                    FROM call_center.cc_member_attempt a_1_1
                   WHERE a_1_1.queue_id = q_1.id) AS active_members,
             q_1.id AS queue_id,
             q_1.name AS queue_name,
             q_1.team_id,
             a_1.domain_id,
             a_1.id AS agent_id,
                 CASE
                     WHEN q_1.type >= 0 AND q_1.type <= 5 THEN 'call'::text
                     WHEN q_1.type = 6 THEN 'chat'::text
                     ELSE 'task'::text
                 END AS chan_name
            FROM call_center.cc_agent a_1
              JOIN call_center.cc_queue q_1 ON q_1.domain_id = a_1.domain_id
              LEFT JOIN call_center.cc_queue_statistics cqs ON q_1.id = cqs.queue_id
           WHERE (q_1.team_id IS NULL OR a_1.team_id = q_1.team_id) AND (EXISTS (
		  		   SELECT qs.queue_id
                    FROM call_center.cc_queue_skill qs
                    JOIN call_center.cc_skill_in_agent csia ON csia.skill_id = qs.skill_id
                   WHERE qs.enabled AND csia.enabled AND csia.agent_id = a_1.id AND qs.queue_id = q_1.id AND csia.capacity >= qs.min_capacity AND csia.capacity <= qs.max_capacity))
           GROUP BY a_1.id, q_1.id, q_1.priority) q
      LEFT JOIN LATERAL ( SELECT DISTINCT array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = 'online'::text AND (a_1.status_id IS NULL OR sp.is_system IS TRUE OR spp.skill_id IS NOT NULL)) AS agent_on_ids,
             array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = 'offline'::text) AS agent_off_ids,
             array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = ANY (ARRAY['pause'::character varying::text, 'break_out'::character varying::text])) AS agent_p_ids,
             array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = 'online'::text AND (a_1.status_id IS NULL OR sp.is_system IS TRUE OR spp.skill_id IS NOT NULL) AND ac.state::text = 'waiting'::text AND (ac_call.user_id IS NULL OR (ac.channel::text = ANY (ARRAY['chat'::text, 'task'::text])))) AS free,
             array_agg(DISTINCT a_1.id) FILTER (WHERE a_1.status::text = 'online'::text AND (a_1.status_id IS NULL OR sp.is_system IS TRUE OR spp.skill_id IS NOT NULL) AND ac_call.user_id IS NOT NULL) AS agent_b_ids,
             array_agg(DISTINCT a_1.id) AS total
            FROM call_center.cc_agent a_1
              JOIN call_center.cc_agent_channel ac ON ac.agent_id = a_1.id AND ac.channel::text = q.chan_name
              LEFT JOIN users_with_calls ac_call ON ac_call.user_id = a_1.user_id
              JOIN call_center.cc_queue_skill qs ON qs.queue_id = q.queue_id AND qs.enabled
              JOIN call_center.cc_skill_in_agent sia ON sia.agent_id = a_1.id AND sia.enabled
              LEFT JOIN call_center.cc_online_skills sp ON sp.id = a_1.status_id AND a_1.status::text = 'online'::text
              LEFT JOIN call_center.cc_skills_in_online_skills spp ON spp.online_skill_id = a_1.status_id AND spp.skill_id = sia.skill_id AND a_1.status::text = 'online'::text
           WHERE a_1.domain_id = q.domain_id AND (q.team_id IS NULL OR a_1.team_id = q.team_id) AND qs.skill_id = sia.skill_id AND sia.capacity >= qs.min_capacity AND sia.capacity <= qs.max_capacity
           GROUP BY ROLLUP(q.queue_id)) a ON true;


      CREATE OR REPLACE VIEW call_center.cc_agent_list
       AS
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
          call_center.cc_get_lookup(a.greeting_media_id::bigint, g.name) AS greeting_media,
          a.allow_channels,
          a.chat_count,
          ( SELECT jsonb_agg(sag."user") AS jsonb_agg
                 FROM call_center.cc_agent_with_user sag
                WHERE sag.id = ANY (a.supervisor_ids)) AS supervisor,
          ( SELECT jsonb_agg(call_center.cc_get_lookup(aud.id, COALESCE(aud.name, aud.username::text)::character varying)) AS jsonb_agg
                 FROM directory.wbt_user aud
                WHERE aud.id = ANY (a.auditor_ids)) AS auditor,
          call_center.cc_get_lookup(t.id, t.name) AS team,
          call_center.cc_get_lookup(r.id::bigint, r.name) AS region,
          a.supervisor AS is_supervisor,
          ( SELECT jsonb_agg(call_center.cc_get_lookup(sa.skill_id::bigint, cs.name)) AS jsonb_agg
                 FROM call_center.cc_skill_in_agent sa
                   JOIN call_center.cc_skill cs ON sa.skill_id = cs.id
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
	coalesce(a.status_payload, os.name, '') as activity_type
         FROM call_center.cc_agent a
           LEFT JOIN directory.wbt_user ct ON ct.id = a.user_id
           LEFT JOIN storage.media_files g ON g.id = a.greeting_media_id
           LEFT JOIN call_center.cc_team t ON t.id = a.team_id
           LEFT JOIN flow.region r ON r.id = a.region_id
           LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', (date_part('epoch'::text, c.joined_at) * 1000::double precision)::bigint)) AS x
                 FROM call_center.cc_agent_channel c
                WHERE c.agent_id = a.id) ch ON true
	 left join call_center.cc_online_skills os on a.status_id is not null and a.status_id = os.id and os.is_system is false;
