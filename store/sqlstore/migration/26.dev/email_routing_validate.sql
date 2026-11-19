-- After email_routing_update.sql commits; run without an enclosing transaction.
-- Each validation is repeatable and permits ordinary reads and writes.
SET lock_timeout = '5s';

ALTER TABLE call_center.cc_agent
    VALIDATE CONSTRAINT cc_agent_email_count_c;
ALTER TABLE call_center.cc_agent
    VALIDATE CONSTRAINT cc_agent_extra_email_count_c;
ALTER TABLE call_center.cc_member_attempt
    VALIDATE CONSTRAINT cc_member_attempt_email_slot_c;
ALTER TABLE call_center.cc_email_join
    VALIDATE CONSTRAINT cc_email_join_priority_c;

RESET lock_timeout;
