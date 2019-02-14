explain (analyse ) select *, row_number() over (partition by crir_id)
                   from (
                          select c.cc_id as cc_id,
                                 m.id,
                                 c.pattern,
                                 c.number,
                                 c.crir_id
                          from cc_member m
                                 inner join lateral (
                            select id as cc_id,
                                   queue_id,
                                   number,
                                   communication_id,
                                   res.*
                            from cc_member_communications c
                                   inner join lateral (
                              select r.pattern, crir.id as crir_id
                              from cc_queue_routing r
                                     inner join cc_resource_in_routing crir on r.id = crir.routing_id
                                     inner join cc_outbound_resource cor on crir.resource_id = cor.id
                              where r.queue_id = m.queue_id
                                and c.number ~ r.pattern
                              order by r.priority, crir.priority
                              limit 1
                              ) res on true
                            where c.member_id = m.id
                              and c.state = 0

                            order by last_calle_at, priority
                            limit 1
                            ) as c on true
                        ) t
                   limit 300
--where rn < 10;

with t as (
  select 1 as n, gg as i
  from generate_series(0, 10) as gg
)
select t.i, max(t.n) as sumN, sum(t2.n) - max(t.n)
from t
       left outer join t as t2 on t.i < t2.i and t2.i < 5
group by t.i;


explain (analyse ) with c as (
  select id, number
  from cc_member_communications
  where exists(select * from cc_queue_routing where number ~ pattern)
  limit 10
)
                   select *, row_number() over (order by r.priority)
                   from c
                          cross join cc_queue_routing r
                   where c.number ~ r.pattern
;


SELECT *
FROM (
       SELECT *, ROW_NUMBER() OVER (ORDER BY id) as s
       FROM cc_member_communications
     ) x
WHERE s BETWEEN 7 AND 13;

select r.*
from cc_outbound_resource r;
;

select *
from cc_outbound_resource
       inner join cc_resource_in_routing crir on cc_outbound_resource.id = crir.resource_id
       inner join cc_queue_routing cqr on crir.routing_id = cqr.id;

--having sum(g.n) > 0;

select r.id, r.max_call_count, cq.id as qid, array_agg(cqr.pattern)
from cc_outbound_resource r
       inner join cc_resource_in_routing crir on r.id = crir.resource_id
       inner join cc_queue_routing cqr on crir.routing_id = cqr.id
       inner join cc_queue cq on cqr.queue_id = cq.id
group by r.id, r.max_call_count, cq.id, cqr.priority, crir.priority
order by cq.priority, cqr.priority, crir.priority;

select s, sum(s) over (order by s)
from generate_series(1, 10) as s
group by s
limit 30;


explain (analyse ) with recursive r as (
  select re.max_call_count as c, re.id as id, 0::text as cid
  from cc_outbound_resource re

  union

  select r.c - 1, r.id, a.number
  from r
         inner join lateral (
    select *
    from cc_member_communications
    where number != r.cid
    limit 1
    ) a on true
  where r.c > 0
)
                   select *
                   from r
                   order by r.id, r.c;

SELECT distinct id
FROM connectby('cc_member_communications', 'id', 'dependson', '4', 0)
       AS t(id int)
where id != 4;



reindex
  (VERBOSE)
  index calendar_accept_of_day_calendar_id_week_day_start_time_of_day_e



select m.cc_id                                       as communication_id,
       q.id                                          as queue_id,
       m.id,
       m.number,
       m.pattern,
       q.priority * 100 / (row_number() over (order by q.priority desc )),
       row_number() over (order by q.priority desc ) as rn
from cc_queue_is_working q
   , lateral (select case
                       when q.max_calls - q.active_calls <= 0
                         then 0
                       else q.max_calls - q.active_calls end) as qq(need_calls)
       inner join lateral (
  select c.cc_id as cc_id,
         m.id,
         c.number,
         r.pattern
  from cc_member m
         inner join lateral (
    select c.id as cc_id,
           queue_id,
           number,
           communication_id
    from cc_member_communications c
    where c.member_id = m.id
      and c.state = 0
      and last_calle_at <= q.sec_between_retries

    order by last_calle_at, c.priority
    limit 1
    ) as c on true
         inner join cc_queue_routing r on c.number ~ r.pattern

  where m.queue_id = q.id
    and not exists(select 1
                   from cc_member_attempt a
                   where a.member_id = m.id
                     and a.state = 0)
    --and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, m.id)
  order by m.priority asc
  limit 10 --qq.need_calls
  ) m on true
order by q.priority desc;


with t as (
  select *
  from cc_member_communications
  where number ~ '^1|^2|^3'
  order by id
  limit 10
)
;

explain (analyse )
select t2.*, r.*
from (
       select t.id, t.number, t.member_id
       from cc_member_communications as t
              --inner join cc_member m on m.id = t.member_id
              --inner join cc_queue q on q.id = m.queue_id
              --inner join cc_queue_routing r on r.queue_id = q.id and t.number ~ r.pattern
              --inner join cc_resource_in_routing crir on r.id = crir.routing_id
        where t.number ~ '^3'
        --limit 2

     ) as t2
        inner join cc_member m on m.id = t2.member_id
        inner join cc_queue q on q.id = m.queue_id
       inner join cc_queue_routing as r on r.queue_id = q.id and t2.number ~ r.pattern
limit 5;



select *
from cc_outbound_resource
       inner join cc_resource_in_routing crir on cc_outbound_resource.id = crir.resource_id
       inner join cc_queue_routing cqr on crir.routing_id = cqr.id
       inner join cc_queue cq on cqr.queue_id = cq.id


explain (analyse ) with recursive r as (
  select re.max_call_count as c, re.id as id, 0::text as cid
  from cc_outbound_resource re

  union

  select r.c - 1, r.id, a.number
  from r
         inner join lateral (
    select *
    from cc_member_communications
    where number != r.cid
    limit r.c
    ) a on true
  where r.c > 0
)
                   select *
                   from r
                   order by r.id, r.c;



select *
from cc_outbound_resource r
       left join lateral (
  select *
  from cc_member_communications

  limit r.max_call_count
  ) mem on true;
