create table IF NOT EXISTS cc_agent_state_history
(
	id bigserial not null
		constraint cc_agent_status_history_pk
			primary key,
	agent_id bigint not null
		constraint cc_agent_status_history_cc_agent_id_fk
			references cc_agent
				on update cascade on delete cascade,
	joined_at timestamp default now() not null,
	state varchar(20) not null,
	timeout_at timestamp,
	payload jsonb
);

create unique index IF NOT EXISTS cc_agent_status_history_id_uindex
	on cc_agent_state_history (id);

create unique index IF NOT EXISTS cc_agent_status_history_agent_id_join_at_index
	on cc_agent_state_history (joined_at desc, agent_id asc, state asc);

create unique index IF NOT EXISTS cc_agent_state_history_agent_id_joined_at_uindex
	on cc_agent_state_history (agent_id asc, joined_at desc);

