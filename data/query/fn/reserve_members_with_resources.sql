
drop function reserve_members_with_resources;

/*
*/


select *
from cc_queue_timing_communication_ids(2);

CREATE OR REPLACE FUNCTION cc_queue_timing_communication_ids(_queue_id bigint)
  RETURNS int[] AS
$$
BEGIN
  return array(select distinct cqt.communication_id
from cc_queue q
  inner join calendar c on q.calendar_id = c.id
  inner join cc_queue_timing cqt on q.id = cqt.queue_id
where q.id = _queue_id
  and (to_char(current_timestamp AT TIME ZONE c.timezone, 'SSSS') :: int / 60)
    between cqt.start_time_of_day and cqt.end_time_of_day);
END;
$$ LANGUAGE 'plpgsql';



explain analyse
SELECT r.*, q.dnc_list_id, cc_queue_timing_communication_ids(r.queue_id) as type_ids
      from get_free_resources() r
        inner join cc_queue q on q.id = r.queue_id
      where r.call_count > 0
      group by r.queue_id, resource_id, routing_ids, call_count, r.sec_between_retries, q.id
      order by q.priority desc;

vacuum full cc_member_attempt;


update cc_member
set stop_at = 0, stop_cause = null
where 1=1;


select count(*)
from cc_member
where stop_at = 0;

select s as count
from reserve_members_with_resources('test') s;

update cc_member_attempt
set state = 3
where hangup_at = 0;


select a.attempt_id, a.agent_id, a.agent_updated_at
			from cc_reserved_agent_for_attempt('test') a;



update cc_agent
set status = 'online'
where id != 1;

explain (analyse, buffers )
select a.id, h.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload, h.state
from cc_agent a
  ,lateral (
    select h.timeout_at, h.state
    from cc_agent_state_history h
    where h.agent_id = a.id --and h.joined_at > current_date
    order by h.joined_at desc
    limit 1
  ) h
where  a.status in  ('online', 'pause') and h.state = 'waiting' -- h.timeout_at < now();






update cc_agent
set status = 'online',
    wrap_up_time = 1,
    no_answer_delay_time = 1,
    busy_delay_time = 1,
    reject_delay_time = 1
where 1=1;

drop view cc_queue_distribute_resources;
create or replace view cc_queue_distribute_resources as
SELECT
  r.queue_id,
   r.resource_id,
   r.routing_ids,
   (((date_part('epoch'::text, now()) * (1000)::double precision))::bigint - (q.sec_between_retries * 1000))::bigint min_activity_at,
   r.call_count,
   q.dnc_list_id,
   a::cc_communication_type_l[] as times,
   q.type,
   q.strategy,
   q.payload
from get_free_resources() r
  inner join cc_queue q on q.id = r.queue_id
  cross join cc_queue_timing_timezones(q.id, q.calendar_id::bigint) a
where r.call_count > 0 and a notnull
group by r.queue_id, a, resource_id, routing_ids, call_count, r.sec_between_retries, q.id
order by q.priority desc;

explain analyze
select r.payload->'amd'->'greeting', json_extract_path_text(r.payload, 'amd', 'greeting') from
      cc_queue_distribute_resources r;


vacuum analyze cc_member;

select *
from cc_queue_timing_timezones(1,1);
select *
from calendar_accept_of_day
where calendar_id = 1;

select *
from cc_reserve_members_with_resources('n');

truncate table cc_member_attempt;

select count(*)
from cc_member_attempt_log;

drop function cc_reserve_members_with_resources;
CREATE OR REPLACE FUNCTION cc_reserve_members_with_resources(node_id varchar(20))
RETURNS integer AS $$
DECLARE
    rec cc_queue_distribute_resources;
    count integer = 0;
BEGIN

    if NOT pg_try_advisory_xact_lock(13213211) then
      raise notice 'LOCK';
      return 0;
    end if;


    FOR rec IN select
          queue_id,
          resource_id,
          routing_ids,
          min_activity_at,
          call_count,
          dnc_list_id,
          times,
          type,
          strategy
      from cc_queue_distribute_resources
    LOOP

      case rec.type
        when 1 then
          select count +  r
          into count
          from cc_queue_distribute_ivr(node_id::varchar(50), rec) r;
        when 2 then
          select count +  r
          into count
          from cc_queue_distribute_preview(node_id::varchar(50), rec) r;
        when 3 then
          select count +  r
          into count
          from cc_queue_distribute_progressive(node_id::varchar(50), rec) r;
        else
          raise exception 'not implement type %', rec.type;
        end CASE;

    END LOOP;
    return count;
END;
$$ LANGUAGE plpgsql;


select *
from cc_member_attempt;
;

explain analyze
select c.id, c.name, c.start, c.finish, c.description, json_build_object('id', ct.id, 'name', ct.name)::jsonb as timezone
from calendar c
       left join calendar_timezones ct on c.timezone_id = ct.id
where c.domain_id = 1;

update calendar
set domain_id = 1
where 1=1;

insert into cc_test (val)
select array[a1,a2,a3,a4]
from generate_series(1,200000) c,
     lateral (
       select (random()::int)::int a1,  (random()::int)::int a2, (random()::int)::int a3,
              (random()::int)::int a4
       where c > 0
     ) r ;

select (random()::int)::text || (random()::int)::text|| (random()::int)::text|| (random()::int)::text;

vacuum full cc_test;

drop index call_center.cc_test_val_index;
create index cc_test_val_index
	on call_center.cc_test using gin(val );


explain analyze
select val
from cc_test t
where t.val[1] = 1;


select count(*)
from cc_test;


update cc_member
set stop_at = 0
where 1=1;

vacuum full cc_member_communications;

truncate table cc_member_attempt;

select *
from cc_member_attempt
where id = 2815020;


select *
from cc_agent;

update cc_agent
set wrap_up_time = 60
where 1=1;

explain analyse
select *
from cc_member_attempt a
--where state > 0 and hangup_at != 0
order by a.id desc ;

drop index cc_member_communications_member_id_communication_id_routing_ids_index;
create index cc_member_communications_member_id_communication_id_routing_ids_index
	on call_center.cc_member_communications using  btree(member_id, coalesce(communication_id, 0), routing_ids, last_hangup_at asc, priority desc) include (id, number)
where state = 0;

drop index cc_member_communications_routing_ids_member_id_communication_id_index;
create index cc_member_communications_routing_ids_member_id_communication_id_index
	on call_center.cc_member_communications using  gin(routing_ids gin__int_ops, coalesce(communication_id, 0), last_hangup_at, priority)
where state = 0;

explain (analyze, format text )
select
        case when lc.number is null then null else 'OUTGOING_CALL_BARRED' end,
       t.communication_id,
      -- 1, -- queue_id
       t.member_id,
     --  1, --resource_id
       t.routing_id
    --   'node-id'
from (
  select
         c.communication_id,
         c.communication_number,
         c.member_id,
        (c.routing_ids & array[18])[1] as routing_id,
        row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d,
         pos
  from (
    select cmc.id as communication_id, cmc.number as communication_number, cmc.routing_ids, cmc.last_hangup_at, cmc.priority, cmc.member_id,
           row_number() over (order by m.priority desc, m.last_hangup_at asc) pos
    from cc_member m
     cross join cc_member_communications cmc
        where m.queue_id = 1
          and not exists(
          select *
          from cc_member_attempt a
          where a.member_id = m.id and a.state > 0
        )
        and m.stop_at = 0
        and m.last_hangup_at < ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint
                                    - (10 * 1000)
        and m."offset"::interval = any ('{00:00:00}'::interval [])

        and cmc.state = 0
        and cmc.member_id = m.id
        and cmc.routing_ids && array[18]::int[]
        and cmc.communication_id = 1

      order by m.priority desc, m.last_hangup_at asc
    limit 2::int * 3 --todo 3 is avg communication count
  ) c
) t
left join cc_list_communications lc on lc.list_id = 1 and lc.number = t.communication_number
where t.d =1
order by t.pos asc
limit 2::int;


drop index call_center.cc_member_communications_member_id_communication_id_routing_ids_x2;

create index cc_member_communications_member_id_communication_id_routing_ids_x2
	on call_center.cc_member_communications using gin(routing_ids gin__int_ops,  communication_id , member_id )
	where (state = 0);

drop index cc_member_communications_member_id_communication_id_routing_ids_x3;
create index cc_member_communications_member_id_communication_id_routing_ids_x3
	on call_center.cc_member_communications using gin(routing_ids gin__int_ops,  communication_id , member_id )
	where (state = 0);

drop index call_center.cc_member_communications_member_id_communication_id_member_id;

create index cc_member_communications_member_id_communication_id_member_id
	on call_center.cc_member_communications (member_id);


drop index call_center.cc_member_communications_member_id_communication_test_1;
create index cc_member_communications_member_id_communication_test_1
	on call_center.cc_member_communications using btree( member_id) include (id, routing_ids, number, last_hangup_at, priority)
	where (state = 0);


explain analyze
select cmc.id as communication_id, cmc.number as communication_number, cmc.routing_ids, cmc.last_hangup_at, cmc.priority, cmc.member_id
    from cc_member m
     cross join cc_member_communications cmc
        where m.queue_id = 1
          and not exists(
          select *
          from cc_member_attempt a
          where a.member_id = m.id and a.state > 0
        )
        and m.stop_at = 0
        and m.last_hangup_at < ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint
                                    - (10 * 1000)
        and m."offset"::interval = any ('{00:00:00,01:00:00}'::interval [])

         and cmc.state = 0
         and cmc.member_id = m.id
         and cmc.routing_ids && array[18]::int[]
         and cmc.communication_id = 1

      order by m.priority desc, m.last_hangup_at asc
    limit 100::int * 3; --todo 3 is avg communication count;

vacuum full analyze cc_member;
vacuum full analyze cc_member_communications;
vacuum full analyze cc_member_communications_old;




select *
from cc_member_attempt;;



truncate table cc_member_attempt;


select routing_ids, count(*)
from cc_member_communications
group by routing_ids;

vacuum full analyze cc_member_communications;

insert into cc_list_communications (list_id, number)
select 1, number
from cc_member_communications
on conflict do nothing ;

select count(*)
from cc_member_attempt;

select *
from cc_member_attempt
where state != -1;

select member_id, count(*)
from cc_member_attempt
group by member_id
having count(*) > 1
--order by id desc
;

select *
from cc_member_attempt
where result=  'OUTGOING_CALL_BARRED';

truncate table cc_member_attempt;

set max_parallel_workers_per_gather = 1;
DISCARD ALL;
explain (analyse, buffers )
select case when lc.number isnull then 0 else 1 end, t.number, *
from (
  select
         c.*,

         row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d
  from (
    select c.id as communication_id, c.number, c.routing_ids, c.last_hangup_at, c.priority, c.member_id
    from cc_member cm
     cross join cc_member_communications c
     --cross join cc_queue_actual_timing(1) t
        where
          not exists(
            select *
            from cc_member_attempt a
            where a.member_id = cm.id and a.state > 0
          )
          and cm.last_hangup_at < ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint
                                    - (1 * 1000)
          and cm.stop_at = 0
          and cm.queue_id = 1
          and c.state = 0
          and ( (c.communication_id = any(array[1, 2,3,4,5,6,7]) ) or c.communication_id isnull )
          and c.member_id = cm.id
          and c.routing_ids && array[18]
--           and not exists(
--             select 1
--             from cc_list_communications lc
--             where lc.list_id = 1 and lc.number = c.number
--           )

      order by cm.priority desc
    limit 100 * 3 --todo 3 is avg communication count
  ) c
) t
left join cc_list_communications lc on lc.list_id = 1 and lc.number = t.number
where t.d =1
limit 100;



select routing_ids
from cc_member_communications;





explain analyse
select c.number
from cc_member_communications c
where not c.number in (
  select number
  from cc_list_communications

);

explain analyse
select *
from cc_member m,
  lateral (
    select *
    from cc_member_communications c
    where c.member_id = m.id
      and c.state = 0
      and ( (c.communication_id = any(array[1, 2,3,4,5,6,7]) ) or c.communication_id isnull )
      and c.routing_ids && array[777]

    order by c.last_hangup_at, c.priority desc
    limit 1
  ) c
where m.queue_id = 1 and m.stop_at = 0
order by m.priority desc
limit 100;


explain analyse
select c.number
from cc_member_communications c
where not exists(
    select *
    from cc_list_communications lc
  where lc.list_id = 1 and lc.number = c.number
);


insert into cc_list_communications (list_id, number)
values (1, 'bf6c11a4f3356778');

vacuum full cc_list_communications;

create index cc_list_communications_list_id_number_index
	on call_center.cc_list_communications using hash(number);


select *
from cc_member_attempt
order by id desc ;

update cc_member
set stop_at =0,
    attempts = 0,
    last_hangup_at = 0

where 1=1;

update cc_member_communications
set state = 0
where 1=1;

truncate table cc_member_attempt;

select cc_test_pair(c)
from cc_member_communications c;

drop index call_center.cc_member_communications_member_id_last_hangup_at_priority_inde;

create index cc_member_communications_member_id_last_hangup_at_priority_inde
	on call_center.cc_member_communications (member_id asc, last_hangup_at asc, priority desc)
	where (state = 0);


vacuum full cc_member_communications;

update cc_member_communications
set communication_id = null
where id in (
  select id
  from cc_member_communications
  limit 50000
);

select *
from cc_member_communications
  where member_id = 81;


vacuum full cc_member_communications;

select *
from cc_queue_actual_timing(1);


explain analyse
select *
from cc_member_communications c
where   rrr > 10 or c.communication_id is null;




select unnest(array[(1,4), (2,6)]);

explain analyse
select c.*, cm.priority member_priority--, row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc)
    from cc_member cm
      cross join lateral (
        select *--, row_number() over (order by c.last_hangup_at, c.priority desc)
        from cc_member_communications c
        where c.member_id = cm.id
          and c.state = 0
          and c.routing_ids && array[100, 27,1001,1002,1003,1004,1005]
        --limit 1
      ) c
    where
      not exists(
        select *
        from cc_member_attempt a
        where a.member_id = cm.id and a.state > 0
      )
      and cm.last_hangup_at < ( ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint - (1::bigint * 60 * 1000)::bigint )
      and cm.stop_at = 0
      and cm.queue_id = 1

order by cm.priority desc
limit 100;

explain analyse
select *
from cc_member m
  cross join lateral (
    select distinct on(c.member_id) c.member_id, first_value(c.id ) over (partition by c.member_id order by c.last_hangup_at, c.priority desc)
    from cc_member_communications c
    where c.state = 0 and c.routing_ids && array[1, 27,1001,1002,1003,1004,1005]
  ) c
where m.stop_at = 0 and m.queue_id = 1 and m.last_hangup_at < ( ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint - (1::bigint * 60 * 1000)::bigint )
order by m.priority desc;


explain analyse
select *
from (
  select distinct on(c.member_id) c.member_id, first_value(c.id ) over (partition by c.member_id order by c.last_hangup_at, c.priority desc)
    ,cm.priority
  from cc_member_communications c
    inner join cc_member cm on c.member_id = cm.id
  where c.state = 0 and c.routing_ids && array[1, 27,1001,1002,1003,1004,1005]
    and cm.last_hangup_at < ( ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint - (1000000::bigint * 60 * 1000)::bigint )
    and cm.stop_at = 0
    and cm.queue_id = 1
) t
limit 100
;


select *
from cc_member
where id = 176;

select *
from cc_member m
where priority = 100 and m.queue_id = 1 and stop_at = 0 and last_hangup_at < ( ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint - (1::bigint * 60 * 1000)::bigint )
and exists(select *
  from cc_member_communications c
where c.state = 0 and c.member_id = m.id and c.routing_ids && array[1, 26, 27]);


select *
from cc_member
where id = 30175;

vacuum full cc_member;

select *
from cc_member_attempt
order by id desc ;

update cc_member_communications
set tst = communication_id || ':' || attempts
where 1=1;

drop index call_center.cc_member_communications_communication_id_attempts_index_t10;
create index cc_member_communications_communication_id_attempts_index_t10
	on call_center.cc_member_communications using btree( cc_test_pair(cc_member_communications), last_hangup_at, priority)
where state = 0;

explain analyse
select *
from cc_member_communications c
where c.state = 0 and cc_test_pair(c) = (1,10)::cc_pair_test
   and c.last_hangup_at < 10000000000000
order by priority
;



explain analyse
with g as (
  select array(select row(t.communication_id, g.idx)::cc_pair_test
  from (
    select t.communication_id, max(t.max_attempt) as max_attempt
    from cc_queue_timing t
    where t.queue_id = 1 and 1=1
    group by t.communication_id
    union
    select null, 100
  ) t,
  lateral ( select generate_series(0, t.max_attempt - 1) g ) g(idx)) as tst
)
select c.*, row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority)
from cc_member_communications c
  cross join g
where c.last_hangup_at < 500 and cc_test_pair(c) = any(g.tst) and c.member_id > 0 ;


select row(communication_id, attempts)::cc_pair_test,*
from cc_member_communications c
where communication_id is null and cc_test_pair(c) = (null,10)::cc_pair_test;

update cc_member_communications
set attempts = 10
where 1=1;



drop function cc_test_pair;
create type cc_pair_test as (
  c int,
  a int
);

CREATE OR REPLACE FUNCTION cc_test_pair(
    cc_member_communications
) RETURNS cc_pair_test LANGUAGE SQL AS $$
    select row($1.communication_id, $1.attempts)::cc_pair_test
$$ ;




select ( row(t.communication_id, t.max_attempt) )
from (
  select communication_id::bigint as communication_id, max(max_attempt)::smallint as max_attempt
  from cc_queue_timing
  group by communication_id
) t ;

;

select *
from cc_queue_actual_timing(1);

drop function cc_queue_actual_timing;

CREATE OR REPLACE FUNCTION cc_queue_actual_timing(_queue_id bigint)
  RETURNS table (
     communication_id bigint,
     max_attempt int
  ) AS
$$
BEGIN
  return query select t.communication_id::bigint, max(t.max_attempt::integer) - 10
    from cc_queue_timing t
    where t.queue_id = _queue_id and -1 between t.start_time_of_day and t.end_time_of_day
    group by t.communication_id;

end;
$$ LANGUAGE 'plpgsql';


select t.communication_id::bigint, max(t.max_attempt::integer)
from cc_queue_timing t
where t.queue_id = 1 and 10 between t.start_time_of_day and t.end_time_of_day
group by t.communication_id;


explain analyse
select *
from cc_queue_timing t
where t.queue_id = 1 and 1 between t.start_time_of_day and t.end_time_of_day;


select *
from cc_member_communications
where member_id = 81;

update cc_member
set stop_at = 0
where id != 81;

update cc_member_attempt a
set hangup_time = TO_TIMESTAMP(a.created_at / 1000)
where 1 = 1;


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



;
        select
             *
        from (
               select c.id as communication_id, c.routing_ids, c.last_hangup_at, c.priority, c.member_id
               from cc_member cm
                      cross join cc_member_communications c
               where not exists(
                   select *
                   from cc_member_attempt a
                   where a.member_id = cm.id
                     and a.state > 0
                 )
                 and cm.last_hangup_at < ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint
                 - (1 * 60 * 1000)
                 and cm.stop_at = 0

                 and cm.queue_id = 1

                 and c.state = 0
                 and ((c.communication_id = any (array [1])) or c.communication_id isnull)
                 and c.member_id = cm.id
                 -- and c.routing_ids && rec.routing_ids

               order by cm.priority desc
               limit 300
             ) a;

vacuum full cc_member_communications;

update cc_member
set stop_at = 0
where queue_id = 1;

