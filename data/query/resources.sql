CREATE OR REPLACE VIEW cc_queue_resources_is_working AS
  select *, get_count_active_resources(r.id) as reserved_count
    from cc_outbound_resource r
where r.enabled = true;



alter function get_count_active_resources
  owner to webitel;



drop view cc_queue_resources_is_working;


select *, get_count_active_resources(r.id)
    from cc_outbound_resource r
where r.enabled = true;


select *
from cc_queue_resources_is_working;


CREATE OR REPLACE FUNCTION get_count_active_resources(int)
  RETURNS SETOF integer AS
$BODY$
BEGIN
  RETURN QUERY SELECT count(*) :: integer
               FROM call_center.cc_member_attempt a
                    inner join call_center.cc_resource_in_routing r on r.id = a.resource_routing_id
               WHERE hangup_at = 0 AND r.routing_id = $1;
END
$BODY$
LANGUAGE plpgsql;



explain analyse
select r.*, res.*
from cc_outbound_resource r
,lateral (
  select *
  from cc_resource_in_routing rr
  where rr.resource_id = r.id
) as res
order by res.priority desc
limit 10;



explain (analyse, buffers )
select m.*
from cc_member m
  inner join lateral (
    select *
    from cc_member_communications c
    where c.member_id = m.id and state = 0 and c.routing_ids @> ARRAY[1]
    order by c.last_calle_at, c.priority asc
    limit 1
  ) c on true
  inner join cc_queue cq on cq.id = 1
where m.queue_id = 1
order by cq.priority,  m.priority desc
limit 100;

