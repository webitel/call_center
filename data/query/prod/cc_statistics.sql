explain (analyze, COSTS, buffers ,format json )
select count(*)
from (
  select
   COALESCE(aq.agent_id, csia.agent_id) as agent_id
  from cc_agent_in_queue aq
    left join cc_skill_in_agent csia on aq.skill_id = csia.skill_id
  where aq.queue_id = 1 and not COALESCE(aq.agent_id, csia.agent_id) isnull
  group by COALESCE(aq.agent_id, csia.agent_id)
) a
where not exists(select 1 from cc_member_attempt at where at.state > 0 and at.agent_id = a.agent_id)
  and exists (select * from cc_agent a1 where a1.id = a.agent_id and a1.status = 'online' and a1.state = 'waiting');



explain analyze
select h.joined_at::date, count(*)
from cc_agent_state_history h
where h.joined_at > (current_date - '4 day'::interval)
group by h.joined_at::date;


;

select attname, correlation from pg_stats where tablename='cc_member_attempt'
order by correlation desc nulls last;

explain analyze
select count(*) --  sum(h.joined_at -  now() ) --sum(coalesce(h2.joined_at, now()) - h.joined_at) filter ( where h.state = 'waiting' )
from cc_agent_state_history h
left join lateral (
  select h2.joined_at, h2.state
  from  cc_agent_state_history h2
  where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
  order by h2.joined_at asc
  limit 1
) h2 on true
where h.joined_at between (current_date - '4 day'::interval) and now()
group by h.agent_id;
--order by h.joined_at desc;


select s.agent_id, sum(t) filter ( where s.state = 'waiting' ) as waiting
from (
  select h.agent_id, h.state,
       coalesce(lag(h.joined_at) over (partition by h.agent_id order by h.joined_at desc) , now()) - h.joined_at as t
  from cc_agent_state_history h
  where h.joined_at between (current_date - '4 day'::interval) and now() --and h.agent_id = 1
) s
group by s.agent_id;







select *
from pg_stat_activity
where application_name = 'call_center';



explain analyze
select a.agent_id, count(*)
from cc_member_attempt a
where a.created_at > ((date_part('epoch'::text, current_date) * (1000)::double precision))::bigint and a.agent_id notnull and a.state = -1
group by a.agent_id;


select count(*)
from cc_agent_state_history
where joined_at > (current_date - '4 day'::interval);

-- вичислення статистики
select *
from (
  select h3.agent_id
  from cc_agent_state_history h3
  where h3.joined_at > (current_date - '4 day'::interval)
  group by h3.agent_id
) h3,
lateral (
  select
     avg(coalesce(h2.joined_at, now()) - h.joined_at) filter ( where h.state = 'waiting' ) as idle,
     avg(coalesce(h2.joined_at, now()) - h.joined_at) filter ( where h.state = 'offering' ) as offering,
     avg(coalesce(h2.joined_at, now()) - h.joined_at) filter ( where h.state = 'talking' ) as talking
  from cc_agent_state_history h
  left join lateral (
    select h2.joined_at, h2.state
    from  cc_agent_state_history h2
    where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
    order by h2.joined_at asc
    limit 1
  ) h2 on true
  where h.joined_at > (current_date - '4 day'::interval) and h.agent_id = h3.agent_id
) s ;
;


explain analyze
select sum(coalesce(h2.joined_at, now()) - h.joined_at) filter ( where h.state = 'waiting' )
  from cc_agent_state_history h
  left join lateral (
    select h2.joined_at, h2.state
    from  cc_agent_state_history h2
    where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
    order by h2.joined_at asc
    limit 1
  ) h2 on true
  where h.joined_at > current_date
group by h.agent_id


