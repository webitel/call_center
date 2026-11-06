insert into call_center.system_settings (domain_id, name, value)
select d.dc, s.name, s.value
from directory.wbt_domain d
         cross join (values ('max_login_attempts', '5'::jsonb),
                            ('block_login_time', '60'::jsonb)) s(name, value)
on conflict (domain_id, name) do nothing;
