
SELECT *, pg_size_pretty(total_bytes) AS total
    , pg_size_pretty(index_bytes) AS INDEX
    , pg_size_pretty(toast_bytes) AS toast
    , pg_size_pretty(table_bytes) AS TABLE
  FROM (
  SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes FROM (
      SELECT c.oid,nspname AS table_schema, relname AS TABLE_NAME
              , c.reltuples AS row_estimate
              , pg_total_relation_size(c.oid) AS total_bytes
              , pg_indexes_size(c.oid) AS index_bytes
              , pg_total_relation_size(reltoastrelid) AS toast_bytes
          FROM pg_class c
          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE relkind = 'r'
  ) a
) a
order by 2, 8 desc;

vacuum full cc_member_attempt;

vacuum full cc_member_communications;


update cc_member_communications
set state = 998
where 1= 1;



create extension pgstattuple;

select nspname,
relname,
pg_size_pretty(relation_size + toast_relation_size) as total_size,
pg_size_pretty(toast_relation_size) as toast_size,
round(((relation_size - (relation_size - free_space)*100/fillfactor)*100/greatest(relation_size, 1))::numeric, 1) table_waste_percent,
pg_size_pretty((relation_size - (relation_size - free_space)*100/fillfactor)::bigint) table_waste,
round(((toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor)*100/greatest(relation_size + toast_relation_size, 1))::numeric, 1) total_waste_percent,
pg_size_pretty((toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor)::bigint) total_waste
from (
    select nspname, relname,
    (select free_space from pgstattuple(c.oid)) as free_space,
    pg_relation_size(c.oid) as relation_size,
    (case when reltoastrelid = 0 then 0 else (select free_space from pgstattuple(c.reltoastrelid)) end) as toast_free_space,
    coalesce(pg_relation_size(c.reltoastrelid), 0) as toast_relation_size,
    coalesce((SELECT (regexp_matches(reloptions::text, E'.*fillfactor=(\\d+).*'))[1]),'100')::real AS fillfactor
    from pg_class c
    left join pg_namespace n on (n.oid = c.relnamespace)
    where nspname not in ('pg_catalog', 'information_schema')
    and nspname !~ '^pg_toast' and nspname !~ '^pg_temp' and relkind in ('r', 'm') and (relpersistence = 'p' or not pg_is_in_recovery())
    --put your table name/mask here
    and relname ~ ''
) t
order by (toast_free_space + relation_size - (relation_size - free_space)*100/fillfactor) desc
limit 20;

update cc_member_communications
set state = 17
where 1 = 1;




reindex INDEX cc_member_communications_member_id_last_hangup_at_priority_inde;


with indexes as (
    select * from pg_stat_user_indexes
)
select schemaname,
table_name,
pg_size_pretty(table_size) as table_size,
index_name,
pg_size_pretty(index_size) as index_size,
idx_scan as index_scans,
round((free_space*100/index_size)::numeric, 1) as waste_percent,
pg_size_pretty(free_space) as waste
from (
    select schemaname, p.relname as table_name, indexrelname as index_name,
    (select (case when avg_leaf_density = 'NaN' then 0
        else greatest(ceil(index_size * (1 - avg_leaf_density / (coalesce((SELECT (regexp_matches(reloptions::text, E'.*fillfactor=(\\d+).*'))[1]),'90')::real)))::bigint, 0) end)
        from pgstatindex(p.indexrelid::regclass::text)
    ) as free_space,
    pg_relation_size(p.indexrelid) as index_size,
    pg_relation_size(p.relid) as table_size,
    idx_scan
    from indexes p
    join pg_class c on p.indexrelid = c.oid
    join pg_index i on i.indexrelid = p.indexrelid
    where pg_get_indexdef(p.indexrelid) like '%USING btree%' and
    i.indisvalid and (c.relpersistence = 'p' or not pg_is_in_recovery()) and
    --put your index name/mask here
    indexrelname ~ ''
) t
order by free_space desc;