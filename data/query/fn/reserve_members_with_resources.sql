
drop function reserve_members_with_resources;

/*
-- потестити апдейт!!!
*/

CREATE OR REPLACE FUNCTION reserve_members_with_resources(node_id varchar(20))
RETURNS integer AS $$
DECLARE
    rec RECORD;
    count integer;
    v_cnt integer;
BEGIN
    count = 0;
    FOR rec IN SELECT r.*, array_agg(cqt.communication_id) as type_ids
      from get_free_resources() r
        inner join cc_queue q on q.id = r.queue_id
        inner join cc_queue_timing cqt on q.id = cqt.queue_id
      where r.call_count > 0
      group by r.queue_id, resource_id, routing_ids, call_count, r.sec_between_retries, q.id
      order by q.priority desc
    LOOP
      insert into cc_member_attempt(communication_id, queue_id, member_id, resource_id, routing_id, node_id)
      select t.communication_id, rec.queue_id, t.member_id, rec.resource_id, t.routing_id, node_id
      from (
        select
               c.*,
              (c.routing_ids & rec.routing_ids)[1] as routing_id,
               row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d
        from (
          select c.id as communication_id, c.routing_ids, c.last_hangup_at, c.priority, c.member_id
          from cc_member cm
           cross join cc_member_communications c
              where
                not exists(
                  select *
                  from cc_member_attempt a
                  where a.member_id = cm.id and a.state > 0
                )
                and cm.last_hangup_at < ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint
                                          - (rec.sec_between_retries  * 60 * 1000)
                and cm.stop_at = 0
                and cm.queue_id = rec.queue_id
                and c.member_id = cm.id
                and c.state = 0
                and c.routing_ids && rec.routing_ids

            order by cm.priority desc
          limit rec.call_count * 3 --todo 3 is avg communication count
        ) c
      ) t
      where t.d =1
      limit rec.call_count;

      get diagnostics v_cnt = row_count;
      count = count + v_cnt;
    END LOOP;
    return count;
END;
$$ LANGUAGE plpgsql;

select *
from cc_member_attempt
order by id desc
limit 100

;

update cc_member
set stop_at = 0
where 2= 2;

update cc_member_attempt
set state = 0
where id in (select a.id
from cc_member_attempt a
where a.state = 5
order by id desc
limit 200)
returning id;


select *
from pg_stat_activity;

CREATE OR REPLACE FUNCTION reserve_members_with_resources(node_id varchar(20))
RETURNS integer AS $$
DECLARE
    rec RECORD;
    count integer;
    v_cnt integer;
BEGIN
    count = 0;
    FOR rec IN SELECT r.*, array_agg(cqt.communication_id) as type_ids
      from get_free_resources() r
        inner join cc_queue q on q.id = r.queue_id
        inner join cc_queue_timing cqt on q.id = cqt.queue_id
      where r.call_count > 0
      group by r.queue_id, resource_id, routing_ids, call_count, r.sec_between_retries, q.id
      order by q.priority desc
    LOOP
      insert into cc_member_attempt(communication_id, queue_id, member_id, resource_id, routing_id, node_id)
      select c.communication_id, rec.queue_id, m.id, rec.resource_id, c.routing_id, node_id
       from cc_member m
          inner join lateral (
            select
                   c.id as communication_id,
                   (c.routing_ids & rec.routing_ids)[1] as routing_id,
                   c.routing_ids as routing_ids
            from cc_member_communications c
            where c.member_id = m.id and c.state = 0 and (c.communication_id is null)
            order by c.last_hangup_at, c.priority desc
            limit 1
          ) c on true
        where m.queue_id = rec.queue_id and m.stop_at = 0 and c.routing_ids && rec.routing_ids
             and not exists(select 1
                   from cc_member_attempt a
                   where a.member_id = m.id
                     and (a.state > 0 or
                          a.hangup_at >
                          (((date_part('epoch'::text, now()) * (1000)::double precision))::bigint) - (rec.sec_between_retries * 60 * 1000)
                     )
                   limit 1
              )
              and exists(select *
                         from cc_member_communications c1
                         where c1.member_id = m.id and c1.state = 0 and c1.routing_ids && rec.routing_ids)

        order by m.priority desc
        limit rec.call_count;

      get diagnostics v_cnt = row_count;
      count = count + v_cnt;
    END LOOP;
    return count;
END;
$$ LANGUAGE plpgsql;

explain analyse
select *
from reserve_members_with_resources('tst');

truncate table cc_member_attempt;

select count(*)
from cc_member_attempt;

delete from cc_member_attempt
where node_id = 'tst';

select *
from cc_member where id = 12663;

vacuum full cc_member_communications;

explain (analyse, buffers, timing )
  select *
  from cc_member m
       inner join lateral (
           select *
           from cc_member_communications c
           where c.state = 0
             and c.member_id = m.id
             and c.routing_ids && array [26,1,2,4]
           order by c.last_hangup_at asc, c.priority desc
       ) c on true
  where m.stop_at = 0
    and m.queue_id = 1
    and not exists(select 1
         from cc_member_attempt a
         where a.member_id = m.id
           and (a.state > 0 or
                a.hangup_at >
                (((date_part('epoch'::text, now()) * (1000)::double precision))::bigint) - (60000000::bigint * 60 * 1000)::bigint
           )
      )
      and exists(select *
                 from cc_member_communications c1
                where c1.member_id = m.id and c1.state = 0 and c1.routing_ids && array [26,1,2,4])
  order by m.priority desc
  limit 100;

select *
from cc_queue_timing;


explain analyse
select count(*)
from cc_member_communications c
  join cc_member cm on c.member_id = cm.id
  left join lateral (
    select *
    from cc_queue_timing t
    where t.queue_id = cm.queue_id and t.communication_id = c.communication_id
    limit  1
  ) t on true
;


explain analyse
select c.id, c.member_id, row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc ) d
from cc_member_communications c
where c.state = 0 and c.routing_ids && array[26];

explain analyse
select *
from (
  select c.id, c.member_id, row_number() over (partition by c.member_id order by c.member_id ) d
  from cc_member_communications c
  where c.state = 0 and c.routing_ids && array[26]
  order by c.last_hangup_at, c.priority desc
) t
where t.d =1
limit 100;

vacuum full cc_member_attempt;

explain analyse
select *
from (
  select
         c.*,
        (c.routing_ids & array[26,1,2,4])[1] as routing_id,
         row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d
  from (
    select c.*
    from cc_member cm
     cross join cc_member_communications c
    where
      not exists(
        select *
        from cc_member_attempt a
        where a.member_id = cm.id and a.state > 0
      )
      and cm.last_hangup_at < ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint - (1 * 60 * 1000)
      and cm.stop_at = 0
      and cm.queue_id = 1
      and c.member_id = cm.id
      and c.state = 0
      and c.routing_ids && array[26,1,2,4]

    order by cm.priority desc
    limit 150
  ) c
) t
where t.d =1
limit 50;

vacuum full cc_member_communications;


explain analyse
  select *
    from cc_member cm
     cross join cc_member_communications c
    where
      not exists(
        select *
        from cc_member_attempt a
        where a.member_id = cm.id and a.state = 0
      )
      and cm.stop_at = 0
      and cm.queue_id = 1
      and cm.last_hangup_at < ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint
      and c.member_id = cm.id
      and c.state = 0
      and c.routing_ids && array[26,1,2,4]

    order by cm.priority desc
    limit 999;


vacuum full cc_member;



update cc_member
set last_hangup_at = 0
where 1= 1;


update cc_member m
set last_hangup_at = t.hangup_at
from (
  select m.id, a.hangup_at
  from cc_member m,
  lateral ( select * from cc_member_attempt a where a.member_id = m.id limit 1) a

) t
where m.id = t.id;

select count(*)
from cc_member
where last_hangup_at > 0;


select *
from cc_member_attempt;

select *
from cc_member_attempt
where member_id = 11;

select *
from cc_member where last_hangup_at > 0;

explain analyse
select cm.priority as member_priority, c.*
from cc_member cm
  inner join cc_member_communications c on c.member_id = cm.id
where cm.stop_at = 0 and c.state = 0
order by cm.priority desc
limit 100;


drop view vw_test_comm;
CREATE VIEW vw_test_comm AS
select cm.priority as member_priority, c.*
from cc_member cm
  inner join cc_member_communications c on c.member_id = cm.id
where cm.stop_at = 0 and c.state = 0
order by cm.priority desc;


explain analyse
select cm.priority as member_priority, c.*
from cc_member cm
  CROSS JOIN cc_member_communications c
where cm.stop_at = 0 and c.member_id = cm.id
order by cm.priority desc
limit 100;


select *
from cc_member_attempt;

select count(*)
from cc_member_attempt;


explain analyse
select *
from cc_member_communications c
,lateral (
  select count(*) cnt
  from cc_member_attempt a
  where a.communication_id = c.id and extract('doy' from a.hangup_time) =  extract('doy' from current_timestamp)
) a;

explain analyse
select *
from cc_member_communications c
where c.state = 0
order by c.last_hangup_at, c.priority desc;

vacuum full cc_member_communications;

update cc_member_communications
set communication_id = 1
where 1= 1;

select (((date_part('epoch'::text, now()) * (1000)::double precision))::bigint) + (360000::bigint * 60 * 1000)::bigint;


select *
from cc_member_attempt
order by id desc;


-- обговорити кейси...
explain analyse
select *
from cc_member m
join (
  select id, member_id, routing_ids,
         row_number() over (partition by c1.member_id order by c1.last_hangup_at, c1.priority desc) rn
  from cc_member_communications c1
  where c1.state = 0
) c on (c.member_id = m.id) and c.rn = 1
where m.stop_at = 0 and c.routing_ids && array[27]
order by m.priority desc ;


explain analyse
select *
from cc_member m
  inner join cc_tst cc on m.id = cc.member_id
where m.stop_at = 0
order by m.priority desc
limit 1000;


explain analyse
select *
from cc_tst cc
  inner join cc_member m on m.id = cc.member_id
  inner join cc_member_communications c on c.id = cc.communication_id
where m.queue_id = 1
order by cc.position asc
limit 1000;


explain analyse
select *
from cc_member_communications c
where c.state = 0 and 27 in(c.routing_ids);

insert into cc_test_r (communication_id, routing_id)
select c.id, unnest(c.routing_ids)
from cc_member_communications c;


drop index cc_test_r_routing_id_communication_id_uindex;
CLUSTER cc_test_r USING cc_test_r_routing_id_communication_id_uindex;
CREATE INDEX cc_test_r_communication_id_index ON cc_test_r USING hash (communication_id);

explain analyse
select c.*
from cc_member_communications c
where exists(select 1 from cc_test_r r
      where r.routing_id = 27 and r.communication_id = c.id)
limit 1;


vacuum full cc_test_r;



select count(*)
from cc_tst
group by member_id
having count(*) > 1;



--where t.rn = 1;


vacuum full cc_member_communications;

select *
from cc_member_attempt
order by id desc ;

select count(*)
from cc_member_communications
where state > 0 ;


update cc_member
set stop_at = 0
where 1 = 1;

update cc_member_communications
set state = 0
where 1= 1;


vacuum full cc_member_communications;
vacuum full cc_member;


select count(*)
from cc_member
where stop_at != 0 ;

select pg_relation_size('cc_member_queue_id_last_hangup_at_priority_index');





explain analyse
select count(*)
from cc_member_attempt a
where a.queue_id = 1 and a.hangup_at = 0;


select *
from reserve_members_with_resources('ddd');


vacuum full cc_member;
vacuum full cc_member_communications;
vacuum full cc_member_attempt;

select *
from cc_member
where id = 81;

update cc_member_communications
set state = 0
where 81 = 81;
update cc_member
set stop_at = 0
where 81 = 81;


DO
$do$
DECLARE
  rec RECORD;
BEGIN
   FOR rec IN select *
    from get_free_resources()
     where call_count > 0
   LOOP
     perform from cc_member m,
      lateral (
       select *
       from cc_member_communications c
       where c.state = 0 and c.member_id = m.id and c.routing_ids && rec.routing_ids
       limit 1
      ) c
    where m.stop_at = 0 and m.queue_id = 1
      and exists(select * from cc_member_communications c1 where c1.member_id = m.id and c1.state = 0 and c1.routing_ids && rec.routing_ids)
    order by m.priority desc
    limit rec.call_count * 100;
     raise notice '%', rec.routing_ids;
   END LOOP;
END
$do$;



-- vacuum full cc_tst;
-- truncate table cc_tst;
explain analyse
select c.*
from cc_tst c
  inner join cc_member m on m.id = c.member_id and m.stop_at = 0
  inner join cc_member_communications cmc on cmc.id = c.communication_id
where m.queue_id = 1 and
      not exists(select * from cc_member_attempt a where a.hangup_at = 0 and a.member_id = c.member_id)
order by c.position asc
limit 10;


explain analyse
delete from cc_tst
where member_id in (select id from cc_member where stop_at > 0 );




delete from cc_tst where member_id = 50036
