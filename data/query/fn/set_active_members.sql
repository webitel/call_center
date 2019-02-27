CREATE OR REPLACE FUNCTION set_active_members(node varchar(20))
  RETURNS TABLE
          (
            id          bigint,
            member_id   bigint,
            queue_id    int,
            queue_updated_at bigint,
            resource_id int,
            resource_updated_at bigint
          ) AS
$$
BEGIN
  RETURN QUERY
    update cc_member_attempt a
      set state = 1,
        node_id = node
      from (
        select c.id, cq.updated_at as queue_updated_at, r.updated_at as resource_updated_at
        from cc_member_attempt c
               inner join cc_member cm on c.member_id = cm.id
               inner join cc_queue cq on cm.queue_id = cq.id
               left join cc_outbound_resource r on r.id = c.resource_id
        where c.state = 0 and c.hangup_at = 0
        order by cq.priority desc, cm.priority desc
        for update of c
      ) c
      where a.id = c.id
      returning
        a.id::bigint as id,
        a.member_id::bigint as member_id,
        a.queue_id::int as qeueue_id,
        c.queue_updated_at::bigint as queue_updated_at,
        a.resource_id::int as resource_id,
        c.resource_updated_at::bigint as resource_updated_at;
END;
$$ LANGUAGE 'plpgsql';

select *
from set_active_members('aaa');

drop function set_active_members;

show log_min_duration_statement;