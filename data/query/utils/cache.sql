create extension pageinspect;


CREATE FUNCTION heap_page(relname text, pageno integer)
RETURNS TABLE(ctid tid, state text, xmin text, xmax text, hhu text, hot text, t_ctid tid)
AS $$
SELECT (pageno,lp)::text::tid AS ctid,
       CASE lp_flags
         WHEN 0 THEN 'unused'
         WHEN 1 THEN 'normal'
         WHEN 2 THEN 'redirect to '||lp_off
         WHEN 3 THEN 'dead'
       END AS state,
       t_xmin || CASE
         WHEN (t_infomask & 256) > 0 THEN ' (c)'
         WHEN (t_infomask & 512) > 0 THEN ' (a)'
         ELSE ''
       END AS xmin,
       t_xmax || CASE
         WHEN (t_infomask & 1024) > 0 THEN ' (c)'
         WHEN (t_infomask & 2048) > 0 THEN ' (a)'
         ELSE ''
       END AS xmax,
       CASE WHEN (t_infomask2 & 16384) > 0 THEN 't' END AS hhu,
       CASE WHEN (t_infomask2 & 32768) > 0 THEN 't' END AS hot,
       t_ctid
FROM heap_page_items(get_raw_page(relname,pageno))
ORDER BY lp;
$$ LANGUAGE SQL;



CREATE FUNCTION index_page(relname text, pageno integer)
RETURNS TABLE(itemoffset smallint, ctid tid)
AS $$
SELECT itemoffset,
       ctid
FROM bt_page_items(relname,pageno);
$$ LANGUAGE SQL;


select *
from cc_member_attempt
order by created_at desc ;

vacuum full verbose cc_agent;

SELECT * FROM heap_page('cc_agent',0);

update cc_agent
set status = 'offline'
where 1=1;



select s as count
from reserve_members_with_resources('test') s;

explain analyse
select a.attempt_id, a.agent_id, a.agent_updated_at
from cc_reserved_agent_for_attempt('test') a;

vacuum full cc_agent_status_history_agent_id_join_at_index;

explain (analyse, format json )
with tmp as (
  select *,
         row_number() over (partition by tmp.queue_id order by tmp.queue_id) rn --TODO strategy
  from (
         select distinct on (a.agent_id) a.agent_id, a.queue_id
         from available_agent_in_queue a
         order by a.agent_id, a.ratio desc
       ) tmp
)
select r.id as attempt_id, r.queue_id, tmp.agent_id
from (
       select *, row_number() over (partition by queue_id order by created_at) rn
       from cc_member_attempt a
       where a.hangup_at = 0
         and a.state = 3
         and a.agent_id isnull
     ) r
       inner join tmp on r.queue_id = tmp.queue_id and r.rn = tmp.rn;



vacuum full cc_agent_state_history;

explain (analyse, timing, buffers , format json )
select distinct on (a.agent_id) a.agent_id, a.queue_id
from available_agent_in_queue a
order by a.agent_id, a.ratio desc;


explain analyze
  select a.agent_id, a.queue_id
  from available_agent_in_queue a
  where a.queue_id = 2
  order by a.agent_id, a.ratio desc;


explain analyze
select
  aq.queue_id,
  array_agg(aq.agent_id order by aq.lvl desc) filter ( where aq.agent_id notnull ) ags,
  array_agg(aq.skill_id order by aq.lvl desc) filter ( where aq.skill_id notnull ) sks
from cc_agent_in_queue aq
where aq.queue_id = 2
group by aq.queue_id;

explain analyze
select aq.agent_id
from cc_agent_in_queue aq
where aq.queue_id = 2 and aq.agent_id notnull

union all

select sa.agent_id
from cc_skill_in_agent sa
where sa.skill_id in (

)
;


explain analyze
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
       --where not COALESCE(aq.agent_id, csia.agent_id) isnull
       group by aq.queue_id, COALESCE(aq.agent_id, csia.agent_id)
) ag
inner join cc_agent a on a.id = ag.agent_id
-- left join lateral ( -- TODO
--   select h.state
--   from cc_agent_state_history h
--   where h.agent_id = ag.agent_id
--   order by h.joined_at desc
--   limit 1
-- ) s on true
where a.status = 'online';

explain (analyze )
select *
from (
  select
   distinct aq.queue_id,
        COALESCE(aq.agent_id, csia.agent_id) as agent_id,
        COALESCE(max(csia.capacity), 0) max_of_capacity,
        max(aq.lvl) max_of_lvl
  from cc_agent_in_queue aq
        left join cc_skils cs on aq.skill_id = cs.id
        left join cc_skill_in_agent csia on cs.id = csia.skill_id
  where aq.queue_id = 2 and not COALESCE(aq.agent_id, csia.agent_id) isnull
  group by aq.queue_id, COALESCE(aq.agent_id, csia.agent_id)
  --order by COALESCE(aq.agent_id, csia.agent_id)
) t
inner join cc_agent a  on t.agent_id = a.id
where a.status = 'online'
order by t.max_of_lvl desc, t.max_of_capacity desc;


explain (analyze, format text )
select t.agent_id, t.queue_id, row_number() over (partition by t.queue_id order by t.max_of_lvl desc, t.max_of_capacity desc) pos
from cc_agent a
inner join (
  select
   aq.queue_id,
--         row_number() over (partition by aq.queue_id order by max(aq.lvl) desc, COALESCE(max(csia.capacity), 0) desc) as rn
        COALESCE(aq.agent_id, csia.agent_id) as agent_id,
        COALESCE(max(csia.capacity), 0) max_of_capacity,
        max(aq.lvl) max_of_lvl
  from cc_agent_in_queue aq
        left join cc_skill_in_agent csia on aq.skill_id = csia.skill_id
  where not COALESCE(aq.agent_id, csia.agent_id) isnull
  group by aq.queue_id, COALESCE(aq.agent_id, csia.agent_id)
) t on t.agent_id = a.id
where a.status = 'online'
order by t.queue_id, t.max_of_lvl desc, t.max_of_capacity desc;



--OK
explain (analyze, format text )
select at.id, at.queue_id, a.agent_id
from (
     select at.id, at.queue_id, row_number() over (partition by at.queue_id order by at.created_at asc) pos
      from cc_member_attempt at
      where at.hangup_at = 0 and at.state = 3 and at.agent_id isnull
      order by created_at desc
 ) at
inner join (
  select t.agent_id, a.updated_at, t.queue_id, row_number() over (partition by t.queue_id order by t.max_of_lvl desc, t.max_of_capacity desc) pos
  from cc_agent a
  inner join (
    select
     aq.queue_id,
  --         row_number() over (partition by aq.queue_id order by max(aq.lvl) desc, COALESCE(max(csia.capacity), 0) desc) as rn
          COALESCE(aq.agent_id, csia.agent_id) as agent_id,
          COALESCE(max(csia.capacity), 0) max_of_capacity,
          max(aq.lvl) max_of_lvl
    from cc_agent_in_queue aq
          left join cc_skill_in_agent csia on aq.skill_id = csia.skill_id
    where not COALESCE(aq.agent_id, csia.agent_id) isnull
    group by aq.queue_id, COALESCE(aq.agent_id, csia.agent_id)
  ) t on t.agent_id = a.id
  where a.status = 'online'
) a on at.queue_id = a.queue_id and at.pos = a.pos;


vacuum full cc_agent_state_history;

explain analyze
select *
from cc_agent a
left join lateral (
  select h.state
  from cc_agent_state_history h
  where h.agent_id = a.id and h.joined_at > current_date - '7 day'::interval
  order by h.joined_at desc
  limit 1
) h on true
where a.status = 'online' and (h.state = 'waiting' );

select count(*)
from cc_agent_state_history;



explain analyze
select *
from (
  select a.id, (select state from cc_agent_state_history h where h.agent_id = a.id order by joined_at desc limit 1)
  from cc_agent a
  where a.status = 'online'
) a
where a.state = 'waiting1';

explain analyze
select h.joined_at
  from cc_agent_state_history h
  where h.agent_id = 10 and joined_at > current_date
  order by h.joined_at desc
  limit 1;

explain analyze
select *
from cc_agent_state_history
where joined_at > current_date;



/*
	AGENT_STRATEGY_LONGEST_IDLE_TIME = "longest-idle-time" // + lvl asc, sum_idle_of_day desc,
	AGENT_STRATYGY_LEAST_TALK_TIME   = "least-talk-time"   // + lvl asc, last_bridge_end_at asc

	AGENT_STRATYGY_ROUND_ROBIN  = "round-robin"  // + lvl asc, last_offering_call_at asc
	AGENT_STRATYGY_TOP_DOWN     = "top-down"     // +
	AGENT_STRATYGY_FEWEST_CALLS = "fewest-calls" // + lvl asc, calls_answered asc
	AGENT_STRATYGY_RANDOM       = "random"       // + lvl asc, random()
 */


select *
from cc_agent a
inner join lateral (
  select *
  from cc_agent_state_history h
  where h.agent_id = a.id
  order by h.joined_at desc
  limit 1
) h on true
where a.id = 2;


select count(*
  )
from cc_agent;



select count(*)
from cc_member_attempt;

explain (analyze, COSTS, buffers ,format text )
select a.id
from cc_agent a
inner join (
  select
   COALESCE(aq.agent_id, csia.agent_id) as agent_id,
   COALESCE(max(csia.capacity), 0) max_of_capacity,
   max(aq.lvl) max_of_lvl
  from cc_agent_in_queue aq
    left join cc_skill_in_agent csia on aq.skill_id = csia.skill_id
  where aq.queue_id = 1 and not COALESCE(aq.agent_id, csia.agent_id) isnull
  group by COALESCE(aq.agent_id, csia.agent_id)
  --order by max(aq.lvl) desc, COALESCE(max(csia.capacity), 0) desc
) t on t.agent_id = a.id
inner join cc_agent_activity ac on t.agent_id = ac.agent_id
-- inner join lateral (
--   select h.state
--   from cc_agent_state_history h
--   where h.agent_id = t.agent_id --and h.joined_at > current_date - '2 day'::interval
--   order by h.joined_at desc
--   limit 1
-- ) h on true
where a.status = 'online' and a.state = 'waiting'
  and not exists(select 1 from cc_member_attempt at where at.state > 0 and at.agent_id = a.id)
  --and h.state = 'waiting'
order by
 --array_position(array[1, 968, 962, 967], a.id) asc nulls last,
 t.max_of_lvl desc, t.max_of_capacity desc,
 ac.last_offering_call_at asc
limit 8;


update cc_agent
set status = 'online'
where id in (
  select id
  from cc_agent a
  where a.status = 'online'
  limit 200
  );


select array[1,2,3,4]::bigint[] @> array[10]::bigint[];

select oprname, oprleft::regtype, oprright::regtype, oprresult::regtype--, *
from pg_operator
where oprname in ('@>', '&&');



select a.id
from cc_agent a
inner join (
  select
   COALESCE(aq.agent_id, csia.agent_id) as agent_id,
   COALESCE(max(csia.capacity), 0) max_of_capacity,
   max(aq.lvl) max_of_lvl
  from cc_agent_in_queue aq
    left join cc_skill_in_agent csia on aq.skill_id = csia.skill_id
  where aq.queue_id = 1 and not COALESCE(aq.agent_id, csia.agent_id) isnull
  group by COALESCE(aq.agent_id, csia.agent_id)
  --order by max(aq.lvl) desc, COALESCE(max(csia.capacity), 0) desc
) t on t.agent_id = a.id
inner join cc_agent_activity ac on t.agent_id = ac.agent_id
inner join lateral (
  select h.state
  from cc_agent_state_history h
  where h.agent_id = t.agent_id --and h.joined_at > current_date - '2 day'::interval
  order by h.joined_at desc
  limit 1
) h on true
where a.status = 'online'
  and not exists(select 1 from cc_member_attempt at where at.state > 0 and at.agent_id = a.id)
  and h.state = 'waiting'
  and not (array[0]::bigint[] && array[a.id]::bigint[])
order by
 --a.id,
 case when array[1::bigint] && array[a.id::bigint] then 1 else null end asc nulls last,
 t.max_of_lvl desc, t.max_of_capacity desc,
 ac.last_offering_call_at asc
limit 10;




drop function cc_available_agents_by_strategy;

CREATE OR REPLACE FUNCTION cc_available_agents_by_strategy(_queue_id bigint, _strategy varchar(50),
_limit int, _last_agents bigint[], _except_agents bigint[])
  RETURNS SETOF int[] AS
$$
BEGIN
  return query select ARRAY(
    select a.id
    from cc_agent a
    inner join (
      select
       COALESCE(aq.agent_id, csia.agent_id) as agent_id,
       COALESCE(max(csia.capacity), 0) max_of_capacity,
       max(aq.lvl) max_of_lvl
      from cc_agent_in_queue aq
        left join cc_skill_in_agent csia on aq.skill_id = csia.skill_id
      where aq.queue_id = _queue_id and not COALESCE(aq.agent_id, csia.agent_id) isnull
      group by COALESCE(aq.agent_id, csia.agent_id)
      --order by max(aq.lvl) desc, COALESCE(max(csia.capacity), 0) desc
    ) t on t.agent_id = a.id
    inner join cc_agent_activity ac on t.agent_id = ac.agent_id
    where a.status = 'online' and a.state = 'waiting'
      and not exists(select 1 from cc_member_attempt at where at.state > 0 and at.agent_id = a.id)
      and not (_except_agents::bigint[] && array[a.id]::bigint[])
    order by
     --a.id,
     case when _last_agents && array[a.id::bigint] then 1 else null end asc nulls last,
     t.max_of_lvl desc, t.max_of_capacity desc,
     ac.last_offering_call_at asc
    limit _limit

  );
END;
$$ LANGUAGE 'plpgsql';


explain analyze
select
from cc_agent a
where a.status = 'online' and a.state = 'waiting';

explain analyze
select cc_available_agents_by_strategy(1, '', 10, null, array[0]) a;



select count(*)
from cc_member_attempt
where state > 0;


select count(*)
from cc_member
where stop_at = 0;

select agent_id, count(*)
from cc_member_attempt
where hangup_at = 0
group by agent_id
having count(*)> 1;


explain (analyze, format json )
select a.id, h.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload
from cc_agent a
  ,lateral (
    select h.timeout_at
    from cc_agent_state_history h
    where h.agent_id = a.id
    order by h.joined_at desc
    limit 1
  ) h
where  a.status in  ('online', 'pause') and h.timeout_at < now();


update cc_agent
set status = 'online'
where 1=1;



explain analyze
select *
from (
  select a.id, s.*
  from cc_agent a
  left join lateral (
    select sa.skill_id, sa.capacity
    from cc_skill_in_agent sa
    where sa.agent_id = a.id
    order by sa.capacity desc

  ) s on true
--   left join lateral (
--     select h.state
--     from cc_agent_state_history h
--     where h.agent_id = a.id
--     order by h.joined_at desc
--     limit 1
--   ) st on true
  where a.status = 'online'-- and st.state = 'waiting'
    and s.skill_id in (2)
  --group by a.id
  order by s.capacity desc
) a
;

explain (analyze, format json )
select a.id
from cc_agent a
left join lateral (
    select h.state
    from cc_agent_state_history h
    where h.agent_id = a.id
    order by h.joined_at desc
    limit 1
) h on true
where a.status = 'online' and a.id in (
  select aq.agent_id
  from cc_agent_in_queue aq
  where aq.queue_id = 1 and not aq.agent_id isnull
  union distinct
  select sa.agent_id
  from cc_skill_in_agent sa
  where sa.skill_id in (
    select id from cc_agent_in_queue aq where aq.queue_id = 1 and not aq.skill_id isnull
  )
) and h.state = 'waiting';






select *
from cc_skill_in_agent;


explain (analyze, format json )
select
     array_agg(aq.agent_id order by aq.lvl desc) filter ( where aq.agent_id notnull ) ags,
     array_agg(aq.skill_id order by aq.lvl desc) filter ( where aq.skill_id notnull ) sks
from cc_agent_in_queue aq
where aq.queue_id = 2;



explain analyse
select a.id, h.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload
from cc_agent a
  ,lateral (
    select h.timeout_at
    from cc_agent_state_history h
    where h.agent_id = a.id
    order by h.joined_at desc
    limit 1
  ) h
where  a.status in  ('online', 'pause') and h.timeout_at < now();