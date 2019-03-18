
drop function reserve_members_with_resources;

CREATE OR REPLACE FUNCTION reserve_members_with_resources(node_id varchar(20))
RETURNS integer AS $$
DECLARE
    rec RECORD;
    count integer;
    v_cnt integer;
BEGIN
    count = 0;
    FOR rec IN SELECT *
      from get_free_resources() r
        inner join cc_queue q on q.id = r.queue_id
      where r.call_count > 0
      order by q.priority desc
    LOOP
      insert into cc_member_attempt(communication_id, queue_id, member_id, resource_id, routing_id, node_id)
      select c.communication_id, rec.queue_id, m.id, rec.resource_id, c.routing_id, node_id
       from cc_member m
          ,lateral (
            select
                   c.id as communication_id,
                   (c.routing_ids & rec.routing_ids)[1] as routing_id
            from cc_member_communications c
            where c.member_id = m.id and c.state = 0 and c.routing_ids && rec.routing_ids
              --and c.last_hangup_at < ( ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint ) - (q.sec_between_retries * 1000)
            order by c.last_hangup_at, c.priority desc
            limit 1
          ) c
        where m.queue_id = rec.queue_id and m.stop_at = 0 and
              --not exists (select * from cc_member_attempt a where a.member_id = m.id and a.hangup_at = 0)
            not exists (select * from cc_member_attempt a
              where a.member_id = m.id --and (hangup_at + (rec.sec_between_retries * 1000))::bigint >  (date_part('epoch'::text, now()) * (1000)::double precision)::bigint
            )

        order by m.priority desc
        limit rec.call_count;

      get diagnostics v_cnt = row_count;
      count = count + v_cnt;
    END LOOP;
    return count;
END;
$$ LANGUAGE plpgsql;



select *
from reserve_members_with_resources('tst');

truncate table cc_member_attempt;

select *
from cc_member m
  inner join cc_member_communications cmc on m.id = cmc.member_id
where m.queue_id = 1 and m.id not in (select member_id from cc_member_attempt);



update cc_member_attempt
  set state = -1,
      hangup_at = 2
where 1 = 1;





vacuum (analyze, analyse) cc_member_communications;
ANALYZE VERBOSE cc_member_communications;
explain (analyse, BUFFERS, timing )
     select *
       from cc_member m
          inner join lateral (
            select
                   c.id as communication_id,
                   (c.routing_ids & array[1,16])[1] as routing_id,
                   c.member_id
            from cc_member_communications c
            where c.member_id = m.id and c.state = 0  and c.routing_ids && array[1,16]
            order by c.last_hangup_at asc, c.priority desc
            limit 1
          ) c on c.member_id = m.id
        where m.queue_id = 1 and m.stop_at = 0
                --and exists(select * from cc_member_communications g where g.member_id = m.id and g.state = 0)
              --and
              --and not exists (select * from cc_member_attempt a where a.member_id = m.id and a.hangup_at = 0)
            and not exists (select * from cc_member_attempt a
              where a.member_id = m.id --and (hangup_at + (5 * 1000))::bigint >  (date_part('epoch'::text, now()) * (1000)::double precision)::bigint
            )
        order by m.priority desc
        limit 10;

select *
from cc_member_communications
where member_id = 81;


SELECT name,setting FROM pg_settings WHERE name ~ 'autova|vacuum';

update cc_member
set stop_at = 0
where 1=1;

select *
from get_free_resources();

select *
from cc_member_attempt
--where member_id = 81
order by id ;


update cc_member_communications
set state = 0
where id in (
  select id
  from cc_member_communications
  where  state = 1
  order by random()
  limit 50000
  );

select count(*)
from cc_member_communications
where state = 0 and routing_ids && array[1,16];

explain analyse
SELECT *
      from get_free_resources() r
      where r.call_count > -1;

SELECT *
from reserve_members_with_resources('aaa') r;

truncate table cc_member_attempt;

select count(*)
from cc_member_attempt
order by id desc;


delete from cc_member_attempt
  where id in (select id from cc_member_attempt limit 10000);


explain analyse
select max(hangup_at)
from cc_member_attempt
where member_id = 81;


select *
from cc_member_attempt
order by id desc ;


truncate table cc_member_attempt