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