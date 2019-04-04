drop function agent_by_queue_strategy;

CREATE OR REPLACE FUNCTION agent_by_queue_strategy(_queue_id bigint, _strategy varchar(20))
  RETURNS table (
    agent_ids int[]
  ) AS
$$
  declare
    sql text;
BEGIN
    if _strategy = 'ring-all' then
      return query
          select array_agg(aq.agent_id)::int[]
          from available_agent_in_queue aq
          where aq.queue_id = _queue_id;
    else
      sql = format('select (array[aq.agent_id])::int[]
      from available_agent_in_queue aq
        inner join cc_agent a on a.id = aq.agent_id
        left join cc_agent_in_queue_statistic s on s.agent_id = aq.agent_id and aq.queue_id = $1
      where aq.queue_id = $1
      order by aq.max_of_lvl desc,
      ')
        || case _strategy
            when 'longest-idle-time' then 's.ready_time desc nulls first'
            --r r
            --t d
            when 'least-talk-time' then 's.last_bridge_end asc nulls first'
            when 'fewest-calls' then 's.calls_answered asc nulls first'
           else 'random()' end
      ;

      return query execute sql using _queue_id;
    end if ;

    --raise notice '% = %',_strategy, sql;


END;
$$ LANGUAGE 'plpgsql';





--where aq.queue_id = 1
;


explain analyse
select *
from (
  select at.id, a.*, at.queue_id, row_number() over (order by at.weight desc, at.created_at) pos_at, at.queue_id
  from (
      select *
      from cc_member_attempt at
      where at.hangup_at = 0 --and at.state = 7
  ) as at
    cross join lateral (
        select *, row_number() over (partition by aq.queue_id order by aq.ratio desc ) pos_ag
        from available_agent_in_queue aq
    ) a
  where at.queue_id = a.queue_id
) marge
-- where marge.pos_ag = marge.pos_at;

explain analyse
select distinct on (agent_id) agent_id, id--, case ratio when 2 then 0 else 1 end
from (
  select a.id, last_agent.agent_ids,  ag.*,
         row_number() over (order by a.weight desc, a.created_at, ag.ratio desc) rn
  from cc_member_attempt a
    left join lateral (
      select a1.agent_ids, a1.id as last_id
      from cc_member_attempt a1
      where a1.member_id = a.member_id and a1.hangup_at > 0
      order by a1.hangup_at desc
      limit 1
    ) last_agent on true
    cross join lateral (
          select *, row_number() over (partition by aq.agent_id order by aq.ratio desc ) pos_ag
          from available_agent_in_queue aq
    ) ag
  where a.hangup_at = 0 and a.state = 7 and a.queue_id = ag.queue_id
  order by a.weight desc, a.created_at, ag.ratio desc
) r
order by agent_id,
         --case ratio when 2 then 0 else 1 end,
         case when r.agent_ids && array[r.agent_id] then 1 else 0 end desc,
         ratio desc,
         rn asc,
         pos_ag asc,
         id asc;

--1 - 6745382
--2 - 6745386

/*
1,6745389
2,6745386
 */
drop function cc_reserved_agent_for_attempt;

CREATE OR REPLACE FUNCTION cc_reserved_agent_for_attempt(_node_id varchar(20))
  RETURNS table
          (
            attempt_id bigint,
            agent_ids  integer[]
          ) AS
$$
BEGIN
  RETURN QUERY update cc_member_attempt a
  set agent_ids = array[a1.agent_id]
  from (
         select distinct on (agent_id) agent_id,
                                       id--, case ratio when 2 then 0 else 1 end
         from (
                select a.id,
                       last_agent.agent_ids,
                       ag.*,
                       row_number() over (order by a.weight desc, a.created_at, ag.ratio desc) rn
                from cc_member_attempt a
                       left join lateral (
                  select a1.agent_ids, a1.id as last_id
                  from cc_member_attempt a1
                  where a1.member_id = a.member_id
                    and a1.hangup_at > 0
                  order by a1.hangup_at desc
                  limit 1
                  ) last_agent on true
                       cross join lateral (
                  select *, row_number() over (partition by aq.agent_id order by aq.ratio desc ) pos_ag
                  from available_agent_in_queue aq
                  ) ag
                where a.hangup_at = 0
                  and a.state = 7
                  and a.node_id = _node_id
                  and a.agent_ids isnull
                  and a.queue_id = ag.queue_id
                order by a.weight desc, a.created_at, ag.ratio desc
              ) r
         order by agent_id,
                  --case ratio when 2 then 0 else 1 end,
                  case when r.agent_ids && array [r.agent_id] then 1 else 0 end desc,
                  ratio desc,
                  rn asc,
                  pos_ag asc,
                  id asc
       ) a1
  where a1.id = a.id
  returning a.id, a.agent_ids;
END;
$$ LANGUAGE 'plpgsql';


select *
from cc_reserved_agent_for_attempt('ddd');


update cc_member_attempt
set state = 7,
    hangup_at = 0,
    agent_ids = null
where id = 6745664;

select * from cc_member_attempt
order by id desc ;

select reserve_members_with_resources('node-1');

delete from cc_member_attempt
where hangup_at = 0;

select aq.*
from available_agent_in_queue aq
  inner join cc_queue q on q.id = aq.queue_id
order by q.priority desc, aq.lvl desc;

select a.*, row_number() over ()
from agent_by_queue_strategy(1::int, 'ring-alla'::varchar(20)) a;


explain analyse
select q.id as queue_id, agents.agent_ids, row_number() over (partition by q.id) rn
from cc_queue q,
  lateral ( select a.agent_ids from agent_by_queue_strategy(q.id, q.strategy) a ) agents
order by q.priority desc;



select q.id, a.agent_ids, q.queue_id
from (
   select a.id, a.queue_id, row_number() over (partition by a.queue_id order by cm.priority desc) rn
   from cc_member_attempt a
          inner join cc_queue cq on a.queue_id = cq.id
          inner join cc_member cm on a.member_id = cm.id
   where a.hangup_at = 0 and a.state = 2 -- MEMBER_STATE_FIND_AGENT
   order by cq.priority desc, cm.priority desc
) q
inner join (
  select q.id as queue_id, agents.agent_ids, row_number() over (partition by q.id) rn
  from cc_queue q,
    lateral ( select a.agent_ids from agent_by_queue_strategy(q.id, q.strategy) a ) agents
  order by q.priority desc
) as a on a.queue_id = q.queue_id and q.rn = a.rn
;

select a.* --, a.hangup_at - a.created_at
from cc_member_attempt a
  inner join cc_member cm on a.member_id = cm.id
where a.hangup_at = 0
order by a.id, cm.priority desc;

update cc_member_attempt
set hangup_at = 100
where hangup_at = 0;

explain analyse
select count(*)
from cc_member_attempt
where hangup_at = 0 and queue_id = 1 ;

select *
from cc_member_attempt
order by id
;


explain analyse
select *
from reserve_members_with_resources('test');

truncate table cc_member_attempt;