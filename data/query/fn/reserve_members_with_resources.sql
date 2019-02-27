
CREATE OR REPLACE FUNCTION reserve_members_with_resources()
RETURNS integer AS $$
DECLARE
    rec RECORD;
    count integer;
    v_cnt integer;
BEGIN
    count = 0;
    FOR rec IN SELECT r.*, ((date_part('epoch'::text, now()) * (1000)))::bigint + (q.sec_between_retries * 1000) as queue_time
      from get_free_resources() r
        inner join cc_queue q on q.id = r.queue_id
      where r.call_count > 0
    LOOP
      insert into cc_member_attempt(communication_id, queue_id, member_id, resource_id)
      select c.communication_id, rec.queue_id, m.id, rec.resource_id
       from cc_member m
          inner join lateral (
            select
                   c.id as communication_id
            from cc_member_communications c
            where c.member_id = m.id and c.state = 0 and c.routing_ids && rec.routing_ids
              and c.last_calle_at < rec.queue_time
            order by c.last_calle_at, c.priority desc
            limit 1
          ) c on true
        where m.queue_id = rec.queue_id
          and not exists (select * from cc_member_attempt a where a.member_id = m.id and a.hangup_at = 0)
        order by m.priority desc
        limit rec.call_count;

      get diagnostics v_cnt = row_count;
      count = count + v_cnt;
    END LOOP;
    return count;
END;
$$ LANGUAGE plpgsql;


explain analyse
select *
       from cc_member m
          inner join lateral (
            select
                   c.id as communication_id
            from cc_member_communications c
            where c.member_id = m.id and c.state = 0 and c.routing_ids && array[1,3,16]
              and c.last_calle_at < 1
            order by c.last_calle_at, c.priority desc
            limit 1
          ) c on true
        where m.queue_id = 1
          and not exists (select * from cc_member_attempt a where a.member_id = m.id and a.hangup_at = 0)
        order by m.priority desc
        limit 500;


