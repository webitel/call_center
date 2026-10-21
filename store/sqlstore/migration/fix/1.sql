create index concurrently cc_audit_rate_rated_user_created_idx
      on call_center.cc_audit_rate (rated_user_id, call_created_at)
      include (score_required, score_optional);

      