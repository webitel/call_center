create table IF NOT EXISTS cc_agent_activity
(
	id serial not null
		constraint agent_statistic_pk
			primary key,
	agent_id bigint not null
		constraint cc_agent_statistic_cc_agent_id_fk
			references cc_agent
				on update cascade on delete cascade,
	last_bridge_start_at bigint default 0 not null,
	last_bridge_end_at bigint default 0 not null,
	last_offering_call_at bigint default 0,
	calls_abandoned integer default 0 not null,
	calls_answered integer default 0 not null,
	sum_talking_of_day bigint default 0 not null,
	sum_pause_of_day bigint default 0 not null,
	successively_no_answers smallint default 0 not null,
	last_answer_at bigint default 0 not null,
	sum_idle_of_day bigint default 0 not null
);

create unique index IF NOT EXISTS agent_statistic_id_uindex
	on cc_agent_activity (id);

create unique index IF NOT EXISTS  cc_agent_activity_agent_id_last_offering_call_at_uindex
	on cc_agent_activity (agent_id, last_offering_call_at);

