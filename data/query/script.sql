-- Unknown how to generate base type type

alter type gtrgm owner to webitel;

create table calendar
(
  id       serial                                       not null
    constraint calendar_pkey
      primary key,
  timezone varchar(15) default 'utc'::character varying not null,
  start    integer,
  "end"    integer,
  name     varchar(20)                                  not null
);

alter table calendar
  owner to webitel;

create unique index calendar_id_uindex
  on calendar (id);

create table calendar_accept_of_day
(
  id                serial                not null
    constraint calendar_accept_of_day_pkey
      primary key,
  calendar_id       integer               not null
    constraint calendar_accept_of_day_calendar_id_fk
      references calendar
      on update cascade on delete cascade,
  week_day          smallint              not null,
  start_time_of_day smallint default 0    not null,
  end_time_of_day   smallint default 1440 not null
);

alter table calendar_accept_of_day
  owner to webitel;

create unique index calendar_accept_of_day_calendar_id_week_day_start_time_of_day_e
  on calendar_accept_of_day (calendar_id, week_day, start_time_of_day, end_time_of_day);

create unique index calendar_accept_of_day_id_uindex
  on calendar_accept_of_day (id);

create table calendar_except
(
  id          serial  not null
    constraint calendar_except_pkey
      primary key,
  calendar_id integer not null
    constraint calendar_except_calendar_id_fk
      references calendar
      on update cascade on delete cascade,
  date        integer not null,
  repeat      smallint
);

alter table calendar_except
  owner to webitel;

create unique index calendar_except_id_uindex
  on calendar_except (id);

create table cc_agent
(
  id   serial      not null
    constraint cc_agent_pkey
      primary key,
  name varchar(50) not null
);

alter table cc_agent
  owner to webitel;

create unique index cc_agent_id_uindex
  on cc_agent (id);

create table cc_communication
(
  id   serial      not null
    constraint cc_communication_pkey
      primary key,
  name varchar(50) not null,
  code varchar(10) not null
);

alter table cc_communication
  owner to webitel;

create unique index cc_communication_id_uindex
  on cc_communication (id);

create table cc_outbound_resource
(
  id             serial               not null
    constraint cc_queue_resource_pkey
      primary key,
  max_call_count integer default 0    not null,
  enabled        boolean default true not null
);

alter table cc_outbound_resource
  owner to webitel;

create unique index cc_queue_resource_id_uindex
  on cc_outbound_resource (id);

create table cc_queue
(
  id                  serial             not null
    constraint cc_queue_pkey
      primary key,
  type                integer            not null,
  strategy            varchar(10)        not null,
  enabled             boolean            not null,
  payload             jsonb,
  calendar_id         integer            not null
    constraint cc_queue_calendar_id_fk
      references calendar,
  priority            integer default 0  not null,
  max_calls           integer default 0  not null,
  sec_between_retries integer default 10 not null
);

alter table cc_queue
  owner to webitel;

create table cc_agent_in_queue
(
  id       serial  not null
    constraint cc_agent_in_queue_pkey
      primary key,
  agent_id integer not null
    constraint cc_agent_in_queue_cc_agent_id_fk
      references cc_agent,
  queue_id integer not null
    constraint cc_agent_in_queue_cc_queue_id_fk
      references cc_queue
      on update cascade on delete cascade
);

alter table cc_agent_in_queue
  owner to webitel;

create unique index cc_agent_in_queue_id_uindex
  on cc_agent_in_queue (id);

create table cc_member
(
  id        serial             not null
    constraint cc_member_pkey
      primary key,
  queue_id  integer            not null
    constraint cc_member_cc_queue_id_fk
      references cc_queue
      on update cascade on delete cascade,
  priority  smallint default 0 not null,
  expire_at integer
);

alter table cc_member
  owner to webitel;

create unique index cc_member_id_uindex
  on cc_member (id);

create index cc_member_queue_id_priority_index
  on cc_member (queue_id, priority);

create table cc_member_communications
(
  id               serial             not null
    constraint cc_member_communications_id_pk
      primary key,
  member_id        integer            not null
    constraint cc_member_communications_cc_member_id_fk
      references cc_member
      on update cascade on delete cascade,
  priority         smallint default 0 not null,
  number           varchar(20)        not null,
  last_calle_at    integer  default 0 not null,
  state            smallint default 0 not null,
  communication_id integer
    constraint cc_member_communications_cc_communication_id_fk
      references cc_communication
);

alter table cc_member_communications
  owner to webitel;

create unique index cc_member_communications_id_uindex
  on cc_member_communications (id);

create index cc_member_communications_last_calle_at_priority_index
  on cc_member_communications (last_calle_at, priority);

create index cc_member_communications_state_member_id_last_calle_at_priority
  on cc_member_communications (state, member_id, last_calle_at, priority);

create index cc_member_communications_number_index
  on cc_member_communications (number);

create index cc_member_communications_number_reg
  on cc_member_communications (number);

create index cc_queue_enabled_priority_index
  on cc_queue (enabled asc, priority desc);

create unique index cc_queue_id_uindex
  on cc_queue (id);

create table cc_queue_routing
(
  id       serial            not null
    constraint cc_queue_routing_pkey
      primary key,
  queue_id integer           not null
    constraint cc_queue_routing_cc_queue_id_fk
      references cc_queue
      on update cascade on delete cascade,
  pattern  varchar(50)       not null,
  priority integer default 0 not null
);

alter table cc_queue_routing
  owner to webitel;

create unique index cc_queue_routing_id_uindex
  on cc_queue_routing (id);

create table cc_queue_timing
(
  id                serial                not null
    constraint cc_queue_timing_pkey
      primary key,
  queue_id          integer               not null
    constraint cc_queue_timing_cc_queue_id_fk
      references cc_queue
      on update cascade on delete cascade,
  communication_id  integer               not null
    constraint cc_queue_timing_cc_communication_id_fk
      references cc_communication,
  priority          smallint default 0    not null,
  start_time_of_day smallint default 0    not null,
  end_time_of_day   smallint default 1439 not null,
  max_attempt       smallint default 0    not null
);

alter table cc_queue_timing
  owner to webitel;

create unique index cc_queue_timing_id_uindex
  on cc_queue_timing (id);

create unique index cc_queue_timing_queue_id_communication_id_start_time_of_day_end
  on cc_queue_timing (queue_id, communication_id, start_time_of_day, end_time_of_day);

create table cc_resource_in_routing
(
  id          serial             not null
    constraint cc_resource_in_queue_pkey
      primary key,
  resource_id integer            not null
    constraint cc_resource_in_queue_cc_outbound_resource_id_fk
      references cc_outbound_resource,
  priority    smallint default 0 not null,
  routing_id  integer            not null
    constraint cc_resource_in_routing_cc_queue_routing_id_fk
      references cc_queue_routing
      on update cascade on delete cascade
);

alter table cc_resource_in_routing
  owner to webitel;

create unique index cc_resource_in_queue_id_uindex
  on cc_resource_in_routing (id);

create table cc_skils
(
  id   serial      not null
    constraint cc_skils_pkey
      primary key,
  code varchar(20) not null
);

alter table cc_skils
  owner to webitel;

create table cc_skill_in_agent
(
  id       serial  not null
    constraint cc_skill_in_agent_pkey
      primary key,
  skill_id integer not null
    constraint cc_skill_in_agent_cc_skils_id_fk
      references cc_skils,
  agent_id integer not null
    constraint cc_skill_in_agent_cc_agent_id_fk
      references cc_agent
      on update cascade on delete cascade
);

alter table cc_skill_in_agent
  owner to webitel;

create unique index cc_skill_in_agent_id_uindex
  on cc_skill_in_agent (id);

create table cc_skill_in_queue
(
  id       serial  not null
    constraint cc_skill_in_queue_pkey
      primary key,
  queue_id integer not null
    constraint cc_skill_in_queue_cc_queue_id_fk
      references cc_queue
      on update cascade on delete cascade,
  skill_id integer not null
    constraint cc_skill_in_queue_cc_skils_id_fk
      references cc_skils
);

alter table cc_skill_in_queue
  owner to webitel;

create unique index cc_skill_in_queue_id_uindex
  on cc_skill_in_queue (id);

create unique index cc_skils_id_uindex
  on cc_skils (id);

create table session
(
  "Id"     varchar(26) not null
    constraint session_pkey
      primary key,
  "Token"  varchar(500),
  "UserId" varchar(26)
);

alter table session
  owner to webitel;

create table cc_member_attempt
(
  id                  serial                                                                                 not null
    constraint cc_member_attempt_pk
      primary key,
  communication_id    integer                                                                                not null
    constraint cc_member_attempt_cc_member_communications_id_fk
      references cc_member_communications
      on update cascade on delete cascade,
  resource_routing_id integer
    constraint cc_member_attempt_cc_resource_in_routing_id_fk
      references cc_resource_in_routing,
  timing_id           integer
    constraint cc_member_attempt_cc_queue_timing_id_fk
      references cc_queue_timing,
  queue_id            integer                                                                                not null
    constraint cc_member_attempt_cc_queue_id_fk
      references cc_queue
      on update cascade on delete cascade,
  state               integer default 0                                                                      not null,
  member_id           integer                                                                                not null
    constraint cc_member_attempt_cc_member_id_fk
      references cc_member
      on update cascade on delete cascade,
  created_at          bigint  default ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint not null,
  weight              integer default 0                                                                      not null,
  hangup_at           integer default 0                                                                      not null,
  bridged_at          integer default 0                                                                      not null
);

alter table cc_member_attempt
  owner to webitel;

create unique index cc_member_attempt_id_uindex
  on cc_member_attempt (id);

create index cc_member_attempt_member_id_state_index
  on cc_member_attempt (member_id, state)
  where (state = 0);

create index cc_member_attempt_state_created_at_weight_index
  on cc_member_attempt (state asc, created_at desc, weight asc);

create index cc_member_attempt_queue_id_hangup_at_index
  on cc_member_attempt (queue_id, hangup_at)
  where (hangup_at = 0);

create view cc_member_communications_is_working as
SELECT row_number()
           OVER (PARTITION BY cc_member_communications.member_id ORDER BY cc_member_communications.last_calle_at, cc_member_communications.priority) AS "position",
       cc_member_communications.id,
       cc_member_communications.member_id,
       cc_member_communications.priority,
       cc_member_communications.number,
       cc_member_communications.last_calle_at,
       cc_member_communications.state,
       cc_member_communications.communication_id
FROM call_center.cc_member_communications
WHERE (cc_member_communications.state = 0);

alter table cc_member_communications_is_working
  owner to webitel;

create view cc_queue_is_working as
SELECT c1.id,
       c1.type,
       c1.strategy,
       c1.enabled,
       c1.payload,
       c1.calendar_id,
       c1.priority,
       c1.max_calls,
       c1.sec_between_retries,
       call_center.cc_queue_require_agents(c1.type)    AS require_agent,
       call_center.cc_queue_require_resources(c1.type) AS require_resource,
       call_center.get_count_call(c1.id)               AS active_calls
FROM call_center.cc_queue c1
WHERE ((c1.enabled = true) AND (EXISTS(SELECT d.id,
                                              d.calendar_id,
                                              d.week_day,
                                              d.start_time_of_day,
                                              d.end_time_of_day,
                                              c2.id,
                                              c2.timezone,
                                              c2.start,
                                              c2.finish,
                                              c2.name
                                       FROM (call_center.calendar_accept_of_day d
                                              JOIN call_center.calendar c2 ON ((d.calendar_id = c2.id)))
                                       WHERE ((d.calendar_id = c1.calendar_id) AND
                                              ((((to_char(timezone((c2.timezone)::text, CURRENT_TIMESTAMP),
                                                          'SSSS'::text))::integer / 60) >= d.start_time_of_day) AND
                                               (((to_char(timezone((c2.timezone)::text, CURRENT_TIMESTAMP),
                                                          'SSSS'::text))::integer / 60) <= d.end_time_of_day))))));

alter table cc_queue_is_working
  owner to webitel;

create view members_in_queue as
SELECT cc_member.id,
       cc_member.queue_id,
       cc_member.priority,
       cc_member.expire_at
FROM call_center.cc_member
  with local check option;

alter table members_in_queue
  owner to webitel;

create view cc_queue_resources_is_working as
SELECT r.id,
       r.max_call_count,
       r.enabled,
       call_center.get_count_active_resources(r.id) AS reserved_count
FROM call_center.cc_outbound_resource r
WHERE (r.enabled = true);

alter table cc_queue_resources_is_working
  owner to webitel;

create function cc_queue_require_agents(integer) returns boolean
  language plpgsql
as
$$
BEGIN
  if $1 = 2 then
    return false;
  end if;
  RETURN true;
END
$$;

alter function cc_queue_require_agents(integer) owner to webitel;

create function cc_queue_require_resources(integer) returns boolean
  language plpgsql
as
$$
BEGIN
  if $1 = 1 then
    return false;
  end if;
  RETURN true;
END
$$;

alter function cc_queue_require_resources(integer) owner to webitel;

create function f_add_task_for_call() returns integer
  language plpgsql
as
$$
declare
  i_cnt integer;
BEGIN
  if pg_try_advisory_lock(77515154878) != true
  then
    return -1;
  end if;

  insert into cc_member_attempt (communication_id, queue_id, member_id, weight)

  select m.cc_id as communication_id,
         q.id    as queue_id,
         m.id,
         row_number() over (order by q.priority desc )
  from cc_queue_is_working q
     , lateral (select case
                         when q.max_calls - q.active_calls <= 0
                           then 0
                         else q.max_calls - q.active_calls end) as qq(need_calls)
         inner join lateral (
    select c.cc_id as cc_id,
           m.id
    from cc_member m
           inner join lateral (
      select id as cc_id,
             queue_id,
             number,
             communication_id
      from cc_member_communications c
      where c.member_id = m.id
        and c.state = 0
        and last_calle_at <= q.sec_between_retries
      order by last_calle_at, priority
      limit 1
      ) as c on true

    where m.queue_id = q.id
      and not exists(select 1
                     from cc_member_attempt a
                     where a.member_id = m.id
                       and a.state = 0)
      and pg_try_advisory_xact_lock('cc_member_communications' :: regclass :: oid :: integer, m.id)
    order by m.priority asc
    limit qq.need_calls
    ) m on true
  order by q.priority desc;
  GET DIAGNOSTICS i_cnt = ROW_COUNT;

  RETURN i_cnt; -- true if INSERT
END
$$;

alter function f_add_task_for_call() owner to webitel;

create function flush_daily_counts_queue() returns boolean
  language plpgsql
as
$$
DECLARE
BEGIN
  SET transaction ISOLATION LEVEL SERIALIZABLE;
  update cc_queue
  set priority = priority + 1 + (select 1
                                 from pg_sleep(10)
                                 limit 1)
  where cc_queue.id = 1;
  return true;
  commit;

EXCEPTION
  --exception within loop
  WHEN OTHERS
    THEN
      begin

        RAISE INFO 'Error Name:%', SQLERRM;

        RAISE INFO 'Error State:%', SQLSTATE;
      end;

      return false;


END;
$$;

alter function flush_daily_counts_queue() owner to webitel;

create function flush_daily_counts_queue2() returns void
  language plpgsql
as
$$
DECLARE
BEGIN

  SET transaction ISOLATION LEVEL SERIALIZABLE;

  update cc_queue
  set priority = priority + 1 + (select 1
                                 from pg_sleep(10)
                                 limit 1)
  where cc_queue.id = 1;


EXCEPTION
  --exception within loop
  WHEN OTHERS
    THEN ROLLBACK;

    return;
    commit;


END;
$$;

alter function flush_daily_counts_queue2() owner to webitel;

create function get_available_member_communication(integer) returns void
  language plpgsql
as
$$
BEGIN
  IF NOT pg_try_advisory_xact_lock(1) THEN
    RAISE NOTICE 'skipping queue flush';
    RETURN;
  END IF;

  perform pg_sleep(10);

END
$$;

alter function get_available_member_communication(integer) owner to webitel;

create function get_count_call(integer) returns SETOF integer
  language plpgsql
as
$$
BEGIN
  RETURN QUERY SELECT count(*) :: integer
               FROM call_center.cc_member_attempt
               WHERE queue_id = $1
                 and hangup_at = 0;
  RETURN;
END
$$;

alter function get_count_call(integer) owner to webitel;

create function get_count_active_resources(integer) returns SETOF integer
  language plpgsql
as
$$
BEGIN
  RETURN QUERY SELECT count(*) :: integer
               FROM call_center.cc_member_attempt a
                      inner join call_center.cc_resource_in_routing r on r.id = a.resource_routing_id
               WHERE hangup_at = 0
                 AND r.routing_id = $1;
END
$$;

alter function get_count_active_resources(integer) owner to webitel;

create function set_limit(real)
  strict
  language c
as -- missing source code
;

alter function set_limit(real) owner to webitel;

create function show_limit()
  stable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function show_limit() owner to webitel;

create function show_trgm(text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function show_trgm(text) owner to webitel;

create function similarity(text, text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function similarity(text, text) owner to webitel;

create function similarity_op(text, text)
  stable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function similarity_op(text, text) owner to webitel;

create function word_similarity(text, text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function word_similarity(text, text) owner to webitel;

create function word_similarity_op(text, text)
  stable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function word_similarity_op(text, text) owner to webitel;

create function word_similarity_commutator_op(text, text)
  stable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function word_similarity_commutator_op(text, text) owner to webitel;

create function similarity_dist(text, text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function similarity_dist(text, text) owner to webitel;

create function word_similarity_dist_op(text, text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function word_similarity_dist_op(text, text) owner to webitel;

create function word_similarity_dist_commutator_op(text, text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function word_similarity_dist_commutator_op(text, text) owner to webitel;

create function gtrgm_in(cstring)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_in(cstring) owner to webitel;

create function gtrgm_out(call_center.gtrgm)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_out(call_center.gtrgm) owner to webitel;

create function gtrgm_consistent(internal, text, smallint, oid, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_consistent(internal, text, smallint, oid, internal) owner to webitel;

create function gtrgm_distance(internal, text, smallint, oid, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_distance(internal, text, smallint, oid, internal) owner to webitel;

create function gtrgm_compress(internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_compress(internal) owner to webitel;

create function gtrgm_decompress(internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_decompress(internal) owner to webitel;

create function gtrgm_penalty(internal, internal, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_penalty(internal, internal, internal) owner to webitel;

create function gtrgm_picksplit(internal, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_picksplit(internal, internal) owner to webitel;

create function gtrgm_union(internal, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_union(internal, internal) owner to webitel;

create function gtrgm_same(call_center.gtrgm, call_center.gtrgm, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gtrgm_same(call_center.gtrgm, call_center.gtrgm, internal) owner to webitel;

create function gin_extract_value_trgm(text, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gin_extract_value_trgm(text, internal) owner to webitel;

create function gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gin_extract_query_trgm(text, internal, smallint, internal, internal, internal, internal) owner to webitel;

create function gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gin_trgm_consistent(internal, smallint, text, integer, internal, internal, internal, internal) owner to webitel;

create function gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function gin_trgm_triconsistent(internal, smallint, text, integer, internal, internal, internal) owner to webitel;

create function strict_word_similarity(text, text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function strict_word_similarity(text, text) owner to webitel;

create function strict_word_similarity_op(text, text)
  stable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function strict_word_similarity_op(text, text) owner to webitel;

create function strict_word_similarity_commutator_op(text, text)
  stable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function strict_word_similarity_commutator_op(text, text) owner to webitel;

create function strict_word_similarity_dist_op(text, text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function strict_word_similarity_dist_op(text, text) owner to webitel;

create function strict_word_similarity_dist_commutator_op(text, text)
  immutable
  strict
  parallel safe
  language c
as -- missing source code
;

alter function strict_word_similarity_dist_commutator_op(text, text) owner to webitel;

create operator % (procedure = "call_center.similarity_op", leftarg = text, rightarg = text);

alter operator %(text, text) owner to webitel;

create operator %> (procedure = "call_center.word_similarity_commutator_op", leftarg = text, rightarg = text);

alter operator %>(text, text) owner to webitel;

create operator <% (procedure = "call_center.word_similarity_op", leftarg = text, rightarg = text);

alter operator <%(text, text) owner to webitel;

create operator <-> (procedure = "call_center.similarity_dist", leftarg = text, rightarg = text);

alter operator <->(text, text) owner to webitel;

create operator <->> (procedure = "call_center.word_similarity_dist_commutator_op", leftarg = text, rightarg = text);

alter operator <->>(text, text) owner to webitel;

create operator <<-> (procedure = "call_center.word_similarity_dist_op", leftarg = text, rightarg = text);

alter operator <<->(text, text) owner to webitel;

create operator %>> (procedure = "call_center.strict_word_similarity_commutator_op", leftarg = text, rightarg = text);

alter operator %>>(text, text) owner to webitel;

create operator <<% (procedure = "call_center.strict_word_similarity_op", leftarg = text, rightarg = text);

alter operator <<%(text, text) owner to webitel;

create operator <->>> (procedure = "call_center.strict_word_similarity_dist_commutator_op", leftarg = text, rightarg = text);

alter operator <->>>(text, text) owner to webitel;

create operator <<<-> (procedure = "call_center.strict_word_similarity_dist_op", leftarg = text, rightarg = text);

alter operator <<<->(text, text) owner to webitel;


