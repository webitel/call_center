CREATE OR REPLACE FUNCTION call_center.cc_trigger_ins_upd() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
        if NEW.type <> 'cron' then
           return NEW;
end if;

        if call_center.cc_cron_valid(NEW.expression) is not true then
            raise exception 'invalid expression %', NEW.expression using errcode ='20808';
end if;

        if old.enabled != new.enabled or old.expression != new.expression or old.timezone_id != new.timezone_id then
select
    call_center.cc_cron_next_after_now(new.expression, (now() at time zone tz.sys_name)::timestamp, (now() at time zone tz.sys_name)::timestamp)
into new.schedule_at
from flow.calendar_timezones tz
where tz.id = NEW.timezone_id;
end if;

RETURN NEW;
END;
$$;


--
-- Name: cc_scheduler_jobs(); Type: PROCEDURE; Schema: call_center; Owner: -
--

CREATE OR REPLACE PROCEDURE call_center.cc_scheduler_jobs()
    LANGUAGE plpgsql
AS $$
begin

    if NOT pg_try_advisory_xact_lock(132132118) then
        raise exception 'LOCKED cc_scheduler_jobs';
    end if;

    with del as (
        delete from call_center.cc_trigger_job
            where stopped_at notnull
            returning id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
    )
    insert into call_center.cc_trigger_job_log (id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id)
    select id, trigger_id, state, created_at, started_at, stopped_at, parameters, error, result, node_id, domain_id
    from del
    ;

    with u as (
        update call_center.cc_trigger t2
            set schedule_at = (t.new_schedule_at)::timestamp
            from (select t.id,
                         jsonb_build_object('variables', t.variables,
                                            'schema_id', t.schema_id,
                                            'timeout', t.timeout_sec
                             ) as                                      params,
                         call_center.cc_cron_next_after_now(t.expression, (t.schedule_at)::timestamp, (now() at time zone tz.sys_name)::timestamp) new_schedule_at,
                         t.domain_id,
                         (t.schedule_at)::timestamp as old_schedule_at,
                         (now() at time zone tz.sys_name)::timestamp - (t.schedule_at)::timestamp < interval '5m' valid
                  from call_center.cc_trigger t
                           inner join flow.calendar_timezones tz on tz.id = t.timezone_id
                  where t.enabled
                    and t.type = 'cron'
                    and (t.schedule_at)::timestamp <= (now() at time zone tz.sys_name)::timestamp
                    and not exists(select 1 from call_center.cc_trigger_job tj where tj.trigger_id = t.id and tj.state = 0)
                      for update of t skip locked) t
            where t2.id = t.id
            returning t.*
    )
    insert
    into call_center.cc_trigger_job(trigger_id, parameters, domain_id)
    select id, params, domain_id
    from u
    where u.valid;
end;
$$;