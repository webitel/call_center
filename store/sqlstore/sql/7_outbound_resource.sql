create table IF NOT EXISTS cc_outbound_resource
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

create unique index IF NOT EXISTS cc_queue_resource_id_uindex
	on cc_outbound_resource (id);


--
-- Name: cc_queue_resources_is_working; Type: VIEW; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE VIEW cc_queue_resources_is_working AS
 SELECT r.id,
    r."limit" AS max_call_count,
    r.enabled,
    get_count_active_resources(r.id) AS reserved_count
   FROM cc_outbound_resource r
  WHERE ((r.enabled IS TRUE) AND (NOT (r.reserve IS TRUE)));