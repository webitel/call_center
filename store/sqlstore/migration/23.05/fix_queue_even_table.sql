update call_center.cc_queue_events e
set enabled = false
from (
         select *, row_number() over (partition by queue_id, event) rn
         from call_center.cc_queue_events
         where enabled
     ) t
where t.rn > 1 and t.id = e.id;

create unique index cc_queue_events_queue_id_event_uindex
    on call_center.cc_queue_events (queue_id, event) where enabled;