CREATE OR REPLACE FUNCTION call_center.cc_queue_params(q call_center.cc_queue) RETURNS jsonb
  LANGUAGE sql IMMUTABLE
AS $$
SELECT jsonb_build_object(
    'has_reporting', q.processing,
    'has_form', (q.processing AND q.form_schema_id IS NOT NULL),
    'processing_sec', q.processing_sec,
    'processing_renewal_sec', q.processing_renewal_sec,
    'queue_name', q.name,
    'has_prolongation', q.prolongation_enabled,
    'remaining_prolongations', q.prolongation_repeats_number,
    'prolongation_sec', q.prolongation_time_sec,
    'is_timeout_retry', q.prolongation_is_timeout_retry,
    'processing_autosave', q.processing_autosave
  );
$$;
