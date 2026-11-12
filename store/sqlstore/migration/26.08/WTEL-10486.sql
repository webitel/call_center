CREATE SEQUENCE IF NOT EXISTS call_center.cc_user_notification_id_seq;

CREATE TABLE IF NOT EXISTS call_center.cc_user_notification
(
    id         bigint                                 NOT NULL,
    domain_id  bigint                                 NOT NULL,
    user_id    bigint                                 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    type       character varying                      NOT NULL,
    message    text                                   NOT NULL,
    read_at    timestamp with time zone,
    CONSTRAINT cc_user_notification_pk PRIMARY KEY (id, user_id),
    CONSTRAINT cc_user_notification_wbt_user_fk FOREIGN KEY (domain_id, user_id)
        REFERENCES directory.wbt_user (dc, id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS cc_user_notification_user_id_created_at_index
    ON call_center.cc_user_notification (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS cc_user_notification_created_at_index
    ON call_center.cc_user_notification (created_at);
