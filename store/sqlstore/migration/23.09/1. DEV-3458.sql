create or replace function call_center.cc_set_active_members(node character varying)
    returns TABLE(id bigint, member_id bigint, result character varying, queue_id integer, queue_updated_at bigint, queue_count integer, queue_active_count integer, queue_waiting_count integer, resource_id integer, resource_updated_at bigint, gateway_updated_at bigint, destination jsonb, variables jsonb, name character varying, member_call_id character varying, agent_id integer, agent_updated_at bigint, team_updated_at bigint, list_communication_id bigint, seq integer, communication_idx integer)
    language plpgsql
as
$$
BEGIN
    return query update call_center.cc_member_attempt a
        set state = case when c.member_id isnull then 'leaving' else
            case when c.queue_type in (3, 4) then 'offering' else 'waiting' end
            end
            ,node_id = node
            ,last_state_change = now()
            ,list_communication_id = lc.id
            ,seq = coalesce(c.attempts, -1) + 1
            ,waiting_other_numbers = coalesce(c.waiting_other_numbers, 0)
            ,result = case when c.member_id isnull then 'cancel' else a.result end
            ,leaving_at = case when c.member_id isnull then now() end
        from (
            select c.id,
                   cq.updated_at                                            as queue_updated_at,
                   r.updated_at::bigint as resource_updated_at,
                   call_center.cc_view_timestamp(gw.updated_at at time zone 'utc')::bigint             as gateway_updated_at,
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
                   cq.type                                                  as queue_type,
                   cm.id as member_id
            from call_center.cc_member_attempt c
                     left join call_center.cc_member cm on c.member_id = cm.id
                     left join lateral (
                select count(*) cnt
                from jsonb_array_elements(cm.communications) WITH ORDINALITY AS x(c, n)
                where coalesce((x.c -> 'stop_at')::int8, 0) < 1
                  and x.n != (c.communication_idx + 1)
                ) x on c.member_id notnull
                     inner join call_center.cc_queue cq on c.queue_id = cq.id
                     left join call_center.cc_team tm on tm.id = cq.team_id
                     left join call_center.cc_outbound_resource r on r.id = c.resource_id
                     left join directory.sip_gateway gw on gw.id = r.gateway_id
                     left join call_center.cc_agent ca on c.agent_id = ca.id
                     left join call_center.cc_queue_statistics cqs on cq.id = cqs.queue_id
                     left join directory.wbt_user u on u.id = ca.user_id
            where c.state = 'idle'
              and c.leaving_at isnull
            order by cq.priority desc, c.weight desc
                for update of c, cq skip locked
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
            greatest(c.resource_updated_at::bigint, c.gateway_updated_at::bigint) as resource_updated_at,
            greatest(c.resource_updated_at::bigint, c.gateway_updated_at::bigint) as gateway_updated_at,
            c.destination,
            coalesce(c.variables, '{}') ,
            coalesce(c.member_name, ''),
            a.member_call_id,
            a.agent_id,
            c.agent_updated_at,
            c.team_updated_at,
            a.list_communication_id,
            a.seq,
            a.communication_idx;
END;
$$;