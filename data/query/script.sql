create table if not exists call_center.cc_communication
(
	id serial not null
		constraint cc_communication_pkey
			primary key,
	name varchar(50) not null,
	code varchar(10) not null,
	type varchar(5)
);

alter table call_center.cc_communication owner to webitel;

create unique index if not exists cc_communication_id_uindex
	on call_center.cc_communication (id);

create table if not exists call_center.session
(
	"Id" varchar(26) not null
		constraint session_pkey
			primary key,
	"Token" varchar(500),
	"UserId" varchar(26)
);

alter table call_center.session owner to webitel;

create table if not exists call_center.cluster
(
	id bigserial not null
		constraint cluster_pk
			primary key,
	node_name varchar(20) not null,
	updated_at bigint default 0 not null,
	master boolean
);

alter table call_center.cluster owner to webitel;

create unique index if not exists cluster_id_uindex
	on call_center.cluster (id);

create table if not exists call_center.domain
(
	id bigserial not null
		constraint domain_pk
			primary key,
	name varchar(50) not null
);

alter table call_center.domain owner to webitel;

create table if not exists call_center.calendar
(
	id serial not null
		constraint calendar_pkey
			primary key,
	timezone varchar(15) default 'utc'::character varying not null,
	start integer,
	finish integer,
	name varchar(20) not null,
	domain_id integer
		constraint calendar_domain_id_fk
			references domain
);

alter table call_center.calendar owner to webitel;

create unique index if not exists calendar_id_uindex
	on call_center.calendar (id);

create index if not exists calendar_name_id_index
	on call_center.calendar (name, id);

create table if not exists call_center.calendar_accept_of_day
(
	id serial not null
		constraint calendar_accept_of_day_pkey
			primary key,
	calendar_id integer not null
		constraint calendar_accept_of_day_calendar_id_fk
			references calendar
				on update cascade on delete cascade,
	week_day smallint not null,
	start_time_of_day smallint default 0 not null,
	end_time_of_day smallint default 1440 not null
);

alter table call_center.calendar_accept_of_day owner to webitel;

create unique index if not exists calendar_accept_of_day_calendar_id_week_day_start_time_of_day_e
	on call_center.calendar_accept_of_day (calendar_id, week_day, start_time_of_day, end_time_of_day);

create unique index if not exists calendar_accept_of_day_id_uindex
	on call_center.calendar_accept_of_day (id);

create table if not exists call_center.calendar_except
(
	id serial not null
		constraint calendar_except_pkey
			primary key,
	calendar_id integer not null
		constraint calendar_except_calendar_id_fk
			references calendar
				on update cascade on delete cascade,
	date integer not null,
	repeat smallint
);

alter table call_center.calendar_except owner to webitel;

create unique index if not exists calendar_except_id_uindex
	on call_center.calendar_except (id);

create table if not exists call_center.cc_outbound_resource
(
	id serial not null
		constraint cc_queue_resource_pkey
			primary key,
	"limit" integer default 0 not null,
	enabled boolean default true not null,
	updated_at integer not null,
	rps integer default '-1'::integer,
	domain_id bigint
		constraint cc_outbound_resource_domain_id_fk
			references domain,
	reserve boolean default false,
	variables jsonb default '{}'::jsonb not null,
	number varchar(20) not null,
	max_successively_errors integer default 0,
	name varchar(50) not null,
	dial_string varchar(50) not null,
	error_ids jsonb default '[]'::jsonb not null,
	last_error_id varchar(50),
	successively_errors smallint default 0 not null,
	last_error_at bigint default 0
);

alter table call_center.cc_outbound_resource owner to webitel;

create unique index if not exists cc_queue_resource_id_uindex
	on call_center.cc_outbound_resource (id);

create table if not exists call_center.cc_skils
(
	id serial not null
		constraint cc_skils_pkey
			primary key,
	code varchar(20) not null,
	domain_id bigint
		constraint cc_skils_domain_id_fk
			references domain
);

alter table call_center.cc_skils owner to webitel;

create unique index if not exists cc_skils_id_uindex
	on call_center.cc_skils (id);

create unique index if not exists domain_id_uindex
	on call_center.domain (id);

create table if not exists call_center."user"
(
	id bigserial not null
		constraint users_pk
			primary key,
	name varchar(50) not null
);

alter table call_center."user" owner to webitel;

create table if not exists call_center.cc_agent
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
	status_payload jsonb
);

alter table call_center.cc_agent owner to webitel;

create unique index if not exists cc_agent_id_uindex
	on call_center.cc_agent (id);

create trigger call_center.tg_cc_set_agent_change_status
	before insert or update
	on call_center.cc_agent
	for each row
	execute procedure call_center.cc_set_agent_change_status();

create table if not exists call_center.cc_skill_in_agent
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

alter table call_center.cc_skill_in_agent owner to webitel;

create unique index if not exists cc_skill_in_agent_id_uindex
	on call_center.cc_skill_in_agent (id);

create table if not exists call_center.cc_agent_activity
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
	calls_abandoned smallint default 0 not null,
	calls_answered smallint default 0 not null,
	sum_talking_of_day bigint default 0 not null,
	sum_pause_of_day bigint default 0 not null,
	successively_no_answers smallint default 0 not null,
	last_answer_at bigint default 0 not null,
	sum_idle_of_day bigint default 0 not null
);

alter table call_center.cc_agent_activity owner to webitel;

create unique index if not exists agent_statistic_id_uindex
	on call_center.cc_agent_activity (id);

create unique index if not exists users_id_uindex
	on call_center."user" (id);

create table if not exists call_center.cc_cluster
(
	id bigserial not null
		constraint cc_cluster_pkey
			primary key,
	node_name varchar(20) not null,
	updated_at bigint not null,
	master boolean not null,
	started_at bigint default 0 not null
);

alter table call_center.cc_cluster owner to webitel;

create unique index if not exists cc_cluster_node_name_uindex
	on call_center.cc_cluster (node_name);

create table if not exists call_center.cc_agent_state_history
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

alter table call_center.cc_agent_state_history owner to webitel;

create unique index if not exists cc_agent_status_history_id_uindex
	on call_center.cc_agent_state_history (id);

create index if not exists cc_agent_state_history_timeout_at_index
	on call_center.cc_agent_state_history (timeout_at desc)
	where (NOT (timeout_at IS NULL));

create index if not exists cc_agent_status_history_agent_id_join_at_index
	on call_center.cc_agent_state_history (agent_id asc, joined_at desc);

create table if not exists call_center.projects
(
	id bigserial not null
		constraint projects_pk
			primary key,
	name varchar(50) not null,
	domain_id bigint not null
		constraint table_name_domain_id_fk
			references domain
);

alter table call_center.projects owner to webitel;

create unique index if not exists projects_id_uindex
	on call_center.projects (id);

create table if not exists call_center.cc_queue_states
(
	id bigserial not null
		constraint cc_queue_states_pk
			primary key,
	queue_id bigint not null
);

alter table call_center.cc_queue_states owner to webitel;

create unique index if not exists cc_queue_states_id_uindex
	on call_center.cc_queue_states (id);

create table if not exists call_center.cc_calls
(
	id bigserial not null
		constraint cc_calls_pk
			primary key
);

alter table call_center.cc_calls owner to webitel;

create unique index if not exists cc_calls_id_uindex
	on call_center.cc_calls (id);

create table if not exists call_center.cc_list
(
	id bigserial not null
		constraint cc_call_list_pk
			primary key,
	name varchar(50) not null,
	type integer default 0 not null,
	description varchar(20),
	domain_id integer not null
		constraint cc_list_domain_id_fk
			references domain
				on update cascade on delete cascade
);

alter table call_center.cc_list owner to webitel;

create table if not exists call_center.cc_queue
(
	id serial not null
		constraint cc_queue_pkey
			primary key,
	type integer not null,
	strategy varchar(20) not null,
	enabled boolean not null,
	payload jsonb not null,
	calendar_id integer not null
		constraint cc_queue_calendar_id_fk
			references calendar,
	priority integer default 0 not null,
	max_calls integer default 0 not null,
	sec_between_retries integer default 10 not null,
	updated_at bigint default ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint not null,
	name varchar(50),
	max_of_retry smallint default 0 not null,
	variables jsonb default '{}'::jsonb not null,
	timeout integer default 60 not null,
	domain_id bigint
		constraint cc_queue_domain_id_fk
			references domain,
	project_id bigint
		constraint cc_queue_projects_id_fk
			references projects,
	dnc_list_id bigint
		constraint cc_queue_cc_list_id_fk
			references cc_list
				on update set null on delete set null
);

alter table call_center.cc_queue owner to webitel;

create table if not exists call_center.cc_agent_in_queue
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

alter table call_center.cc_agent_in_queue owner to webitel;

create unique index if not exists cc_agent_in_queue_id_uindex
	on call_center.cc_agent_in_queue (id);

create table if not exists call_center.cc_member
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

alter table call_center.cc_member owner to webitel;

create index if not exists cc_member_id_index
	on call_center.cc_member (id);

create index if not exists cc_member_last_hangup_at_queue_id_index
	on call_center.cc_member (last_hangup_at, queue_id);

create index if not exists cc_member_priority_id_last_hangup_at_queue_id_index
	on call_center.cc_member (priority desc, id asc, last_hangup_at asc, queue_id desc)
	where (stop_at = 0);

create table if not exists call_center.cc_member_communications
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

alter table call_center.cc_member_communications owner to webitel;

create index if not exists cc_member_communications_routing_ids_gin
	on call_center.cc_member_communications (member_id, routing_ids)
	where (state = 0);

create index if not exists cc_member_communications_member_id_last_hangup_at_priority_inde
	on call_center.cc_member_communications (communication_id asc, member_id asc, last_hangup_at asc, priority desc)
	where (state = 0);

create unique index if not exists cc_member_communications_member_id_number_uindex
	on call_center.cc_member_communications (member_id, number);


drop trigger tg_set_routing_ids_on_update_number on call_center.cc_member_communications;
create trigger tg_set_routing_ids_on_update_number
	before update
	on call_center.cc_member_communications
	for each row when ( new.number != old.number )
	execute procedure tg_get_member_communication_resource();

create trigger call_center.tg_set_routing_ids_on_insert
	before insert
	on call_center.cc_member_communications
	for each row
	execute procedure call_center.tg_get_member_communication_resource();

create unique index if not exists cc_queue_id_uindex
	on call_center.cc_queue (id);

create index if not exists cc_queue_enabled_priority_index
	on call_center.cc_queue (enabled asc, priority desc);

create table if not exists call_center.cc_queue_routing
(
	id serial not null
		constraint cc_queue_routing_pkey
			primary key,
	queue_id integer not null
		constraint cc_queue_routing_cc_queue_id_fk
			references cc_queue
				on update cascade on delete cascade,
	pattern varchar(50) not null,
	priority integer default 0 not null
);

alter table call_center.cc_queue_routing owner to webitel;

create unique index if not exists cc_queue_routing_id_uindex
	on call_center.cc_queue_routing (id);

create index if not exists cc_queue_routing_queue_id_index
	on call_center.cc_queue_routing (queue_id);

create trigger call_center.tg_set_routing_ids_on_insert_or_delete_pattern
	after insert or delete
	on call_center.cc_queue_routing
	for each row
	execute procedure call_center.tg_fill_member_communication_resource();

create trigger call_center.tg_set_routing_ids_on_update_pattern
	after update
	on call_center.cc_queue_routing
	for each row
	execute procedure call_center.tg_fill_member_communication_resource();

create table if not exists call_center.cc_queue_timing
(
	id serial not null
		constraint cc_queue_timing_pkey
			primary key,
	queue_id integer not null
		constraint cc_queue_timing_cc_queue_id_fk
			references cc_queue
				on update cascade on delete cascade,
	communication_id integer not null
		constraint cc_queue_timing_cc_communication_id_fk
			references cc_communication,
	priority smallint default 0 not null,
	start_time_of_day smallint default 0 not null,
	end_time_of_day smallint default 1439 not null,
	max_attempt smallint default 0 not null,
	enabled boolean default false
);

alter table call_center.cc_queue_timing owner to webitel;

create unique index if not exists cc_queue_timing_id_uindex
	on call_center.cc_queue_timing (id);

create unique index if not exists cc_queue_timing_queue_id_communication_id_start_time_of_day_end
	on call_center.cc_queue_timing (queue_id, communication_id, start_time_of_day, end_time_of_day);

create index if not exists cc_queue_timing_communication_id_max_attempt_index
	on call_center.cc_queue_timing (communication_id, max_attempt);

create table if not exists call_center.cc_resource_in_routing
(
	id serial not null
		constraint cc_resource_in_queue_pkey
			primary key,
	resource_id integer not null
		constraint cc_resource_in_queue_cc_outbound_resource_id_fk
			references cc_outbound_resource,
	priority smallint default 0 not null,
	routing_id integer not null
		constraint cc_resource_in_routing_cc_queue_routing_id_fk
			references cc_queue_routing
				on update cascade on delete cascade,
	capacity integer default 0
);

alter table call_center.cc_resource_in_routing owner to webitel;

create unique index if not exists cc_resource_in_queue_id_uindex
	on call_center.cc_resource_in_routing (id);

create index if not exists cc_resource_in_routing_resource_id_routing_id_index
	on call_center.cc_resource_in_routing (resource_id, routing_id);

create index if not exists cc_resource_in_routing_priority_index
	on call_center.cc_resource_in_routing (priority);

create table if not exists call_center.cc_member_attempt
(
	id bigserial not null
		constraint cc_member_attempt_pk
			primary key,
	communication_id bigint not null
		constraint cc_member_attempt_cc_member_communications_id_fk
			references cc_member_communications
				on update cascade on delete cascade,
	timing_id integer
		constraint cc_member_attempt_cc_queue_timing_id_fk
			references cc_queue_timing,
	queue_id bigint not null
		constraint cc_member_attempt_cc_queue_id_fk
			references cc_queue
				on update cascade on delete cascade,
	state integer default 0 not null,
	member_id bigint not null
		constraint cc_member_attempt_cc_member_id_fk
			references cc_member
				on update cascade on delete cascade,
	created_at bigint default ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint not null,
	weight integer default 0 not null,
	hangup_at bigint default 0 not null,
	bridged_at bigint default 0 not null,
	resource_id integer,
	leg_a_id varchar(36),
	leg_b_id varchar(36),
	node_id varchar(20),
	result varchar(200),
	originate_at bigint default 0 not null,
	answered_at bigint default 0 not null,
	routing_id integer,
	logs jsonb,
	hangup_time timestamp,
	agent_id bigint
);

comment on table call_center.cc_member_attempt is 'todo';

alter table call_center.cc_member_attempt owner to webitel;

create index if not exists cc_member_attempt_node_id_index
	on call_center.cc_member_attempt (node_id)
	where (hangup_at = 0);

create index if not exists cc_member_attempt_state_index
	on call_center.cc_member_attempt (state);

create unique index if not exists cc_member_attempt_id_uindex
	on call_center.cc_member_attempt (id);

create index if not exists cc_member_attempt_queue_id_index
	on call_center.cc_member_attempt (queue_id);

create index if not exists cc_member_attempt_member_id_index
	on call_center.cc_member_attempt (member_id);

create index if not exists cc_member_attempt_member_id_created_at_index
	on call_center.cc_member_attempt (member_id asc, created_at desc);

create index if not exists cc_member_attempt_member_id_state_hangup_at_index
	on call_center.cc_member_attempt (member_id, state, hangup_at);

create index if not exists cc_member_attempt_communication_id_hangup_time_index
	on call_center.cc_member_attempt (communication_id, hangup_time);

create table if not exists call_center.cc_member_messages
(
	id bigserial not null
		constraint cc_member_messages_pk
			primary key,
	member_id bigint not null
		constraint cc_member_messages_cc_member_id_fk
			references cc_member
				on update cascade on delete cascade,
	communication_id bigint not null
		constraint cc_member_messages_cc_member_communications_id_fk
			references cc_member_communications
				on update cascade on delete cascade,
	state integer default 0 not null,
	created_at bigint default 0 not null,
	message bytea
);

alter table call_center.cc_member_messages owner to webitel;

create unique index if not exists cc_member_messages_id_uindex
	on call_center.cc_member_messages (id);

create unique index if not exists cc_call_list_id_uindex
	on call_center.cc_list (id);

create table if not exists call_center.call_list_communications
(
	id bigserial not null
		constraint call_list_communications_pk
			primary key,
	list_id bigint not null,
	number varchar(50) not null
);

alter table call_center.call_list_communications owner to webitel;

create unique index if not exists call_list_communications_id_uindex
	on call_center.call_list_communications (id);

create table if not exists call_center.cc_list_communications
(
	list_id bigint not null
		constraint cc_list_communications_cc_list_id_fk
			references cc_list
				on update cascade on delete cascade,
	number varchar(25) not null,
	id bigserial not null
		constraint cc_list_communications_pk
			primary key
);

alter table call_center.cc_list_communications owner to webitel;

create unique index if not exists cc_list_communications_id_uindex
	on call_center.cc_list_communications (id);

