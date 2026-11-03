-- WTEL-10766: user status Active/Deactivated (directory.wbt_user.deleted_at).

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
   COALESCE(a.status_payload, os.name::character varying, ''::character varying) AS status_type,
   ct.deleted_at IS NOT NULL AS user_deactivated
  FROM call_center.cc_agent a
    LEFT JOIN directory.wbt_user ct ON ct.id = a.user_id
    LEFT JOIN storage.media_files g ON g.id = a.greeting_media_id
    LEFT JOIN call_center.cc_team t ON t.id = a.team_id
    LEFT JOIN flow.region r ON r.id = a.region_id
    LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', (date_part('epoch'::text, c.joined_at) * 1000::double precision)::bigint)) AS x
          FROM call_center.cc_agent_channel c
         WHERE c.agent_id = a.id) ch ON true
    LEFT JOIN call_center.cc_online_skills os ON a.status_id IS NOT NULL AND a.status_id = os.id AND os.is_system IS FALSE;

CREATE OR REPLACE FUNCTION call_center.cc_set_agent_online(
	p_agent_id bigint,
	p_domain_id bigint,
	p_on_demand boolean,
	p_status_id bigint DEFAULT NULL::bigint,
	p_status_name character varying DEFAULT NULL::character varying)
    RETURNS TABLE(id bigint, user_id bigint, domain_id bigint, updated_at bigint, name character varying, destination text, extension character varying, status character varying, status_payload jsonb, on_demand boolean, greeting_media jsonb, team_id bigint, team_updated_at bigint, variables jsonb, has_push boolean, chat_name character varying, channels jsonb, login_timestamp bigint, status_preset jsonb)
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
    ROWS 1000

AS $BODY$
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

    IF EXISTS (
        SELECT 1
        FROM call_center.cc_agent a
            INNER JOIN directory.wbt_user u ON u.id = a.user_id
        WHERE a.id = p_agent_id
            AND u.deleted_at IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'agent_user_deactivated' USING errcode = '09000';
    END IF;

    IF p_status_id IS NOT NULL THEN
        v_target_status_id := p_status_id;
    ELSIF p_status_name IS NOT NULL THEN
        SELECT s.id INTO v_target_status_id
        FROM call_center.cc_online_skills s
        WHERE LOWER(s."name") = LOWER(TRIM(p_status_name))
          AND s.domain_id = p_domain_id
        LIMIT 1;
    ELSE
		select s.id into v_target_status_id
		from call_center.cc_online_skills s
		where s.domain_id = p_domain_id
		and s.is_system is true
		limit 1;
    END IF;

    IF v_current_status = 'online'
       AND v_current_on_demand IS NOT DISTINCT FROM p_on_demand
       AND v_current_status_id IS NOT DISTINCT FROM v_target_status_id THEN
        RAISE EXCEPTION 'agent_already_online' USING errcode = '23000';
    END IF;

    SELECT channel, "timestamp"
    INTO v_set_login_res
    FROM call_center.cc_agent_set_login_v2(CAST(p_agent_id AS integer), p_on_demand, v_target_status_id, p_status_name)
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
        LEFT JOIN call_center.cc_online_skills sp ON sp.id = a.status_id
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
$BODY$;

ALTER FUNCTION call_center.cc_set_agent_online(bigint, bigint, boolean, bigint, character varying)
    OWNER TO opensips;

ALTER TABLE call_center.cc_agent DROP CONSTRAINT cc_agent_wbt_user_id_fk;
ALTER TABLE call_center.cc_agent
    ADD CONSTRAINT cc_agent_wbt_user_id_fk FOREIGN KEY (user_id) REFERENCES directory.wbt_user(id) ON DELETE CASCADE NOT VALID;
ALTER TABLE call_center.cc_agent VALIDATE CONSTRAINT cc_agent_wbt_user_id_fk;

ALTER TABLE call_center.socket_session DROP CONSTRAINT socket_session_wbt_user_id_fk;
ALTER TABLE call_center.socket_session
    ADD CONSTRAINT socket_session_wbt_user_id_fk FOREIGN KEY (user_id) REFERENCES directory.wbt_user(id) ON DELETE CASCADE NOT VALID;
ALTER TABLE call_center.socket_session VALIDATE CONSTRAINT socket_session_wbt_user_id_fk;

CREATE OR REPLACE VIEW call_center.cc_audit_rate_view AS
SELECT r.id,
    r.domain_id,
    r.form_id,
    r.created_at,
    call_center.cc_get_lookup(uc.id, COALESCE(uc.name::character varying, uc.username::character varying)) AS created_by,
    r.updated_at,
    call_center.cc_get_lookup(u.id, COALESCE(u.name::character varying, u.username::character varying)) AS updated_by,
    call_center.cc_get_lookup(ur.id, ur.name::character varying) AS rated_user,
    call_center.cc_get_lookup(f.id::bigint, f.name) AS form,
    ans.v AS answers,
    r.score_required,
    r.score_optional,
    r.comment,
    r.call_id,
    f.questions,
    r.rated_user_id,
    r.created_by AS grantor,
    r.select_yes_count,
    r.critical_count,
    r.conversation_id,
    ur.deleted_at IS NOT NULL AS rated_user_deactivated
FROM call_center.cc_audit_rate r
    LEFT JOIN LATERAL ( SELECT jsonb_agg(
            CASE
                WHEN u_1.id IS NOT NULL THEN x.j || jsonb_build_object('updated_by', call_center.cc_get_lookup(u_1.id, COALESCE(u_1.name, u_1.username::text)::character varying))
                ELSE x.j
            END ORDER BY x.i) AS v
       FROM jsonb_array_elements(r.answers) WITH ORDINALITY x(j, i)
         LEFT JOIN directory.wbt_user u_1 ON u_1.id = ((x.j -> 'updated_by'::text) -> 'id'::text)::bigint) ans ON true
    LEFT JOIN call_center.cc_audit_form f ON f.id = r.form_id
    LEFT JOIN directory.wbt_user ur ON ur.id = r.rated_user_id
    LEFT JOIN directory.wbt_user uc ON uc.id = r.created_by
    LEFT JOIN directory.wbt_user u ON u.id = r.updated_by;
