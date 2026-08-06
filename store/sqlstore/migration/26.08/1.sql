alter table "call_center"."cc_agent"
add column "status_id" int8 references "call_center"."skill_preset" on delete set null;


CREATE OR REPLACE FUNCTION "call_center"."cc_set_agent_online"(
    p_agent_id int8,
    p_domain_id int8,
    p_on_demand boolean,
    p_status_id int8 DEFAULT NULL,
    p_status_name varchar DEFAULT NULL
)
RETURNS TABLE (
    id int8,
    user_id int8,
    domain_id int8,
    updated_at int8,
    "name" varchar,
    destination text,
    "extension" varchar,
    status varchar,
    status_payload jsonb,
    on_demand boolean,
    greeting_media jsonb,
    team_id int8,
    team_updated_at int8,
    variables jsonb,
    has_push boolean,
    chat_name varchar,
    channels jsonb,
    login_timestamp int8,
    status_preset jsonb
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_status varchar;
    v_current_on_demand boolean;
    v_current_status_id int8;
    v_target_status_id int8;
    v_set_login_res record;
BEGIN
    SELECT a.status, a.on_demand, a.status_id
    INTO v_current_status, v_current_on_demand, v_current_status_id
    FROM call_center.cc_agent a
    WHERE a.id = p_agent_id
        AND a.domain_id = p_domain_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'agent_not_found' USING errcode = 'P0002';
    END IF;

    IF p_status_id IS NOT NULL THEN
        v_target_status_id := p_status_id;
    ELSIF p_status_name IS NOT NULL THEN
        SELECT s.id INTO v_target_status_id
        FROM call_center.skill_preset s
        WHERE LOWER(s."name") = LOWER(TRIM(p_status_name))
          AND s.domain_id = p_domain_id
        LIMIT 1;
    ELSE
        v_target_status_id := NULL;
    END IF;

    IF v_current_status = 'online'
       AND v_current_on_demand IS NOT DISTINCT FROM p_on_demand
       AND v_current_status_id IS NOT DISTINCT FROM v_target_status_id THEN
        RAISE EXCEPTION 'agent_already_online' USING errcode = '23000';
    END IF;

    SELECT channel, "timestamp"
    INTO v_set_login_res
    FROM call_center.cc_agent_set_login(CAST(p_agent_id AS integer), p_on_demand, p_status_id, p_status_name)
    AS (channel jsonb, timestamp int8);

    RETURN QUERY
    SELECT
        a.id::int8,
        a.user_id::int8,
        a.domain_id::int8,
        (a.updated_at - EXTRACT(EPOCH FROM u.updated_at))::int8 AS updated_at,
        COALESCE((u.name)::varchar, u.username)::varchar AS name,
        ('sofia/sip/' || u.extension || '@' || d.name)::text AS destination,
        u.extension::varchar,
        a.status::varchar,
        a.status_payload::jsonb,
        a.on_demand::boolean,
        CASE
            WHEN g.id IS NOT NULL THEN json_build_object('id', g.id, 'type', g.mime_type)::jsonb
        END AS greeting_media,
        a.team_id::int8,
        team.updated_at::int8 AS team_updated_at,
        COALESCE(push.config, '{}'::jsonb)::jsonb AS variables,
        (push.config IS NOT NULL)::boolean AS has_push,
        COALESCE(NULLIF(u.chat_name, ''), u.name, u.username)::varchar AS chat_name,
        v_set_login_res.channel::jsonb AS channels,
        v_set_login_res.timestamp::int8 AS login_timestamp,
        coalesce(call_center.cc_get_lookup(sp.id, sp.name), '{}'::jsonb) AS status_preset
    FROM call_center.cc_agent a
        INNER JOIN directory.wbt_user u ON u.id = a.user_id
        INNER JOIN directory.wbt_domain d ON d.dc = a.domain_id
        INNER JOIN call_center.cc_team team ON team.id = a.team_id
        LEFT JOIN storage.media_files g ON g.id = a.greeting_media_id
        LEFT JOIN call_center.skill_preset sp ON sp.id = a.status_id
        LEFT JOIN LATERAL (
            SELECT jsonb_object(array_agg(key), array_agg(val)) AS push
            FROM (
                SELECT
                    CASE
                        WHEN s.props->>'pn-type'::text = 'fcm' THEN 'wbt_push_fcm'
                        ELSE 'wbt_push_apn'
                    END AS key,
                    array_to_string(
                        array_agg(DISTINCT s.props->>'pn-rpid'::text),
                        '::'
                    ) AS val
                FROM directory.wbt_session s
                WHERE s.user_id IS NOT NULL
                    AND s.access IS NOT NULL
                    AND NULLIF(s.props->>'pn-rpid'::text, ''::text) IS NOT NULL
                    AND s.user_id = a.user_id
                    AND s.props->>'pn-type'::text IN ('fcm', 'apns')
                    AND NOW() AT TIME ZONE 'UTC' < s.expires
                GROUP BY (s.props->>'pn-type'::text = 'fcm')
            ) t
            WHERE key IS NOT NULL AND val IS NOT NULL
        ) push(config) ON TRUE
    WHERE a.id = p_agent_id AND a.domain_id = p_domain_id;
END;
$$;

CREATE OR REPLACE FUNCTION call_center.cc_agent_set_login(
    agent_id_ integer,
    on_demand_ boolean DEFAULT false,
    p_status_id int8 DEFAULT NULL,
    p_status_name varchar DEFAULT NULL
)
RETURNS record
LANGUAGE 'plpgsql'
COST 100
VOLATILE PARALLEL UNSAFE
AS $BODY$
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
                FROM call_center.skill_preset s
                WHERE LOWER(s."name") = LOWER(TRIM(p_status_name))
                  AND s.domain_id = a.domain_id
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
$BODY$;
