
drop function cc_add_to_queue;

CREATE OR REPLACE FUNCTION cc_add_to_queue(_queue_id bigint, _call_id varchar(36), _number varchar(50), _name varchar(50), _priority integer = 0)
  RETURNS bigint AS
$$
  declare
    _attempt_id bigint = null;
    _member_id bigint;
    _communication_id bigint;
BEGIN

  select cm.id, cc.id
  from cc_member_communications cc
    inner join cc_member cm on cc.member_id = cm.id
  where cc.number = _number and cm.queue_id = _queue_id
  limit 1
  into _member_id, _communication_id
  ;



  if _member_id isnull  then
    insert into cc_member(queue_id, name, priority)
    values (_queue_id, _name, _priority)
    returning id into _member_id;


    insert into cc_member_communications (member_id, priority, number)
    values (_member_id, _priority, _number)
    returning id into _communication_id;
  end if;

  insert into cc_member_attempt (state, communication_id, queue_id, member_id, weight, leg_a_id)
  values (0, _communication_id, _queue_id, _member_id, _priority, _call_id)
  returning id into _attempt_id;

  --raise notice '%', _attempt_id;

  return _attempt_id;

END;
$$ LANGUAGE 'plpgsql';

do
$do$
  declare
     i int;
begin
  FOR i IN 1..10 LOOP

   -- raise notice '%', i;
    perform from cc_add_to_queue(3, null, '7777' || i, 'IGOR', 100);
    commit;
--     perform from cc_add_to_queue(3, null, '7778' || i, 'IGOR', 100);
--     commit;


--     perform pg_sleep(1);
  end loop;
end
$do$;

select count(*)
--delete
from cc_member_attempt
where hangup_at = 0;




select *
from cc_member_attempt a
where a.id = 1124579 and hangup_at = 0 and state > -1 and state != 5;; [1:map[AttemptId:1124579]] (35.133802126s)



select r.agent_id, r.attempt_id, a2.updated_at
  from cc_distribute_agent_to_attempt('call-center') r
  inner join cc_agent a2 on a2.id = r.agent_id;



update cc_member_attempt a
set state = 7
where a.id = 11 and state != 5;

;
select q.id as queue_id, q.enabled,  case when q.enabled is true
  then (select attempt_id
     from cc_add_to_queue(q.id::bigint, '4dd01b60-cc8c-417e-baef-f9e8d19032d7'::varchar(36), 'linphone'::varchar(50), 'aaaa'::varchar(50), 0) attempt_id)
  else null
  end as attempt_id
from cc_queue q
where q.name = '32908' and q.type = 0;

select *
from cc_queue q
where q.name = '32908';

select attempt_id
from cc_add_to_queue(3, null, '7777' || 5, 'IGOR', 100) attempt_id;

select *
from cc_member_attempt
where id = 998851;


select q.id, case when q.enabled is true
  then (select attempt_id
     from cc_add_to_queue(3, null, '7777' || 5, 'IGOR', 100) attempt_id)
  else null
  end as attempt_id
from cc_queue q
where q.id = 3 and q.type = 0 ;


select count(*)
from cc_member_communications;

select count(*), agent_id
from cc_member_attempt
where hangup_at = 0
group by agent_id
having count(*) > 0;

select count(*)
from cc_member_attempt
where hangup_at = 0;



update cc_agent
set status = 'online'
where 1=1;


select count(*)
from cc_member_attempt
where hangup_at = 0;

select a.id, a.hangup_at - a.created_at, a.result, a.logs
from cc_member_attempt a
where a.hangup_at > 0
order by a.id desc
limit 100;



explain analyze
select *
from cc_member_attempt
where state > -1 and hangup_at = 0
order by leg_a_id;


select  extract(epoch from created_at)::bigint * 1000
from cc_member_attempt
where created_at > 0
order by id desc
limit 1;

explain (analyse, COSTS )
select *
from cc_member_attempt
where member_id = 100090 and node_id = 'call-center-1';

select *
from cc_set_active_members();


 select cc_available_agents_by_strategy(3, 'bla', 1000, array[0]::bigint[] , array[0]::bigint[]);


    select r.agent_id, r.attempt_id, a2.updated_at
    from cc_distribute_agent_to_attempt('test') r
    inner join cc_agent a2 on a2.id = r.agent_id;


select *
			from cc_reserve_members_with_resources('node-1');

select *
from cc_set_active_members('node-1');


select count(*)
--delete
from cc_member_attempt
where hangup_at = 0;


update cc_member_attempt
set state  = 3, agent_id = null
where hangup_at = 0;





create or replace view dispatcher as
SELECT t1.id,
       t1.destination,
       t1.attrs,
       t1.setid
FROM call_center.dblink(
         'hostaddr=192.168.177.199 dbname=webitel user=opensips password=webitel options=-csearch_path=public'::text, 'select id, destination, attrs, setid
from dispatcher'::text) t1(id integer, destination character varying(192), attrs character varying(128), setid integer);


select *
from get_free_resources();

select *
from cc_queue_is_working;

explain analyze
update cc_agent
set state = 'waiting',
    status = 'offline',
    state_timeout = null;
--where state_timeout < now();

select *
from cc_agent;

select *
from cc_member_attempt
where hangup_at = 0;

select *
			from cc_set_active_members('node-1') s;





explain analyze
select count(distinct  COALESCE(aq.agent_id, csia.agent_id)) as cnt
from cc_agent_in_queue aq
   left join cc_skils cs on aq.skill_id = cs.id
   left join cc_skill_in_agent csia on cs.id = csia.skill_id
where aq.queue_id = 3
  --and COALESCE(aq.agent_id, csia.agent_id) notnull
  and  COALESCE(aq.agent_id, csia.agent_id) not in (
    select a.agent_id
    from cc_member_attempt a
    where a.state > 0 and not a.agent_id isnull
  );




update cc_agent
set status = 'online',
    state = 'waiting'
where 1=1;

select *
from cc_agent;


vacuum full cc_member_communications;

select count(*)
--delete
from cc_member_attempt
where hangup_at = 0;


 select *
from cc_set_active_members('aaa');

SELECT * FROM heap_page('cc_member_attempt',0);


explain analyze
select count(*)
from cc_member_attempt
where hangup_at = 0;



 select s as count
from cc_reserve_members_with_resources('aaa') s;


select *
from get_free_resources();


select *
from cc_queue_is_working;



explain analyze
select id, name, timeout, updated_at, max_calls, active_calls.cnt as active_calls, enabled, calendar.ready as calendar_ready
from cc_queue q,
 lateral (
   select exists(
     select *
     from calendar_accept_of_day d
       inner join calendar c2 on d.calendar_id = c2.id
     where d.calendar_id = q.calendar_id AND
           (to_char(current_timestamp AT TIME ZONE c2.timezone, 'SSSS') :: int / 60)
           between d.start_time_of_day AND d.end_time_of_day
     ) as ready
 ) calendar
 left join lateral (
    select count(*) cnt
    from cc_member_attempt a
    where a.hangup_at = 0 and a.queue_id = q.id
 ) active_calls on true
where q.type = 0 and q.domain_id = 1
limit 1;


  select * from cc_add_to_queue(3, null, '7777' || 10, 'IGOR', 100);

select *
from cc_member_attempt
where id = 584689;


select '7777' || 1;

select *
from cc_member
where queue_id = 3;




update cc_agent
set status = 'online'
where 1=1;


delete from cc_member
where id = 50054;

select *
from cc_member m
  inner join cc_member_communications cmc on m.id = cmc.member_id
where m.queue_id = 3;


explain analyze
  select cm.id
  from cc_member_communications cc
    inner join cc_member cm on cc.member_id = cm.id
  where cc.number = 'fc97b9c7c4243538' and cm.queue_id = 1