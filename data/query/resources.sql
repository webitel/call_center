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