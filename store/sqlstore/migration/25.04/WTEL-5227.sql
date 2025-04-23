CREATE OR REPLACE VIEW cc_agent_in_queue_view AS
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
            WHEN (q.min_online_agents > 0) THEN GREATEST(((COALESCE(array_length(a.agent_p_ids, 1), 0) + COALESCE(array_length(a.agent_on_ids, 1), 0)) - q.min_online_agents), 0)
            ELSE NULL::integer
        END) AS agents,
    q.max_member_limit
   FROM (( SELECT cc_get_lookup((q_1.id)::bigint, q_1.name) AS queue,
            q_1.priority,
            q_1.type,
            q_1.strategy,
            q_1.enabled,
            COALESCE(((q_1.payload -> 'min_online_agents'::text))::integer, 0) AS min_online_agents,
            COALESCE(((q_1.payload -> 'max_member_limit'::text))::integer, 0) AS max_member_limit,
            COALESCE(sum(cqs.member_count), (0)::bigint) AS count_members,
                CASE
                    WHEN (q_1.type = ANY (ARRAY[1, 6])) THEN ( SELECT count(*) AS count
                       FROM cc_member_attempt a_1_1
                      WHERE ((a_1_1.queue_id = q_1.id) AND ((a_1_1.state)::text = ANY (ARRAY[('wait_agent'::character varying)::text, ('offering'::character varying)::text])) AND (a_1_1.leaving_at IS NULL)))
                    ELSE COALESCE(sum(cqs.member_waiting), (0)::bigint)
                END AS waiting_members,
            ( SELECT count(*) AS count
                   FROM cc_member_attempt a_1_1
                  WHERE (a_1_1.queue_id = q_1.id)) AS active_members,
            q_1.id AS queue_id,
            q_1.name AS queue_name,
            q_1.team_id,
            a_1.domain_id,
            a_1.id AS agent_id,
                CASE
                    WHEN ((q_1.type >= 0) AND (q_1.type <= 5)) THEN 'call'::text
                    WHEN (q_1.type = 6) THEN 'chat'::text
                    ELSE 'task'::text
                END AS chan_name
           FROM ((cc_agent a_1
             JOIN cc_queue q_1 ON ((q_1.domain_id = a_1.domain_id)))
             LEFT JOIN cc_queue_statistics cqs ON ((q_1.id = cqs.queue_id)))
          WHERE (((q_1.team_id IS NULL) OR (a_1.team_id = q_1.team_id)) AND (EXISTS ( SELECT qs.queue_id
                   FROM (cc_queue_skill qs
                     JOIN cc_skill_in_agent csia ON ((csia.skill_id = qs.skill_id)))
                  WHERE (qs.enabled AND csia.enabled AND (csia.agent_id = a_1.id) AND (qs.queue_id = q_1.id) AND (csia.capacity >= qs.min_capacity) AND (csia.capacity <= qs.max_capacity)))))
          GROUP BY a_1.id, q_1.id, q_1.priority) q
     LEFT JOIN LATERAL ( SELECT DISTINCT array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = 'online'::text)) AS agent_on_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = 'offline'::text)) AS agent_off_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE ((a_1.status)::text = ANY (ARRAY[('pause'::character varying)::text, ('break_out'::character varying)::text]))) AS agent_p_ids,
            array_agg(DISTINCT a_1.id) FILTER (WHERE (((a_1.status)::text = 'online'::text) AND ((ac.state)::text = 'waiting'::text))) AS free,
            array_agg(DISTINCT a_1.id) AS total
           FROM (((cc_agent a_1
             JOIN cc_agent_channel ac ON (((ac.agent_id = a_1.id) AND ((ac.channel)::text = q.chan_name))))
             JOIN cc_queue_skill qs ON (((qs.queue_id = q.queue_id) AND qs.enabled)))
             JOIN cc_skill_in_agent sia ON (((sia.agent_id = a_1.id) AND sia.enabled)))
          WHERE ((a_1.domain_id = q.domain_id) AND ((q.team_id IS NULL) OR (a_1.team_id = q.team_id)) AND (qs.skill_id = sia.skill_id) AND (sia.capacity >= qs.min_capacity) AND (sia.capacity <= qs.max_capacity))
          GROUP BY ROLLUP(q.queue_id)) a ON (true));