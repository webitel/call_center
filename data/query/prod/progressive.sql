
explain (analyze, format text )
select
     t.result,
     t.communication_id,
     t.member_id,
     t.routing_id,
     a.agent_id as agent_id,
      1 as queue_id,
      2 as resource_id,
      3 as node_name
from (
  select
         row_number() over  (partition by ra % 3 order by result nulls first ) rn,
         *
    from (
      select
       case when lc.number is null then null else 'OUTGOING_CALL_BARRED' end result,
       t.communication_id,
       t.member_id,
       t.routing_id,
       row_number() over (order by lc.number nulls first, t.member_id ) ra,
       t.d
      from (
        select
             c.communication_id,
             c.communication_number,
             c.member_id,
            (c.routing_ids & array[18]::int[])[1] as routing_id,
             row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d
            from (
              select cmc.id as communication_id, cmc.number as communication_number, cmc.routing_ids, cmc.last_hangup_at, cmc.priority, cmc.member_id
              from cc_member m
               cross join cc_member_communications cmc
                  where m.queue_id = 1
                    and not exists(
                    select *
                    from cc_member_attempt a
                    where a.member_id = m.id and a.state > 0
                  )
                  and m.stop_at = 0
                  and m.last_hangup_at < 10000000000000
                  and m."offset"::interval = any ('{00:00:00}'::interval[])

                  and cmc.member_id = m.id
                  and cmc.state = 0
                  and cmc.routing_ids && array[18]::int[]
                  and cmc.communication_id = 1

                order by m.priority desc, m.last_hangup_at asc
              limit 20 * 3 --todo 3 is avg communication count
        ) c
      ) t
      left join cc_list_communications lc on lc.list_id = 1 and lc.number = t.communication_number
      where t.d = 1
    ) t
) t
left join cc_waiting_agents(1, 20, 'todo') a on a.pos = t.rn and t.result isnull
where (a.agent_id isnull and t.result notnull ) or a.agent_id notnull
limit 20;
--where t.agent_like = a.pos;


select *
from pg_stat_activity;

select *
from cc_set_active_members('111');

select *
from cc_reserve_members_with_resources('ff')



CREATE OR REPLACE FUNCTION cc_queue_distribute_progressive(node_ varchar(50), rec cc_queue_distribute_resources)
  RETURNS int AS
$$
 declare
  v_cnt integer;
  count integer = 0;
  seg_cnt integer;
  x cc_communication_type_l;
BEGIN
    seg_cnt = 0;

    foreach x in array rec.times
    loop
      execute 'insert into cc_member_attempt(result, communication_id, member_id, routing_id, agent_id, queue_id, resource_id, node_id)
              select
                 t.result,
                 t.communication_id,
                 t.member_id,
                 t.routing_id,
                 a.agent_id as agent_id,
                  $1 as queue_id,
                  $2 as resource_id,
                  $3 as node_name
            from (
              select
                     row_number() over  (partition by ra % $10 order by result nulls first ) rn,
                     *
                from (
                  select
                   case when lc.number is null then null else ''OUTGOING_CALL_BARRED'' end result,
                   t.communication_id,
                   t.member_id,
                   t.routing_id,
                   row_number() over (order by lc.number nulls first, t.member_id ) ra,
                   t.d
                  from (
                    select
                         c.communication_id,
                         c.communication_number,
                         c.member_id,
                        (c.routing_ids & $4::int[])[1] as routing_id,
                         row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d
                        from (
                          select cmc.id as communication_id, cmc.number as communication_number, cmc.routing_ids, cmc.last_hangup_at, cmc.priority, cmc.member_id
                          from cc_member m
                           cross join cc_member_communications cmc
                              where m.queue_id = $1
                                and not exists(
                                select *
                                from cc_member_attempt a
                                where a.member_id = m.id and a.state > 0
                              )
                              and m.stop_at = 0
                              and m.last_hangup_at < $5
                              and m."offset"::interval = any ($6::interval[])

                              and cmc.member_id = m.id
                              and cmc.state = 0
                              and cmc.routing_ids && $4::int[]
                              and cmc.communication_id = $7

                            order by m.priority desc, m.last_hangup_at asc
                          limit $8 * 3 --todo 3 is avg communication count
                    ) c
                  ) t
                  left join cc_list_communications lc on lc.list_id = 1 and lc.number = t.communication_number
                  where t.d = 1
                ) t
            ) t
            left join cc_waiting_agents($1, $8, $9) a on a.pos = t.rn and t.result isnull
            where (a.agent_id isnull and t.result notnull ) or a.agent_id notnull
            limit $8'
          using
            rec.queue_id::bigint,
            rec.resource_id::int,
            node_,
            rec.routing_ids::int[],
            rec.min_activity_at,
            x.l,
            x.type_id,
            rec.call_count::int - seg_cnt,
            (rec.payload->'agent'->'strategy')::varchar(50),
            coalesce((rec.payload->'agent'->>'call_per_agent')::int, 1)::int;

      get diagnostics v_cnt = row_count;
      count = count + v_cnt;
      seg_cnt = seg_cnt + v_cnt;

      exit when rec.call_count::int - seg_cnt <= 0;
    end loop;

  return count;
END;
$$ LANGUAGE 'plpgsql';

explain analyze
select t.*
from cc_queue_distribute_resources r,
     lateral ( select * from cc_queue_distribute_progressive('aa', r) ) t;

select agent_id, count(*)
from cc_member_attempt
group by agent_id
;

truncate table cc_member_attempt;