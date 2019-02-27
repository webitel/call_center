CREATE OR REPLACE VIEW cc_queue_resources_is_working AS
select *, get_count_active_resources(r.id) as reserved_count
from cc_outbound_resource r
where r.enabled = true;


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




explain analyse
  select *
  from (
         select res.id as resource_id,
                res.max_call_count,
                q.id as queue_id,
                q.max_calls,
                m.id as member_id,
                m.comm_id,
                m.number,
                row_number() over (partition by q.id order by q.priority desc ) as pos_in_q
         from (
           select r.id, r.max_call_count, array_agg(d.cqr_id) as cri_ids
           from cc_outbound_resource r,
                lateral (
                  select cqr.id as cqr_id
                  from cc_resource_in_routing rr
                         inner join cc_queue_routing cqr on rr.routing_id = cqr.id
                  where rr.resource_id = r.id
                  order by rr.priority desc, cqr.priority desc
                  ) d
           group by r.id
         ) res
         inner join lateral (
             select *
             from cc_member m,
              lateral (
                select c.id as comm_id, c.number
                from cc_member_communications c
                where c.member_id = m.id
                  and c.state = 0
                  and c.routing_ids && res.cri_ids
                order by c.last_calle_at desc, c.priority desc
                limit 1
               ) c1
               order by m.priority desc
               limit res.max_call_count
           ) as m on true
         inner join cc_queue q on q.id = m.queue_id

       ) as result
  --where result.pos_in_q <= result.max_calls;


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