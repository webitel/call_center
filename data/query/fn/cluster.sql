select *
from cc_cluster;


insert into cc_cluster (node_name, updated_at, master)
values ('aaa', 1000, false)
on conflict (node_name)
  do update
    set updated_at = 1000,
      master = false
returning *;


update cc_cluster
set updated_at = 12
where node_name = '';