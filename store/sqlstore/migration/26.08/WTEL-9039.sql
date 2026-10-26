ALTER TABLE call_center.cc_pause_cause ADD COLUMN IF NOT EXISTS team_ids integer[];

CREATE OR REPLACE VIEW call_center.cc_pause_cause_list AS
 SELECT s.id,
    s.created_at,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS created_by,
    s.updated_at,
    call_center.cc_get_lookup(uc.id, (COALESCE(uc.name, (uc.username)::text))::character varying) AS updated_by,
    s.name,
    s.description,
    s.limit_min,
    s.allow_agent,
    s.allow_supervisor,
    s.allow_admin,
    s.domain_id,
    s.team_ids,
    (SELECT jsonb_agg(call_center.cc_get_lookup(t.id, t.name::character varying))
       FROM call_center.cc_team t
      WHERE t.id = ANY (s.team_ids) AND t.domain_id = s.domain_id) AS teams
   FROM ((call_center.cc_pause_cause s
     LEFT JOIN directory.wbt_user uc ON ((uc.id = s.created_by)))
     LEFT JOIN directory.wbt_user uu ON ((uu.id = s.updated_by)));