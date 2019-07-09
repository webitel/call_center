

drop function cc_set_attempt_success;
CREATE OR REPLACE FUNCTION cc_set_attempt_success(_attempt_id bigint, _hangup_at bigint, _logs jsonb, _cause varchar(50))
  RETURNS void AS
$$
DECLARE
  _cnt int;
  _member_id bigint;
  _communication_id bigint;
BEGIN
     update cc_member_attempt
     set hangup_at = _hangup_at,
         state = -2, --todo
         result = _cause,
         logs = _logs
     where id = _attempt_id
     returning member_id, communication_id into _member_id, _communication_id;

     GET DIAGNOSTICS _cnt = ROW_COUNT;

     if _cnt = 0 then
       RAISE EXCEPTION 'not found attempt';
     end if;

     update cc_member
     set attempts = attempts + 1,
         stop_cause = _cause,
         stop_at = _hangup_at,
         last_hangup_at = _hangup_at
     where id = _member_id;

     GET DIAGNOSTICS _cnt = ROW_COUNT;

     if _cnt = 0 then
       RAISE EXCEPTION 'not found member in attempt';
     end if;

     update cc_member_communications
      set state = 1,
          attempts = case _communication_id when id then attempts + 1 else attempts end,
          last_hangup_at = case _communication_id when id then _hangup_at else last_hangup_at end,
          last_hangup_cause = case _communication_id when id then _cause else last_hangup_cause end
     where member_id = _member_id;

     GET DIAGNOSTICS _cnt = ROW_COUNT;

     if _cnt = 0 then
       RAISE EXCEPTION 'not found member communications';
     end if;
END;
$$ LANGUAGE 'plpgsql';

select cc_set_attempt_success(6695831, 6695831, '{}');

explain analyze
update cc_member m
     set attempts = attempts + 1,
         stop_cause = case when (q.max_of_retry <= attempts + 1) or c.cnt = 0 then 'ddd' else stop_cause end,
         stop_at = case when (q.max_of_retry <= attempts + 1) or c.cnt = 0 then 0 else stop_at end,
         last_hangup_at = 0
     from cc_queue q,
          lateral (
             select count(c.id) as cnt
             from cc_member_communications c
             where c.member_id = 51833 and c.state = 0
          ) c
     where m.id = 51833 and q.id = m.queue_id
     returning stop_at > 0, c.cnt > 0;


update  cc_member m
set last_hangup_at = 0
from cc_member m1
where m.id = 51833;


select cc_set_attempt_stop(644116::bigint, 0::smallint, true, 1555679162594::bigint, null::jsonb, 'OUTGOING_CALL_BARRED'::varchar(50));

drop function cc_set_attempt_stop;
CREATE OR REPLACE FUNCTION cc_set_attempt_stop(_attempt_id bigint, _delta smallint, _is_err boolean, _hangup_at bigint, _logs jsonb, _cause varchar(50))
  RETURNS boolean AS
$$
DECLARE
--   _cnt int;
  _stopped boolean;
  _break boolean;
  _member_id bigint;
  _communication_id bigint;
BEGIN
     update cc_member_attempt
     set hangup_at = _hangup_at,
         state = -1, --todo
         result = _cause,
         logs = _logs
     where id = _attempt_id
     returning member_id, communication_id into _member_id, _communication_id;


     if _member_id isnull then
       RAISE EXCEPTION 'not found attempt';
     end if;

     update cc_member_communications c
      set state = case when _is_err then 1 else state end,
          attempts = attempts + _delta,
          last_hangup_cause = _cause,
          last_hangup_at = _hangup_at
     where c.id = _communication_id and _delta != 0;

--      if _cnt = 0 and _delta != 0 then
--        RAISE EXCEPTION 'not found communication';
--      end if;

     update cc_member m
     set attempts = attempts + _delta,
         stop_cause = case when (q.max_of_retry <= attempts + _delta) or c.cnt = 0 then _cause else stop_cause end,
         stop_at = case when (q.max_of_retry <= attempts + _delta) or c.cnt = 0 then _hangup_at else stop_at end,
         last_hangup_at = _hangup_at
     from cc_queue q,
          lateral (
             select count(c.id) as cnt
             from cc_member_communications c
             where c.member_id = _member_id and c.state = 0
          ) c
     where m.id = _member_id and q.id = m.queue_id and _delta != 0
     returning stop_at > 0, c.cnt > 0 into _stopped, _break;

--      GET DIAGNOSTICS _cnt = ROW_COUNT;
--
--      if _cnt = 0 and _delta != 0 then
--        RAISE EXCEPTION 'not found member in attempt';
--      end if;

     if _stopped is true and _break is true then
--
        update cc_member_communications
         set state = 1
        where member_id = _member_id and id != _communication_id;
     end if;

     if _stopped isnull then
       _stopped = false;
     end if;

     return _stopped;
END;
$$ LANGUAGE 'plpgsql';


update cc_member_communications
   set state = 1
where member_id = 50706 and id != 150789;



select *
from cc_member
where id = 81;

UPDATE "call_center"."cc_agent" SET max_no_answer = 0 , no_answer_delay_time = 1, "updated_at" = 4, "call_timeout" = 1 WHERE "id" = 1;

select *
from cc_member_communications
where member_id = 81;

drop function cc_set_attempt_barred;

CREATE OR REPLACE FUNCTION cc_set_attempt_barred(_attempt_id bigint, _hangup_at bigint, _logs jsonb, _cause varchar(50))
  RETURNS boolean AS
$$
DECLARE
  _cnt int;
  _stopped boolean;
  _member_id bigint;
  _communication_id bigint;
BEGIN
     update cc_member_attempt
     set hangup_at = _hangup_at,
         state = -1, --todo
         result = _cause,
         logs = _logs
     where id = _attempt_id
     returning member_id, communication_id into _member_id, _communication_id;

     GET DIAGNOSTICS _cnt = ROW_COUNT;

     if _cnt = 0 then
       RAISE EXCEPTION 'not found attempt';
     end if;

     update cc_member_communications c
      set state = 1,
          last_hangup_cause = _cause,
          last_hangup_at = _hangup_at
     where c.id = _communication_id;

     GET DIAGNOSTICS _cnt = ROW_COUNT;

     if _cnt = 0 then
       RAISE EXCEPTION 'not found communication';
     end if;

     _stopped = false;
     if not exists(select * from cc_member_communications where member_id = _member_id and state = 0) then
       update cc_member m
        set stop_at = _hangup_at,
            last_hangup_at = _hangup_at,
            stop_cause = _cause
       where m.id = _member_id;

       _stopped = true;
     end if;

  return _stopped;
END;
$$ LANGUAGE 'plpgsql';



select cc_set_attempt_error(6695842, 1231, '{}', 'aaaa');

-- need calls to member
select *
from cc_member m,
     lateral ( select *
     from cc_member_communications c
     where c.member_id = m.id and c.state = 0
     order by c.last_hangup_at asc
     limit 1
     ) as c
where m.stop_at = 0 and m.queue_id = 1;

update cc_member_communicationsst
set state = 0, last_hangup_at = 0
where 1=1;

update cc_member
set  stop_at = 0
where queue_id=1;

select count(*)
from cc_member_communications c,
     lateral (
      select * from cc_member_attempt a
      where a.communication_id = c.id
       order by hangup_at desc
       limit 1
       )a
;

select *
from cc_member_communications
where id = 121500;

select * --count(*)
from cc_member_attempt
where not id in (
  select a.id
  from cc_member_communications c,
     lateral (
      select * from cc_member_attempt a
      where a.communication_id = c.id
       order by hangup_at desc
       limit 1
       )a
  );

select *
from cc_member_attempt
order by id desc ;

select count(*)
from cc_member
where stop_at = 0
order by stop_at desc;

vacuum full cc_member_communications;

select *
from cc_member
where id = 9367;

select *
from cc_member_communications
where member_id = 9367;


