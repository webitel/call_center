CREATE OR REPLACE PROCEDURE call_center.cc_distribute(IN disable_omnichannel boolean)
 LANGUAGE plpgsql
AS $procedure$begin
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
                                                   communication_idx, member_call_id, team_id, resource_group_id, domain_id, import_id, sticky_agent_id, queue_params, queue_type)
            select case when q.type = 7 then 'task' else 'call' end, --todo
                   dis.id,
                   dis.queue_id,
                   dis.resource_id,
                   dis.agent_id,
                   dis.bucket_id,
                   jsonb_set(x, '{type,channel}'::text[], to_jsonb(c.channel::text)) || jsonb_build_object('name', m.name),
                   dis.comm_idx,
                   uuid_generate_v4(),
                   dis.team_id,
                   dis.resource_group_id,
                   q.domain_id,
                   m.import_id,
                   case when q.type = 5 and q.sticky_agent and m.agent_id notnull then dis.agent_id end,
                   call_center.cc_queue_params(q),
                   q.type
            from dis
                     inner join call_center.cc_queue q on q.id = dis.queue_id
                     inner join call_center.cc_member m on m.id = dis.id
                     inner join lateral jsonb_extract_path(m.communications, (dis.comm_idx)::text) x on true
                     left join call_center.cc_communication c on c.id = (x->'type'->'id')::int
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
               and (q.type is null or q.type in (6, 7, 9) or not exists(select 1 from call_center.cc_calls cc where cc.user_id = a.user_id and cc.hangup_at isnull ))
         ) t
where t.id = a.id
  and a.agent_id isnull;

end;
$procedure$
