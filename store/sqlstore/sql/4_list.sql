create table IF NOT EXISTS cc_list
(
	id bigserial not null
		constraint cc_call_list_pk
			primary key,
	name varchar(50) not null,
	type integer default 0 not null,
	description varchar(20),
	domain_id integer not null
		constraint cc_list_domain_id_fk
			references domain
				on update cascade on delete cascade
);

create unique index IF NOT EXISTS cc_call_list_id_uindex
	on cc_list (id);

--

