CREATE OR REPLACE FUNCTION flow.calendar_check_timing(domain_id_ bigint, calendar_id_ integer, name_ character varying) RETURNS record
    LANGUAGE plpgsql STABLE
    AS $$
declare
        res record;
begin
    select c.name,
           case when e.has_except and not e.open then e.name end as excepted,
           case
               when e.has_except then e.open
               else exists(
                   select 1
                   from unnest(c.accepts) as x
                   where not x.disabled is true
                     and x.day + 1 = extract(isodow from current_timestamp AT TIME ZONE ct.sys_name)::int
                     and (to_char(current_timestamp AT TIME ZONE ct.sys_name, 'SSSS') :: int / 60) between x.start_time_of_day and x.end_time_of_day
               ) end              accept,
           case
               when c.start_at > 0 and c.end_at > 0 then
                   not (current_timestamp AT TIME ZONE ct.sys_name)::date between (to_timestamp(c.start_at / 1000) at time zone ct.sys_name)::date and (to_timestamp(c.end_at / 1000) at time zone ct.sys_name)::date + interval '1d'
               else false end as expire
    into res
    from flow.calendar c
             inner join flow.calendar_timezones ct on c.timezone_id = ct.id
             left join lateral (
                 select count(*) > 0 as has_except,
                        coalesce(bool_or(x.working is true and (to_char(current_timestamp AT TIME ZONE ct.sys_name, 'SSSS') :: int / 60) between x.work_start and x.work_stop), false) as open,
                        (array_agg(x.name) filter (where not (x.working is true and (to_char(current_timestamp AT TIME ZONE ct.sys_name, 'SSSS') :: int / 60) between x.work_start and x.work_stop)))[1]::varchar as name
                 from unnest(c.excepts) as x
                 where not x.disabled is true
                   and case
                           when x.repeat is true then
                                   to_char((current_timestamp AT TIME ZONE ct.sys_name)::date, 'MM-DD') =
                                   to_char((to_timestamp(x.date / 1000) at time zone ct.sys_name)::date, 'MM-DD')
                           else
                                   (current_timestamp AT TIME ZONE ct.sys_name)::date =
                                   (to_timestamp(x.date / 1000) at time zone ct.sys_name)::date
                     end
             ) e on true
    where c.domain_id = domain_id_
      and (
        c.id = calendar_id_ or c.name = name_
        )
    limit 1;

    return res;
end;
$$;
