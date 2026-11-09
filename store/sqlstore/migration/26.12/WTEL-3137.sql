create or replace function storage.media_file_delete_returning(p_id bigint, p_domain_id bigint, p_force boolean)
returns table(
  id bigint,
  name text,
  created_at bigint,
  created_by jsonb,
  updated_at bigint,
  updated_by jsonb,
  mime_type text,
  size bigint,
  properties jsonb,
  domain_name text
)
language plpgsql
as $$
#variable_conflict use_column
declare
  v_in_queue boolean;
  v_in_agent boolean;
  v_what text;
begin
  perform 1
  from storage.media_files m
  where (m.id, m.domain_id) = (p_id, p_domain_id)
  for update;

  if not found then
    return;
  end if;

  if p_force then
        update call_center.cc_queue q
        set ringtone_id = null
        where q.ringtone_id = p_id
          and q.domain_id = p_domain_id;

        update call_center.cc_agent a
        set greeting_media_id = null
        where a.greeting_media_id = p_id
          and a.domain_id = p_domain_id;
    else
        select exists(select 1 from call_center.cc_queue q
                      where q.ringtone_id = p_id and q.domain_id = p_domain_id),
               exists(select 1 from call_center.cc_agent a
                      where a.greeting_media_id = p_id and a.domain_id = p_domain_id)
        into v_in_queue, v_in_agent;

        if v_in_queue or v_in_agent then
            v_what := case
                when v_in_queue and v_in_agent then 'an agent and a queue'
                when v_in_agent                then 'an agent'
                else                                'a queue'
            end;

            raise exception 'Cannot delete the file because it''s assigned to %', v_what
                using errcode = 'CC409',
                      detail  = format('media_id=%s, domain_id=%s', p_id, p_domain_id);
        end if;
    end if;

    return query
    with media_del as (
        delete from storage.media_files m
        where m.id = p_id
          and m.domain_id = p_domain_id
        returning m.id, m.name, m.created_at, m.created_by, m.updated_at, m.updated_by,
                  m.mime_type, m.size, m.properties, m.domain_id
    )
   select f.id::bigint,
       f.name::text,
       f.created_at::bigint,
       call_center.cc_get_lookup(c.id, c.name)::jsonb,
       f.updated_at::bigint,
       call_center.cc_get_lookup(u.id, u.name)::jsonb,
       f.mime_type::text,
       f.size::bigint,
       f.properties::jsonb,
       d.name::text
    from media_del f
         left join directory.wbt_user c on c.id = f.created_by
         left join directory.wbt_user u on u.id = f.updated_by
         inner join directory.wbt_domain d on d.dc = f.domain_id;
end;
$$;
