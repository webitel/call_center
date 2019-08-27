truncate table cc_member_attempt;



select tgname, tgfoid::regproc from pg_trigger where tgrelid = 'cc_member_attempt'::regclass order by 1;


drop index call_center.cc_member_communications_member_id_communication_test_1;

create index cc_member_communications_member_id_communication_test_1
	on call_center.cc_member_communications (member_id asc)
  include (id , routing_ids , number , last_hangup_at , priority, communication_id )
	where (state = 0);


drop index call_center.cc_member_queue_id_priority_last_hangup_at_timezone_index;

create index cc_member_queue_id_priority_last_hangup_at_timezone_index
	on call_center.cc_member (queue_id asc, priority desc, last_hangup_at asc, "offset" asc) include (id)
	where (stop_at = 0);


explain (analyze , buffers , verbose )
insert into cc_member_attempt(result, communication_id, queue_id, member_id, resource_id, routing_id, node_id, timing_id)
select
       case when lc.number is null then null else 'OUTGOING_CALL_BARRED' end,
       t.communication_id,
       1,
       t.member_id,
       1,
       t.routing_id,
       'test',
       1
from (

  select
     c.communication_id,
     c.communication_number,
     c.member_id,
    (c.routing_ids & array[18]::int[])[1] as routing_id,
     row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d
  from (
    select cmc.id as communication_id, cmc.number as communication_number, cmc.routing_ids, cmc.last_hangup_at, cmc.priority, cmc.member_id
    from cc_member m
     cross join cc_member_communications cmc
        where m.queue_id = 1
          and not exists(
          select *
          from cc_member_attempt a
          where a.member_id = m.id --and a.state > 0
        )
        and m.stop_at = 0
        and m.last_hangup_at < 1566892253767
        and m."offset"::interval = any ('{-09:00:00,-08:00:00,-07:00:00,-06:00:00,-05:00:00,-04:00:00,-03:00:00,-02:30:00,-02:00:00,00:00:00,01:00:00,02:00:00,03:00:00,04:30:00}'::interval[])

        and cmc.member_id = m.id
        and cmc.state = 0
        and cmc.routing_ids && array[18]
        and cmc.communication_id = 1

      order by m.priority desc, m.last_hangup_at asc
    limit 1000 * 3 --todo 3 is avg communication count
  ) c
) t
left join cc_list_communications lc on lc.list_id = 1 and lc.number = t.communication_number
where t.d =1
limit 1000;



--SET CONSTRAINTS ALL DEFERRED;
drop function cc_queue_distribute_ivr;
CREATE OR REPLACE FUNCTION cc_queue_distribute_ivr(node varchar(50), rec cc_queue_distribute_resources)
  RETURNS int AS
$$
  declare
    v_cnt integer;
    count integer = 0;
    seg_cnt integer;
    x cc_communication_type_l;
BEGIN
    seg_cnt = 0;

    foreach x in array rec.times
    loop
      execute 'insert into cc_member_attempt(result, communication_id, queue_id, member_id, resource_id, routing_id, node_id)
      select
             case when lc.number is null then null else ''OUTGOING_CALL_BARRED'' end,
             t.communication_id,
             $2,
             t.member_id,
             $7,
             t.routing_id,
             $8
      from (
        select
           c.communication_id,
           c.communication_number,
           c.member_id,
          (c.routing_ids & $1::int[])[1] as routing_id,
           row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d
        from (
          select cmc.id as communication_id, cmc.number as communication_number, cmc.routing_ids, cmc.last_hangup_at, cmc.priority, cmc.member_id
          from cc_member m
           cross join cc_member_communications cmc
              where m.queue_id = $2
                and not exists(
                select *
                from cc_member_attempt a
                where a.member_id = m.id and a.state > 0
              )
              and m.stop_at = 0
              and m.last_hangup_at < $3
              and m."offset"::interval = any ($4::interval[])

              and cmc.member_id = m.id
              and cmc.state = 0
              and cmc.routing_ids && $1
              and cmc.communication_id = $5

            order by m.priority desc, m.last_hangup_at asc
          limit $6 * 3 --todo 3 is avg communication count
        ) c
      ) t
      left join cc_list_communications lc on lc.list_id = $9 and lc.number = t.communication_number
      where t.d =1
      limit $6'
        using
          rec.routing_ids::int[],
          rec.queue_id::bigint,
          rec.min_activity_at,
          x.l::interval [],
          x.type_id::int,
          rec.call_count::int - seg_cnt,
          rec.resource_id::int,
          node::text,
          rec.dnc_list_id::bigint;

      get diagnostics v_cnt = row_count;
      count = count + v_cnt;
      seg_cnt = seg_cnt + v_cnt;

      exit when rec.call_count::int - seg_cnt <= 0;
    end loop;

    return  count;
END;
$$ LANGUAGE 'plpgsql';


truncate table cc_member_attempt;

explain analyze
select t.*
from cc_queue_distribute_resources r,
     lateral ( select * from cc_queue_distribute_ivr('aa', r) ) t;

select *
from cc_queue_distribute_resources;

select *
from cc_member_attempt;
truncate table cc_member_attempt;

select count(*)
from cc_member_attempt_log;

select *
from calendar_accept_of_day
where calendar_id = 1;
