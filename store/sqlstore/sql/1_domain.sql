create table IF NOT EXISTS  "domain"
(
	id bigserial not null
		constraint domain_pk
			primary key,
	name varchar(50) not null
);

create unique index IF NOT EXISTS  domain_id_uindex
	on "domain" (id);

