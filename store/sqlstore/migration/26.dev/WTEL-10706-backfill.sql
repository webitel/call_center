create or replace procedure call_center.cc_audit_rate_backfill_call_root_id(_batch int default 1000)
    language plpgsql
as
$$
declare
    _last_id bigint := 0;
    _rows    int;
    _total   bigint := 0;
begin
    loop
        with batch as (select ar.id
                       from call_center.cc_audit_rate ar
                       where ar.id > _last_id
                         and ar.call_root_id is null
                         and ar.call_id is not null
                       order by ar.id
                       limit _batch),
             upd as (update call_center.cc_audit_rate ar
                     set call_root_id = call_center.cc_call_root_id(ar.call_id::uuid)
                     from batch b
                     where ar.id = b.id
                     returning ar.id)
        select count(*), coalesce(max(id), _last_id)
        into _rows, _last_id
        from upd;

        exit when _rows = 0;
        _total := _total + _rows;
        commit;
        raise notice 'cc_audit_rate call_root_id backfill: % rows, last id %', _total, _last_id;
    end loop;
    raise notice 'cc_audit_rate call_root_id backfill done: % rows', _total;
end;
$$;

call call_center.cc_audit_rate_backfill_call_root_id();

drop procedure call_center.cc_audit_rate_backfill_call_root_id(int);
