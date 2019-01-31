-- TODO add except dates

CREATE OR REPLACE VIEW cc_queue_is_working AS
  SELECT *
  from cc_queue c1
  where c1.enabled = true and exists(select *
                                     from calendar_accept_of_day d
                                       inner join calendar c2 on d.calendar_id = c2.id
                                     where d.calendar_id = c1.calendar_id AND
                                           (to_char(current_timestamp AT TIME ZONE c2.timezone, 'SSSS') :: int / 60)
                                           between d.start_time_of_day AND d.end_time_of_day
  );

set enable_seqscan = off;
explain (analyse ) select *
from cc_queue_is_working;
set enable_seqscan = on;

drop view cc_queue_is_working;