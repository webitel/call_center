CREATE OR REPLACE FUNCTION un_reserve_members_with_resources(node varchar(20), res varchar(30))
RETURNS integer AS $$
DECLARE
    count integer;
BEGIN
    update cc_member_attempt
      set state  = -1,
          hangup_at = ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint,
          result = res
    where hangup_at = 0 and node_id = node;

    get diagnostics count = row_count;
    return count;
END;
$$ LANGUAGE plpgsql;

select id, "limit", enabled, priority, updated_at, rps, domain_id, reserve, variables, number, max_successively_errors
from cc_outbound_resource;

select count(*)
from calendar;
