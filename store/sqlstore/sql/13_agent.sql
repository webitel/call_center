create table IF NOT EXISTS cc_agent
(
	id serial not null
		constraint cc_agent_pkey
			primary key,
	name varchar(50) not null,
	max_no_answer integer default 0 not null,
	wrap_up_time integer default 0 not null,
	reject_delay_time integer default 0 not null,
	busy_delay_time integer default 0 not null,
	no_answer_delay_time integer default 0 not null,
	user_id bigint
		constraint cc_agent_user_id_fk
			references "user",
	updated_at bigint default 0 not null,
	destination varchar(50) default 'error/USER_BUSY'::character varying not null,
	call_timeout integer default 0 not null,
	status varchar(20) default ''::character varying not null,
	status_payload jsonb,
	state varchar(20) default '_none_'::character varying not null,
	state_timeout timestamp
);

create unique index IF NOT EXISTS cc_agent_id_uindex
	on cc_agent (id);

create index IF NOT EXISTS cc_agent_state_timeout_index
	on cc_agent (state_timeout);

create index IF NOT EXISTS cc_agent_status_state_index
	on cc_agent (status, state);


drop trigger IF EXISTS tg_cc_set_agent_change_status_u on cc_agent;

create trigger tg_cc_set_agent_change_status_u
	after update
	on cc_agent
	for each row
	execute procedure cc_set_agent_change_status();

