set enable_seqscan = off;
explain ( ANALYSE ) with mem as (
    select
      ROW_NUMBER()
      OVER pos    as position,
      c2.priority as q_p,
      --res.*,
      c.*,
      range.max_attempt,
      range.priority,
      m2.queue_id
    from cc_member_communications c
      join cc_member m2 on c.member_id = m2.id
      join cc_queue_is_working c2 on m2.queue_id = c2.id
      join calendar cal on cal.id = c2.calendar_id
      left join cc_communication c4 on c.communication_id = c4.id

      left join lateral (
                select *
                from cc_queue_timing t
                where t.queue_id = c2.id and t.communication_id = c.communication_id
                      and (to_char(current_timestamp AT TIME ZONE cal.timezone, 'SSSS') :: int / 60)
                      between t.start_time_of_day AND t.end_time_of_day
                limit 1
                ) range on c.communication_id notnull
      left join cc_queue_timing c5 on c5.communication_id = c.communication_id
    --       inner join LATERAL (
    --         select r.queue_id , regexp_matches(c.number, r.pattern), c3.max_call_count
    --         from cc_queue_routing r
    --           join cc_resource_in_routing rr on rr.resource_id = r.id
    --           join cc_outbound_resource c3 on rr.resource_id = c3.id
    --           where r.queue_id = c2.id
    --         order by r.priority, rr.priority
    --         limit 1
    --       ) res on res.queue_id = c2.id

    where state = 0
    WINDOW pos AS (
      partition by c.member_id
      ORDER BY c.last_calle_at, c.priority DESC )
    order by c2.priority DESC
    limit 100
)
select *
from mem
where mem.position = 1 and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, mem.id)
limit 100;


select *
from cc_queue_is_working q
  inner join lateral (
             select *
             from cc_member m
               inner join lateral (
                          select
                            id as cc_id,
                            queue_id,
                            number,
                            communication_id
                          from cc_member_communications c

                          where c.member_id = m.id and c.state = 0 and last_calle_at <= q.sec_between_retries
                          order by last_calle_at, priority
                          limit 1
                          ) as c on true

             where m.queue_id = q.id and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, m.id)
             order by m.priority asc
             limit q.max_calls
             ) m on true
order by q.priority desc;

select * from cc_member where queue_id = 2;