CREATE OR REPLACE FUNCTION call_center.cc_prevent_sys_record_mod()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
begin
	if OLD.is_system is true then
    raise exception 'Cannot % system record with id=%', TG_OP, OLD.id
      using errcode = 'check_violation',
            detail = 'System presets are read-only and cannot be updated or deleted.';
    end if;

	if TG_OP = 'DELETE' then
        return OLD;
    end if;

    return NEW;
end;
$BODY$;

ALTER FUNCTION call_center.cc_prevent_sys_record_mod()
    OWNER TO opensips;

-- Table: call_center.cc_online_skills

-- DROP TABLE IF EXISTS call_center.cc_online_skills;

CREATE TABLE IF NOT EXISTS call_center.cc_online_skills
(
    id bigserial,
    domain_id bigint NOT NULL,
    created_by bigint,
    created_at timestamp with time zone NOT NULL DEFAULT now(),
    updated_by bigint,
    updated_at timestamp with time zone NOT NULL DEFAULT now(),
    name text COLLATE pg_catalog."default" NOT NULL,
    description text COLLATE pg_catalog."default",
    is_system boolean NOT NULL DEFAULT false,
    CONSTRAINT skill_preset_pkey PRIMARY KEY (id),
    CONSTRAINT uk_skill_preset_domain_id_id UNIQUE (domain_id, id),
    CONSTRAINT skill_preset_domain_id_created_by_fkey FOREIGN KEY (domain_id, created_by)
        REFERENCES directory.wbt_user (dc, id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE SET NULL,
    CONSTRAINT skill_preset_domain_id_fkey FOREIGN KEY (domain_id)
        REFERENCES directory.wbt_domain (dc) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE,
    CONSTRAINT skill_preset_domain_id_updated_by_fkey FOREIGN KEY (domain_id, updated_by)
        REFERENCES directory.wbt_user (dc, id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE SET NULL,
    CONSTRAINT chk_skill_preset_name_valid CHECK (TRIM(BOTH FROM name) <> ''::text AND (is_system IS TRUE OR lower(TRIM(BOTH FROM name)) <> 'standart online'::text))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS call_center.cc_online_skills
    OWNER to opensips;
-- Index: idx_skill_preset_domain_id_created_by

-- DROP INDEX IF EXISTS call_center.idx_skill_preset_domain_id_created_by;

CREATE INDEX IF NOT EXISTS idx_skill_preset_domain_id_created_by
    ON call_center.cc_online_skills USING btree
    (domain_id ASC NULLS LAST, created_by ASC NULLS LAST)
    TABLESPACE pg_default
    WHERE created_by IS NOT NULL;
-- Index: idx_skill_preset_domain_id_updated_by

-- DROP INDEX IF EXISTS call_center.idx_skill_preset_domain_id_updated_by;

CREATE INDEX IF NOT EXISTS idx_skill_preset_domain_id_updated_by
    ON call_center.cc_online_skills USING btree
    (domain_id ASC NULLS LAST, updated_by ASC NULLS LAST)
    TABLESPACE pg_default
    WHERE updated_by IS NOT NULL;
-- Index: idx_uq_skill_preset_domain_name_lower

-- DROP INDEX IF EXISTS call_center.idx_uq_skill_preset_domain_name_lower;

CREATE UNIQUE INDEX IF NOT EXISTS idx_uq_skill_preset_domain_name_lower
    ON call_center.cc_online_skills USING btree
    (domain_id ASC NULLS LAST, lower(TRIM(BOTH FROM name)) COLLATE pg_catalog."default" ASC NULLS LAST)
    TABLESPACE pg_default;

-- Trigger: trg_prevent_skill_preset_delete

-- DROP TRIGGER IF EXISTS trg_prevent_skill_preset_delete ON call_center.cc_online_skills;

CREATE OR REPLACE TRIGGER trg_prevent_skill_preset_delete
    BEFORE DELETE
    ON call_center.cc_online_skills
    FOR EACH ROW
    EXECUTE FUNCTION call_center.cc_prevent_sys_record_mod();

-- Trigger: trg_prevent_skill_preset_update

-- DROP TRIGGER IF EXISTS trg_prevent_skill_preset_update ON call_center.cc_online_skills;

CREATE OR REPLACE TRIGGER trg_prevent_skill_preset_update
    BEFORE UPDATE
    ON call_center.cc_online_skills
    FOR EACH ROW
    EXECUTE FUNCTION call_center.cc_prevent_sys_record_mod();

    -- Table: call_center.cc_skills_in_online_skills

    -- DROP TABLE IF EXISTS call_center.cc_skills_in_online_skills;

    CREATE TABLE IF NOT EXISTS call_center.cc_skills_in_online_skills
    (
        domain_id bigint NOT NULL,
        online_skill_id bigint NOT NULL,
        skill_id bigint NOT NULL,
        CONSTRAINT skills_in_skill_preset_pkey PRIMARY KEY (online_skill_id, skill_id),
        CONSTRAINT skills_in_skill_preset_domain_id_skill_id_fkey FOREIGN KEY (domain_id, skill_id)
            REFERENCES call_center.cc_skill (domain_id, id) MATCH SIMPLE
            ON UPDATE NO ACTION
            ON DELETE CASCADE,
        CONSTRAINT skills_in_skill_preset_domain_id_skill_preset_id_fkey FOREIGN KEY (domain_id, online_skill_id)
            REFERENCES call_center.cc_online_skills (domain_id, id) MATCH SIMPLE
            ON UPDATE NO ACTION
            ON DELETE CASCADE
    )

    TABLESPACE pg_default;

    ALTER TABLE IF EXISTS call_center.cc_skills_in_online_skills
        OWNER to opensips;
    -- Index: idx_skills_in_skill_preset

    -- DROP INDEX IF EXISTS call_center.idx_skills_in_skill_preset;

    CREATE INDEX IF NOT EXISTS idx_skills_in_skill_preset
        ON call_center.cc_skills_in_online_skills USING btree
        (skill_id ASC NULLS LAST)
        TABLESPACE pg_default;



alter table call_center.cc_agent add column status_id bigint references call_center.cc_online_skills("id");

insert into call_center.cc_online_skills ("domain_id", "name", "is_system")
select
	d.dc,
	'Standart Online',
	true
from directory.wbt_domain d;

create or replace function "call_center"."cc_agent_has_queue_skill"(p_agent_id int8, p_queue_id int8, p_domain_id int8, p_ignore_status boolean default false)
returns boolean
language sql
stable
as $$
  select exists (
    select 1
    from "call_center"."cc_agent" a
    where a."id" = p_agent_id
      and a."domain_id" = p_domain_id
      and (a."status" = 'online' or p_ignore_status is true)
      and exists (
        select 1
        from "call_center"."cc_skill_in_agent" sa
        inner join "call_center"."cc_queue_skill" qs on qs."skill_id" = sa."skill_id" and qs."queue_id" = p_queue_id
        left join "call_center"."cc_online_skills" sp on sp."id" = a."status_id" and a."status" = 'online'
        left join "call_center"."cc_skills_in_online_skills" spp on spp."online_skill_id" = a."status_id" and spp."skill_id" = sa."skill_id" and a."status" = 'online'
        where sa."agent_id" = a."id"
          and sa."enabled"
          and sa."capacity" between qs."min_capacity" and qs."max_capacity"
          and (
            a."status_id" is null or a."status" <> 'online' or spp."skill_id" is not null or sp."is_system" is true
          )
      )
  );
$$;


-- FUNCTION: call_center.cc_set_agent_online(bigint, bigint, boolean, bigint, character varying)

-- DROP FUNCTION IF EXISTS call_center.cc_set_agent_online(bigint, bigint, boolean, bigint, character varying);

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


    -- FUNCTION: call_center.cc_agent_set_login_v2(integer, boolean, bigint, character varying)

    -- DROP FUNCTION IF EXISTS call_center.cc_agent_set_login_v2(integer, boolean, bigint, character varying);

    CREATE OR REPLACE FUNCTION call_center.cc_agent_set_login_v2(
	agent_id_ integer,
	on_demand_ boolean DEFAULT false,
	p_status_id bigint DEFAULT NULL::bigint,
	p_status_name character varying DEFAULT NULL::character varying)
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
                    FROM call_center.cc_online_skills s
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

    ALTER FUNCTION call_center.cc_agent_set_login_v2(integer, boolean, bigint, character varying)
        OWNER TO opensips;

        CREATE or replace FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer) RETURNS record
            LANGUAGE plpgsql
            AS $$declare
            _timezone_id int4;
            _discard_abandoned_after int4;
            _weight int4;
            dnc_list_id_ int4;
            _domain_id int8;
            _calendar_id int4;
            _queue_updated_at int8;
            _team_updated_at int8;
            _team_id_ int;
            _enabled bool;
            _q_type smallint;
            _attempt record;
            _con_created timestamptz;
            _con_name varchar;
            _con_type varchar;
            _last_msg varchar;
            _client_name varchar;
            _inviter_channel_id varchar;
            _inviter_user_id varchar;
            _sticky bool;
            _sticky_ignore_status bool;
            _max_waiting_size int;
            _qparams jsonb;
            _ignore_calendar bool;
            _member_jsonb jsonb;
            _last_msg_channel_type varchar;
        BEGIN
          select c.timezone_id,
                   (coalesce(payload->>'discard_abandoned_after', '0'))::int discard_abandoned_after,
                 q.domain_id,
                 q.dnc_list_id,
                 q.calendar_id,
                 q.updated_at,
                 ct.updated_at,
                 q.team_id,
                 q.enabled,
                 q.type,
                 q.sticky_agent,
                 (payload->>'max_waiting_size')::int max_size,
                 case when jsonb_typeof(payload->'sticky_ignore_status') = 'boolean'
                     then (payload->'sticky_ignore_status')::bool else false end sticky_ignore_status,
                 call_center.cc_queue_params(q),
                 case when jsonb_typeof(q.payload->'ignore_calendar') = 'boolean' then (q.payload->'ignore_calendar')::bool else false end
          from call_center.cc_queue q
            left join flow.calendar c on q.calendar_id = c.id
            left join call_center.cc_team ct on q.team_id = ct.id
          where  q.id = _queue_id
          into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
              _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _sticky_ignore_status, _qparams, _ignore_calendar;

          if not _q_type = 6 then
              raise exception 'queue type not inbound chat';
          end if;

          if not _enabled = true then
              raise exception 'queue disabled';
          end if;

          if not _calendar_id isnull  and (not _ignore_calendar and not exists(select accept
                    from flow.calendar_check_timing(_domain_id, _calendar_id, null)
                    as x (name varchar, excepted varchar, accept bool, expire bool)
                    where accept and excepted is null and not expire)) then
              raise exception 'conversation [%] calendar not working [%] [%]', _conversation_id, _calendar_id, _queue_id;
          end if;

          if _max_waiting_size > 0 then
              if (select count(*) from call_center.cc_member_attempt aa
                                  where aa.queue_id = _queue_id
                                    and aa.bridged_at isnull
                                    and aa.leaving_at isnull
                                    and (bucket_id_ isnull or aa.bucket_id = bucket_id_)) >= _max_waiting_size then
                raise exception using
                    errcode='MAXWS',
                    message='Queue maximum waiting size';
              end if;
          end if;

          select cli.external_id,
                 c.created_at,
                 c.id::varchar inviter_channel_id,
                 c.user_id,
                 c.name,
                 lst.message,
                 lst.channel_type,
                 c.type
          from chat.channel c
                   left join chat.client cli on cli.id = c.user_id
                   left join lateral (
                       	select
					coalesce(m.text, m.file_name, 'empty') message,
					ch.type as channel_type
                        from chat.message m
                        left join chat.channel ch on ch.id = m.channel_id
                        where m.conversation_id = _conversation_id::uuid
                        order by m.created_at desc
                        limit 1
                   ) lst on true
          where c.closed_at isnull
                and c.conversation_id = _conversation_id::uuid
            and not c.internal
          into _con_name, _con_created, _inviter_channel_id, _inviter_user_id, _client_name, _last_msg, _last_msg_channel_type, _con_type;

          if coalesce(_inviter_channel_id, '') = '' or coalesce(_inviter_user_id, '') = '' isnull then
              raise exception using
                    errcode='VALID',
                    message='Bad request inviter_channel_id or user_id';
          end if;

          _member_jsonb := null;

          if _last_msg_channel_type is null then
              _member_jsonb := jsonb_build_object('type', 'bot');
          elseif _last_msg_channel_type = 'webitel' then
              _member_jsonb := jsonb_build_object('type', 'agent');
          else
              _member_jsonb := jsonb_build_object('type', 'contacts');
          end if;


          if  _discard_abandoned_after > 0 then
              select
                    case when log.result = 'abandoned' then
                         extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
                    else coalesce(_priority, 0) end
                from call_center.cc_member_attempt_history log
                where log.leaving_at >= (now() -  (_discard_abandoned_after || ' sec')::interval)
                    and log.queue_id = _queue_id
                    and log.destination->>'destination' = _con_name
                order by log.leaving_at desc
                limit 1
                into _weight;
          end if;

          if _sticky_agent_id is not null and _sticky then
            if not call_center.cc_agent_has_queue_skill(_sticky_agent_id, _queue_id, _domain_id, _sticky_ignore_status) then
              _sticky_agent_id = null;
            end if;
          else _sticky_agent_id = null;
          end if;


          insert into call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_id, bucket_id, weight, member_call_id,
                                                     destination, node_id, sticky_agent_id, list_communication_id, queue_params, queue_type)
          values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id::varchar,
                  jsonb_build_object('destination', _con_name, 'name', _client_name, 'msg', _last_msg, 'chat', _con_type) ||
		  case when _member_jsonb notnull then jsonb_build_object('member', _member_jsonb) else '{}'::jsonb end,
                      _node_name, _sticky_agent_id, (select clc.id
                                    from call_center.cc_list_communications clc
                                    where (clc.list_id = dnc_list_id_ and clc.number = _con_name)), _qparams, 6)
          returning * into _attempt;


          return row(
              _attempt.id::int8,
              _attempt.queue_id::int,
              _queue_updated_at::int8,
              _attempt.destination::jsonb,
              coalesce((variables_::jsonb), '{}'::jsonb) || jsonb_build_object('inviter_channel_id', _inviter_channel_id) || jsonb_build_object('inviter_user_id', _inviter_user_id),
              _conversation_id::varchar,
              _team_updated_at::int8,

              _conversation_id::varchar,
              call_center.cc_view_timestamp(_con_created)::int8,
              _attempt.list_communication_id::int8
          );
        END;
        $$;


        CREATE OR REPLACE FUNCTION call_center.cc_distribute_inbound_call_to_queue(
	_node_name character varying,
	_queue_id bigint,
	_call_id character varying,
	variables_ jsonb,
	bucket_id_ integer,
	_priority integer DEFAULT 0,
	_sticky_agent_id integer DEFAULT NULL::integer)
            RETURNS record
            LANGUAGE 'plpgsql'
            COST 100
            VOLATILE PARALLEL UNSAFE
        AS $BODY$
        declare
        _timezone_id             int4;
            _discard_abandoned_after int4;
            _weight                  int4;
            dnc_list_id_ int4;
            _domain_id               int8;
            _calendar_id             int4;
            _queue_updated_at        int8;
            _team_updated_at         int8;
            _team_id_                int;
            _list_comm_id            int8;
            _enabled                 bool;
            _q_type                  smallint;
            _sticky                  bool;
            _sticky_ignore_status                  bool;
            _call                    record;
            _attempt                 record;
            _number                  varchar;
            _name                  varchar;
            _max_waiting_size        int;
            _grantee_id              int8;
            _qparams jsonb;
            _ignore_calendar bool;
        BEGIN
        select c.timezone_id,
               (payload ->> 'discard_abandoned_after')::int discard_abandoned_after,
                q.domain_id,
               q.dnc_list_id,
               q.calendar_id,
               q.updated_at,
               ct.updated_at,
               q.team_id,
               q.enabled,
               q.type,
               q.sticky_agent,
               (payload ->> 'max_waiting_size')::int        max_size,
                case when jsonb_typeof(payload->'sticky_ignore_status') = 'boolean'
                     then (payload->'sticky_ignore_status')::bool else false end sticky_ignore_status,
                q.grantee_id,
                call_center.cc_queue_params(q),
                case when jsonb_typeof(q.payload->'ignore_calendar') = 'boolean' then (q.payload->'ignore_calendar')::bool else false end
        from call_center.cc_queue q
                 left join flow.calendar c on q.calendar_id = c.id
                 left join call_center.cc_team ct on q.team_id = ct.id
        where q.id = _queue_id
            into _timezone_id, _discard_abandoned_after, _domain_id, dnc_list_id_, _calendar_id, _queue_updated_at,
                _team_updated_at, _team_id_, _enabled, _q_type, _sticky, _max_waiting_size, _sticky_ignore_status, _grantee_id, _qparams, _ignore_calendar;

        if
        not _q_type = 1 then
                raise exception 'queue not inbound';
        end if;

            if
        not _enabled = true then
                raise exception 'queue disabled';
        end if;

        select *
        from call_center.cc_calls c
        where c.id = _call_id::uuid
        --   for update
            into _call;

        if
        _call.domain_id != _domain_id then
                raise exception 'the queue on another domain';
        end if;

            if
        _call.id isnull or _call.direction isnull then
                raise exception 'not found call';
            ELSIF
        _call.direction <> 'outbound' or _call.user_id notnull then
                _number = _call.from_number;
                _name = _call.from_name;
        else
                _number = _call.destination;
        end if;

        --   raise  exception '%', _name;

            if not _calendar_id isnull  and not _ignore_calendar and
        not exists(select accept
                           from flow.calendar_check_timing(_domain_id, _calendar_id, null)
                                    as x (name varchar, excepted varchar, accept bool, expire bool)
                           where accept
                             and excepted is null
                             and not expire)
            then
                raise exception 'number % calendar not working [%]', _number, _calendar_id;
        end if;

            if
        _max_waiting_size > 0 then
                if (select count(*)
                    from call_center.cc_member_attempt aa
                    where aa.queue_id = _queue_id
                      and aa.bridged_at isnull
                      and aa.leaving_at isnull
                      and (bucket_id_ isnull or aa.bucket_id = bucket_id_)) >= _max_waiting_size then
                    raise exception using
                        errcode = 'MAXWS',
                        message = 'Queue maximum waiting size';
        end if;
        end if;

            if
        dnc_list_id_ notnull then
        select clc.id
        into _list_comm_id
        from call_center.cc_list_communications clc
        where (clc.list_id = dnc_list_id_
          and clc.number = _number)
            limit 1;
        end if;

            if
        _list_comm_id notnull then
                raise exception 'number % banned', _number;
        end if;

            if
        _discard_abandoned_after > 0 then
        select case
                   when log.result = 'abandoned' then
                       extract(epoch from now() - log.leaving_at)::int8 + coalesce(_priority, 0)
                           else coalesce(_priority, 0)
        end
        from call_center.cc_member_attempt_history log
                where log.leaving_at >= (now() - (_discard_abandoned_after || ' sec')::interval)
                  and log.queue_id = _queue_id
                  and log.destination ->> 'destination' = _number
                order by log.leaving_at desc
                limit 1
                into _weight;
        end if;

        if _sticky_agent_id is not null and _sticky then
          if not call_center.cc_agent_has_queue_skill(_sticky_agent_id::int8, _queue_id, _domain_id, _sticky_ignore_status)
            then _sticky_agent_id = null;
          end if;
        else _sticky_agent_id = null;
        end if;


        insert into call_center.cc_member_attempt (domain_id, state, queue_id, team_id, member_id, bucket_id, weight,
                                                   member_call_id, destination, node_id, sticky_agent_id,
                                                   list_communication_id,
                                                   parent_id, queue_params, queue_type)
        values (_domain_id, 'waiting', _queue_id, _team_id_, null, bucket_id_, coalesce(_weight, _priority), _call_id,
                jsonb_build_object('destination', _number, 'name', coalesce(_name, _number)),
                _node_name, _sticky_agent_id, null, _call.attempt_id, _qparams, 1) -- todo inbound queue
            returning * into _attempt;

        update call_center.cc_calls
        set queue_id   = _attempt.queue_id,
            team_id    = _team_id_,
            attempt_id = _attempt.id,
            payload    = case when jsonb_typeof(variables_::jsonb) = 'object' then variables_ else coalesce(payload, '{}') end, --coalesce(variables_, '{}'),
            grantee_id = _grantee_id
        where id = _call_id::uuid
            returning * into _call;

        if
        _call.id isnull or _call.direction isnull then
                raise exception 'not found call';
        end if;

        return row (
                _attempt.id::int8,
                _attempt.queue_id::int,
                _queue_updated_at::int8,
                _attempt.destination::jsonb,
                variables_::jsonb,
                _call.from_name::varchar,
                _team_updated_at::int8,
                _call.id::varchar,
                _call.state::varchar,
                _call.direction::varchar,
                _call.destination::varchar,
                call_center.cc_view_timestamp(_call.timestamp)::int8,
                _call.app_id::varchar,
                _number::varchar,
                case
                    when (_call.direction <> 'outbound'
                        and _call.to_name:: varchar <> ''
                        and _call.to_name:: varchar notnull)
                        then _call.from_name::varchar
                    else _call.to_name::varchar end,
                call_center.cc_view_timestamp(_call.answered_at)::int8,
                call_center.cc_view_timestamp(_call.bridged_at)::int8,
                call_center.cc_view_timestamp(_call.created_at)::int8,
                _call.parent_id::varchar
            );

        END;
        $BODY$;
