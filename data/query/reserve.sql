set timeOfDay = 400;
select c1.id as queue_id
from cc_queue c1
where c1.enabled = true and exists(select *
                                   from calendar_accept_of_day d
                                   where d.calendar_id = c1.calendar_id and d.end_time_of_day < 0)
order by c1.priority;


with q as (
    select
      c1.id as queue_id,
      c1.priority
    from cc_queue c1
    where c1.enabled = true and exists(select *
                                       from calendar_accept_of_day d
                                         inner join calendar c2 on d.calendar_id = c2.id
                                       where d.calendar_id = c1.calendar_id
                                             and d.end_time_of_day >
                                                 to_char(current_timestamp AT TIME ZONE c2.timezone, 'SSSS') :: int / 60
                                             and d.start_time_of_day <
                                                 to_char(current_timestamp AT TIME ZONE c2.timezone, 'SSSS') :: int / 60
    )
)
select *
from q;


explain analyse select *
from (
  select
    ROW_NUMBER () OVER pos as position,
    pg_sleep(10),
    c.*
  from cc_member_communications c
  where state = 0 and pg_try_advisory_lock(c.id)
  WINDOW pos AS  (partition by c.member_id ORDER BY c.last_calle_at, c.priority DESC )
  limit 100
) as mem
where mem.position = 1;


select *
from pg_locks;

select pg_advisory_unlock_all();

BEGIN;
  select 1;

  select pg_sleep(1);
COMMIT;


drop table call_center.cc_member_attempt;

create UNLOGGED table call_center.cc_member_attempt
(
	id serial not null,
	communication_id integer not null
		constraint cc_member_attempt_cc_member_communications_id_fk
			references cc_member_communications
				on update cascade on delete cascade,
	resource_routing_id integer
		constraint cc_member_attempt_cc_resource_in_routing_id_fk
			references cc_resource_in_routing,
	timing_id integer
		constraint cc_member_attempt_cc_queue_timing_id_fk
			references cc_queue_timing,
	queue_id integer not null
		constraint cc_member_attempt_cc_queue_id_fk
			references cc_queue
				on update cascade on delete cascade,
	state integer default 0 not null,
	member_id integer not null
		constraint cc_member_attempt_cc_member_id_fk
			references cc_member
				on update cascade on delete cascade,
	created_at bigint default ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint not null,
	weight integer default 0 not null
)
;

create unique index cc_member_attempt_id_uindex
	on call_center.cc_member_attempt (id)
;

create index cc_member_attempt_state_queue_id_index
	on call_center.cc_member_attempt (state, queue_id)
;

create index cc_member_attempt_member_id_state_index
	on call_center.cc_member_attempt (member_id, state)
	where (state = 0)
;

create index cc_member_attempt_state_created_at_weight_index
	on call_center.cc_member_attempt (state asc, created_at desc, weight asc)
;





select *
from cc_queue_is_working q
  inner join lateral (
             select *
             from cc_member m
               inner join lateral (
                          select
                            id as cc_id,
                            queue_id,
                            number,
                            communication_id
                          from cc_member_communications c

                          where c.member_id = m.id and c.state = 0 and last_calle_at <= q.sec_between_retries
                          order by last_calle_at, priority
                          limit 1
                          ) as c on true

             where m.queue_id = q.id and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, m.id)
             order by m.priority asc
             limit 0 --q.max_calls
             ) m on true
order by q.priority desc;



CREATE OR REPLACE FUNCTION get_free_resources()
  RETURNS TABLE (
    queue_id int,
    resource_id int,
    routing_ids int[],
    call_count int
  ) AS
$$
BEGIN
  RETURN QUERY
    with rr as (
      select q.id as q_id,
             cor.id resource_id,
             q.need_call as q_cnt,
             (case when cor.max_call_count - cor.reserved_count <= 0 then
               0 else cor.max_call_count - cor.reserved_count end) r_cnt,
             round(100.0 * (q.need_call + 1) / NULLIF(SUM(q.need_call + 1) OVER(partition by cor.id),0)) AS "ratio",
             array_agg(distinct r.id) as routing_ids
      from cc_queue_is_working q
             inner join cc_queue_routing r on q.id = r.queue_id
             inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
             inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
      where q.need_call > 0 and exists ( --todo big table...
        select * from cc_member_communications cmc
        where cmc.state = 0 and cmc.routing_ids && array[r.id] limit 1)
      group by q.id, q.need_call, cor.id, cor.max_call_count, cor.reserved_count

    ), res_s as (
        select * ,
               sum(cnt) over (partition by rr.q_id order by ratio desc ) s
        from rr,
             lateral (select round(rr.ratio * rr.r_cnt / 100) ) resources_by_ration(cnt)
      ),
      res as (
        select *, coalesce(lag(s) over(partition by q_id order by ratio desc), 0) as lag_sum
        from res_s
      )
      select res.q_id::int, res.resource_id::int, res.routing_ids::int[],
             (case when s < q_cnt then res.cnt else res.q_cnt - res.lag_sum end)::int call_count
      from res
    where res.lag_sum < res.q_cnt;
END;
$$ LANGUAGE 'plpgsql';


select *
from get_free_resources() re;

drop function get_free_resources;

select *
from cc_member_attempt
order by id desc;


with rr as (
    select q.id as q_id,
           cor.id resource_id,
           q.need_call as q_cnt,
           (case when cor.max_call_count - cor.reserved_count <= 0 then
             0 else cor.max_call_count - cor.reserved_count end) r_cnt,
           round(100.0 * (q.need_call + 1) / NULLIF(SUM(q.need_call + 1) OVER(partition by cor.id),0)) AS "ratio",
           array_agg(distinct r.id) as routing_ids
    from cc_queue_is_working q
           inner join cc_queue_routing r on q.id = r.queue_id
           inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
           inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
    where q.need_call > 0 and exists ( --todo big table...
      select * from cc_member_communications cmc
      where cmc.state = 0 and cmc.routing_ids && array[r.id] limit 1)
    group by q.id, q.need_call, cor.id, cor.max_call_count, cor.reserved_count

), res_s as (
    select * ,
           sum(cnt) over (partition by rr.q_id order by ratio desc ) s
    from rr,
         lateral (select round(rr.ratio * rr.r_cnt / 100) ) resources_by_ration(cnt)
  ),
  res as (
    select *, coalesce(lag(s) over(partition by q_id order by ratio desc), 0) as lag_sum
    from res_s
  )
  select res.q_id::int, res.resource_id::int, res.routing_ids::int[],
             (case when s < q_cnt then res.cnt else res.q_cnt - res.lag_sum end)::int call_count
  from res
  where res.lag_sum < res.q_cnt;


select *, case when max_call_count - reserved_count <=0 then 0 else max_call_count - reserved_count end
from cc_queue_resources_is_working;

select *
from cc_queue_is_working q;


select * from cc_member_communications cmc
      where cmc.routing_ids && array[1]