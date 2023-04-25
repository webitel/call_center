-- TASK WTEL-3313
--
-- Name: cc_distribute_direct_member_to_queue(character varying, bigint, integer, bigint); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION call_center.cc_distribute_direct_member_to_queue;
CREATE FUNCTION call_center.cc_distribute_direct_member_to_queue(_node_name character varying, _member_id bigint, _communication_id integer, _agent_id bigint) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id bigint, agent_updated_at bigint, team_updated_at bigint, seq integer, communication_idx integer)
    LANGUAGE plpgsql
AS $$
BEGIN

    return query with attempts as (
        insert into call_center.cc_member_attempt (state, queue_id, member_id, destination, communication_idx, node_id, agent_id, resource_id,
                                                   bucket_id, seq, team_id, domain_id)
            select 1,
                   m.queue_id,
                   m.id,
                   m.communications -> (_communication_id::int2),
                   (_communication_id::int2),
                   _node_name,
                   _agent_id,
                   r.resource_id,
                   m.bucket_id,
                   m.attempts + 1,
                   q.team_id,
                   q.domain_id
            from call_center.cc_member m
                     inner join call_center.cc_queue q on q.id = m.queue_id
                     inner join lateral (
                select (t::call_center.cc_sys_distribute_type).resource_id
                from call_center.cc_sys_queue_distribute_resources r,
                     unnest(r.types) t
                where r.queue_id = m.queue_id
                  and (t::call_center.cc_sys_distribute_type).type_id =
                      (m.communications -> (_communication_id::int2) -> 'type' -> 'id')::int4
                limit 1
                ) r on true
                     left join call_center.cc_outbound_resource cor on cor.id = r.resource_id
            where m.id = _member_id
              and m.communications -> (_communication_id::int2) notnull
              and not exists(select 1 from call_center.cc_member_attempt ma where ma.member_id = _member_id)
            returning call_center.cc_member_attempt.*
    )
                 select a.id,
                        a.member_id,
                        null::varchar          result,
                        a.queue_id,
                        cq.updated_at as       queue_updated_at,
                        0::integer             queue_count,
                        0::integer             queue_active_count,
                        0::integer             queue_waiting_count,
                        a.resource_id::integer resource_id,
                        r.updated_at::bigint   resource_updated_at,
                        null::bigint           gateway_updated_at,
                        a.destination          destination,
                        cm.variables,
                        cm.name,
                        null::varchar,
                        a.agent_id::bigint     agent_id,
                        ag.updated_at::bigint  agent_updated_at,
                        t.updated_at::bigint   team_updated_at,
                        a.seq::int seq,
                        a.communication_idx::int communication_idx
                 from attempts a
                          left join call_center.cc_member cm on a.member_id = cm.id
                          inner join call_center.cc_queue cq on a.queue_id = cq.id
                          left join call_center.cc_outbound_resource r on r.id = a.resource_id
                          left join call_center.cc_agent ag on ag.id = a.agent_id
                          inner join call_center.cc_team t on t.id = ag.team_id;

    --raise notice '%', _attempt_id;

END;
$$;




--
-- Name: cc_set_active_members(character varying); Type: FUNCTION; Schema: call_center; Owner: -
--
drop FUNCTION call_center.cc_set_active_members;
CREATE FUNCTION call_center.cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer, communication_idx integer)
    LANGUAGE plpgsql
AS $$
BEGIN
    return query update call_center.cc_member_attempt a
        set state = case when c.queue_type in (3, 4) then 'offering' else 'waiting' end
            ,node_id = node
            ,last_state_change = now()
            ,list_communication_id = lc.id
            ,seq = c.attempts + 1
            ,waiting_other_numbers = c.waiting_other_numbers
        from (
            select c.id,
                   cq.updated_at                                            as queue_updated_at,
                   r.updated_at                                             as resource_updated_at,
                   call_center.cc_view_timestamp(gw.updated_at)             as gateway_updated_at,
                   c.destination                                            as destination,
                   cm.variables                                             as variables,
                   cm.name                                                  as member_name,
                   c.state                                                  as state,
                   cqs.member_count                                         as queue_cnt,
                   0                                                        as queue_active_cnt,
                   cqs.member_waiting                                       as queue_waiting_cnt,
                   (ca.updated_at - extract(epoch from u.updated_at))::int8 as agent_updated_at,
                   tm.updated_at                                            as team_updated_at,
                   cq.dnc_list_id,
                   cm.attempts,
                   x.cnt                                                    as waiting_other_numbers,
                   cq.type                                                  as queue_type
            from call_center.cc_member_attempt c
                     inner join call_center.cc_member cm on c.member_id = cm.id
                     left join lateral (
                select count(*) cnt
                from jsonb_array_elements(cm.communications) WITH ORDINALITY AS x(c, n)
                where coalesce((x.c -> 'stop_at')::int8, 0) < 1
                  and x.n != (c.communication_idx + 1)
                ) x on c.member_id notnull
                     inner join call_center.cc_queue cq on cm.queue_id = cq.id
                     left join call_center.cc_team tm on tm.id = cq.team_id
                     left join call_center.cc_outbound_resource r on r.id = c.resource_id
                     left join directory.sip_gateway gw on gw.id = r.gateway_id
                     left join call_center.cc_agent ca on c.agent_id = ca.id
                     left join call_center.cc_queue_statistics cqs on cq.id = cqs.queue_id
                     left join directory.wbt_user u on u.id = ca.user_id
            where c.state = 'idle'
              and c.leaving_at isnull
            order by cq.priority desc, c.weight desc
                for update of c, cm, cq skip locked
        ) c
            left join call_center.cc_list_communications lc on lc.list_id = c.dnc_list_id and
                                                               lc.number = c.destination ->> 'destination'
        where a.id = c.id --and node = 'call_center-igor'
        returning
            a.id::bigint as id,
            a.member_id::bigint as member_id,
            a.result as result,
            a.queue_id::int as qeueue_id,
            c.queue_updated_at::bigint as queue_updated_at,
            c.queue_cnt::int,
            c.queue_active_cnt::int,
            c.queue_waiting_cnt::int,
            a.resource_id::int as resource_id,
            c.resource_updated_at::bigint as resource_updated_at,
            c.gateway_updated_at::bigint as gateway_updated_at,
            c.destination,
            c.variables ,
            c.member_name,
            a.member_call_id,
            a.agent_id,
            c.agent_updated_at,
            c.team_updated_at,
            a.list_communication_id,
            a.seq,
            a.communication_idx;
END;
$$;





-- TASK EVER-7
--
-- Name: cc_attempt_flip_next_resource(bigint, integer[]); Type: FUNCTION; Schema: call_center; Owner: -
--

CREATE FUNCTION call_center.cc_attempt_flip_next_resource(attempt_id_ bigint, skip_resources integer[]) RETURNS record
    LANGUAGE plpgsql
AS $$
declare destination_ varchar;
        type_id_ int4;
        queue_id_ int4;
        cur_res_id_ int4;

        resource_id_ int4;
        resource_updated_at_ int8;
        gateway_updated_at_ int8;
        allow_call_ bool;
begin
    select a.destination->>'destination', (a.destination->'type'->>'id')::int, a.queue_id, a.resource_id
    from call_center.cc_member_attempt a
    where a.id = attempt_id_
    into destination_, type_id_, queue_id_, cur_res_id_;

    with r as (
        select r.id,
               r.updated_at                                 as resource_updated_at,
               call_center.cc_view_timestamp(gw.updated_at) as gateway_updated_at,
               r."limit" - coalesce(used.cnt, 0) > 0 as allow_call
        from call_center.cc_queue_resource qr
                 inner join call_center.cc_outbound_resource_group rq on rq.id = qr.resource_group_id
                 inner join call_center.cc_outbound_resource_in_group rig on rig.group_id = rq.id
                 inner join call_center.cc_outbound_resource r on r.id = rig.resource_id
                 inner join directory.sip_gateway gw on gw.id = r.gateway_id
                 LEFT JOIN LATERAL ( SELECT count(*) AS cnt
                                     FROM (SELECT 1 AS cnt
                                           FROM call_center.cc_member_attempt c_1
                                           WHERE c_1.resource_id = r.id
                                             AND (c_1.state::text <> ALL
                                                  (ARRAY ['leaving'::character varying::text, 'processing'::character varying::text]))) c) used on true
        where qr.queue_id = queue_id_
          and rq.communication_id = type_id_
          and (array_length(coalesce(r.patterns::text[], '{}'), 1) isnull or exists(select 1 from unnest(r.patterns::text[]) pts
                                                                                    where destination_ similar to regexp_replace(regexp_replace(pts, 'x|X', '_', 'gi'), '\+', '\+', 'gi')))
          and r.enabled
          and not r.id = any(call_center.cc_array_merge(array[cur_res_id_::int], skip_resources))
        order by r."limit" - coalesce(used.cnt, 0) > 0 desc nulls last, rig.priority desc
        limit 1
    )
    update call_center.cc_member_attempt a
    set resource_id = r.id
    from r
    where a.id = attempt_id_
    returning r.id, r.resource_updated_at, r.gateway_updated_at, r.allow_call
        into resource_id_, resource_updated_at_, gateway_updated_at_, allow_call_;

    return row(resource_id_, resource_updated_at_, gateway_updated_at_, allow_call_);
end
$$;