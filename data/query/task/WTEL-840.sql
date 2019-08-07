

create table cc_member_attempt_log (
    like cc_member_attempt
    including defaults
    including constraints
    including indexes
);

select *
from cc_member_attempt_log;


select *
into cc_member_attempt_log
from cc_member_attempt;


insert into cc_member_attempt_log (id, communication_id, timing_id, queue_id, state, member_id, created_at, weight,
                                   hangup_at, bridged_at, resource_id, leg_a_id, leg_b_id, node_id, result,
                                   originate_at, answered_at, routing_id, logs, agent_id)
select id, communication_id, timing_id, queue_id, state, member_id, created_at, weight, hangup_at, bridged_at, resource_id, leg_a_id, leg_b_id, node_id, result, originate_at, answered_at, routing_id, logs, agent_id
from cc_member_attempt;


select count(*)
--delete
from cc_member_attempt_log
where hangup_at = 0;



truncate table cc_member_attempt;

alter table cc_member_attempt set UNLOGGED;
alter table cc_member_attempt set (log_autovacuum_min_duration = 0,
autovacuum_vacuum_scale_factor = 0.01,
autovacuum_analyze_scale_factor = 0.05,
autovacuum_enabled= 1,
--autovacuum_naptime = 60,
autovacuum_vacuum_cost_delay = 20);


explain analyze
select *
from cc_member_attempt;

drop function cc_transfer_attempt_to_log;
CREATE OR REPLACE FUNCTION cc_transfer_attempt_to_log()
  RETURNS trigger AS
$$
BEGIN
  with rem as (
    delete from cc_member_attempt a
      where a.id = new.id
      returning *
  )
  insert
  into cc_member_attempt_log (id, communication_id, timing_id, queue_id, state, member_id, created_at, weight,
                              hangup_at, bridged_at, resource_id, leg_a_id, leg_b_id, node_id, result,
                              originate_at, answered_at, routing_id, logs, agent_id)
  select id,
         communication_id,
         timing_id,
         queue_id,
         state,
         member_id,
         created_at,
         weight,
         hangup_at,
         bridged_at,
         resource_id,
         leg_a_id,
         leg_b_id,
         node_id,
         result,
         originate_at,
         answered_at,
         routing_id,
         logs,
         agent_id
  from rem;

  return new;
END;
$$ LANGUAGE 'plpgsql';



CREATE TRIGGER cc_tg_transfer_attempt_to_log
  after update
  ON cc_member_attempt
FOR EACH ROW
  WHEN (NEW.state = -1)
  EXECUTE PROCEDURE  cc_transfer_attempt_to_log();

explain
select count(*)
from cc_member_attempt; -- 0

select count(*)
from cc_member_attempt_log; --1102909

select *
from cc_member_attempt_log
where id = 1690769
order by hangup_at desc ;


truncate table cc_member_attempt;




