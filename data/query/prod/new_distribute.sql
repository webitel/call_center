select *
from get_free_resources()
;




do
$do$
  declare
     i int;
begin
   raise exception 'fuck ^)';

  FOR i IN 1..10 LOOP
    raise notice '%', i;
  end loop;
end
$do$;



explain analyze
select q.*, c.timezone
from cc_queue q
       left join lateral (
  SELECT count(*) :: integer
  FROM cc_member_attempt
  WHERE hangup_at = 0
    AND queue_id = q.id
  ) active on true
inner join calendar c on q.calendar_id = c.id
where q.enabled is true and q.max_calls > active.count;



select ca.start_time_of_day, ca.end_time_of_day
from calendar_accept_of_day ca
where ca.week_day = extract(isodow from now() at time zone 'Europe/Kiev') and ca.calendar_id = 1;


 select amop.amopopr::regoperator
from pg_opclass opc, pg_opfamily opf, pg_am am, pg_amop amop
where opc.opcname = 'array_ops'
and opf.oid = opc.opcfamily
and am.oid = opf.opfmethod
and amop.amopfamily = opc.opcfamily
and am.amname = 'gin'
and amop.amoplefttype = opc.opcintype;

select (to_char(current_timestamp AT TIME ZONE 'utc', 'SSSS') :: int / 60);

select p.name, pg_index_has_property('cc_member_queue_id_priority_last_hangup_at_timezone_index'::regclass,p.name)
from unnest(array['clusterable','index_scan','bitmap_scan','backward_scan']) p(name);

select p.name, pg_index_column_has_property('cc_member_queue_id_priority_last_hangup_at_timezone_index'::regclass,1,p.name)
from unnest(array['asc','desc','nulls_first','nulls_last','orderable','distance_orderable','returnable','search_array','search_nulls']) p(name);

drop index call_center.cc_member_queue_id_priority_last_hangup_at_timezone_index;

create index cc_member_queue_id_priority_last_hangup_at_timezone_index
	on call_center.cc_member using btree (queue_id,  "offset", last_hangup_at,  priority desc) include (id)
	where (stop_at = 0);





explain analyze
  select *
  from calendar_timezones;

explain analyze
select t.name
from calendar_timezones t,
     lateral (select current_timestamp AT TIME ZONE t.name t) with_timezone
where exists(
  select 1
  from  calendar_accept_of_day a
  where a.calendar_id = 7
    and a.week_day = extract(dow from with_timezone.t)
    and (to_char(with_timezone.t, 'SSSS') :: int / 60) between a.start_time_of_day and a.end_time_of_day
);

select *
from calendar_accept_of_day
where calendar_id = 7;


select (to_char(current_timestamp AT time zone 'Europe/Kiev', 'SSSS') :: int / 60);


select *, (to_char(current_timestamp AT TIME ZONE c.timezone, 'SSSS') :: int / 60)
from calendar_accept_of_day a
  inner join calendar c on a.calendar_id = c.id
where a.calendar_id = 7 and (to_char(current_timestamp AT TIME ZONE c.timezone, 'SSSS') :: int / 60) between a.start_time_of_day and a.end_time_of_day;

select (1,2)::cc_int4_pair;

select (t.r).a
from (
  select unnest(h.r) r
  from (
    select array(select range.r
        from (
          select array [(c.start_time_of_day::int - utc_t.minOfDay, c.end_time_of_day::int - utc_t.minOfDay)::cc_int4_pair] r
          from calendar_accept_of_day c
          cross join (
            select (to_char(current_timestamp AT TIME ZONE 'UTC', 'SSSS') :: int / 60) -1400  minOfDay
          ) utc_t
          where c.calendar_id = 7
        ) range) r
  ) h
) t;

vacuum analyze cc_member;

vacuum full analyze  cc_member;
reindex index cc_member_queue_id_priority_last_hangup_at_timezone_index;

create type cc_communication_type_l as (
  type_id int,
  l interval[]
);

select * from unnest(cc_queue_timing_timezones(1,1));

--IVR
set enable_seqscan = on;

do
$do$
  declare rec record;
  declare res bigint[];
  declare calendar_id_ bigint default 7;
  declare queue_id_ bigint default 1;
  declare last_hangup_at_ bigint default 15619820544620;
  declare routing_ids_ int[] default array[18];

  declare txt jsonb;
begin

  for rec in SELECT r.queue_id, r.resource_id, r.routing_ids, q.sec_between_retries, r.call_count, q.dnc_list_id, a.type_id, a.l
      from get_free_resources() r
        cross join cc_queue_timing_timezones(r.queue_id, 1::bigint) a
        inner join cc_queue q on q.id = r.queue_id
      where r.call_count > 0
      group by r.queue_id, a.pos, a.type_id, resource_id, routing_ids, call_count, r.sec_between_retries, q.id, a.l
      order by q.priority desc, a.pos asc
    loop
      raise notice 'rec %', rec;

      execute format ('explain (analyze, format json)
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
              where m.queue_id = $2::bigint
                and not exists(
                select *
                from cc_member_attempt a
                where a.member_id = m.id and a.state > 0
              )
              and m.stop_at = 0
              and m.last_hangup_at < $3::bigint
             -- and m."offset"::interval = any ($4::interval[])


              and cmc.member_id = m.id
              and cmc.state = 0
              and cmc.routing_ids && $1::int[]
              and cmc.communication_id = $5::int

            order by m.priority desc, m.last_hangup_at asc
          limit $6::int * 3 --todo 3 is avg communication count
        ) c
      ) t
      left join cc_list_communications lc on lc.list_id = $9::bigint and lc.number = t.communication_number
      where t.d =1
      limit $6')
        into txt
        using
          rec.routing_ids::int[],
          rec.queue_id::bigint,
          (((date_part('epoch'::text, now()) * (1000)::double precision))::bigint - (rec.sec_between_retries * 1000))::bigint,
          rec.l::interval [],
          rec.type_id,
          rec.call_count::int,
          rec.resource_id::int,
          'tst'::text,
          rec.dnc_list_id::bigint;

        raise notice 'w %', txt;

    end loop;
end;
$do$;
;

truncate table cc_member_attempt;

explain analyze
select t.val, *
from cc_member_communications c
  left join (values (1), (null)) t(val) on (c.communication_id = t.val )
where c.member_id = 1 ;


update cc_member_communications
set communication_id = 1
where 1=1;


select *
  from calendar_accept_of_day_timezones(7) t;


select *
from cc_queue_timing_timezones(1, 7);

update cc_queue_timing
set enabled = false
where 1=1;

select * from cc_member_communications
where exists(select * from cc_member m where m.queue_id = 1 and m.id = member_id)

update cc_member_communications
set communication_id = 1
where 1=1;



CREATE OR REPLACE FUNCTION cc_interval_to_arr(i_ interval )
  RETURNS interval[] AS
$$
BEGIN
  return array [i_]::interval [];
END;
$$ LANGUAGE 'plpgsql' IMMUTABLE RETURNS NULL ON NULL INPUT COST 900;




select utc_offset
from calendar_timezones
group by utc_offset;

select *
from cc_member;

drop statistics cc_member_timezone_stats;
create statistics cc_member_timezone_stats (dependencies ) on queue_id, "offset" from cc_member ;

vacuum full analyze  cc_member;

select *
from calendar_accept_of_day
where calendar_id = 7;



update cc_member
set timezone = (select name
from calendar_timezones
order by random(), cc_member.id
limit 1)
where 1=1;

update cc_member
set
  "offset" = current_timestamp at time zone 'UTC' - current_timestamp at time zone 'UTC',
  timezone = 'UTC'
where 1=1;

select *
from cc_member;

select *
from calendar_accept_of_day
where calendar_id = 7;

vacuum full analyze cc_member;

CREATE OR REPLACE FUNCTION cc_test_calendar(timezone_ varchar(50))
  RETURNS boolean AS
$$
BEGIN
  return false;
END;
$$ LANGUAGE 'plpgsql' cost 999;

drop function calendar_accept_of_day_timezones;
CREATE OR REPLACE FUNCTION calendar_accept_of_day_timezones(calendar_id_ bigint)
  RETURNS interval[] AS
$$
  declare
    res_ interval[];
begin
    select array_agg(distinct t.utc_offset)
    into res_
    from calendar_timezones t,
         lateral (select current_timestamp AT TIME ZONE t.name t) with_timezone
    where exists(
              select 1
              from calendar_accept_of_day a
              where a.calendar_id = calendar_id_
                and a.week_day = extract(dow from with_timezone.t)
                and (to_char(with_timezone.t, 'SSSS') :: int / 60) between a.start_time_of_day and a.end_time_of_day
            );
    return res_;
end;
$$ LANGUAGE 'plpgsql' strict  COST 10 ;

explain analyze
select array_agg(distinct t.utc_offset)
    from calendar_timezones t,
         lateral (select current_timestamp AT TIME ZONE t.name t) with_timezone
    where exists(
              select 1
              from calendar_accept_of_day a
              where a.calendar_id = 7
                and a.week_day = extract(dow from with_timezone.t)
                and (to_char(with_timezone.t, 'SSSS') :: int / 60) between a.start_time_of_day and a.end_time_of_day
            );


explain analyze
select t.communication_id, t.priority as prior, t.r
from (
  select t.communication_id, t.priority, array_agg(distinct z.r)  r
  from cc_queue_timing t,
      lateral (
        select distinct ct.utc_offset r
      from calendar_timezones ct,
           lateral (select current_timestamp AT TIME ZONE ct.name t) with_timezone
      where (to_char(with_timezone.t, 'SSSS') :: int / 60) between t.start_time_of_day and t.end_time_of_day
            and exists(
                select 1
                from calendar_accept_of_day a
                where a.calendar_id = 7
                  and a.week_day = extract(dow from with_timezone.t)
                  and (to_char(with_timezone.t, 'SSSS') :: int / 60) between a.start_time_of_day and a.end_time_of_day

              )
        ) z
  where t.queue_id = 1 and t.enabled is true
  group by t.communication_id, t.priority
) t
group by t.communication_id, t.r
order by t.priority desc;

drop materialized view calendar_timezones_by_interval;
create materialized view calendar_timezones_by_interval as
select distinct on (utc_offset) utc_offset, array_agg(name) as names
from calendar_timezones
group by utc_offset;

select *
from calendar_timezones_by_interval;

explain analyze
select t.id
           , t.communication_id
           , t.priority
           , z.ofs
      from cc_queue_timing t,
           lateral (
              select array_agg(distinct ct.utc_offset) ofs
              from calendar_timezones_by_interval ct,
                   lateral (select current_timestamp AT TIME ZONE ct.names[1] t) with_timezone
              where (to_char(with_timezone.t, 'SSSS') :: int / 60)
                  between t.start_time_of_day and t.end_time_of_day
                  and exists(
                      select 1
                      from calendar_accept_of_day a
                      where a.calendar_id = 7
                        and a.week_day = extract(dow from with_timezone.t)
                        and (to_char(with_timezone.t, 'SSSS') :: int / 60) between a.start_time_of_day and a.end_time_of_day

                  )
           ) z
      where t.queue_id = 1
      order by priority desc;


SELECT r.queue_id, r.resource_id, r.routing_ids, q.sec_between_retries, r.call_count, q.dnc_list_id, a.type_id, a.l
      from get_free_resources() r
        cross join cc_queue_timing_timezones(r.queue_id, 1::bigint) a
        inner join cc_queue q on q.id = r.queue_id
      where r.call_count > 0
      group by r.queue_id, a.pos, a.type_id, resource_id, routing_ids, call_count, r.sec_between_retries, q.id, a.l
      order by q.priority desc, a.pos asc;


drop function cc_queue_timing_timezones;
create or replace function cc_queue_timing_timezones(queue_id_ bigint, calendar_id_ bigint) returns call_center.cc_communication_type_l[]
  language plpgsql
as
$$
declare res_types cc_communication_type_l[];
  declare res_type cc_communication_type_l;
  declare r record;
  declare i int default 0;
BEGIN
  for r in select t.id
           , t.communication_id
           , t.priority
           , z.ofs
      from cc_queue_timing t,
           lateral (
              select array_agg(distinct ct.utc_offset) ofs
              from calendar_timezones_by_interval ct,
                   lateral (select current_timestamp AT TIME ZONE ct.names[1] t) with_timezone
              where (to_char(with_timezone.t, 'SSSS') :: int / 60)
                  between t.start_time_of_day and t.end_time_of_day
                  and exists (
                      select 1
                      from calendar_accept_of_day a
                      where a.calendar_id = calendar_id_
                        and a.week_day = extract(dow from with_timezone.t)
                        and (to_char(with_timezone.t, 'SSSS') :: int / 60) between a.start_time_of_day and a.end_time_of_day

                  )
           ) z
      where t.queue_id = queue_id_ and z.ofs notnull
      order by priority desc
  loop

    if res_types[i] notnull and (res_types[i]::cc_communication_type_l).type_id = r.communication_id  then

      SELECT r.communication_id::int, array_agg(distinct t.v)::interval[]
      into res_type
      from (
           select unnest(array_cat(res_types[i].l, r.ofs)) v
      ) t
      limit 1;

      res_types[i] = res_type;
    else
      SELECT
             array_append(res_types, (r.communication_id, r.ofs)::cc_communication_type_l)
      into res_types;
      i = i + 1;
    end if;

  end loop;
  return res_types;
END;
$$;
;

select ((r.v)::cc_communication_type_l).type_id, ((r.v)::cc_communication_type_l).l
from (
     select unnest(t.c::cc_communication_type_l[]) v
      from (
        values ('{"(1,\"{-09:00:00,-08:00:00,-07:00:00,-06:00:00,-05:00:00,-04:00:00,-03:00:00,-02:30:00,-02:00:00,00:00:00,01:00:00,02:00:00,03:00:00}\")","(2,\"{-09:00:00,-08:00:00,-07:00:00,-06:00:00,-05:00:00,-04:00:00,-03:00:00,-02:30:00,-02:00:00,00:00:00,01:00:00,02:00:00,03:00:00,04:30:00}\")","(1,\"{-09:00:00,-08:00:00,-07:00:00,-06:00:00,-05:00:00,-04:00:00,-03:00:00,-02:30:00,-02:00:00,00:00:00,01:00:00,02:00:00,03:00:00,04:30:00}\")"}' )
      ) t (c )
) r;


select t.rn::int, t.tp::int, t.l::interval []
    from (
       select *
       from unnest(array [(1, array ['1h'])::cc_communication_type_l]::cc_communication_type_l[]) WITH ORDINALITY a(tp, l, rn)
    ) t
    order by t.rn asc;


select unnest(cc_queue_timing_timezones(1::bigint, 1::bigint));

select array [(1, array['1h']::interval[])] ;


select *
from cc_member_attempt;
select *
from cc_distribute_inbound_call_to_queue(1, 'dasdsada', '123213');

select *
from calendar_accept_of_day
where calendar_id = 7;

select *
from cc_queue_timing
where queue_id = 1;

  select r.agent_id, r.attempt_id, a2.updated_at
  from cc_distribute_agent_to_attempt('call-center-1') r
  inner join cc_agent a2 on a2.id = r.agent_id;

select cc_available_agents_by_strategy(1, '132131', 1, null::bigint[], null::bigint[]);


select calendar_accept_of_day_timezones(20);


select array_agg(t.name)
    from calendar_timezones t,
         lateral (select current_timestamp AT TIME ZONE t.name t) with_timezone
    where exists(
              select 1
              from calendar_accept_of_day a
              where a.calendar_id = 7
                and a.week_day = extract(dow from with_timezone.t)
                and (to_char(with_timezone.t, 'SSSS') :: int / 60) between a.start_time_of_day and a.end_time_of_day
            )

select cc_test_time(null);

 select (to_char(current_timestamp AT TIME ZONE 'UTC', 'SSSS') :: int / 60)   minOfDay;

drop function cc_get_time(_t varchar, _def_t varchar);
CREATE OR REPLACE FUNCTION cc_get_time(_t varchar(25), _def_t varchar(25))
  RETURNS int AS
$$
BEGIN
  return (to_char(current_timestamp AT TIME ZONE coalesce(_t, _def_t), 'SSSS') :: int / 60)::int;
END;
$$ LANGUAGE 'plpgsql' IMMUTABLE ;

select cc_get_time('Europe/Kiev', 'Europe/Kiev');

drop index call_center.calendar_accept_of_day_calendar_id_week_day_start_time_of_day_e;

create unique index calendar_accept_of_day_calendar_id_week_day_start_time_of_day_e
	on call_center.calendar_accept_of_day using btree (calendar_id, week_day ) include (start_time_of_day, end_time_of_day);


select int4range(1, 2, '[]');


explain analyze
select distinct on(c.member_id) c.member_id, c.number
from cc_member_communications c
where c.state = 0 and  c.member_id in (
  select m.id
  from cc_member m
  where m.queue_id = 1 and m.stop_at = 0
  order by m.priority desc
  --limit 100
) and c.routing_ids && array[18]
limit 100;

explain analyze
  select m.id
  from cc_member m
  where m.queue_id = 1 and m.stop_at = 0
  order by m.priority desc
  limit 100;


select *
from cc_member_communications
where routing_ids notnull ;

drop index call_center.cc_member_communications_routing_ids_gin2;
drop index call_center.cc_member_communications_routing_ids_gin3;

create index cc_member_communications_routing_ids_gin2
	on call_center.cc_member_communications using gin (routing_ids gin__int_ops ,  )
	where (state = 0);
create index cc_member_communications_routing_ids_gin3
	on call_center.cc_member_communications using gin (member_id , routing_ids gin__int_ops )
	where (state = 0);

create table cc_member_communications_old (
    like cc_member_communications
    INCLUDING ALL
);

select  extract(isodow from current_date) ;