-- WTEL-9873 [Monix][Admin][BE] Extra chat count (переліміт кількості активних чатів)

ALTER TABLE call_center.cc_agent
    ADD COLUMN extra_chat_count smallint DEFAULT 0,
    ADD CONSTRAINT cc_agent_extra_chat_count_c CHECK ((extra_chat_count > '-1'::integer));

------------
ALTER TABLE call_center.cc_member_attempt
    ADD COLUMN extra_chat_count boolean DEFAULT false NOT NULL;

------------
drop function if exists call_center.cc_distribute_inbound_chat_to_queue(character varying, bigint, character varying, jsonb, integer, integer, integer);

CREATE OR REPLACE FUNCTION call_center.cc_distribute_inbound_chat_to_queue(_node_name character varying, _queue_id bigint, _conversation_id character varying, variables_ jsonb, bucket_id_ integer, _priority integer DEFAULT 0, _sticky_agent_id integer DEFAULT NULL::integer, _extra_chat_count boolean DEFAULT false) RETURNS record
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

  if _sticky_agent_id notnull and _sticky then
    if not exists(select 1
                  from call_center.cc_agent a
                  where a.id = _sticky_agent_id
                    and a.domain_id = _domain_id
                    and (a.status = 'online' or _sticky_ignore_status is true)
                    and exists(select 1
                               from call_center.cc_skill_in_agent sa
                                      inner join call_center.cc_queue_skill qs
                                                 on qs.skill_id = sa.skill_id and qs.queue_id = _queue_id
                               where sa.agent_id = _sticky_agent_id
                                 and sa.enabled
                                 and sa.capacity between qs.min_capacity and qs.max_capacity)
    ) then
      _sticky_agent_id = null;
    end if;
  else
    _sticky_agent_id = null;
  end if;

  insert into call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_id, bucket_id, weight, member_call_id,
                                             destination, node_id, sticky_agent_id, extra_chat_count, list_communication_id, queue_params, queue_type)
  values (_domain_id, 'chat', 'waiting', _queue_id, null, bucket_id_, coalesce(_weight, _priority), _conversation_id::varchar,
          jsonb_build_object('destination', _con_name, 'name', _client_name, 'msg', _last_msg, 'chat', _con_type) ||
          case when _member_jsonb notnull then jsonb_build_object('member', _member_jsonb) else '{}'::jsonb end,
          _node_name, _sticky_agent_id, coalesce(_extra_chat_count, false), (select clc.id
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

------------
CREATE OR REPLACE VIEW call_center.cc_agent_list AS
 SELECT a.domain_id,
    a.id,
    (COALESCE(ct.name, ((ct.username)::text COLLATE "default")))::character varying AS name,
    a.status,
    a.description,
    ((date_part('epoch'::text, a.last_state_change) * (1000)::double precision))::bigint AS last_status_change,
    (date_part('epoch'::text, (now() - a.last_state_change)))::bigint AS status_duration,
    a.progressive_count,
    ch.x AS channel,
    (json_build_object('id', ct.id, 'name', COALESCE(ct.name, (ct.username)::text)))::jsonb AS "user",
    call_center.cc_get_lookup((a.greeting_media_id)::bigint, g.name) AS greeting_media,
    a.allow_channels,
    a.chat_count,
    ( SELECT jsonb_agg(sag."user") AS jsonb_agg
           FROM call_center.cc_agent_with_user sag
          WHERE (sag.id = ANY (a.supervisor_ids))) AS supervisor,
    ( SELECT jsonb_agg(call_center.cc_get_lookup(aud.id, (COALESCE(aud.name, (aud.username)::text))::character varying)) AS jsonb_agg
           FROM directory.wbt_user aud
          WHERE (aud.id = ANY (a.auditor_ids))) AS auditor,
    call_center.cc_get_lookup(t.id, t.name) AS team,
    call_center.cc_get_lookup((r.id)::bigint, r.name) AS region,
    a.supervisor AS is_supervisor,
    ( SELECT jsonb_agg(call_center.cc_get_lookup((sa.skill_id)::bigint, cs.name)) AS jsonb_agg
           FROM (call_center.cc_skill_in_agent sa
             JOIN call_center.cc_skill cs ON ((sa.skill_id = cs.id)))
          WHERE (sa.agent_id = a.id)) AS skills,
    a.team_id,
    a.region_id,
    a.supervisor_ids,
    a.auditor_ids,
    a.user_id,
    ct.extension,
    a.task_count,
    a.screen_control,
    (t.screen_control IS FALSE) AS allow_set_screen_control,
    row_number() OVER (PARTITION BY a.domain_id ORDER BY
        CASE
            WHEN ((a.status)::text = 'online'::text) THEN 0
            WHEN ((a.status)::text = 'pause'::text) THEN 1
            WHEN ((a.status)::text = 'offline'::text) THEN 2
            ELSE 3
        END, COALESCE(ct.name, (ct.username)::text)) AS "position",
    COALESCE(( SELECT array_agg(status.open) AS array_agg
           FROM ( SELECT 'dnd'::name AS "?column?"
                   FROM directory.wbt_user_status stt
                  WHERE ((stt.user_id = a.user_id) AND stt.dnd)
                UNION ALL
                ( SELECT stt.status
                   FROM directory.wbt_user_presence stt
                  WHERE ((stt.user_id = a.user_id) AND (stt.status IS NOT NULL) AND (stt.open > 0))
                  ORDER BY stt.prior, stt.status)) status(open)), '{}'::name[]) AS user_presence_status,
    a.extra_chat_count
   FROM (((((call_center.cc_agent a
     LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
     LEFT JOIN storage.media_files g ON ((g.id = a.greeting_media_id)))
     LEFT JOIN call_center.cc_team t ON ((t.id = a.team_id)))
     LEFT JOIN flow.region r ON ((r.id = a.region_id)))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint)) AS x
           FROM call_center.cc_agent_channel c
          WHERE (c.agent_id = a.id)) ch ON (true));
