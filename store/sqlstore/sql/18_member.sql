create table IF NOT EXISTS cc_member
(
	id serial not null
		constraint cc_member_pkey
			primary key,
	queue_id integer not null
		constraint cc_member_cc_queue_id_fk
			references cc_queue
				on update cascade on delete cascade,
	priority smallint default 0 not null,
	expire_at integer,
	variables jsonb default '{}'::jsonb,
	name varchar(50) default ''::character varying not null,
	stop_cause varchar(50),
	stop_at bigint default 0 not null,
	last_hangup_at bigint default 0 not null,
	attempts integer default 0 not null
);

create index IF NOT EXISTS cc_member_id_index
	on cc_member (id);

create index IF NOT EXISTS cc_member_last_hangup_at_queue_id_index
	on cc_member (last_hangup_at, queue_id);

create index IF NOT EXISTS cc_member_priority_id_last_hangup_at_queue_id_index
	on cc_member (priority desc, id asc, last_hangup_at asc, queue_id desc)
	where (stop_at = 0);

