CREATE OR REPLACE VIEW cc_queue_resources_is_working AS
SELECT r.id,
    r."limit" AS max_call_count,
    r.enabled,
    call_center.get_count_active_resources(r.id) AS reserved_count
   FROM call_center.cc_outbound_resource r
  WHERE r.enabled is true and not r.reserve is true;


select *
from cc_queue_resources_is_working;


CREATE OR REPLACE FUNCTION get_count_active_resources(int)
  RETURNS SETOF integer AS
$BODY$
BEGIN
  RETURN QUERY SELECT count(*) :: integer
               FROM cc_member_attempt a
               WHERE hangup_at = 0
                 AND a.resource_id = $1;
END
$BODY$
  LANGUAGE plpgsql;


alter function get_count_active_resources
  owner to webitel;

SELECT count(*) :: integer
FROM cc_member_attempt a
WHERE hangup_at = 0 and a.resource_id = 1;



drop view cc_queue_resources_is_working;


select *, get_count_active_resources(r.id)
from cc_outbound_resource r
where r.enabled = true;


select *
from cc_queue_resources_is_working;




select q.id, m.* -- qr.*
from cc_queue q
 ,lateral (
  select array_agg(qr.id) as cri_ids
  from cc_queue_routing qr
  where qr.queue_id = q.id
  group by qr.queue_id
) as qr
inner join (
    select c.id as comm_id, c.number, c.routing_ids, c.last_calle_at, c.priority
    from cc_member_communications c
    where c.state = 0
  ) c1 on true
) m on m.queue_id = q.id and m.rn = 1;



select *
from (
  select
    *
  from cc_queue q,
  lateral (
    select
      *
    from cc_member m
    where m.queue_id = q.id
    order by m.priority desc
    limit q.max_calls
  ) as m
) as q;


-- res
select qr.queue_id, array_agg(DISTINCT rr.routing_id) as routing_id, array_agg(DISTINCT rr.resource_id) as resource_id
from cc_resource_in_routing rr
  inner join cc_queue_routing qr on qr.id = rr.routing_id
group by qr.queue_id;


select
  *
from cc_outbound_resource r;


select *
from (
  select q.id, res.*, m.* --, unnest(res.res_ids)
  from cc_queue q,
  lateral (
    select array_agg(distinct  qr.id) as rout_ids, array_agg(distinct crir.resource_id) as res_ids
    from cc_queue_routing as qr
      inner join cc_resource_in_routing crir on qr.id = crir.routing_id
    where qr.queue_id = q.id
  ) as res
  inner join lateral (
    select m.id, row_number() over (order by m.priority)
    from cc_member m,
     lateral (
       select *
       from cc_member_communications c1
       where c1.member_id = m.id and c1.state = 0 and c1.routing_ids && res.rout_ids
       order by c1.last_calle_at, c1.priority
       limit 1
     ) as c
    where m.queue_id = q.id
    order by m.priority
    limit q.max_calls
  ) m on true
  order by q.priority desc
) as mems;


select unnest(ARRAY[1,2])
from cc;



select *
from calendar
ORDER BY id desc
limit 10
offset 0;