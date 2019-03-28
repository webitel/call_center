create UNLOGGED table  if not exists call_center.cc_member_attempt
(
	id serial not null
		constraint cc_member_attempt_pk
			primary key,
	communication_id integer not null
		constraint cc_member_attempt_cc_member_communications_id_fk
			references cc_member_communications
				on update cascade on delete cascade,
	timing_id integer
		constraint cc_member_attempt_cc_queue_timing_id_fk
			references cc_queue_timing,
	queue_id integer not null
		constraint cc_member_attempt_cc_queue_id_fk
			references cc_queue
				on update cascade on delete cascade,
	state integer default 0 not null,
	member_id integer not null
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
	result varchar(30)
);

comment on table call_center.cc_member_attempt is 'todo';

alter table call_center.cc_member_attempt owner to webitel;

create unique index if not exists cc_member_attempt_id_uindex
	on call_center.cc_member_attempt (id);

create index if not exists cc_member_attempt_member_id_index
	on call_center.cc_member_attempt (member_id);

create index if not exists cc_member_attempt_queue_id_index
	on call_center.cc_member_attempt (queue_id);

create index if not exists cc_member_attempt_queue_id_index_2
	on call_center.cc_member_attempt (queue_id)
	where (hangup_at = 0);

create index if not exists cc_member_attempt_member_id_index_2
	on call_center.cc_member_attempt (member_id)
	where (hangup_at = 0);

create index if not exists cc_member_attempt_node_id_index
	on call_center.cc_member_attempt (node_id)
	where (hangup_at = 0);

create index if not exists cc_member_attempt_state_index
	on call_center.cc_member_attempt (state);


create unique index if not exists cc_member_attempt_Member_id_index_test
	on call_center.cc_member_attempt (member_id)
where state != -1;


select member_id, count(*)
from cc_member_attempt
where state > -1
group by member_id
having count(*) > 1 ;

truncate table cc_member_attempt;

select  *
from cc_member_attempt
order by id desc;

select
	count(*)
from call_center.cc_member_attempt
where hangup_at = 0;


select *
from call_center.;

select to_timestamp(1551797927);


with att as (
	update cc_member_attempt
	  set state =  3,
	    	originate_at = 0
	where id = 0
  returning id
)
update cc_member_communications c
set last_calle_at = 1
from cc_member m
where m.id = 81 and c.id = 212 and exists(select * from att)
returning
	m.id as member_id,
  m.name as name,
	m.variables as variables,
  c.id as communication_id,
  c.number as number,
  c.description as description;



with att as (
	update cc_member_attempt
		set state = :State,
			originate_at = :OriginateAt
		where id = :AttemptId
		returning id
)
update cc_member_communications c
set last_calle_at = :OriginateAt
from cc_member m
where m.id = :MemberId
	and c.id = :CommunicationId
	and exists(select * from att)
returning
	m.name as name,
	m.variables as variables,
	c.number as number,
	c.description as description;


select ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint;



update cc_queue_routing
set pattern = '(.*)'
where id = 26;

select count(*)
from cc_member_attempt;


select *
from cc_member_attempt
where id = 6164765;

update cc_queue_routing
set pattern = '(.*)'
where id = 18;


select number, routing_ids
from cc_member_communications
where state = 0 and number ~* '^1111';


explain analyse
update cc_member_communications c
    set routing_ids = c.routing_ids - ARRAY [old.id]
    where c.id in (
      select c1.id
      from cc_member_communications c1
      	inner join cc_member cm on c1.member_id = cm.id
      where c1.routing_ids @> ARRAY [18] and cm.queue_id = 1
    );;

vacuum full cc_member_communications;

	explain analyse
      select c1.*
			from cc_member_communications c1
      	--inner join cc_member cm on c1.member_id = cm.id
      where c1.routing_ids @> ARRAY [5]
        and c1.number ~* '^12(.*)'

      ;


select *
from cc_member_communications where id = 212;

truncate table cc_member_attempt;

select *
from cc_member_attempt
order by id desc ;
