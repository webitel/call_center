create table IF NOT EXISTS cc_list_communications
(
	list_id bigint not null
		constraint cc_list_communications_cc_list_id_fk
			references cc_list
				on update cascade on delete cascade,
	number varchar(25) not null,
	id bigserial not null
		constraint cc_list_communications_pk
			primary key
);

create unique index IF NOT EXISTS cc_list_communications_id_uindex
	on cc_list_communications (id);

create unique index IF NOT EXISTS cc_list_communications_list_id_number_uindex
	on cc_list_communications (list_id, number);

