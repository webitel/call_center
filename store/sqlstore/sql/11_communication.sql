create table IF NOT EXISTS cc_communication
(
	id serial not null
		constraint cc_communication_pkey
			primary key,
	name varchar(50) not null,
	code varchar(10) not null,
	type varchar(5)
);

create unique index IF NOT EXISTS cc_communication_id_uindex
	on cc_communication (id);

