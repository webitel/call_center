CREATE OR REPLACE FUNCTION cc_set_agent_change_status()
  RETURNS trigger AS
$BODY$
BEGIN
  insert into cc_agent_state_history (agent_id, joined_at, state, payload)
  select new.id, now(), case when new.status = 'online' then 'waiting' else new.status end, new.status_payload
  where not exists(
    select *
    from cc_member_attempt a
    where a.hangup_at = 0 and a.agent_id = new.id
  );
  RETURN new;
END;
$BODY$ language plpgsql;

drop trigger tg_cc_set_agent_change_status on cc_agent;


CREATE TRIGGER tg_cc_set_agent_change_status
  BEFORE UPDATE OR INSERT
  ON cc_agent
  FOR EACH ROW WHEN (  )
EXECUTE PROCEDURE cc_set_agent_change_status();


select count(*)
from cc_member_attempt
where agent_id = 1
group by queue_id;

select count(*)
from cc_agent_state_history;

explain analyse
select a.id, ca.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload
from (
       select distinct on (agent_id) agent_id, joined_at, timeout_at, state
       from cc_agent_state_history h
       where h.joined_at > current_date - '1 day'::interval
       order by h.agent_id, h.joined_at desc
     ) ca
       inner join cc_agent a on a.id = ca.agent_id
where ca.timeout_at <= now();


explain analyse
select *
from (
  select a.id, h.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload
from cc_agent a
  ,lateral (
    select h.timeout_at
    from cc_agent_state_history h
    where h.agent_id = a.id
    order by h.joined_at desc
    limit 1
  ) h
where  a.status in  ('online', 'pause') and h.timeout_at < now()
) t;

select count(id)
from cc_agent_state_history
where agent_id = 1 and timeout_at < now();


UPDATE "call_center"."cc_agent" SET "no_answer_delay_time" = 2, "updated_at" = 6 WHERE "id" = 1

vacuum full cc_agent_state_history;

select count(*)
from cc_member_attempt
where to_timestamp(created_at/1000) > current_date - '1 day'::interval;



update cc_agent
set status = 'waiting'
  ,status_payload = '{}'
where id = 1;


select *
from cc_agent_state_history h
order by h.joined_at desc ;

truncate table cc_agent_state_history;
vacuum full cc_agent_state_history;

;

explain analyse
select h1.state,h1.joined_at,lag(joined_at) over (order by joined_at desc) as leaving_at--, to_char(coalesce(lag(join_at) over (order by join_at desc), now()) - join_at, 'HH24:MI:SS') "min_sec"
from cc_agent_state_history h1
where h1.agent_id= 2
order by h1.joined_at desc--, h2.join_at  desc nulls first
limit 1;


explain analyse
select agent_id, h1.state, h1.joined_at
from cc_agent_state_history h1
where h1.agent_id = 2 and h1.joined_at < now() - interval '20 sec'
order by h1.joined_at desc--, h2.join_at  desc nulls first
    ;


select *
from (select distinct on (h1.agent_id) agent_id,h1.state,h1.joined_at,to_char(coalesce(lag(joined_at) over (partition by agent_id order by joined_at desc), now()) - joined_at, 'MI:SS') "min_sec"
    from cc_agent_state_history h1
    order by h1.agent_id, h1.joined_at desc--, h2.join_at  desc nulls first
) h
limit 10
;

select *
from cc_member_attempt
order by id desc;

explain analyse
select h.agent_id, h.state, h.joined_at, h2.joined_at leaving_at, to_char(coalesce(h2.joined_at, now()) - h.joined_at, 'HH24:MI:SS') as min_sec
from cc_agent_state_history h
 left join lateral (
  select *
   from cc_agent_state_history h2
   where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
   order by h2.joined_at asc
   limit 1
  ) h2 on true
where h.agent_id = 1 --and h.joined_at > '2019-04-11 07:47:47.164791' and not h2.joined_at isnull
order by h.joined_at desc
limit 10
;
--2019-04-11 10:57:05.595552


select h.agent_id, h.state, h.joined_at, h2.joined_at leaving_at, to_char(coalesce(h2.joined_at, now()) - h.joined_at, 'HH24:MI:SS') as min_sec
from call_center.cc_agent_state_history h
 left join lateral (
  select *
   from call_center.cc_agent_state_history h2
   where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
   order by h2.joined_at asc
   limit 1
  ) h2 on true
where h.agent_id = 1 --and h.joined_at > '2019-04-11 07:47:47.164791' and not h2.joined_at isnull
order by h.joined_at desc
limit 10;

delete from cc_member_attempt
  where state != -1;

explain analyse
select h.agent_id, ca.name, h.state, to_char(avg(coalesce(h2.joined_at, now()) - h.joined_at), 'HH24:MI:SS') as t--, max(h.joined_at)
from cc_agent_state_history h
 left join lateral (
  select *
   from cc_agent_state_history h2
   where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
   order by h2.joined_at asc
   limit 1
  ) h2 on true
inner join cc_agent ca on h.agent_id = ca.id
where h.agent_id = 1 and h.joined_at > now() - interval '25 min '-- '2019-04-11 07:47:47.164791'-- and not h2.joined_at isnull
group by h.agent_id, h.state, ca.name
;

explain analyse
select a.id, a.name, h.state, to_char(now() - h.joined_at, 'HH24:MI:SS') as min_sec
from cc_agent a
 left join lateral (
  select h.agent_id, h.state, joined_at
   from cc_agent_state_history h
   where h.agent_id = a.id
   order by h.joined_at desc
   limit 1
  ) h on true
--where a.id = 2
order by h.joined_at desc nulls last
limit 10;

insert into cc_agent_state_history (agent_id, state)
select 2, 'ready2'
returning *;



select cm.id as member_id, cmc.number, cq.name, case a.state when -1 then 'hangup' else 'talk' end as call_state, a.result
from cc_member_attempt a
  inner join cc_member cm on a.member_id = cm.id
  inner join cc_member_communications cmc on a.communication_id = cmc.id
  inner join cc_queue cq on cm.queue_id = cq.id
where agent_id = 1
order by a.created_at desc
limit 15;

explain analyse
select *
from cc_agent_state_history h
where h.agent_id = 1 and h.joined_at > CURRENT_DATE --and h.state = 'waiting'
order by h.joined_at desc;
--extract(doy from now()) and h.state = 'waiting';

--100000 rows affected in 8 s 404 ms

select CURRENT_DATE ;

explain analyse
select h.agent_id, ca.name as agent_name, h.state, to_char(sum(coalesce(h2.joined_at, now()) - h.joined_at), 'HH24:MI:SS') as t--, max(h.joined_at)
from cc_agent_state_history h
 left join lateral (
  select *
   from cc_agent_state_history h2
   where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
   order by h2.joined_at asc
   limit 1
  ) h2 on true
inner join cc_agent ca on h.agent_id = ca.id
where h.agent_id = 1 and h.joined_at > CURRENT_DATE and h.state = 'waiting'
group by h.agent_id, h.state, ca.name;


explain analyse
select q.name queue_name, g.cnt
from (
   select a.queue_id, count(*) cnt
  from cc_member_attempt a
  where to_timestamp(created_at/1000) > CURRENT_DATE and a.agent_id = 1
  group by a.queue_id
) g
inner join cc_queue q on q.id = g.queue_id;


update cc_agent a
set logged = true
where a.id = 1
returning a.*;


DO
$do$
DECLARE
  rec RECORD;
BEGIN
   FOR rec IN select 2, md5(random()::TEXT)::varchar(20)
      from generate_series(1, 2)
   LOOP
     insert into cc_agent_state_history (agent_id, state)
     values (2, md5(random()::TEXT)::varchar(20));

     perform pg_sleep(1);
     raise notice 'OK';
   END LOOP;
END
$do$;

select * from cc_agent
where id = 1;

select *
from cc_agent_activity;

explain analyse
with ag as (
  select a.id as agent_id, a.max_no_answer, caa.successively_no_answers, (a.max_no_answer > 0 and a.max_no_answer > caa.successively_no_answers + 1) next_call
  from cc_agent a
    inner join cc_agent_activity caa on a.id = caa.agent_id
  where a.id = :AgentId
)
update cc_agent_activity a
set last_offering_call_at = :OfferingAt,
    last_answer_at = case when :AnswerAt = 0::bigint then last_answer_at else :AnswerAt end,
    last_bridge_start_at = case when :BridgedStartAt = 0::bigint then last_bridge_start_at else :BridgedStartAt end,
    last_bridge_end_at = case when :BridgedStopAt = 0::bigint then last_bridge_end_at else :BridgedStopAt end,
    calls_abandoned = case when :AnswerAt = 0::bigint then calls_abandoned + 1 else calls_abandoned end,
    calls_answered = case when :AnswerAt != 0::bigint then calls_answered + 1 else calls_answered end,
    successively_no_answers = case when :NoAnswer and ag.next_call is true then a.successively_no_answers + 1 else 0 end
from ag
where a.agent_id = ag.agent_id
returning case when :NoAnswer and ag.next_call is false then 1 else 0 end stopped;



explain analyse
update cc_agent_activity ac
  set sum_idle_of_day = EXTRACT(epoch FROM t.sum_idle),
      sum_talking_of_day = EXTRACT(epoch FROM t.sum_talking),
      sum_pause_of_day = EXTRACT(epoch FROM t.sum_pause)
from (
  select h.agent_id,
       sum(coalesce(h2.joined_at, now()) - h.joined_at) filter ( where h.state = 'waiting' ) sum_idle,
       sum(coalesce(h2.joined_at, now()) - h.joined_at) filter ( where h.state = 'talking' ) sum_talking,
       sum(coalesce(h2.joined_at, now()) - h.joined_at) filter ( where h.state = 'pause' ) sum_pause
  from call_center.cc_agent_state_history h
   left join lateral (
    select *
     from call_center.cc_agent_state_history h2
     where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
     order by h2.joined_at asc
     limit 1
    ) h2 on true
  where  h.joined_at > current_date
  group by h.agent_id
) t
where ac.agent_id = t.agent_id;


select count(*)
from cc_agent_state_history h
where h.joined_at > current_date;


explain analyse
select *
from (
  select
    h.agent_id,
    h.joined_at,
    h.timeout_at,
    row_number() over (partition by h.agent_id order by h.joined_at desc) rn
  from cc_agent_state_history h
) t
where t.rn =1 and not t.timeout_at isnull ;


explain analyse
select a.id, ca.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload
from (
  select distinct on(agent_id) agent_id, joined_at, timeout_at, state
  from cc_agent_state_history h
  where h.joined_at > current_date - '1 day'::interval
  order by h.agent_id, h.joined_at desc
) ca
inner join cc_agent a on a.id = ca.agent_id
where not ca.timeout_at isnull ;


vacuum full cc_member_communications;


select a.id, ca.timeout_at, case when a.status = 'online' then 'waiting' else a.status end, a.status_payload
from (
  select distinct on(agent_id) agent_id, joined_at, timeout_at, state
  from cc_agent_state_history h
  where h.joined_at > current_date - '1 day'::interval
  order by h.agent_id, h.joined_at desc
) ca
inner join cc_agent a on a.id = ca.agent_id
where ca.timeout_at <= now()

update cc_member
set stop_at = 0
where 1=1;


delete from cc_list_communications
where number in (
  select cc_member_communications.number
  from cc_member_communications
);


explain analyse
select h.agent_id, h.timeout_at, case when ca.status = 'online' then 'waiting' else ca.status end, ca.status_payload
from cc_agent_state_history h
    inner join cc_agent ca on h.agent_id = ca.id
where h.timeout_at <= now()
    and not exists(
      select *
      from cc_agent_state_history h2
       where h2.agent_id = h.agent_id and h2.joined_at > h.joined_at
  );