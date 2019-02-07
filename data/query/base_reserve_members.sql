explain (analyze )
  select m.cc_id as communication_id,
         q.id    as queue_id,
         m.id,
         q.priority * 100 / (row_number() over (order by q.priority desc ))
  from cc_queue_is_working q
     , lateral (select case
                         when q.max_calls - q.active_calls <= 0
                           then 0
                         else q.max_calls - q.active_calls end) as qq(need_calls)
         inner join lateral (
    select c.cc_id as cc_id,
           m.id
    from cc_member m
           inner join lateral (
      select id as cc_id,
             queue_id,
             number,
             communication_id
      from cc_member_communications c
      where c.member_id = m.id
        and c.state = 0
        and last_calle_at <= q.sec_between_retries

      order by last_calle_at, priority
      limit 1
      ) as c on true

    where m.queue_id = q.id
      and not exists(select 1
                     from cc_member_attempt a
                     where a.member_id = m.id
                       and a.state = 0)
      --and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, m.id)
    order by m.priority asc
    limit qq.need_calls
    ) m on true
  order by q.priority desc;



explain (analyse ) select m.*
from cc_outbound_resource re
  inner join cc_resource_in_routing rr on rr.resource_id = re.id
  inner join cc_queue_routing qr on qr.id = rr.routing_id
  inner join cc_queue cq on qr.queue_id = cq.id
  inner join lateral (
    select c.cc_id as cc_id,
           m.id
    from cc_member m
           inner join lateral (
      select id as cc_id,
             queue_id,
             number,
             communication_id
      from cc_member_communications c
      where c.member_id = m.id
        and c.state = 0 and c.number ~ qr.pattern

      order by last_calle_at, priority
      limit 1
      ) as c on true

    where m.queue_id = cq.id
      and not exists(select 1
                     from cc_member_attempt a
                     where a.member_id = m.id
                       and a.state = 0)
      --and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, m.id)
    order by m.priority asc
    limit 10
    ) m on true
order by cq.priority;


explain (analyse ) select number
from cc_member_communications where number ~ '^5(\d+)$'
limit 100;


CREATE INDEX cc_member_communications_number_reg ON cc_member_communications USING gin (number gin_trgm_ops);


select regexp_matches('1', '^1');

select count(*)
from cc_member_attempt;

explain (analyse ) select *
                   from cc_queue_is_working;

UPDATE cc_member_attempt
SET state     = -1,
    hangup_at = 100
WHERE id in (
  SELECT id
  FROM cc_member_attempt
  WHERE state = 0
        --AND    pg_try_advisory_xact_lock(id)
  order by created_at desc, weight asc
  LIMIT 100
    FOR UPDATE
) RETURNING *;



CREATE OR REPLACE FUNCTION f_add_task_for_call()
  RETURNS integer AS
$func$
declare
  i_cnt integer;
BEGIN
  if pg_try_advisory_lock(77515154878) != true
  then
    return -1;
  end if;

  insert into cc_member_attempt (communication_id, queue_id, member_id, weight)

  select m.cc_id as communication_id,
         q.id    as queue_id,
         m.id,
         row_number() over (order by q.priority desc )
  from cc_queue_is_working q
     , lateral (select case
                         when q.max_calls - q.active_calls <= 0
                           then 0
                         else q.max_calls - q.active_calls end) as qq(need_calls)
         inner join lateral (
    select c.cc_id as cc_id,
           m.id
    from cc_member m
           inner join lateral (
      select id as cc_id,
             queue_id,
             number,
             communication_id
      from cc_member_communications c
      where c.member_id = m.id
        and c.state = 0
        and last_calle_at <= q.sec_between_retries
      order by last_calle_at, priority
      limit 1
      ) as c on true

    where m.queue_id = q.id
      and not exists(select 1
                     from cc_member_attempt a
                     where a.member_id = m.id
                       and a.state = 0)
      and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, m.id)
    order by m.priority asc
    limit qq.need_calls
    ) m on true
  order by q.priority desc;
  GET DIAGNOSTICS i_cnt = ROW_COUNT;

  RETURN i_cnt; -- true if INSERT
END
$func$
  LANGUAGE plpgsql;

vacuum cc_member_attempt;


drop function f_add_task_for_call;
explain ( analyze ) select *
                    from f_add_task_for_call();


select pg_advisory_unlock_all();

select *
from pg_locks
where locktype = 'advisory';

truncate table cc_member_attempt;


update cc_member_attempt
set hangup_at = 1
where hangup_at = 0;



explain (analyse )
  SELECT *
  FROM cc_member_attempt
  WHERE state = 0
    AND pg_try_advisory_xact_lock(id)
  order by created_at desc, weight asc
  LIMIT 10
    FOR UPDATE



select id as cc_id,
       number,
       communication_id
from cc_member_communications c,
     lateral ( select regexp_matches(c.number, r1.pattern) as tst from cc_queue_routing r1 ) res;
;
