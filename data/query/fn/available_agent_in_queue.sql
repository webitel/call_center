drop view  available_agent_in_queue;

CREATE OR REPLACE VIEW available_agent_in_queue AS
select ag.*,
       a.updated_at as updated_at,
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
) ag
inner join cc_agent a on a.id = ag.agent_id;


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


select *
from cc_member_attempt a
where a.hangup_at = 0;



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