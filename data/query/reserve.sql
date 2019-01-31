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



create table call_center.cc_member_attempt
(
	id serial not null
		constraint cc_member_attempt_pkey
			primary key,
	communication_id integer not null
		constraint cc_member_attempt_cc_member_communications_id_fk
			references cc_member_communications
				on update cascade on delete cascade,
	resource_routing_id integer
		constraint cc_member_attempt_cc_resource_in_routing_id_fk
			references cc_resource_in_routing,
	timing_id integer
		constraint cc_member_attempt_cc_queue_timing_id_fk
			references cc_queue_timing
)
;

create unique index cc_member_attempt_id_uindex
	on call_center.cc_member_attempt (id)
;

