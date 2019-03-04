CREATE OR REPLACE FUNCTION get_free_resources()
  RETURNS TABLE (
    queue_id int,
    resource_id int,
    routing_ids int[],
    call_count int
  ) AS
$$
BEGIN
  RETURN QUERY
    with rr as (
      select q.id as q_id,
             cor.id resource_id,
             q.need_call as q_cnt,
             (case when cor.max_call_count - cor.reserved_count <= 0 then
               0 else cor.max_call_count - cor.reserved_count end) r_cnt,
             round(100.0 * (q.need_call + 1) / NULLIF(SUM(q.need_call + 1) OVER(partition by cor.id),0)) AS "ratio",
             array_agg(distinct r.id) as routing_ids
      from cc_queue_is_working q
             inner join cc_queue_routing r on q.id = r.queue_id
             inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
             inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
      where q.need_call > 0 and exists ( --todo big table...
        select * from cc_member_communications cmc
        where cmc.state = 0 and cmc.routing_ids && array[r.id] limit 1)
      group by q.id, q.need_call, cor.id, cor.max_call_count, cor.reserved_count

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
             (case when s < q_cnt then res.cnt else res.q_cnt - res.lag_sum end)::int call_count
      from res
    where res.lag_sum < res.q_cnt;
END;
$$ LANGUAGE 'plpgsql';


explain (analyse, timing )
 select q.id as q_id,
             cor.id resource_id,
             q.need_call as q_cnt,
             (case when cor.max_call_count - cor.reserved_count <= 0 then
               0 else cor.max_call_count - cor.reserved_count end) r_cnt,
             round(100.0 * (q.need_call + 1) / NULLIF(SUM(q.need_call + 1) OVER(partition by cor.id),0)) AS "ratio",
             array_agg(distinct r.id) as routing_ids
      from cc_queue_is_working q
             inner join cc_queue_routing r on q.id = r.queue_id
             inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
             inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
       where q.need_call > 0
         and exists ( --todo big table...
          select * from cc_member_communications cmc
          where cmc.state = 0 and cmc.routing_ids && array[r.id] limit 1)
      group by q.id, q.need_call, cor.id, cor.max_call_count, cor.reserved_count;


select *
from cc_queue_is_working;

select *
from cc_queue_resources_is_working;