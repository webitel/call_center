-- TODO add except dates

CREATE OR REPLACE VIEW cc_queue_is_working AS
  SELECT
    c1.*,
    cc_queue_require_agents(c1.type) as require_agent,
    cc_queue_require_resources(c1.type) as require_resource,
    get_count_call(c1.id) as active_calls
  from cc_queue c1
  where c1.enabled = true and exists(select *
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


CREATE OR REPLACE FUNCTION get_count_call(int)
  RETURNS SETOF integer AS
$BODY$
BEGIN
  RETURN QUERY SELECT count(*) :: integer
               FROM cc_member_attempt
               WHERE state > -1 AND queue_id = $1;
  RETURN;
END
$BODY$
LANGUAGE plpgsql;

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