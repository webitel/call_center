

DO
$do$
DECLARE
  rec RECORD;
BEGIN
   FOR rec IN select *
    from cc_member_attempt a
     where a.hangup_at = 0 and a.state = 3
   LOOP

     raise notice '%', rec.id;
   END LOOP;
END
$do$;






explain (analyse , format json )
select *
from (
  select a.id,
         a.queue_id,
         a.agent_id as last_agent_id,
         row_number() over (partition by a.queue_id order by a.queue_id,  a.weight desc, a.created_at asc) pos
  from cc_member_attempt a
    left join lateral (
     select a1.agent_id
     from cc_member_attempt a1
     where a1.created_at < a.created_at and a1.member_id = a.member_id
     order by a1.created_at desc
     limit 1
    ) l on true
  where a.hangup_at = 0 and a.state = 3 and a.agent_id isnull
) t;



select *
from available_agent_in_queue;



explain analyse
with records as (
  select 1 as id, 1 as project_id
  union all
  select 2 as id, 2 as project_id
  union all
  select 3 as id, 1 as project_id
  union all
  select 4 as id, 1 as project_id
  union all
  select 5 as id, 1 as project_id
  union all
  select 6 as id, 1 as project_id
)
, owners as (
  select 1 as id, 1 as project_id, 20 as ratio
  union
  select 1 as id, 2 as project_id, 80 as ratio
  union
  select 2 as id, 1 as project_id, 100 as ratio
  union
  select 3 as id, 1 as project_id, 100 as ratio
  union
  select 4 as id, 1 as project_id, 100 as ratio
  union
  select 5 as id, 1 as project_id, 100 as ratio
)
select r.id as id, r.project_id, tmp.owner_id
from (
  select *, row_number() over (partition by project_id order by id) rn
  from records
) r
inner join (
  select *, row_number() over (partition by tmp.project_id order by tmp.owner_id) rn
  from (
    select distinct on(id) id owner_id,  project_id, null::bigint as record_id
    from owners
    order by id, ratio desc
  ) tmp
) tmp on r.project_id = tmp.project_id and r.rn = tmp.rn;



explain (analyse, verbose , format json)
select *
from (
  with tmp as (
    select *, row_number() over (partition by tmp.queue_id order by tmp.queue_id) rn --TODO strategy
    from (
      select distinct on(agent_id) agent_id, queue_id
      from available_agent_in_queue a
      order by a.agent_id, a.ratio desc
    ) tmp
  )
  select r.id as attempt_id, r.queue_id, tmp.agent_id
  from (
    select *, row_number() over (partition by queue_id order by created_at) rn
    from cc_member_attempt a
    where a.hangup_at = 0 and a.state = 3
  ) r
  inner join tmp on r.queue_id = tmp.queue_id and r.rn = tmp.rn
) result;


update cc_member_attempt a
set agent_id = res.agent_id
from (
with tmp as (
  select *, row_number() over (partition by tmp.queue_id order by tmp.queue_id) rn --TODO strategy
    from (
      select distinct on(agent_id) agent_id, queue_id
      from available_agent_in_queue a
      order by a.agent_id, a.ratio desc
    ) tmp
  )
  select r.id as attempt_id, r.queue_id, tmp.agent_id
  from (
    select *, row_number() over (partition by queue_id order by created_at) rn
    from cc_member_attempt a
    where a.hangup_at = 0 and a.state = 3 and a.agent_id isnull
  ) r
  inner join tmp on r.queue_id = tmp.queue_id and r.rn = tmp.rn
) res
inner join cc_agent ag on ag.id = res.agent_id
where a.id = res.attempt_id and a.agent_id isnull
returning a.id::bigint as attempt_id, a.agent_id::bigint, ag.updated_at::bigint as agent_updated_at;



select *
from (
  select *, row_number() over (partition by tmp.queue_id order by tmp.queue_id) rn --TODO strategy
  from (
    select distinct on(agent_id) agent_id, queue_id
    from available_agent_in_queue a
    order by a.agent_id, a.ratio desc
  ) tmp
) a;




/*

select *, row_number() over (partition by tmp.project_id order by tmp.owner_id) rn
  from (
    select distinct on(id) id owner_id,  project_id, null::bigint as record_id
    from owners
    order by id, ratio desc
  ) tmp
 */
;





select ag.*,
       s.*,
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
where a.id = 997;-- a.status = 'online' and (s.state isnull or s.state = 'waiting')


select *
from pg_stats
where tablename = 'cc_member_communications';
;



explain (analyse, verbose)
with attempts as (
  select a.id, a.queue_id, last_a.agent_id as old_agent_id
    ,row_number() over (partition by a.queue_id order by a.weight desc, a.created_at asc) pos
  from cc_member_attempt a
    left join lateral (
      select a1.agent_id
      from cc_member_attempt a1
      where a1.member_id = a.member_id and a1.created_at < a.created_at
    ) last_a on true
  where a.hangup_at = 0 and a.agent_id isnull
), agents as (
  select
         ag.*,
         a.updated_at
  from (
    select
      aq.queue_id,
      COALESCE(aq.agent_id, csia.agent_id) as agent_id,
      COALESCE(max(csia.capacity), 0) max_of_capacity,
      max(aq.lvl) max_of_lvl
    from cc_agent_in_queue aq
      left join cc_skill_in_agent csia on csia.skill_id = aq.skill_id
    where aq.queue_id in (
            select a.queue_id
            from attempts a
            group by a.queue_id
          ) and
          not COALESCE(aq.agent_id, csia.agent_id) isnull
    group by aq.queue_id, COALESCE(aq.agent_id, csia.agent_id)
  ) ag
    inner join cc_agent a on a.id = ag.agent_id
    left join lateral (
      select h.state
      from cc_agent_state_history h
      where h.agent_id = ag.agent_id
      order by h.joined_at desc
      limit 1
    ) s on true
  where a.status = 'online' and (s.state = 'waiting')
    and not exists(
      select *
      from cc_member_attempt at
      where at.hangup_at = 0 and at.agent_id = a.id
    )
)
select distinct on (t.id) t.id, a.agent_id
  from agents a
cross join attempts t
where a.queue_id = t.queue_id
;


with recursive t as (
  select queue_id, count(*) as cnt
  from cc_member_attempt
  group by queue_id
)
select *
from t;





select *
from reserve_members_with_resources('test');

update cc_member_attempt
set state = 3
where 1=1;






select *
from available_agent_in_queue;


explain analyse
select cq.id queue_id, cq.strategy, array_agg(a.id) as ids, null::bigint as aggent_id, '{}'::integer[] as agents_ids
from cc_queue cq
  inner join cc_member_attempt a on a.queue_id = cq.id
where a.hangup_at = 0 and a.agent_id isnull
group by cq.id
order by cq.id asc
limit 1;


explain analyse
with recursive att_arr as (
  select
         a.*,
         t.ids as agents_ids
  from (
    select cq.id queue_id, cq.strategy, array_agg(a.id) as ids, null::bigint as aggent_id
    from cc_queue cq
      inner join cc_member_attempt a on a.queue_id = cq.id
    where a.hangup_at = 0 and a.agent_id isnull
    group by cq.id
     order by cq.id asc
     limit 1
  ) a ,
   lateral (
    select array_agg(k.agent_id) ids
    from (
      select f.agent_id
      from available_agent_in_queue f
      where f.queue_id = a.queue_id
      order by f.max_of_lvl desc
      limit array_length(a.ids, 1)
    ) k
   ) t

  union

  select a.queue_id, a.strategy, a.ids, null, a.agents_ids
  from att_arr a,
  lateral (
    select count(r)
    from cc_member_attempt r
    where r.hangup_at = 0
  ) k
)
select *
from att_arr
limit 50;


SELECT _pos
    FROM generate_subscripts(array[1,2,3], 1) gs(_pos);


update cc_agent
set status = 'offline'
where id in (
select id
from cc_agent
where id > 10);


explain (analyse, format JSON )
select a.id, a.queue_id, last_agent.agent_id
from cc_member_attempt a
  left join lateral (
    select a1.agent_id
    from cc_member_attempt a1
    where a1.member_id = a.id and a1.created_at < a.created_at
    order by a1.created_at desc
    limit 1
  ) last_agent on true;


explain (analyse)
select
       ag.*,
       a.id as agent_id,
       a.updated_at as agent_updated_at,
       row_number() over (order by ag.max_of_lvl desc, max_of_capacity desc ) pos
from (
  select
    COALESCE(aq.agent_id, csia.agent_id) as agent_id,
    COALESCE(max(csia.capacity), 0) max_of_capacity,
    max(aq.lvl) max_of_lvl
  from cc_agent_in_queue aq
    left join cc_skill_in_agent csia on csia.skill_id = aq.skill_id
  where aq.queue_id = 1 and not COALESCE(aq.agent_id, csia.agent_id) isnull
  group by  COALESCE(aq.agent_id, csia.agent_id)
) ag
  inner join cc_agent a on a.id = ag.agent_id
  left join lateral (
    select h.state
    from cc_agent_state_history h
    where h.agent_id = ag.agent_id
    order by h.joined_at desc
    limit 1
  ) s on true
where a.status = 'online' and (s.state = 'waiting')
  and not exists(
    select *
    from cc_member_attempt at
    where at.hangup_at = 0 and at.agent_id = a.id
  )
limit 10;


explain analyse
DO
$do$
DECLARE
  rec RECORD;
  att record;
  agents integer[];
  a integer;
BEGIN
   FOR rec IN select cq.id queue_id, cq.strategy, count(*) as cnt
           from cc_member_attempt a
            inner join cc_queue cq on a.queue_id = cq.id
           where a.hangup_at = 0 and a.agent_id isnull
           group by cq.id
           order by cq.priority desc
   LOOP

    select array_agg(t.agent_id)
    into agents
    from (
     select agent_id
     from available_agent_in_queue
     where queue_id = rec.queue_id
     order by max_of_lvl desc, ratio desc
    ) t;

    for att IN select a.id, a1.agent_id
      from cc_member_attempt a
       left join lateral (
          select a1.agent_id
          from cc_member_attempt a1
          where a1.member_id = a.member_id and a1.created_at < a.created_at
          order by a1.created_at desc
         limit  1
        ) a1 on true
      where a.hangup_at = 0 and a.agent_id isnull and a.queue_id = rec.queue_id --and a.id = 7421650
      order by a.created_at asc, a.weight desc, a1.agent_id nulls last
    loop
      if array_length(agents, 1) > 0 then
        select agents - case when not att.agent_id isnull and agents && array[att.agent_id]::integer[] then att.agent_id::integer else agents[1] end,
               case when not att.agent_id isnull and agents && array[att.agent_id]::integer[] then att.agent_id::integer else agents[1] end
         into agents, a;

         if a = 77 then
           --raise notice '% to %', att.id, a;
         end if;
         raise notice '% to %', att.id, a;
         raise notice '%', agents;

      end if;

    end loop;
   END LOOP;
END
$do$;


select  max_calls, sum(max_calls) over (order by id  rows unbounded preceding) as start,
       sum(max_calls) over (order by id  rows unbounded preceding) - max_calls  as finish
from cc_queue;

select *
from cc_member_attempt
where member_id = 26518 or id = 7421650;

update cc_member_attempt
set agent_id = null
where state = 3;

update cc_agent
set status = 'online'
where 1=1;


select a.id, a1.agent_id
from cc_member_attempt a
 left join lateral (
    select a1.agent_id
    from cc_member_attempt a1
    where a1.member_id = a.member_id and a1.created_at < a.created_at
    order by a1.created_at desc
   limit  1
  ) a1 on true
where a.hangup_at = 0 and a.agent_id isnull --and a.queue_id = rec.queue_id -- and a.id = 7421650
order by a1.agent_id nulls last ,  a.created_at asc, a.weight desc




select array_agg(t.agent_id) agents
from (
 select agent_id
 from available_agent_in_queue
 where queue_id = 1
 order by max_of_lvl desc, ratio desc
) t;

select a.id, a1.agent_id
from cc_member_attempt a
 left join lateral (
    select a1.agent_id
    from cc_member_attempt a1
    where a1.member_id = a.member_id and a1.created_at < a.created_at
    order by a1.created_at desc
   limit  1
  ) a1 on true
where a.hangup_at = 0 and a.agent_id isnull and a.queue_id = 1
order by a.created_at asc, a.weight desc;


select array[1,2,3] - (array[1,2,3])[1:1];

select *
from (
  select a.id, last.agent_id as last_agent_id, a.queue_id--, row_number() over (order by a.created_at desc, a.weight desc) pos
  from cc_member_attempt a
   left join lateral (
    select a2.agent_id
    from cc_member_attempt a2
     where a2.member_id = a.member_id and a2.queue_id = a.queue_id and a2.created_at < a.created_at
  ) last on true
  where a.hangup_at = 0 and a.agent_id isnull and a.queue_id = 1
) a
union
select null, agent_id, queue_id
from available_agent_in_queue;

select *
from available_agent_in_queue q
where q.queue_id = 1;


select agent_id, max(joined_at)
from cc_agent_state_history
group by agent_id
limit 10;




with a as (
  select v.agent_id, v.queue_id-- dense_rank() over (partition by a.id, v.agent_id) rn
  from available_agent_in_queue v
  where  v.queue_id = 1
)
select *
from a
  inner join cc_member_attempt g on g.queue_id = a.queue_id
where g.queue_id = 1 and g.hangup_at = 0 and g.agent_id isnull ;


select *
from (
  select v.agent_id, a.* --, dense_rank() over (partition by a.id, v.agent_id) rn
  from available_agent_in_queue v
  inner join (
    select *
    from (
           select a.id,
                  last.agent_id as last_agent_id,
                  a.queue_id--, row_number() over (order by a.created_at desc, a.weight desc) pos
           from cc_member_attempt a
                  left join lateral (
             select a2.agent_id
             from cc_member_attempt a2
             where a2.member_id = a.member_id
               and a2.queue_id = a.queue_id
               and a2.created_at < a.created_at
             ) last on true
           where a.hangup_at = 0
             and a.agent_id isnull
         ) a
  ) a on v.queue_id = a.queue_id
) h
order by h.agent_id
;




with a as (
  select agent_id, queue_id, row_number() over (order by max_of_lvl desc, max_of_capacity desc ) rn
  from available_agent_in_queue
  where queue_id = 1
)
select a.agent_id, b.id
from a
cross join (
  select *, row_number() over (order by t.id desc) rn
  from cc_member_attempt t
  where t.hangup_at = 0 and t.agent_id isnull
) b
where b.queue_id = a.queue_id;




with recursive r as (
  select a.id, a.agent_id, a.queue_id, 0 k
  from cc_member_attempt a
  where a.hangup_at = 0 and a.agent_id isnull
  --order by a.id asc
  --limit 1
  union all
  select r.id, r.agent_id, r.queue_id, r.k + 1
  from r
)
select *
from r
where r.k = 1
limit 100;