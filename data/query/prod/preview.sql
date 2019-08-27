truncate table cc_member_attempt;

explain (analyze, format text )
select
    case when lc.number is null then null else 'OUTGOING_CALL_BARRED' end result,
    t.communication_id,
    t.member_id,
    t.routing_id,
    a.agent_id as agent_id,
--
    1 as queue_id,
    1 as resource_id,
    '' as node_name
from (
  select
       c.communication_id,
       c.communication_number,
       c.member_id,
      (c.routing_ids & array[18]::int[])[1] as routing_id,
       row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d,
       dense_rank()  over (order by  c.member_id) ra
      from (
        select cmc.id as communication_id, cmc.number as communication_number, cmc.routing_ids, cmc.last_hangup_at, cmc.priority, cmc.member_id
        from cc_member m
         inner join cc_member_communications cmc on cmc.member_id = m.id
            where m.queue_id = 1
              and not exists(
              select 1
              from cc_member_attempt a
              where a.member_id = m.id and a.state > 0
            )
            and m.stop_at = 0
            and m.last_hangup_at < 1566892253767
            and m."offset"::interval =  any ('{-09:00:00,-08:00:00,-07:00:00,-06:00:00,-05:00:00,-04:00:00,-03:00:00,-02:30:00,-02:00:00,00:00:00,01:00:00,02:00:00,03:00:00,04:30:00}'::interval[])

--             and cmc.member_id = m.id
            and cmc.state = 0
            and cmc.routing_ids && array[18]::int[]
            and cmc.communication_id = 1

          order by m.priority desc, m.last_hangup_at asc
        limit 1000 * 3 --todo 3 is avg communication count
        for UPDATE SKIP LOCKED
  ) c
) t
left join cc_list_communications lc on lc.list_id = 1 and lc.number = t.communication_number
inner join cc_waiting_agents(1, 1000, 'todo') a on a.pos = t.ra
where t.d = 1
order by a.pos
;

select *
from cc_waiting_agents(1, 500, 'todo')
order by pos;

update cc_agent
set state = 'waiting',
    status = 'online'
where 1=1;

truncate table cc_member_attempt;

select *
from calendar_accept_of_day
where calendar_id = 1;


select *
from cc_member_communications c
where c.state = 0 and  member_id in (
select id
from cc_member where stop_at = 0 and queue_id = 1);


update cc_agent
set wrap_up_time = 5,
    state = 'waiting',
    status = 'online',
    updated_at = ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint
where 1=1;

truncate cc_member_attempt;

select *
from cc_set_active_members('aa');


CREATE OR REPLACE FUNCTION cc_queue_distribute_preview(node_ varchar(50), rec cc_queue_distribute_resources)
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
      execute 'insert into cc_member_attempt(result, communication_id, member_id, routing_id, agent_id, resource_id, queue_id , node_id)
              select
                 case when lc.number is null then null else ''OUTGOING_CALL_BARRED'' end result,
                 t.communication_id,
                 t.member_id,
                 t.routing_id,
                 a.agent_id as agent_id,
                 $1 as queue_id,
                 $2 as resource_id,
                 $3 as node_name
              from (
                select
                     c.communication_id,
                     c.communication_number,
                     c.member_id,
                    (c.routing_ids & $4::int[])[1] as routing_id,
                     row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d,
                     dense_rank()  over (order by  c.member_id) ra
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
                          and m."offset"::interval =  any ($6::interval[])

                          and cmc.member_id = m.id
                          and cmc.state = 0
                          and cmc.routing_ids && $4::int[]
                          and cmc.communication_id = $7

                        order by m.priority desc, m.last_hangup_at asc
                      limit $8 * 3 for UPDATE SKIP LOCKED --todo 3 is avg communication count
                ) c
              ) t
              left join cc_list_communications lc on lc.list_id = 1 and lc.number = t.communication_number
              cross join cc_waiting_agents($1, $8, null) a
              where t.d = 1 and t.ra = a.pos and not exists(
                  select 1
                  from cc_member_attempt a1
                  where a1.agent_id = a.agent_id
              )
              limit $8'
          using
            rec.queue_id::bigint,
            rec.resource_id::int,
            node_,
            rec.routing_ids::int[],
            rec.min_activity_at,
            x.l,
            x.type_id,
            rec.call_count,
            rec.call_count::int - seg_cnt;

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
     lateral ( select * from cc_queue_distribute_preview('aa', r) ) t;