drop function get_free_resources;

CREATE OR REPLACE FUNCTION get_free_resources()
  RETURNS TABLE (
    queue_id int,
    resource_id int,
    routing_ids int[],
    call_count int,
    sec_between_retries int
  ) AS
$$
BEGIN
  RETURN QUERY
    with rr as (
      select q.id as q_id,
             q.sec_between_retries,
             cor.id resource_id,
             q.need_call as q_cnt,
             (case when cor.max_call_count - cor.reserved_count <= 0 then
               0 else cor.max_call_count - cor.reserved_count end) r_cnt,

             --todo absolute to calc priority!!!
             round(100.0 * (q.need_call + 1) / NULLIF(SUM(q.need_call + 1) OVER(partition by cor.id),0)) AS "ratio",
             array_agg(r.id order by r.priority desc, crir2.priority desc) as routing_ids
      from cc_queue_is_working q
             inner join cc_queue_routing r on q.id = r.queue_id
             inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
             inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
      where q.need_call > 0 and q.type != 0 --todo
      group by q.id, q.sec_between_retries, q.need_call, cor.id, cor.max_call_count, cor.reserved_count

    ), res_s as (
        select * ,
               sum(cnt) over (partition by rr.q_id order by ratio desc ) s
        from rr,
             lateral (select round(rr.ratio * rr.r_cnt / 100) ) resources_by_ration(cnt)
      ),
      res as (
        select *, coalesce(lag(s) over(partition by q_id order by ratio desc), 0) as lag_sum
        from res_s
      )
      select res.q_id::int, res.resource_id::int, res.routing_ids::int[],
             (case when s < q_cnt then res.cnt else res.q_cnt - res.lag_sum end)::int call_count,
             res.sec_between_retries
      from res
    where res.lag_sum < res.q_cnt;
END;
$$ LANGUAGE 'plpgsql';



select *
from get_free_resources() res,
 lateral (
   select unnest(routing_ids)
 ) r(route_id)
inner join cc_queue_routing qr on qr.id = r.route_id
where res.queue_id = 1 and res.resource_id = 1
order by qr.priority desc;



select *
from cc_member_communications c
where c.state = 0
order by c.priority desc;



 select k.q_id, resource_id, call_count, sec_between_retries, routing_ids::record[]
      from (with rr as (
      select q.id as q_id,
             q.sec_between_retries,
             cor.id resource_id,
             q.need_call as q_cnt,
             (case when cor.max_call_count - cor.reserved_count <= 0 then
               0 else cor.max_call_count - cor.reserved_count end) r_cnt,
             round(100.0 * (q.priority + 1) / NULLIF(SUM(q.priority + 1) OVER(partition by cor.id),0)) AS "ratio",
             array_agg(r) as routing_ids -- todo distinct ???
      from cc_queue_is_working q
             inner join cc_queue_routing r on q.id = r.queue_id
             inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
             inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
      where q.need_call > 0
      --     and exists ( --todo big table... не можуть пересікитися в чергах
      --       select * from cc_member_communications cmc
      --       where cmc.state = 0 and cmc.routing_ids && array[r.id])
      group by q.id, q.sec_between_retries, q.need_call, q.priority, cor.id, cor.max_call_count, cor.reserved_count

      ), res_s as (
        select * ,
               sum(cnt) over (partition by rr.q_id order by ratio desc ) s
        from rr,
             lateral (select round(rr.ratio * rr.r_cnt / 100) ) resources_by_ration(cnt)
      ),
      res as (
        select *, coalesce(lag(s) over(partition by q_id order by ratio desc), 0) as lag_sum
        from res_s
      )
      select res.q_id::int, res.resource_id::int,
             (case when s < q_cnt then res.cnt else res.q_cnt - res.lag_sum end)::int call_count,
             res.sec_between_retries,
             res.routing_ids
             ,k.*
      from res,
           lateral (
              select * from (
                select (unnest(res.routing_ids)).*
              ) k
              order by k.priority desc
              limit 1
           ) k
      where res.lag_sum < res.q_cnt) k;

DO
$do$
DECLARE
  rec RECORD;
BEGIN
   FOR rec IN select k.q_id, resource_id, call_count, sec_between_retries, routing_ids
      from (with rr as (
      select q.id as q_id,
             q.sec_between_retries,
             cor.id resource_id,
             q.need_call as q_cnt,
             (case when cor.max_call_count - cor.reserved_count <= 0 then
               0 else cor.max_call_count - cor.reserved_count end) r_cnt,
             round(100.0 * (q.priority + 1) / NULLIF(SUM(q.priority + 1) OVER(partition by cor.id),0)) AS "ratio",
             array_agg(r) as routing_ids -- todo distinct ???
      from cc_queue_is_working q
             inner join cc_queue_routing r on q.id = r.queue_id
             inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
             inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
      where q.need_call > 0
      --     and exists ( --todo big table... не можуть пересікитися в чергах
      --       select * from cc_member_communications cmc
      --       where cmc.state = 0 and cmc.routing_ids && array[r.id])
      group by q.id, q.sec_between_retries, q.need_call, q.priority, cor.id, cor.max_call_count, cor.reserved_count

      ), res_s as (
        select * ,
               sum(cnt) over (partition by rr.q_id order by ratio desc ) s
        from rr,
             lateral (select round(rr.ratio * rr.r_cnt / 100) ) resources_by_ration(cnt)
      ),
      res as (
        select *, coalesce(lag(s) over(partition by q_id order by ratio desc), 0) as lag_sum
        from res_s
      )
      select res.q_id::int, res.resource_id::int,
             (case when s < q_cnt then res.cnt else res.q_cnt - res.lag_sum end)::int call_count,
             res.sec_between_retries,
             res.routing_ids
             ,k.*
      from res,
           lateral (
              select * from (
                select (unnest(res.routing_ids)).*
              ) k
              order by k.priority desc
              limit 1
           ) k
      where res.lag_sum < res.q_cnt) k
   LOOP
     perform 1;
     raise notice '%', rec.q_id;
   END LOOP;
END
$do$;


select q.id as q_id,
             q.sec_between_retries,
             cor.id resource_id,
             q.need_call as q_cnt,
             (case when cor.max_call_count - cor.reserved_count <= 0 then
               0 else cor.max_call_count - cor.reserved_count end) r_cnt,

             --todo absolute to calc priority!!!
             round(100.0 * (q.need_call + 1) / NULLIF(SUM(q.need_call + 1) OVER(partition by cor.id),0)) AS "ratio",
              array_agg(r.id order by r.priority desc) as routing_ids
      from cc_queue_is_working q
             inner join cc_queue_routing r on q.id = r.queue_id
             inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
             inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
      where q.need_call > 0
--           and exists ( --todo big table... не можуть пересікитися в чергах
--             select * from cc_member_communications cmc
--             where cmc.state = 0 and cmc.routing_ids && array[r.id])
      group by q.id, q.sec_between_retries, q.need_call, cor.id, cor.max_call_count, cor.reserved_count