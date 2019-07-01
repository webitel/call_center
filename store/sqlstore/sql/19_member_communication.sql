create table IF NOT EXISTS cc_member_communications
(
	id serial not null
		constraint cc_member_communications_id_pk
			primary key,
	member_id integer not null
		constraint cc_member_communications_cc_member_id_fk
			references cc_member
				on update cascade on delete cascade,
	priority smallint default 0 not null,
	number varchar(20) not null,
	last_originate_at bigint default 0 not null,
	state smallint default 0 not null,
	communication_id integer
		constraint cc_member_communications_cc_communication_id_fk
			references cc_communication,
	routing_ids integer[],
	description varchar(100) default ''::character varying,
	last_hangup_at bigint default 0 not null,
	attempts smallint default 0 not null,
	last_hangup_cause varchar(50) default ''::character varying not null
);

--TODO using gin!!!
create index IF NOT EXISTS  cc_member_communications_routing_ids_gin
	on cc_member_communications (member_id, routing_ids)
	where (state = 0);

create index IF NOT EXISTS cc_member_communications_member_id_last_hangup_at_priority_inde
	on cc_member_communications (communication_id asc, member_id asc, last_hangup_at asc, priority desc)
	where (state = 0);

create unique index IF NOT EXISTS  cc_member_communications_member_id_number_uindex
	on cc_member_communications (member_id, number);

create index IF NOT EXISTS  cc_member_communications_number_index
	on cc_member_communications (number);


drop trigger IF EXISTS tg_set_routing_ids_on_update_number on cc_member_communications;
create trigger tg_set_routing_ids_on_update_number
	before update
	on cc_member_communications
	for each row
	execute procedure tg_get_member_communication_resource();


drop trigger IF EXISTS tg_set_routing_ids_on_insert on cc_member_communications;
create trigger tg_set_routing_ids_on_insert
	before insert
	on cc_member_communications
	for each row
	execute procedure tg_get_member_communication_resource();

