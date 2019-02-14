explain (analyze )
  select m.cc_id                                       as communication_id,
         q.id                                          as queue_id,
         m.id,
         q.priority * 100 / (row_number() over (order by q.priority desc )),
         row_number() over (order by q.priority desc ) as rn
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
        and c.number ~ '.*'

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


explain (analyse ) select r.id,
                          qr.pattern,
                          r.max_call_count,
                          r.max_call_count - row_number() over (partition by qr.pattern)
                   from cc_outbound_resource r
                          join cc_outbound_resource r2 on r2.id = r.id
                          join cc_queue_routing qr on true
                   group by r.id, qr.pattern
;
;


explain (analyse ) select r.*
                   from cc_outbound_resource r
                          inner join lateral (
                     select *
                     from cc_queue q
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
                       order by m.priority asc
                       limit q.max_calls
                       ) m on true --m.queue_id = q.id
                     order by q.priority--, m.priority
                     limit 1
                     ) m on true;
--left join cc_member m on true;


explain (analyse ) select q.*
                   from cc_queue q
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
                     order by m.priority asc
                     limit q.max_calls
                     ) m on true --m.queue_id = q.id
                   order by q.priority--, m.priority
                   limit 10;

select *
from cc_queue_routing
       inner join cc_resource_in_routing crir on cc_queue_routing.id = crir.routing_id
       inner join cc_outbound_resource cor on crir.resource_id = cor.id
order by crir.priority desc
;

select *, sum(t.a) over (order by id rows between unbounded preceding and current row)
from cc_queue_routing,
     lateral ( select 100 as a) t
group by id
having sum(t.a) over (order by id rows between unbounded preceding and current row) < 100

select r.*, t.*
from cc_outbound_resource r
       inner join lateral (
  select *
  from cc_resource_in_routing rr
         inner join cc_queue_routing qr on qr.id = routing_id
  where rr.routing_id = r.id
  ) as t on true
;
CREATE EXTENSION tablefunc;

explain analyse select *
                from cc_outbound_resource r
                       inner join cc_resource_in_routing crir on r.id = crir.resource_id
--   inner join lateral (
--    select gid, r.max_call_count from generate_series(1, r.max_call_count) as gid
--    ) rr on true


explain (analyse ) select re.*, cq.*
                   from cc_queue_resources_is_working re
                          inner join cc_resource_in_routing rr on rr.resource_id = re.id
                          inner join cc_queue_routing qr on qr.id = rr.routing_id
                          inner join cc_queue cq on qr.queue_id = cq.id
                        --   inner join lateral (
                        --     select c.cc_id as cc_id,
                        --            m.id
                        --     from cc_member m
                        --            inner join lateral (
                        --       select id as cc_id,
                        --              queue_id,
                        --              number,
                        --              communication_id
                        --       from cc_member_communications c
                        --       where c.member_id = m.id
                        --         and c.state = 0 and c.number ~ qr.pattern
                        --
                        --       order by last_calle_at, priority
                        --       limit 1
                        --       ) as c on true
                        --
                        --     where m.queue_id = cq.id
                        --       and not exists(select 1
                        --                      from cc_member_attempt a
                        --                      where a.member_id = m.id
                        --                        and a.state = 0)
                        --       --and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, m.id)
                        --     order by m.priority asc
                        --     limit 10
                        --     ) m on true
                   order by cq.priority;


explain (analyse ) select number
                   from cc_member_communications
                   where number ~ '^5(\d+)$'
                   limit 100;


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



select id as cc_id,
       number,
       communication_id
from cc_member_communications c,
     lateral ( select regexp_matches(c.number, r1.pattern) as tst from cc_queue_routing r1 ) res;
;



explain (analyse ) select c.cc_id as cc_id,
                          m.id,
                          c.number,
                          c.rn,
                          c.resource_id
                   from cc_member m
                          inner join lateral (
                     select c.id                                                                           as cc_id,
                            queue_id,
                            number,
                            communication_id,
                            row_number() over (partition by c.id order by qr.priority, crir.priority desc) as rn,
                            crir.resource_id
                     from cc_member_communications c
                            inner join cc_queue_routing qr on qr.queue_id = m.queue_id and c.number ~ qr.pattern
                            inner join cc_resource_in_routing crir on qr.id = crir.routing_id
                     where c.member_id = m.id
                       and c.state = 0
                       and last_calle_at <= 10
                     order by last_calle_at, c.priority
                     --limit 1
                     ) as c on true --c.rn = 1
                        --inner join cc_outbound_resource r on r.id = c.resource_id
                        --order by number
                   limit 100;


select m.id, c.number, c.resource_id, m.queue_id, c.pattern
from cc_member m
       inner join lateral (
  select c.id                                                                           as cc_id,
         queue_id,
         number,
         communication_id,
         row_number() over (partition by c.id order by qr.priority, crir.priority desc) as rn,
         crir.resource_id,
         qr.pattern
  from cc_member_communications c
         inner join cc_queue_routing qr on qr.queue_id = m.queue_id and c.number ~ qr.pattern
         inner join cc_resource_in_routing crir on qr.id = crir.routing_id
         inner join cc_queue q on qr.queue_id = q.id
  where c.member_id = m.id
    and c.state = 0
    and last_calle_at <= 10
  order by q.priority asc, last_calle_at, c.priority, qr.priority, crir.priority

  ) as c on true;



explain (analyse )
  select m.*
  from (
         select m.cc_id                                                                               as communication_id,
                q.id                                                                                  as queue_id,
                m.id,
                m.number,
                r.pattern,
                rr.resource_id,
                row_number() over (partition by rr.resource_id order by q.priority, r.priority desc ) as rn
         from cc_queue_is_working q
                inner join cc_queue_routing r on r.queue_id = q.id
                inner join cc_resource_in_routing rr on rr.routing_id = r.id
            , lateral (select case
                                when q.max_calls - q.active_calls <= 0
                                  then 0
                                else q.max_calls - q.active_calls end) as qq(need_calls)

                inner join lateral (
           select c.cc_id as cc_id,
                  m.id,
                  c.number,
                  m.priority
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
               and c.number ~ r.pattern
             order by last_calle_at, priority
             limit 1
             ) as c on true

           where m.queue_id = q.id
             and not exists(select 1
                            from cc_member_attempt a
                            where a.member_id = m.id
                              and a.state = 0)
           order by m.priority asc
           limit qq.need_calls
           ) m on true

         order by q.priority, m.priority, r.priority, rr.priority desc
       ) as m
         inner join cc_queue qq on m.queue_id = qq.id
         inner join cc_outbound_resource ro on ro.id = m.resource_id
  where m.rn between 1 AND ro.max_call_count
  order by qq.priority desc;


explain (analyse )
  select m.*,
         cqr.pattern --,  array_agg(cqr.pattern)
  from cc_outbound_resource
         inner join cc_resource_in_routing crir on cc_outbound_resource.id = crir.resource_id
         inner join cc_queue_routing cqr on crir.routing_id = cqr.id
         inner join (
    select m1.id, m1.queue_id, c.number
    from cc_member m1
           inner join (
      select *
      from cc_member_communications as c
      where c.state = 0
      order by c.last_calle_at, c.priority
    ) as c on c.member_id = m1.id
  ) as m on m.queue_id = cqr.queue_id and m.number ~ cqr.pattern
  order by crir.priority
--group by cc_outbound_resource.id, cqr.queue_id, m.id
--limit 100;

explain (analyse )
  select c.number
  from cc_member_communications c
  where c.number ~ '^0000';

explain (analyse )
  select c.id
  from cc_member m
         inner join cc_member_communications c on c.member_id = m.id
  where c.state = 0
  order by c.last_calle_at, c.priority desc


vacuum cc_member_communications;

explain (analyse )
  select c.id
  from cc_member_communications c
         inner join cc_member m on m.id = c.member_id
  where c.state = 0
--order by c.last_calle_at, c.priority desc


explain (analyse )
  select *
  from cc_member m
         inner join lateral (
    select *
    from cc_member_communications c
    where c.member_id = m.id
      and c.state = 0
    limit 1
    ) as a on true;



explain (analyse )
  select *
  from (
         select *, row_number() over (partition by c.member_id order by c.last_calle_at, c.priority asc) as rn
         from cc_member_communications c
                inner join cc_member cm on c.member_id = cm.id
         where c.state = 0 --and c.number ~ '^1'
       ) c
  where c.rn = 1;


--where number ~ '^1232' ;
;
--order by m.priority
--limit 5;

explain (analyse )
  select *
  from cc_member m
  order by m.priority;



select r.*, rr
from cc_outbound_resource r,
     lateral (
       select *
       from cc_resource_in_routing rr
              inner join cc_queue_routing cqr on rr.routing_id = cqr.id
       where rr.resource_id = 1
       ) as rr
;

explain (analyse )
  select r.id, r.max_call_count, cqr.id, cqr.pattern, cqr.queue_id
  from cc_outbound_resource r
         inner join cc_resource_in_routing crir on r.id = crir.resource_id
         inner join cc_queue_routing cqr on crir.routing_id = cqr.id
;


drop index cc_member_communications_number_reg;
drop index cc_member_communications_number_reg_gin;
drop index cc_member_communications_number_reg_gist;
drop index cc_member_communications_number_reg_spgist;
CREATE INDEX cc_member_communications_number_reg_gin ON cc_member_communications using gin(number gin_trgm_ops) ;
CREATE INDEX cc_member_communications_number_reg_gist ON cc_member_communications using gist(number gist_trgm_ops) ;
CREATE INDEX cc_member_communications_number_reg_spgist ON cc_member_communications using spgist(number text_ops) ;
CREATE INDEX cc_member_communications_number_reg ON cc_member_communications (number varchar_pattern_ops, state);

ANALYZE cc_member_communications;
vacuum full;

explain (analyse )
select * from (
  select *
  from cc_member m
       inner join cc_member_communications c on c.member_id = m.id
  where c.state = 0 and c.number ~ '^1.*'
  order by c.last_calle_at, c.priority desc
) as t;


create extension btree_gin;
-- it is top for hunting but ^\+?3?8?0?3?2?(\d{7})$ large
-- походу сейвити і реплесити при зміні...
--CREATE INDEX cc_member_communications_number_reg_gin ON cc_member_communications using gin(number gin_trgm_ops) where state = 0 ;

explain (analyse )
select *
from cc_member m
inner join lateral (
  select *
  from cc_member_communications c
  where c.number ~ '^1z' and c.member_id = m.id and c.state = 0
  order by c.last_calle_at, c.priority
  limit 1
) c on true;

SELECT * FROM pg_stats
where tablename = 'cc_member_communications';

explain (analyse, BUFFERS) select *
   from cc_member_communications c1
   where  c1.number ~* '^\+?\d+$';

explain analyse select *, REGEXP_MATCHES('^112', number)
   from cc_member_communications c1;

insert into cc_member_communications (member_id, number, communication_id)
values (1, '+380320367300', null);

explain (analyse )
select m.id as mid, c.*
from cc_member m,
 lateral (
   select *
   from cc_member_communications c1
   where  c1.number ~ '^1' and c1.member_id = m.id and state = 0
 ) c
limit 10;


explain (analyse )
select *
from cc_member m
inner join (
  select c.*
  from cc_member_communications c
  where state = 0
) c on c.member_id = m.id
where m.queue_id = 1
order by m.id, c.last_calle_at, c.priority
offset 0;


update  cc_member_communications
set state = 0
where state = 1;


select *, row(cqr.pattern)
from cc_outbound_resource r
inner join cc_resource_in_routing crir on r.id = crir.resource_id
inner join cc_queue_routing cqr on crir.routing_id = cqr.id;




explain (analyse, buffers, timing )
select *
from cc_member_communications c
where ARRAY[9,57,8] && c.routing_ids::int[];