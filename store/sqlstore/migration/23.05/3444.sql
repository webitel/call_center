
drop FUNCTION call_center.cc_calls_rbac_users_from_group;
CREATE FUNCTION call_center.rbac_users_from_group(_class_name varchar, _domain_id bigint, _access smallint, _groups integer[]) RETURNS integer[]
    LANGUAGE sql IMMUTABLE
AS $$
select array_agg(distinct am.member_id::int)
from directory.wbt_class c
         inner join directory.wbt_default_acl a on a.object = c.id
         join directory.wbt_auth_member am on am.role_id = a.grantor
where c.name = _class_name
  and c.dc = _domain_id
  and a.access&_access = _access and a.subject = any(_groups)
$$;