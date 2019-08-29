drop function cc_set_active_members;

create or replace function cc_set_active_members(node character varying)
  returns TABLE
          (
            id                  bigint,
            member_id           bigint,
            communication_id    bigint,
            result              character varying,
            queue_id            integer,
            queue_updated_at    bigint,
            queue_count  int,
            queue_active_count int,
            resource_id  integer,
            resource_updated_at bigint,
            routing_id          integer,
            routing_pattern     character varying,
            destination         character varying,
            description         character varying,
            variables           jsonb,
            name                character varying,
            leg_a_id            character varying,
            agent_id bigint,
            agent_updated_at bigint
          )
  language plpgsql
as
$$
BEGIN
    return query update cc_member_attempt a
      set state = 1
        ,node_id = node
        ,result = case c.state when 3 then 'TIMEOUT' when 7 then 'CANCEL' else a.result end
      from (
--         with stats as (
--           select a.queue_id,
--                  count(*)                            count,
--                  count(*) filter ( where state = 5 ) active
--           from cc_member_attempt a
--           where a.hangup_at = 0
--           group by a.queue_id
--         )
        select c.id,
               cq.updated_at   as queue_updated_at,
               r.updated_at    as resource_updated_at,
               qr.id           as routing_id,
               qr.pattern      as routing_pattern,
               cmc.number      as destination,
               cmc.description as description,
               cm.variables    as variables,
               cm.name         as member_name,
               c.state         as state,
               cq.sec_locate_agent,
--                s.count as queue_cnt,
               0 as queue_cnt,
--                s.active as queue_active_cnt
               0 as queue_active_cnt,
               ca.updated_at as agent_updated_at
        from cc_member_attempt c
               --inner join stats s on s.queue_id = c.queue_id
               inner join cc_member cm on c.member_id = cm.id
               inner join cc_member_communications cmc on cmc.id = c.communication_id
               inner join cc_queue cq on cm.queue_id = cq.id
               left join cc_queue_routing qr on qr.id = c.routing_id
               left join cc_outbound_resource r on r.id = c.resource_id
               left join cc_agent ca on c.agent_id = ca.id
        where (c.state = 0
                or (c.state = 3 and c.agent_id isnull and cq.sec_locate_agent > 0 and c.created_at <= (extract(EPOCH  from current_timestamp)::bigint - cq.sec_locate_agent) * 1000)
                or c.state = 7
          ) and c.hangup_at = 0
        order by cq.priority desc, c.weight desc
                 for update of c skip locked
      ) c
      where a.id = c.id
      returning
        a.id::bigint as id,
        a.member_id::bigint as member_id,
        a.communication_id::bigint as communication_id,
        a.result as result,
        a.queue_id::int as qeueue_id,
        c.queue_updated_at::bigint as queue_updated_at,
        c.queue_cnt::int,
        c.queue_active_cnt::int,
        a.resource_id::int as resource_id,
        c.resource_updated_at::bigint as resource_updated_at,
        c.routing_id,
        c.routing_pattern,
        c.destination,
        c.description,
        c.variables,
        c.member_name,
        a.leg_a_id,
        a.agent_id,
        c.agent_updated_at;
END;
$$;


select *
from cc_set_active_members('call-center-1');


select *
from cc_member_attempt;

truncate table cc_member_attempt;

explain analyze
 select
               c.id,
               cq.updated_at as queue_updated_at,
               r.updated_at as resource_updated_at,
               qr.id as routing_id,
               qr.pattern as routing_pattern,
               cmc.number as destination,
               cmc.description as description,
               cm.variables as variables,
               cm.name as member_name,
               c.state as state
        from cc_member_attempt c
               inner join cc_member cm on c.member_id = cm.id
               inner join cc_member_communications cmc on cmc.id = c.communication_id
               inner join cc_queue cq on cm.queue_id = cq.id
               left join cc_queue_routing qr on qr.id = c.routing_id
               left join cc_outbound_resource r on r.id = c.resource_id
        where  (c.state = 0
                or (c.state = 3 and c.agent_id isnull and cq.sec_locate_agent > 0 and c.created_at <= (extract(EPOCH  from current_timestamp)::bigint - cq.sec_locate_agent) * 1000)
                or c.state = 7
          ) and c.hangup_at = 0
        order by cq.priority desc, cm.priority desc
        for update of c;

1558005839648
1562578328
select extract(EPOCH  from current_timestamp)::bigint * 1000;


select *
from cc_member_attempt
where id = 2815020
order by id desc ;


update cc_agent
set status = 'online',
    state = 'waiting',
    call_timeout = 5
where 1=1;


DISCARD PLANS;



select *
from cc_agent
where id in(479, 480) ;


truncate table cc_member_attempt;
select *
from reserve_members_with_resources('aaa');

select *
from set_active_members('aaa');

drop function set_active_members;

show log_min_duration_statement;

select
       c.id,
       cq.updated_at as queue_updated_at,
       r.updated_at as resource_updated_at,
       qr.pattern as routing_pattern,
       cm.name as member_name,
       cm.variables as member_variables,
       cmc.number as member_number,
       cmc.description as member_number_description
  from cc_member_attempt c
     inner join cc_member cm on c.member_id = cm.id
     inner join cc_member_communications cmc on cmc.id = c.communication_id
     inner join cc_queue cq on cm.queue_id = cq.id
     left join cc_queue_routing qr on qr.id = c.routing_id
     left join cc_outbound_resource r on r.id = c.resource_id
        --where c.state = 0 and c.hangup_at = 0
order by cq.priority desc, cm.priority desc
for update of c;



select c.id, cq.updated_at as queue_updated_at, r.updated_at as resource_updated_at
        from cc_member_attempt c
               inner join cc_member cm on c.member_id = cm.id
               inner join cc_queue cq on cm.queue_id = cq.id
               left join cc_outbound_resource r on r.id = c.resource_id
        where c.state = 0 and c.hangup_at = 0
        order by cq.priority desc, cm.priority desc
        for update of c;


select *
from (
       select row_number() over (order by cq.priority desc, cm.priority desc) arn, a.*
       from cc_member_attempt a
              inner join cc_member cm on a.member_id = cm.id
              inner join cc_queue cq on cm.queue_id = cq.id
       where a.hangup_at = 0
     ) as at
       inner join (
  select q.id as queue_id, array_agg(aq.agent_id) agent_ids, row_number() over () as rn
  from available_agent_in_queue aq
         inner join cc_agent a on a.id = aq.agent_id
         inner join cc_queue q on q.id = aq.queue_id
  --where not exists(select * from cc_member_attempt at where at.hangup_at = 0 and at.agent_id = q.id)
  group by q.id, case q.strategy when 'ring-all' then q.id else aq.agent_id end
  order by q.priority desc
) as a on true --a.rn = at.arn;


truncate table cc_member_attempt;

select *
from cc_member_attempt
where hangup_at = 0;



