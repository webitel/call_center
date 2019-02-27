CREATE OR REPLACE FUNCTION tg_fill_member_communication_resource()
  RETURNS trigger AS
$BODY$
BEGIN

  if (tg_op = 'UPDATE' or tg_op = 'DELETE') then
    update cc_member_communications c
    set routing_ids = c.routing_ids - ARRAY [old.id]
    where c.id in (
      select id
      from cc_member_communications c1
      where c1.routing_ids @> ARRAY [old.id]
        and c1.member_id in (select id from cc_member m where m.queue_id = old.queue_id)
    );
  end if;

--  raise notice 'end delete';
  if (tg_op = 'UPDATE' or tg_op = 'INSERT') then
    update cc_member_communications c
    set routing_ids = c.routing_ids | ARRAY [new.id]
    where c.id in (
      select id
      from cc_member_communications c1
      where not c1.routing_ids @> ARRAY [new.id]
        and c1.member_id in (select id from cc_member m where m.queue_id = new.queue_id)
        and c1.number ~* new.pattern
    );
  end if;

--  raise notice 'end add';
  RETURN new;
END;
$BODY$ language plpgsql;

drop trigger tg_set_routing_ids_on_update_pattern on cc_queue_routing;
drop trigger tg_set_routing_ids_on_insert_or_delete_pattern on cc_queue_routing;

alter table cc_member_communications owner to webitel;

CREATE TRIGGER tg_set_routing_ids_on_update_pattern
  AFTER UPDATE
  ON cc_queue_routing
  FOR EACH ROW
  WHEN (OLD.pattern <> NEW.pattern OR OLD.id <> NEW.id OR OLD.queue_id <> NEW.queue_id)
EXECUTE PROCEDURE tg_fill_member_communication_resource();

CREATE TRIGGER tg_set_routing_ids_on_insert_or_delete_pattern
  AFTER INSERT OR DELETE
  ON cc_queue_routing
  FOR EACH ROW
EXECUTE PROCEDURE tg_fill_member_communication_resource();


INSERT INTO "call_center"."cc_queue_routing" ("id", "queue_id", "pattern", "priority")
VALUES
       (DEFAULT, 1, '^1', DEFAULT),
       (DEFAULT, 1, '^2', DEFAULT),
       (DEFAULT, 1, '^3', DEFAULT),
       (DEFAULT, 1, '^4', DEFAULT),
       (DEFAULT, 1, '^5', DEFAULT),
       (DEFAULT, 1, '^6', DEFAULT),
       (DEFAULT, 1, '^7', DEFAULT),
       (DEFAULT, 1, '^8', DEFAULT),
       (DEFAULT, 1, '^9', DEFAULT);

select *
from cc_member_communications where number ~ '^\d';