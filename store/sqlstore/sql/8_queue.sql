create table IF NOT EXISTS cc_queue
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
	dnc_list_id bigint
		constraint cc_queue_cc_list_id_fk
			references cc_list
				on update set null on delete set null
);


create unique index IF NOT EXISTS cc_queue_id_uindex
	on cc_queue (id);

create index IF NOT EXISTS cc_queue_enabled_priority_index
	on cc_queue (enabled asc, priority desc);


CREATE OR REPLACE VIEW cc_queue_is_working AS
 SELECT c1.id,
    c1.type,
    c1.strategy,
    c1.enabled,
    c1.payload,
    c1.calendar_id,
    c1.priority,
    c1.max_calls,
    c1.sec_between_retries,
    c1.updated_at,
    c1.name,
        CASE
            WHEN ((c1.max_calls - tmp.active_calls) <= 0) THEN 0
            ELSE (c1.max_calls - tmp.active_calls)
        END AS need_call,
    a.a AS available_agents
   FROM cc_queue c1,
    (LATERAL ( SELECT get_count_call(c1.id) AS active_calls) tmp(active_calls)
     LEFT JOIN LATERAL ( SELECT get_agents_available_count_by_queue_id(c1.id) AS a
          WHERE (c1.type <> 1)) a ON (true))
  WHERE ((c1.enabled = true) AND (EXISTS ( SELECT d.id,
            d.calendar_id,
            d.week_day,
            d.start_time_of_day,
            d.end_time_of_day,
            c2.id,
            c2.timezone,
            c2.start,
            c2.finish,
            c2.name
           FROM (calendar_accept_of_day d
             JOIN calendar c2 ON ((d.calendar_id = c2.id)))
          WHERE ((d.calendar_id = c1.calendar_id) AND ((((to_char(timezone((c2.timezone)::text, CURRENT_TIMESTAMP), 'SSSS'::text))::integer / 60) >= d.start_time_of_day) AND (((to_char(timezone((c2.timezone)::text, CURRENT_TIMESTAMP), 'SSSS'::text))::integer / 60) <= d.end_time_of_day))))));