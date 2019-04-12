drop view  available_agent_in_queue;

CREATE OR REPLACE VIEW available_agent_in_queue AS
select ag.*,
       a.updated_at as updated_at,
--        q.priority +
         round(100.0 * (ag.max_of_capacity + 1) / NULLIF(SUM(ag.max_of_capacity + 1) OVER(partition by ag.agent_id),0)) AS "ratio"
--,         (0.5 / 2) + (0.5* (100/(100 + ag.max_of_capacity)))
from (
       select
         distinct aq.queue_id,
              COALESCE(aq.agent_id, csia.agent_id) as agent_id,
              COALESCE(max(csia.capacity), 0) max_of_capacity,
              max(aq.lvl) max_of_lvl
       from cc_agent_in_queue aq
              left join cc_skils cs on aq.skill_id = cs.id
              left join cc_skill_in_agent csia on cs.id = csia.skill_id
       where not COALESCE(aq.agent_id, csia.agent_id) isnull
       group by aq.queue_id, COALESCE(aq.agent_id, csia.agent_id)
) ag
inner join cc_agent a on a.id = ag.agent_id
left join lateral ( -- TODO
  select h.state
  from cc_agent_state_history h
  where h.agent_id = ag.agent_id
  order by h.joined_at desc
  limit 1
) s on true
where a.logged is true and (s.state isnull or s.state = 'waiting');


select count(*)
from cc_member_attempt;

select * from available_agent_in_queue
where agent_id = 1;



select reserve_members_with_resources('dd');
select row_number() over (order by cq.priority desc, cm.priority desc, a.created_at asc), *
from cc_member_attempt a
 inner join cc_member cm on a.member_id = cm.id
 inner join cc_queue cq on cm.queue_id = cq.id
where a.hangup_at = 0;



select ag.*,
--        q.priority +
         round(100.0 * (ag.max_of_capacity + 1) / NULLIF(SUM(ag.max_of_capacity + 1) OVER(partition by ag.agent_id),0)) AS "ratio"
--         (0.5 / 2) + (0.5* (100/(100 + a.max_of_capacity)))
from (
       select
         distinct aq.queue_id,
              COALESCE(aq.agent_id, csia.agent_id) as agent_id,
              COALESCE(max(csia.capacity), 0) max_of_capacity,
              max(aq.lvl) max_of_lvl
       from cc_agent_in_queue aq
              left join cc_skils cs on aq.skill_id = cs.id
              left join cc_skill_in_agent csia on cs.id = csia.skill_id
       where not COALESCE(aq.agent_id, csia.agent_id) isnull
       group by aq.queue_id, COALESCE(aq.agent_id, csia.agent_id)
) ag;

select to_timestamp(created_at/ 1000), extract(doy  from to_timestamp(created_at/ 1000)), extract(doy  from now())
from cc_member_attempt;

explain analyse
select (success_calls::float / all_cals) * 100 as sla
from (
  select
    count(a.id) filter ( where a.result = 'NORMAL_CLEARING' ) as success_calls,
    count(a.id) all_cals
  from cc_member_attempt a
  where extract(doy  from to_timestamp(created_at/ 1000)) = extract(doy  from now()) and  a.hangup_at > 0 and a.agent_id = 1
) c;

explain analyse
select (EXTRACT(epoch FROM s.busy_t)) / (EXTRACT(epoch FROM s.waiting_t)) * 100 as utilization
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
    where h.agent_id = 1 and h.joined_at > CURRENT_DATE
    group by h.agent_id, h.state, ca.name
  ) s
  where s.state != 'logged_out'
) s;

truncate table cc_agent_state_history;

vacuum full cc_agent_state_history;

explain analyse
select *
from cc_agent_state_history
where timeout_at > CURRENT_DATE;

insert into cc_agent_state_history(agent_id, state)
select *
from cc_agent_state_history h;






select q.name queue_name, g.*
from (
  select a.queue_id, count(*) filter ( where a.result = 'NORMAL_CLEARING' ) as "Answered",
         count(*) filter ( where a.result != 'NORMAL_CLEARING' ) as "Lose"
  from call_center.cc_member_attempt a
  where to_timestamp(created_at/1000) > CURRENT_DATE and a.agent_id = 1
  group by a.queue_id
) g
inner join call_center.cc_queue q on q.id = g.queue_id



select * --distinct qa.agent_id, qa.queue_id, qa.lvl
from (
       select aq.queue_id, COALESCE(aq.agent_id, csia.agent_id) as agent_id, csia.capacity, aq.lvl
       from cc_agent_in_queue aq
              left join cc_skils cs on aq.skill_id = cs.id
              left join cc_skill_in_agent csia on cs.id = csia.skill_id
       group by aq.queue_id, aq.agent_id, csia.agent_id, aq.lvl, csia.capacity
     ) as qa
where not qa.agent_id is null
  --and not exists(select * from cc_member_attempt a where a.hangup_at = 0 and a.agent_id = qa.agent_id)
order by qa.agent_id;