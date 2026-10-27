CREATE OR REPLACE FUNCTION call_center.cc_calls_rbac_users(_domain_id bigint, _user_id bigint) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
    AS $$
    with x as materialized (
        select a.user_id, a.id agent_id, a.supervisor, a.domain_id
        from directory.wbt_user u
                 inner join call_center.cc_agent a on a.user_id = u.id
        where u.id = _user_id
          and u.dc = _domain_id
    )
    select array_agg(distinct a.user_id::int) users
    from x
             left join lateral (
        select a.user_id, a.auditor_ids && array [x.user_id] aud
        from call_center.cc_agent a
        where a.domain_id = x.domain_id
          and (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and x.supervisor) or
               a.auditor_ids && array [x.user_id])

        union
        distinct

        select a.user_id, a.auditor_ids && array [x.user_id] aud
        from call_center.cc_team t
                 inner join call_center.cc_agent a on a.team_id = t.id
        where t.admin_ids && array [x.agent_id]
          and x.domain_id = t.domain_id
        ) a on true
$$;
