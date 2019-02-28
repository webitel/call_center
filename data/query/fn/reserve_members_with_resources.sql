
drop function reserve_members_with_resources;

CREATE OR REPLACE FUNCTION reserve_members_with_resources(node_id varchar(20))
RETURNS integer AS $$
DECLARE
    rec RECORD;
    count integer;
    v_cnt integer;
BEGIN
    count = 0;
    FOR rec IN SELECT *
      from get_free_resources() r
      where r.call_count > 0
    LOOP
      insert into cc_member_attempt(communication_id, queue_id, member_id, resource_id, node_id)
      select c.communication_id, rec.queue_id, m.id, rec.resource_id, node_id
       from cc_member m
          inner join lateral (
            select
                   c.id as communication_id
            from cc_member_communications c
            where c.member_id = m.id and c.state = 0 and c.routing_ids && rec.routing_ids
            order by c.last_calle_at, c.priority desc
            limit 1
          ) c on true
        where m.queue_id = rec.queue_id and
              not exists (select * from cc_member_attempt a where a.member_id = m.id and a.hangup_at = 0)
        order by m.priority desc
        limit rec.call_count;

      get diagnostics v_cnt = row_count;
      count = count + v_cnt;
    END LOOP;
    return count;
END;
$$ LANGUAGE plpgsql;
