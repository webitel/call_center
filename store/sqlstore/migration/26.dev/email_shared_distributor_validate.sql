-- After email_shared_distributor_prepare.sql commits; no enclosing transaction.
SET lock_timeout = '5s';

ALTER TABLE call_center.cc_email_join
    VALIDATE CONSTRAINT cc_email_join_priority_c;

RESET lock_timeout;
