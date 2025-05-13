CREATE OR REPLACE VIEW call_center.cc_audit_form_view AS
SELECT i.id,
       i.name,
       i.description,
       i.domain_id,
       i.created_at,
       call_center.cc_get_lookup(uc.id, (coalesce(uc.name, uc.username))::character varying) AS created_by,
       i.updated_at,
       call_center.cc_get_lookup(u.id, (coalesce(u.name, u.username))::character varying) AS updated_by,
       (SELECT jsonb_agg(call_center.cc_get_lookup(aud.id, (aud.name)::character varying)) AS jsonb_agg
        FROM call_center.cc_team aud
        WHERE (aud.id = ANY (i.team_ids))) AS teams,
       i.enabled,
       i.questions,
       i.team_ids,
       i.editable,
       i.archive
FROM ((call_center.cc_audit_form i
         LEFT JOIN directory.wbt_user uc ON ((uc.id = i.created_by)))
         LEFT JOIN directory.wbt_user u ON ((u.id = i.updated_by))); 