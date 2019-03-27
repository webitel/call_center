CREATE OR REPLACE FUNCTION tg_get_member_communication_resource()
  RETURNS trigger AS
$BODY$
BEGIN
  --TODO change to STATEMENT !!!
  new.routing_ids = ARRAY(select r.id
  from cc_queue_routing r
  where r.queue_id = (select queue_id from cc_member m where m.id = new.member_id)
        and new.number ~ r.pattern
  );
 --raise notice 'TG "%" % -> %', new.routing_ids, new.member_id, new.number;

 RETURN new;
END;
$BODY$ language plpgsql;

CREATE TRIGGER tg_set_routing_ids_on_update_number
    BEFORE UPDATE ON cc_member_communications
    FOR EACH ROW
    WHEN (OLD.number <> NEW.number)
    EXECUTE PROCEDURE tg_get_member_communication_resource();

CREATE TRIGGER tg_set_routing_ids_on_insert
    BEFORE INSERT ON cc_member_communications
    FOR EACH ROW
    WHEN (NEW.number <> '')
    EXECUTE PROCEDURE tg_get_member_communication_resource();

alter table cc_queue_routing owner to webitel;

DROP index cc_member_communications_routing_ids_gin;
CREATE INDEX cc_member_communications_routing_ids_gin
  ON cc_member_communications using gin(member_id, routing_ids gin__int_ops) where state = 0 ;


select *
from pg_stat_activity;

select *
from pg_cancel_backend(21332);

drop index cc_member_communications_routing_ids_gin2;
CREATE INDEX cc_member_communications_routing_ids_gin2
  ON cc_member_communications using gin(routing_ids gin__int_ops, number gin_trgm_ops);

select relname, reloptions, pg_namespace.nspname
from pg_class
join pg_namespace on pg_namespace.oid = pg_class.relnamespace
where relname like 'cc_member_communications';
/*
The below autovacuum settings are very crucial.

1. autovacuum_vacuum_threshold

2. autovacuum_vacuum_scale_factor

3. autovacuum_vacuum_cost_delay

4. autovacuum_vacuum_cost_limit

5. autovacuum_max_workers

6. autovacuum_naptime
 */
