--
-- Name: cc_array_to_string(text[], text); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_array_to_string(text[], text) RETURNS text
    LANGUAGE sql IMMUTABLE
    AS $_$SELECT array_to_string($1, $2)$_$;



drop PROCEDURE call_center.cc_distribute;
--
-- Name: cc_distribute(boolean); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean)
    LANGUAGE plpgsql
    AS $$
begin
    if NOT pg_try_advisory_xact_lock(132132117) then
        raise exception 'LOCK';
    end if;

    with dis as MATERIALIZED (
        select x.*, a.team_id
        from call_center.cc_sys_distribute(disable_omnichannel) x (agent_id int, queue_id int, bucket_id int, ins bool, id int8, resource_id int,
                                                                   resource_group_id int, comm_idx int)
                 left join call_center.cc_agent a on a.id= x.agent_id
    )
       , ins as (
        insert into call_center.cc_member_attempt (channel, member_id, queue_id, resource_id, agent_id, bucket_id, destination,
                                                   communication_idx, member_call_id, team_id, resource_group_id, domain_id, import_id, sticky_agent_id)
            select case when q.type = 7 then 'task' else 'call' end, --todo
                   dis.id,
                   dis.queue_id,
                   dis.resource_id,
                   dis.agent_id,
                   dis.bucket_id,
                   x,
                   dis.comm_idx,
                   uuid_generate_v4(),
                   dis.team_id,
                   dis.resource_group_id,
                   q.domain_id,
                   m.import_id,
                   case when q.type = 5 and q.sticky_agent then dis.agent_id end
            from dis
                     inner join call_center.cc_queue q on q.id = dis.queue_id
                     inner join call_center.cc_member m on m.id = dis.id
                     inner join lateral jsonb_extract_path(m.communications, (dis.comm_idx)::text) x on true
            where dis.ins
    )
    update call_center.cc_member_attempt a
    set agent_id = t.agent_id,
        team_id = t.team_id
    from (
             select dis.id, dis.agent_id, dis.team_id
             from dis
                inner join call_center.cc_agent a on a.id = dis.agent_id
                left join call_center.cc_queue q on q.id = dis.queue_id
             where not dis.ins is true
                and (q.type is null or q.type in (6, 7) or not exists(select 1 from call_center.cc_calls cc where cc.user_id = a.user_id and cc.hangup_at isnull ))
         ) t
    where t.id = a.id
      and a.agent_id isnull;

end;
$$;

drop FUNCTION if exists call_center.cc_member_attempt_log_day_f;
drop FUNCTION if exists call_center.cc_team_agents_by_bucket;


--
-- Name: cc_set_agent_channel_change_status(); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE or replace FUNCTION call_center.cc_set_agent_channel_change_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
        -- FIXME
    if TG_OP = 'INSERT' then
        return new;
    end if;
  if new.online != old.online and new.state = 'waiting' then
      new.joined_at := now();
      if new.online then
          return new;
      end if;
  end if;

  --
  if new.state = 'waiting' then
      new.lose_attempt = 0;
      new.queue_id := null;
      new.attempt_id := null;
  end if;

  --fixme error when agent set offline/pause in active call
  if new.joined_at - old.joined_at = interval '0' then
        return new;
  end if;

  new.channel_changed_at = now();

  insert into call_center.cc_agent_state_history (agent_id, joined_at, state, channel, duration, queue_id, attempt_id)
  values (old.agent_id, old.joined_at, old.state, old.channel, new.joined_at - old.joined_at, old.queue_id, old.attempt_id);

  RETURN new;
END;
$$;

alter table call_center.cc_agent add column task_count smallint DEFAULT 1 NOT NULL;


drop VIEW call_center.cc_agent_list;
CREATE VIEW call_center.cc_agent_list AS
 SELECT a.domain_id,
    a.id,
    (COALESCE(((ct.name)::character varying)::name, (ct.username COLLATE "default")))::character varying AS name,
    a.status,
    a.description,
    ((date_part('epoch'::text, a.last_state_change) * (1000)::double precision))::bigint AS last_status_change,
    (date_part('epoch'::text, (now() - a.last_state_change)))::bigint AS status_duration,
    a.progressive_count,
    ch.x AS channel,
    (json_build_object('id', ct.id, 'name', COALESCE(((ct.name)::character varying)::name, ct.username)))::jsonb AS "user",
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
    a.task_count
   FROM (((((call_center.cc_agent a
     LEFT JOIN directory.wbt_user ct ON ((ct.id = a.user_id)))
     LEFT JOIN storage.media_files g ON ((g.id = a.greeting_media_id)))
     LEFT JOIN call_center.cc_team t ON ((t.id = a.team_id)))
     LEFT JOIN flow.region r ON ((r.id = a.region_id)))
     LEFT JOIN LATERAL ( SELECT jsonb_agg(json_build_object('channel', c.channel, 'online', true, 'state', c.state, 'joined_at', ((date_part('epoch'::text, c.joined_at) * (1000)::double precision))::bigint)) AS x
           FROM call_center.cc_agent_channel c
          WHERE (c.agent_id = a.id)) ch ON (true));

alter table call_center.cc_email_profile add column token jsonb;

drop VIEW call_center.cc_email_profile_list;
CREATE VIEW call_center.cc_email_profile_list AS
 SELECT t.id,
    t.domain_id,
    call_center.cc_view_timestamp(t.created_at) AS created_at,
    call_center.cc_get_lookup(t.created_by, (cc.name)::character varying) AS created_by,
    call_center.cc_view_timestamp(t.updated_at) AS updated_at,
    call_center.cc_get_lookup(t.updated_by, (cu.name)::character varying) AS updated_by,
    call_center.cc_view_timestamp(t.last_activity_at) AS activity_at,
    t.name,
    t.imap_host,
    t.smtp_host,
    t.login,
    t.mailbox,
    t.smtp_port,
    t.imap_port,
    t.fetch_err AS fetch_error,
    t.fetch_interval,
    t.state,
    call_center.cc_get_lookup((t.flow_id)::bigint, s.name) AS schema,
    t.description,
    t.enabled,
    t.password,
    t.listen,
    (((t.token ->> 'expiry'::text) IS NOT NULL) AND ((t.token ->> 'access_token'::text) IS NOT NULL)) AS logged
   FROM (((call_center.cc_email_profile t
     LEFT JOIN directory.wbt_user cc ON ((cc.id = t.created_by)))
     LEFT JOIN directory.wbt_user cu ON ((cu.id = t.updated_by)))
     LEFT JOIN flow.acr_routing_scheme s ON ((s.id = t.flow_id)));


