create table  IF NOT EXISTS cc_queue_routing
(
	id serial not null
		constraint cc_queue_routing_pkey
			primary key,
	queue_id integer not null
		constraint cc_queue_routing_cc_queue_id_fk
			references cc_queue
				on update cascade on delete cascade,
	pattern varchar(50) not null,
	priority integer default 0 not null
);


create unique index  IF NOT EXISTS  cc_queue_routing_id_uindex
	on cc_queue_routing (id);

create index  IF NOT EXISTS  cc_queue_routing_queue_id_index
	on cc_queue_routing (queue_id);


drop trigger IF EXISTS tg_set_routing_ids_on_insert_or_delete_pattern on cc_queue_routing;

create trigger tg_set_routing_ids_on_insert_or_delete_pattern
	after insert or delete
	on cc_queue_routing
	for each row
	execute procedure tg_fill_member_communication_resource();


drop trigger IF EXISTS tg_set_routing_ids_on_update_pattern on cc_queue_routing;

create trigger tg_set_routing_ids_on_update_pattern
	after update
	on cc_queue_routing
	for each row
	execute procedure tg_fill_member_communication_resource();

