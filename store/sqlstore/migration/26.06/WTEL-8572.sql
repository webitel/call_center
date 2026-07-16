CREATE OR REPLACE FUNCTION call_center.rbac_users_from_group(_class_name character varying, _domain_id bigint, _access smallint, _groups integer[]) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
    AS $$
    select array_agg(distinct m)
    from (
        -- role -> role: members of the grantor role
        select am.member_id::int as m
        from directory.wbt_class c
            inner join directory.wbt_default_acl a on a.object = c.id
            join directory.wbt_auth_member am on am.role_id = a.grantor
        where c.name = _class_name
          and c.dc = _domain_id
          and a.access & _access = _access
          and a.subject = any(_groups)

        union

        -- user -> role: the grantor itself as a user
        select a.grantor::int as m
        from directory.wbt_class c
            inner join directory.wbt_default_acl a on a.object = c.id
        where c.name = _class_name
          and c.dc = _domain_id
          and a.access & _access = _access
          and a.subject = any(_groups)
    ) t
$$;
