create table IF NOT EXISTS cc_agent_in_queue
(
	id serial not null
		constraint cc_agent_in_queue_pkey
			primary key,
	agent_id integer
		constraint cc_agent_in_queue_cc_agent_id_fk
			references cc_agent,
	queue_id integer not null
		constraint cc_agent_in_queue_cc_queue_id_fk
			references cc_queue
				on update cascade on delete cascade,
	skill_id integer
		constraint cc_agent_in_queue_cc_skils_id_fk
			references cc_skils,
	lvl smallint default 0 not null
);

create unique index IF NOT EXISTS cc_agent_in_queue_id_uindex
	on cc_agent_in_queue (id);

create index IF NOT EXISTS cc_agent_in_queue_agent_id_index
	on cc_agent_in_queue (agent_id);

create index IF NOT EXISTS cc_agent_in_queue_queue_id_lvl_index
	on cc_agent_in_queue (queue_id asc, lvl desc);

create unique index IF NOT EXISTS cc_agent_in_queue_skill_id_queue_id_uindex
	on cc_agent_in_queue (skill_id, queue_id);

create unique index IF NOT EXISTS cc_agent_in_queue_queue_id_agent_id_skill_id_uindex
	on cc_agent_in_queue (queue_id, agent_id, skill_id);