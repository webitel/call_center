create table IF NOT EXISTS  "user"
(
	id bigserial not null
		constraint users_pk
			primary key,
	name varchar(50) not null,
	variables jsonb
);

create unique index IF NOT EXISTS users_id_uindex
	on "user" (id);