create table IF NOT EXISTS  cc_skils
(
	id serial not null
		constraint cc_skils_pkey
			primary key,
	code varchar(20) not null,
	domain_id bigint
		constraint cc_skils_domain_id_fk
			references domain
);

create unique index IF NOT EXISTS  cc_skils_id_uindex
	on cc_skils (id);

