
drop function get_agents_available_count_by_queue_id;

CREATE OR REPLACE FUNCTION get_agents_available_count_by_queue_id(_queue_id integer)
  RETURNS SETOF integer AS
$$
BEGIN
  return query select count(distinct qa.agent_id)::integer as cnt
               from (
                      select aq.queue_id, COALESCE(aq.agent_id, csia.agent_id) as agent_id
                      from cc_agent_in_queue aq
                             left join cc_skils cs on aq.skill_id = cs.id
                             left join cc_skill_in_agent csia on cs.id = csia.skill_id
                      where aq.queue_id = _queue_id
                      group by aq.queue_id, aq.agent_id, csia.agent_id
                    ) as qa

               where qa.queue_id = _queue_id
                 and not qa.agent_id is null
                 and not exists(select * from cc_member_attempt a where a.hangup_at = 0 and a.agent_id = qa.agent_id);
END;
$$ LANGUAGE plpgsql;
;

select get_agents_available_count_by_queue_id(3);

explain analyse
select distinct qa.agent_id, qa.queue_id
from (
  select aq.queue_id, COALESCE(aq.agent_id, csia.agent_id) as agent_id
  from cc_agent_in_queue aq
    left join cc_skils cs on aq.skill_id = cs.id
    left join cc_skill_in_agent csia on cs.id = csia.skill_id
  group by aq.queue_id, aq.agent_id, csia.agent_id
) as qa
where qa.queue_id = 1 and not qa.agent_id is null
  and not exists(select * from cc_member_attempt a where a.hangup_at = 0 and a.agent_id = qa.agent_id)
order by qa.agent_id;


explain analyse
with r as (
  select 1 as queue_id, a.id agent_id,
         row_number() over () - 1 as pos
  from cc_agent a
), q1 as (
  select a.id, q.name, a.queue_id,
         row_number() over (partition by a.queue_id order by q.priority desc, cm.priority desc) - 1 pos_idx,
         count(*) over (partition by a.queue_id) cnt
  from cc_member_attempt a
    inner join cc_queue q on a.queue_id = q.id
    inner join cc_member cm on a.member_id = cm.id
  where a.state = 0
)
select *
from r, q1
where q1.queue_id = r.queue_id and q1.pos_idx  = (r.pos % q1.cnt) ;



select *
from reserve_members_with_resources('test');









