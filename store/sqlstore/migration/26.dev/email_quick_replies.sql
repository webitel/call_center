-- Email quick replies: channel and HTML of a reply. Existing replies keep an empty channel.
-- Every step can be repeated.

ALTER TABLE call_center.cc_quick_reply
    ADD COLUMN IF NOT EXISTS channel text DEFAULT ''::text NOT NULL,
    ADD COLUMN IF NOT EXISTS html text DEFAULT ''::text NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_quick_reply'::regclass
          AND conname = 'cc_quick_reply_channel_c'
    ) THEN
        ALTER TABLE call_center.cc_quick_reply
            ADD CONSTRAINT cc_quick_reply_channel_c CHECK (channel IN ('', 'email'));
    END IF;

    -- HTML is kept only for Email replies.
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'call_center.cc_quick_reply'::regclass
          AND conname = 'cc_quick_reply_html_c'
    ) THEN
        ALTER TABLE call_center.cc_quick_reply
            ADD CONSTRAINT cc_quick_reply_html_c CHECK (channel = 'email' OR html = '');
    END IF;
END
$$;

CREATE OR REPLACE VIEW call_center.cc_quick_reply_list AS
 SELECT a.domain_id,
    a.id,
    a.text,
    ( SELECT jsonb_agg(call_center.cc_get_lookup((q.id)::bigint, q.name)) AS jsonb_agg
           FROM call_center.cc_queue q
          WHERE (q.id = ANY (a.queues))) AS queues,
    a.queues AS queue_ids,
    a.teams AS team_ids,
    ( SELECT jsonb_agg(call_center.cc_get_lookup(t.id, t.name)) AS jsonb_agg
           FROM call_center.cc_team t
          WHERE (t.id = ANY (a.teams))) AS teams,
    a.name,
    a.created_at,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
    a.updated_at,
    call_center.cc_get_lookup(uu.id, (COALESCE(uu.name, (uu.username)::text))::character varying) AS updated_by,
    row_number() OVER (PARTITION BY a.domain_id ORDER BY
        CASE
            WHEN (COALESCE(array_length(a.queues, 1), 0) > 0) THEN 1
            WHEN (COALESCE(array_length(a.teams, 1), 0) > 0) THEN 2
            ELSE 3
        END) AS sort_priority,
    a.channel,
    a.html
   FROM ((call_center.cc_quick_reply a
     LEFT JOIN directory.wbt_user uc ON ((uc.id = a.created_by)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = a.updated_by)));
