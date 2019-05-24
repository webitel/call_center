
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
    set agent_id = res.agent_id
    from (
    with tmp as (
      select *, row_number() over (partition by tmp.queue_id order by tmp.queue_id) rn --TODO strategy
        from (
          select distinct on(a.agent_id) a.agent_id, a.queue_id
          from available_agent_in_queue a
          order by a.agent_id, a.ratio desc
        ) tmp
      )
      select r.id as attempt_id, r.queue_id, tmp.agent_id
      from (
        select *, row_number() over (partition by queue_id order by created_at) rn
        from cc_member_attempt a
        where a.hangup_at = 0 and a.state = 3 and a.agent_id isnull
      ) r
      inner join tmp on r.queue_id = tmp.queue_id and r.rn = tmp.rn
    ) res
    inner join cc_agent ag on ag.id = res.agent_id
    where a.id = res.attempt_id and a.agent_id isnull
    returning a.id::bigint as attempt_id, a.agent_id::bigint, ag.updated_at::bigint as agent_updated_at;
END;
$$ LANGUAGE 'plpgsql';



explain analyze
with r as (
 select *, row_number() over (partition by queue_id order by created_at) rn
 from cc_member_attempt a
 where a.hangup_at = 0
   and a.state = 3
   and a.agent_id isnull
)
select r.id as attempt_id, r.queue_id, tmp.agent_id
from (
select *,
         row_number() over (partition by tmp.queue_id order by tmp.queue_id) rn --TODO strategy
  from (
         select distinct on (a.agent_id) a.agent_id, a.queue_id
         from available_agent_in_queue a
         order by a.agent_id, a.ratio desc
       ) tmp
) tmp
 inner join r on r.queue_id = tmp.queue_id and r.rn = tmp.rn;