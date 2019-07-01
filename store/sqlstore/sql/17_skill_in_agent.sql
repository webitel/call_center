create table IF NOT EXISTS cc_skill_in_agent
(
	id serial not null
		constraint cc_skill_in_agent_pkey
			primary key,
	skill_id integer not null
		constraint cc_skill_in_agent_cc_skils_id_fk
			references cc_skils,
	agent_id integer not null
		constraint cc_skill_in_agent_cc_agent_id_fk
			references cc_agent
				on update cascade on delete cascade,
	capacity smallint default 0 not null
);

create unique index IF NOT EXISTS cc_skill_in_agent_id_uindex
	on cc_skill_in_agent (id);

create unique index IF NOT EXISTS cc_skill_in_agent_skill_id_agent_id_capacity_uindex
	on cc_skill_in_agent (skill_id asc, agent_id asc, capacity desc);

