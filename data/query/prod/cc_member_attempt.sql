drop table cc_member_attempt;

create table call_center.cc_member_attempt
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
		constraint cc_member_attempt_cc_agent_id_fk
			references cc_agent
				on update set null on delete set null
) WITH (fillfactor = 50);

comment on table call_center.cc_member_attempt is 'todo';

alter table call_center.cc_member_attempt owner to webitel;

create index cc_member_attempt_node_id_index
	on call_center.cc_member_attempt (node_id)
	where (hangup_at = 0);

create index cc_member_attempt_state_index
	on call_center.cc_member_attempt (state);

create unique index cc_member_attempt_id_uindex
	on call_center.cc_member_attempt (id);

create index cc_member_attempt_queue_id_index
	on call_center.cc_member_attempt (queue_id);

create index cc_member_attempt_member_id_index
	on call_center.cc_member_attempt (member_id);

create index cc_member_attempt_member_id_created_at_index
	on call_center.cc_member_attempt (member_id asc, created_at desc);

create index cc_member_attempt_member_id_state_hangup_at_index
	on call_center.cc_member_attempt (member_id, state, hangup_at);

create index cc_member_attempt_communication_id_hangup_time_index
	on call_center.cc_member_attempt (communication_id, hangup_time);

create index cc_member_attempt_hangup_at_queue_id_index
	on call_center.cc_member_attempt (hangup_at, queue_id);

