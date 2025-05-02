ALTER TABLE call_center.cc_audit_rate
ADD COLUMN select_yes_count bigint DEFAULT 0,
ADD COLUMN critical_count bigint DEFAULT 0;