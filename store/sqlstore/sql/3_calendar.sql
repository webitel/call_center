
create table IF NOT EXISTS calendar
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

create unique index IF NOT EXISTS calendar_id_uindex
	on calendar (id);

create index IF NOT EXISTS calendar_name_id_index
	on calendar (name, id);


--
create table IF NOT EXISTS  calendar_accept_of_day
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

create unique index IF NOT EXISTS  calendar_accept_of_day_calendar_id_week_day_start_time_of_day_e
	on calendar_accept_of_day (calendar_id, week_day, start_time_of_day, end_time_of_day);

create unique index IF NOT EXISTS  calendar_accept_of_day_id_uindex
	on calendar_accept_of_day (id);

--
create table IF NOT EXISTS calendar_except
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

create unique index IF NOT EXISTS calendar_except_id_uindex
	on calendar_except (id);