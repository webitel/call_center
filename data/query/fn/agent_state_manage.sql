CREATE OR REPLACE FUNCTION name()
  RETURNS void  AS
$$
BEGIN

END;
$$ LANGUAGE 'plpgsql';


explain analyse
insert into cc_agent_state_history (agent_id, joined_at, state)
select a.id, now(), 'waiting'
from cc_agent a,
lateral (
 select h.state, h.timeout_at
 from cc_agent_state_history h
 where h.agent_id = a.id
 order by joined_at desc
 limit 1
) s
where s.timeout_at <= now();

 UPDATE "call_center"."cc_agent" SET "state" = 'waiting' WHERE "id" = 1;

select (success_calls::float / all_cals) * 100 as sla
from (
  select
    count(a.id) filter ( where a.result = 'NORMAL_CLEARING' ) as success_calls,
    count(a.id) all_cals
  from call_center.cc_member_attempt a
  where extract(doy  from to_timestamp(created_at/ 1000)) = extract(doy  from now()) and  a.hangup_at > 0 and a.agent_id = 1
) c;


select coalesce  (EXTRACT(epoch FROM s.busy_t) / (EXTRACT(epoch FROM s.waiting_t))  * 100, 0.01) as utilization
from (
  select sum(s.t) filter ( where s.state = 'waiting' ) as waiting_t, sum(s.t) filter ( where s.state != 'waiting' ) as busy_t
  from (
    select h.state, sum(coalesce(h2.joined_at, now()) - h.joined_at) as t
    from call_center.cc_agent_state_history h
     left join lateral (
      select *
       from call_center.cc_agent_state_history h2
       where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
       order by h2.joined_at asc
       limit 1
      ) h2 on true
    inner join call_center.cc_agent ca on h.agent_id = ca.id
    where h.agent_id = 1 and 1=2
    group by h.agent_id, h.state, ca.name
  ) s
  where s.state != 'logged_out'
) s