-- Inbox of email-service events in flow_manager: one row per event_id, so a
-- redelivered event never starts a second Flow.
-- No foreign keys: a failing insert would make the consumer retry the event forever.
CREATE TABLE IF NOT EXISTS flow.email_event
(
    event_id        uuid NOT NULL,
    domain_id       bigint NOT NULL,
    event_type      text NOT NULL,
    schema_version  integer NOT NULL,
    thread_id       bigint NOT NULL,
    message_id      bigint NOT NULL,
    flow_id         bigint,
    payload         jsonb NOT NULL,

    state           text NOT NULL DEFAULT 'pending',
    -- Counts failed Flow launches; recovering a lease does not spend one.
    attempts        integer NOT NULL DEFAULT 0,
    next_attempt_at timestamp with time zone NOT NULL DEFAULT now(),
    -- Lease of the worker handling the row; set only while processing.
    locked_by       text,
    locked_until    timestamp with time zone,
    accepted_at     timestamp with time zone,
    last_error      text,

    created_at      timestamp with time zone NOT NULL DEFAULT now(),
    updated_at      timestamp with time zone NOT NULL DEFAULT now(),

    CONSTRAINT email_event_pkey PRIMARY KEY (event_id),
    CONSTRAINT email_event_ids_valid
        CHECK (domain_id > 0 AND thread_id > 0 AND message_id > 0 AND schema_version > 0),
    CONSTRAINT email_event_flow_id_valid
        CHECK (flow_id IS NULL OR flow_id > 0),
    CONSTRAINT email_event_type_not_empty
        CHECK (event_type <> ''),
    CONSTRAINT email_event_state_valid
        CHECK (state IN ('pending', 'processing', 'accepted', 'failed')),
    CONSTRAINT email_event_attempts_valid
        CHECK (attempts >= 0),
    CONSTRAINT email_event_lease_complete
        CHECK (
            (state = 'processing' AND locked_by IS NOT NULL AND locked_until IS NOT NULL)
            OR (state <> 'processing' AND locked_by IS NULL AND locked_until IS NULL)
        ),
    CONSTRAINT email_event_accepted_complete
        CHECK ((state = 'accepted') = (accepted_at IS NOT NULL)),
    CONSTRAINT email_event_failed_has_error
        CHECK (state <> 'failed' OR last_error IS NOT NULL),
    CONSTRAINT email_event_last_error_length
        CHECK (last_error IS NULL OR char_length(last_error) <= 1024)
);

-- Rows due for a launch, in the order workers claim them.
CREATE INDEX IF NOT EXISTS email_event_ready_idx
    ON flow.email_event (next_attempt_at, created_at, event_id)
    WHERE state = 'pending';

-- Leases of workers that stopped without finishing their row.
CREATE INDEX IF NOT EXISTS email_event_lease_idx
    ON flow.email_event (locked_until)
    WHERE state = 'processing';

-- Cleanup of accepted rows after the retention period.
CREATE INDEX IF NOT EXISTS email_event_accepted_idx
    ON flow.email_event (accepted_at, event_id)
    WHERE state = 'accepted';
