drop view vw_cc_member_communication;

create view vw_cc_member_communication as
SELECT c.id,
       c.member_id,
       c.priority,
       c.number,
       c.last_originate_at,
       c.state,
       c.communication_id,
       c.routing_ids,
       c.description,
       c.last_hangup_at,
       c.attempts,
       c.last_hangup_cause,
       a.attempt_in_day
FROM call_center.cc_member_communications c,
     LATERAL ( SELECT count(*) AS attempt_in_day
               FROM call_center.cc_member_attempt a_1
               WHERE ((a_1.communication_id = c.id) AND
                      (date_part('doy'::text, a_1.hangup_time) = date_part('doy'::text, CURRENT_TIMESTAMP)))) a;

alter table vw_cc_member_communication
  owner to webitel;

