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
  select distinct on (r.agent_id) r.agent_id as agent_id,
                                    r.updated_at,
                                    r.attempt_id
      from (
             select a.id as attempt_id,
                    last_agent.agent_id as last_agent_id,
                    ag.*,
                    row_number() over (order by a.weight desc, a.created_at, ag.ratio desc) rn
             from cc_member_attempt a
                    left join lateral (
               select a1.agent_id, a1.id as last_id
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
               and a.state = 3
               and a.queue_id = ag.queue_id
               and a.node_id = 'node-1'
               and a.agent_id isnull
             order by a.weight desc, a.created_at, ag.ratio desc
           ) r
      order by r.agent_id,
               --case ratio when 2 then 0 else 1 end,
               case when r.agent_id = r.last_agent_id then 1 else 0 end desc,
               r.ratio desc,
               r.rn asc,
               r.pos_ag asc,
               r.attempt_id asc;

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
            attempt_id       bigint,
            agent_id         bigint,
            agent_updated_at bigint
          ) AS
$$
BEGIN
  RETURN QUERY update cc_member_attempt a
    set agent_id = a1.agent_id
    from (
      select distinct on (r.agent_id) r.agent_id as agent_id,
                                    r.updated_at,
                                    r.attempt_id
      from (
             select a.id as attempt_id,
                    last_agent.agent_id as last_agent_id,
                    ag.*,
                    row_number() over (order by a.weight desc, a.created_at, ag.ratio desc) rn
             from cc_member_attempt a
                    left join lateral (
               select a1.agent_id, a1.id as last_id
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
               and a.state = 3
               and a.queue_id = ag.queue_id
               and a.node_id = _node_id
               and a.agent_id isnull
             order by a.weight desc, a.created_at, ag.ratio desc
           ) r
      order by r.agent_id,
               --case ratio when 2 then 0 else 1 end,
               case when r.agent_id = r.last_agent_id then 1 else 0 end desc,
               r.ratio desc,
               r.rn asc,
               r.pos_ag asc,
               r.attempt_id asc
    ) a1
    where a1.attempt_id = a.id
    returning a.id::bigint as attempt_id, a.agent_id::bigint as agent_id, a1.updated_at::bigint as agent_updated_at;
END;
$$ LANGUAGE 'plpgsql';


select *
from cc_member_attempt
order by id desc;

explain analyse
select h.state
from cc_agent_state_history h
where h.agent_id = 1
order by h.joined_at desc
limit 1;


explain analyse
select info
from cc_agent_state_history h
where h.joined_at > CURRENT_DATE and h.agent_id = 1
order by h.joined_at desc
limit 1;

explain analyse
select *
from cc_agent a
 left join lateral (
   select h.joined_at, h.state, h.timeout_at, h.info
   from cc_agent_state_history h
   where h.agent_id = a.id --and h.joined_at > current_date
   order by h.joined_at desc
   limit 1
   ) s on true
--where a.id = 1
order by a.id asc
limit 1000;
--where a.id = 1;

select status
from cc_agent a
where a.id = 1;

explain analyse
select *
from cc_member_attempt a
where a.hangup_at = 0 and a.agent_id = 1
for update;



insert into cc_agent_state_history (agent_id, state)
select a.id, a.status
from cc_agent a;


select *
from cc_member_attempt a;

update cc_agent
set status = 'test'
where id = 1;




explain analyse
select a.id, h.*
from cc_agent a
  left join (
    select h.agent_id, h.state, h.joined_at, row_number() over (partition by h.agent_id order by h.joined_at desc) rn
    from cc_agent_state_history h
    where h.joined_at > CURRENT_DATE
  ) h on h.agent_id = a.id and h.rn = 1
--where  a.id = 1
order by a.id asc;



select *
from cc_reserved_agent_for_attempt('node-1');

select *
from reserve_members_with_resources('node-1');

select *
from cc_member_attempt
where state <>-1
order by id desc ;


truncate table cc_member_attempt;

select *
from cc_member
where id = 41206;


update cc_member
set name = 'TODO-NAME-DB'
where 1= 1;

update cc_member_attempt
set state = 7,
    hangup_at = 0,
    agent_id = null
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
order by id desc
;

select count(*)
from cc_member_attempt;

explain analyse
select *
from reserve_members_with_resources('test');

truncate table cc_member_attempt;


update cc_member
set name = '223231321'
where 1=1;

select node_name,  TO_CHAR((( (updated_at - started_at)/1000 )::bigint || ' second')::interval, 'HH24:MI:SS') uptime
from cc_cluster;

truncate table cc_member_attempt;

select *
from cc_queue_is_working;


create unique index cc_queue_routing_queue_id_pattern_uindex
	on call_center.cc_queue_routing (queue_id, pattern);

select *
from reserve_members_with_resources('aa');

select *
from cc_queue;

update cc_member
set last_hangup_at  = 1
where 1=1;
