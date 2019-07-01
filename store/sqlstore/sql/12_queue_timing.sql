create table IF NOT EXISTS cc_queue_timing
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

create unique index IF NOT EXISTS cc_queue_timing_id_uindex
	on cc_queue_timing (id);

create unique index IF NOT EXISTS  cc_queue_timing_queue_id_communication_id_start_time_of_day_end
	on cc_queue_timing (queue_id, communication_id, start_time_of_day, end_time_of_day);

create index IF NOT EXISTS cc_queue_timing_communication_id_max_attempt_index
	on cc_queue_timing (communication_id, max_attempt);

