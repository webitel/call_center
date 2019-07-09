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
  FOR i IN 1..1000 LOOP

   -- raise notice '%', i;
    perform from cc_add_to_queue(3, null, '7777' || i, 'IGOR', 100);
--     commit;
--     perform from cc_add_to_queue(3, null, '7778' || i, 'IGOR', 100);
--     commit;


    --perform pg_sleep(1);
  end loop;
end
$do$;

;



vacuum full cc_member_communications;

select count(*)
--delete
from cc_member_attempt
where state != -1
;


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