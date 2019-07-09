-- TODO add except dates

drop view cc_queue_is_working;

CREATE OR REPLACE VIEW cc_queue_is_working AS
  SELECT
    c1.*,
    case when c1.max_calls - tmp.active_calls <= 0 then 0 else c1.max_calls - tmp.active_calls end as need_call,
    a as available_agents
  from cc_queue c1,
    lateral ( select get_count_call(c1.id) as active_calls ) tmp(active_calls)
  left join lateral (
      select get_agents_available_count_by_queue_id(c1.id) as a
      where c1.type != 1 --inbound
  ) a on true
  where  c1.enabled = true and exists(select *
                                     from calendar_accept_of_day d
                                       inner join calendar c2 on d.calendar_id = c2.id
                                     where d.calendar_id = c1.calendar_id AND
                                           (to_char(current_timestamp AT TIME ZONE c2.timezone, 'SSSS') :: int / 60)
                                           between d.start_time_of_day AND d.end_time_of_day);

set enable_seqscan = off;
explain ( analyse ) select *
                    from cc_queue_is_working;
set enable_seqscan = on;

drop view cc_queue_is_working;

select *
from cc_member_attempt
where state > -1;

update cc_member_attempt
set state = -1
where state > -1;

CREATE OR REPLACE FUNCTION get_count_call(int)
  RETURNS SETOF integer AS
$BODY$
BEGIN
  RETURN QUERY SELECT count(*) :: integer
               FROM cc_member_attempt
               WHERE hangup_at = 0 AND queue_id = $1 AND state > -1;
  RETURN;
END
$BODY$
LANGUAGE plpgsql;


select proname,prosrc from pg_proc where proname = 'get_count_call';

/*
queue types
1 - inbound
2 - outbound voice
3 - outbound preview
4 - outbound predictive
 */

CREATE OR REPLACE FUNCTION cc_queue_require_agents(int)
  RETURNS boolean AS
$BODY$
BEGIN
  if $1 = 2
  then
    return false;
  end if;
  RETURN true;
END
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cc_queue_require_resources(int)
  RETURNS boolean AS
$BODY$
BEGIN
  if $1 = 1
  then
    return false;
  end if;
  RETURN true;
END
$BODY$
LANGUAGE plpgsql;



create table cc_member_attempt
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
);

alter table cc_queue_is_working owner to webitel;

select *
from cc_member_attempt a;