

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

vacuum analyze cc_agent_state_history;


explain analyze
    SELECT timeout_at
    FROM cc_agent_state_history h
    WHERE h.agent_id=100
    ORDER BY h.joined_at DESC--, h.timeout_at desc
    LIMIT 1;


explain (analyze, verbose, buffers, timing, format text )
SELECT id, timeout_at,
       case when status = 'online' then 'waiting' else status end, status_payload FROM (
 SELECT
  (
    SELECT h.timeout_at
    FROM cc_agent_state_history h
    WHERE h.agent_id=t.id
    ORDER BY h.joined_at DESC
    LIMIT 1
  ) as timeout_at,
   t.id,
   t.status,
   t.status_payload
 FROM cc_agent AS t
 WHERE t.status in  ('online', 'pause')
 OFFSET 0
)  as _t
where timeout_at notnull
;

explain (analyze, verbose, buffers, timing, format json )
select a.id, h.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload
from cc_agent a,lateral (
    select h.timeout_at
    from cc_agent_state_history h
    where h.agent_id = a.id
    order by h.joined_at desc
    limit 1
) h
where  a.status in  ('online', 'pause') and h.timeout_at < now();



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
  where aq.queue_id = 2 and not COALESCE(aq.agent_id, csia.agent_id) isnull
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
order by pos asc;
;


explain analyze
select count(*)
  from cc_member_attempt
where hangup_at = 0 and not agent_id isnull ;


drop function cc_distribute_agent_to_attempt;

CREATE OR REPLACE FUNCTION cc_distribute_agent_to_attempt(_node_id varchar(20))
  RETURNS SETOF cc_agent_in_attempt AS
$$
declare
  rec RECORD;
  agents bigint[];
  reserved_agents bigint[] := array[0];
  at cc_agent_in_attempt;
  counter int := 0;
BEGIN
FOR rec IN select cq.id::bigint queue_id, cq.strategy::varchar(50), count(*)::int as cnt,
                     array_agg((a.id, la.agent_id)::cc_agent_in_attempt order by a.created_at asc, a.weight desc )::cc_agent_in_attempt[] ids, array_agg(distinct la.agent_id) filter ( where not la.agent_id isnull )  last_agents
           from cc_member_attempt a
            inner join cc_queue cq on a.queue_id = cq.id
            left join lateral (
             select a1.agent_id
             from cc_member_attempt a1
             where a1.member_id = a.member_id and a1.created_at < a.created_at
             order by a1.created_at desc
             limit 1
           ) la on true
           where a.hangup_at = 0 and a.agent_id isnull and a.state = 3
           group by cq.id
           order by cq.priority desc
   LOOP

    select cc_available_agents_by_strategy(rec.queue_id, rec.strategy, rec.cnt, rec.last_agents, reserved_agents)
    into agents;

    counter := 0;
    foreach at IN ARRAY rec.ids
    LOOP
      if array_length(agents, 1) isnull then
        exit;
      end if;

      counter := counter + 1;

      if at.agent_id isnull OR not (agents && array[at.agent_id]) then
        at.agent_id = agents[array_upper(agents, 1)];
      end if;

      select agents::int[] - at.agent_id::int, reserved_agents::int[] || at.agent_id::int
      into agents, reserved_agents;

      return next at;
    END LOOP;
   END LOOP;

   --raise notice '%', reserved_agents;

  return;
END;
$$ LANGUAGE 'plpgsql';


update cc_member_attempt a
set agent_id = r.agent_id
from (
  select r.agent_id, r.attempt_id, a2.updated_at
  from cc_distribute_agent_to_attempt() r
  inner join cc_agent a2 on a2.id = r.agent_id
) r
where a.id = r.attempt_id
returning a.id as attempt_id, a.agent_id as agent_id, r.updated_at agent_updated_at;


CREATE TYPE   cc_agent_in_attempt AS (attempt_id bigint, agent_id bigint);

DO
$do$
DECLARE
  rec RECORD;
  agents bigint[];
  at cc_agent_in_attempt;
  counter int := 0;
BEGIN
   FOR rec IN select cq.id::bigint queue_id, cq.strategy::varchar(50), count(*)::int as cnt,
                     array_agg((a.id, la.agent_id)::cc_agent_in_attempt order by a.created_at asc, a.weight desc )::cc_agent_in_attempt[] ids, array_agg(distinct la.agent_id) filter ( where not la.agent_id isnull )  last_agents
           from cc_member_attempt a
            inner join cc_queue cq on a.queue_id = cq.id
            left join lateral (
             select a1.agent_id
             from cc_member_attempt a1
             where a1.member_id = a.member_id and a1.created_at < a.created_at
             order by a1.created_at desc
             limit 1
           ) la on true
           where a.hangup_at = 0 and a.agent_id isnull and a.state = 3
           group by cq.id
           order by cq.priority desc
   LOOP

    select cc_available_agents_by_strategy(rec.queue_id, rec.strategy, rec.cnt, rec.last_agents)
    into agents;

    counter := 0;
    foreach at IN ARRAY rec.ids
    LOOP
      if array_length(agents, 1) isnull then
        exit;
      end if;

      counter := counter + 1;

      if at.agent_id isnull OR not (agents && array[at.agent_id]) then
        at.agent_id = agents[array_upper(agents, 1)];
      end if;

      select agents::int[] - at.agent_id::int
      into agents;

      rec.ids[counter] = at;
--       RAISE NOTICE '% %', t, agents;
    END LOOP;

    RAISE NOTICE '%', rec.ids;
   END LOOP;
END
$do$;


select *
from cc_agent
where status = 'online';



update cc_agent
set status = 'online'
where id in (select id from cc_agent where status != 'online' limit 4);


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