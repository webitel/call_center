ALTER TABLE call_center.cc_audit_rate
ADD COLUMN select_yes_count bigint DEFAULT 0,
ADD COLUMN critical_count bigint DEFAULT 0;



-- Create view for audit rate
CREATE OR REPLACE VIEW call_center.cc_audit_rate_view AS
SELECT r.id,
    r.domain_id,
    r.form_id,
    r.created_at,
    call_center.cc_get_lookup(uc.id, COALESCE(uc.name::character varying, uc.username::character varying)) AS created_by,
    r.updated_at,
    call_center.cc_get_lookup(u.id, COALESCE(u.name::character varying, u.username::character varying)) AS updated_by,
    call_center.cc_get_lookup(ur.id, ur.name::character varying) AS rated_user,
    call_center.cc_get_lookup(f.id::bigint, f.name) AS form,
    ans.v AS answers,
    r.score_required,
    r.score_optional,
    r.comment,
    r.call_id,
    f.questions,
    r.rated_user_id,
    r.created_by AS grantor,
    r.select_yes_count,
    r.critical_count
FROM call_center.cc_audit_rate r
    LEFT JOIN LATERAL ( SELECT jsonb_agg(
            CASE
                WHEN u_1.id IS NOT NULL THEN x.j || jsonb_build_object('updated_by', call_center.cc_get_lookup(u_1.id, COALESCE(u_1.name, u_1.username::text)::character varying))
                ELSE x.j
            END ORDER BY x.i) AS v
       FROM jsonb_array_elements(r.answers) WITH ORDINALITY x(j, i)
         LEFT JOIN directory.wbt_user u_1 ON u_1.id = ((x.j -> 'updated_by'::text) -> 'id'::text)::bigint) ans ON true
    LEFT JOIN call_center.cc_audit_form f ON f.id = r.form_id
    LEFT JOIN directory.wbt_user ur ON ur.id = r.rated_user_id
    LEFT JOIN directory.wbt_user uc ON uc.id = r.created_by
    LEFT JOIN directory.wbt_user u ON u.id = r.updated_by;