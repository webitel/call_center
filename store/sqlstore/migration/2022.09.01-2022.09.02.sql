create or replace  function call_center.cc_calls_rbac_users_from_group(_domain_id int8, _access smallint, _groups int[]) returns int[]
as
$$
select array_agg(distinct am.member_id::int)
from directory.wbt_class c
         inner join directory.wbt_default_acl a on a.object = c.id
         join directory.wbt_auth_member am on am.role_id = a.grantor
where c.name = 'calls'
  and c.dc = _domain_id
  and a.access&_access = _access and a.subject = any(_groups)
$$ language sql immutable ;

create or replace function call_center.cc_calls_rbac_users(_domain_id int8, _user_id int8) returns int[]
as
$$
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
      and (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and a.supervisor) or
           a.auditor_ids && array [x.user_id])

    union
    distinct

    select a.user_id, a.auditor_ids && array [x.user_id] aud
    from call_center.cc_team t
             inner join call_center.cc_agent a on a.team_id = t.id
    where t.admin_ids && array [x.agent_id]
      and x.domain_id = t.domain_id
    ) a on true
$$ language sql immutable ;


create or replace  function call_center.cc_calls_rbac_queues(_domain_id int8, _user_id int8, _groups int[]) returns int[]
as
$$
with x as (select a.user_id, a.id agent_id, a.supervisor, a.domain_id
           from directory.wbt_user u
                    inner join call_center.cc_agent a on a.user_id = u.id and a.domain_id = u.dc
           where u.id = _user_id
             and u.dc = _domain_id)
select array_agg(distinct t.queue_id)
from (select qs.queue_id::int as queue_id
      from x
               left join lateral (
          select a.id, a.auditor_ids && array [x.user_id] aud
          from call_center.cc_agent a
          where (a.user_id = x.user_id or (a.supervisor_ids && array [x.agent_id] and a.supervisor))
          union
          distinct
          select a.id, a.auditor_ids && array [x.user_id] aud
          from call_center.cc_team t
                   inner join call_center.cc_agent a on a.team_id = t.id
          where t.admin_ids && array [x.agent_id]
          ) a on true
               inner join call_center.cc_skill_in_agent sa on sa.agent_id = a.id
               inner join call_center.cc_queue_skill qs
                          on qs.skill_id = sa.skill_id and sa.capacity between qs.min_capacity and qs.max_capacity
      where sa.enabled
        and qs.enabled
      union distinct
      select q.id
      from call_center.cc_queue q
      where q.domain_id = _domain_id
        and q.grantee_id = any (_groups)) t
$$ language sql immutable ;;


create index concurrently  if not exists cc_calls_history_grantee_id_index
    on call_center.cc_calls_history
        using btree(grantee_id asc nulls last );