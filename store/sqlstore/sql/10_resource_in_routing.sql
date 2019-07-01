create table  IF NOT EXISTS cc_resource_in_routing
(
	id serial not null
		constraint cc_resource_in_queue_pkey
			primary key,
	resource_id integer not null
		constraint cc_resource_in_queue_cc_outbound_resource_id_fk
			references cc_outbound_resource,
	priority smallint default 0 not null,
	routing_id integer not null
		constraint cc_resource_in_routing_cc_queue_routing_id_fk
			references cc_queue_routing
				on update cascade on delete cascade,
	capacity integer default 0
);


create unique index  IF NOT EXISTS  cc_resource_in_queue_id_uindex
	on cc_resource_in_routing (id);

create index  IF NOT EXISTS  cc_resource_in_routing_resource_id_routing_id_index
	on cc_resource_in_routing (resource_id, routing_id);

create index  IF NOT EXISTS  cc_resource_in_routing_priority_index
	on cc_resource_in_routing (priority);

