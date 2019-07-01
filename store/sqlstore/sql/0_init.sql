DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'cc_agent_in_attempt') THEN
        CREATE TYPE cc_agent_in_attempt AS (
          attempt_id bigint,
          agent_id bigint
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'cc_communication_t') THEN
      CREATE TYPE cc_communication_t AS (
        number character varying(50),
        priority integer,
        state integer,
        routing_ids integer[]
      );
    END IF;
END$$;

--
-- Name: cc_available_agents_by_strategy(bigint, character varying, integer, bigint[], bigint[]); Type: FUNCTION; Schema: call_center; Owner: webitel
--
CREATE OR REPLACE FUNCTION cc_available_agents_by_strategy(_queue_id bigint, _strategy character varying, _limit integer, _last_agents bigint[], _except_agents bigint[]) RETURNS SETOF integer[]
    LANGUAGE plpgsql
    AS $$
BEGIN
  return query select ARRAY(
    select a.id
    from cc_agent a
    inner join (
      select
       COALESCE(aq.agent_id, csia.agent_id) as agent_id,
       COALESCE(max(csia.capacity), 0) max_of_capacity,
       max(aq.lvl) max_of_lvl
      from cc_agent_in_queue aq
        left join cc_skill_in_agent csia on aq.skill_id = csia.skill_id
      where aq.queue_id = _queue_id and not COALESCE(aq.agent_id, csia.agent_id) isnull
      group by COALESCE(aq.agent_id, csia.agent_id)
      --order by max(aq.lvl) desc, COALESCE(max(csia.capacity), 0) desc
    ) t on t.agent_id = a.id
    inner join cc_agent_activity ac on t.agent_id = ac.agent_id
    where a.status = 'online' and a.state = 'waiting'
      and not exists(select 1 from cc_member_attempt at where at.state > 0 and at.agent_id = a.id)
      and not (_except_agents::bigint[] && array[a.id]::bigint[])
    order by
     --a.id,
     case when _last_agents && array[a.id::bigint] then 1 else null end asc nulls last,
     t.max_of_lvl desc, t.max_of_capacity desc,
     ac.last_offering_call_at asc
    limit _limit

  );
END;
$$;


--
-- Name: cc_distribute_agent_to_attempt(character varying); Type: FUNCTION; Schema: call_center; Owner: webitel
--
CREATE OR REPLACE  FUNCTION cc_distribute_agent_to_attempt(_node_id character varying) RETURNS SETOF cc_agent_in_attempt
    LANGUAGE plpgsql
    AS $$
declare
  rec RECORD;
  agents bigint[];
  reserved_agents bigint[] := array[0];
  at cc_agent_in_attempt;
  counter int := 0;
BEGIN
FOR rec IN select cq.id::bigint queue_id, cq.strategy::varchar(50), count(*)::int as cnt,
                     array_agg((a.id, la.agent_id)::cc_agent_in_attempt order by a.created_at asc, a.weight desc )::cc_agent_in_attempt[] ids, array_agg(distinct la.agent_id) filter ( where not la.agent_id isnull )  last_agents
           from cc_member_attempt a
            inner join cc_queue cq on a.queue_id = cq.id
            left join lateral (
             select a1.agent_id
             from cc_member_attempt a1
             where a1.member_id = a.member_id and a1.created_at < a.created_at
             order by a1.created_at desc
             limit 1
           ) la on true
           where a.hangup_at = 0 and a.agent_id isnull and a.state = 3
           group by cq.id
           order by cq.priority desc
   LOOP

    select cc_available_agents_by_strategy(rec.queue_id, rec.strategy, rec.cnt, rec.last_agents, reserved_agents)
    into agents;

    counter := 0;
    foreach at IN ARRAY rec.ids
    LOOP
      if array_length(agents, 1) isnull then
        exit;
      end if;

      counter := counter + 1;

      if at.agent_id isnull OR not (agents && array[at.agent_id]) then
        at.agent_id = agents[array_upper(agents, 1)];
      end if;

      select agents::int[] - at.agent_id::int, reserved_agents::int[] || at.agent_id::int
      into agents, reserved_agents;

      return next at;
    END LOOP;
   END LOOP;

   --raise notice '%', reserved_agents;

  return;
END;
$$;



--
-- Name: cc_queue_timing_communication_ids(bigint); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION cc_queue_timing_communication_ids(_queue_id bigint) RETURNS integer[]
    LANGUAGE plpgsql
    AS $$
BEGIN
  return array(select distinct cqt.communication_id
from cc_queue q
  inner join calendar c on q.calendar_id = c.id
  inner join cc_queue_timing cqt on q.id = cqt.queue_id
where q.id = _queue_id
  and (to_char(current_timestamp AT TIME ZONE c.timezone, 'SSSS') :: int / 60)
    between cqt.start_time_of_day and cqt.end_time_of_day);
END;
$$;

--
-- Name: tg_fill_member_communication_resource(); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION tg_fill_member_communication_resource() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN

  if (tg_op = 'UPDATE' or tg_op = 'DELETE') then
    update cc_member_communications c
    set routing_ids = c.routing_ids - ARRAY [old.id]
    where c.id in (
      select c1.id
      from cc_member_communications c1
      	inner join cc_member cm on c1.member_id = cm.id
      where c1.routing_ids @> ARRAY [old.id] and cm.queue_id = old.queue_id
    );
  end if;

--  raise notice 'end delete';
  if (tg_op = 'UPDATE' or tg_op = 'INSERT') then

    update cc_member_communications c
    set routing_ids = c.routing_ids | ARRAY [new.id]
		from cc_member_communications c1
			inner join cc_member cm on c1.member_id = cm.id
		where c1.id = c.id and cm.queue_id = new.queue_id and not c1.routing_ids @> ARRAY [new.id]
        and c1.number ~* new.pattern;
  end if;

--  raise notice 'end add';
  RETURN new;
END;
$$;

--
-- Name: cc_set_agent_change_status(); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION cc_set_agent_change_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  insert into cc_agent_state_history (agent_id, joined_at, state)
  values (new.id, now(), new.state);
  RETURN new;
END;
$$;


--
-- Name: tg_get_member_communication_resource(); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION tg_get_member_communication_resource() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  --TODO change to STATEMENT !!!
  new.routing_ids = ARRAY(select r.id
  from cc_queue_routing r
  where r.queue_id = (select queue_id from cc_member m where m.id = new.member_id)
        and new.number ~ r.pattern
  );
 --raise notice 'TG "%" % -> %', new.routing_ids, new.member_id, new.number;

 RETURN new;
END;
$$;

--
-- Name: cc_unreserve_members_with_resources(character varying, character varying); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION cc_unreserve_members_with_resources(node character varying, res character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    count integer;
BEGIN
    update cc_member_attempt
      set state  = -1,
          hangup_at = ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint,
          result = res
    where hangup_at = 0 and node_id = node and state = 0;

    get diagnostics count = row_count;
    return count;
END;
$$;


--
-- Name: cc_reserve_members_with_resources(character varying); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION cc_reserve_members_with_resources(node_id character varying) RETURNS integer
    LANGUAGE plpgsql
    AS $$
DECLARE
    rec RECORD;
    count integer;
    v_cnt integer;
BEGIN
    count = 0;


    if NOT pg_try_advisory_xact_lock(13213211) then
      raise notice 'LOCK';
      return 0;
    end if;


    FOR rec IN SELECT r.*, q.dnc_list_id, cc_queue_timing_communication_ids(r.queue_id) as type_ids
      from get_free_resources() r
        inner join cc_queue q on q.id = r.queue_id
      where r.call_count > 0
      group by r.queue_id, resource_id, routing_ids, call_count, r.sec_between_retries, q.id
      order by q.priority desc
    LOOP
      insert into cc_member_attempt(result, communication_id, queue_id, member_id, resource_id, routing_id, node_id)
      select
              case when lc.number is null then null else 'OUTGOING_CALL_BARRED' end,
             t.communication_id,
             rec.queue_id,
             t.member_id,
             rec.resource_id,
             t.routing_id,
             node_id
      from (
        select
               c.*,
              (c.routing_ids & rec.routing_ids)[1] as routing_id,
               row_number() over (partition by c.member_id order by c.last_hangup_at, c.priority desc) d
        from (
          select c.id as communication_id, c.number as communication_number, c.routing_ids, c.last_hangup_at, c.priority, c.member_id
          from cc_member cm
           cross join cc_member_communications c
              where
                not exists(
                  select *
                  from cc_member_attempt a
                  where a.member_id = cm.id and a.state > 0
                )
                and cm.last_hangup_at < ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint
                                          - (rec.sec_between_retries * 1000)
                and cm.stop_at = 0
                and cm.queue_id = rec.queue_id

                and c.state = 0
                and ( (c.communication_id = any(rec.type_ids) ) or c.communication_id isnull )
                and c.member_id = cm.id
                and c.routing_ids && rec.routing_ids

            order by cm.priority desc
          limit rec.call_count * 3 --todo 3 is avg communication count
        ) c
      ) t
      left join cc_list_communications lc on lc.list_id = rec.dnc_list_id and lc.number = t.communication_number
      where t.d =1
      limit rec.call_count;

      get diagnostics v_cnt = row_count;
      count = count + v_cnt;
    END LOOP;
    return count;
END;
$$;



--
-- Name: get_free_resources(); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION get_free_resources() RETURNS TABLE(queue_id integer, resource_id integer, routing_ids integer[], call_count integer, sec_between_retries integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
    with rr as (
      select q.id as q_id,
             q.sec_between_retries,
             cor.id resource_id,
             q.need_call as q_cnt,
             (case when cor.max_call_count - cor.reserved_count <= 0 then
               0 else cor.max_call_count - cor.reserved_count end) r_cnt,

             --todo absolute to calc priority!!!
             round(100.0 * (q.need_call + 1) / NULLIF(SUM(q.need_call + 1) OVER(partition by cor.id),0)) AS "ratio",
              array_agg(r.id order by r.priority desc, crir2.priority desc) as routing_ids
      from cc_queue_is_working q
             inner join cc_queue_routing r on q.id = r.queue_id
             inner join cc_resource_in_routing crir2 on r.id = crir2.routing_id
             inner join cc_queue_resources_is_working cor on crir2.resource_id = cor.id
      where q.need_call > 0
--           and exists ( --todo big table... не можуть пересікитися в чергах
--             select * from cc_member_communications cmc
--             where cmc.state = 0 and cmc.routing_ids && array[r.id])
      group by q.id, q.sec_between_retries, q.need_call, cor.id, cor.max_call_count, cor.reserved_count

    ), res_s as (
        select * ,
               sum(cnt) over (partition by rr.q_id order by ratio desc ) s
        from rr,
             lateral (select round(rr.ratio * rr.r_cnt / 100) ) resources_by_ration(cnt)
      ),
      res as (
        select *, coalesce(lag(s) over(partition by q_id order by ratio desc), 0) as lag_sum
        from res_s
      )
      select res.q_id::int, res.resource_id::int, res.routing_ids::int[],
             (case when s < q_cnt then res.cnt else res.q_cnt - res.lag_sum end)::int call_count,
             res.sec_between_retries
      from res
    where res.lag_sum < res.q_cnt;
END;
$$;


--
-- Name: get_count_call(integer); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION get_count_call(integer) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $_$
BEGIN
  RETURN QUERY SELECT count(*) :: integer
               FROM cc_member_attempt
               WHERE hangup_at = 0 AND queue_id = $1 AND state > -1;
  RETURN;
END
$_$;


--
-- Name: get_agents_available_count_by_queue_id(integer); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION get_agents_available_count_by_queue_id(_queue_id integer) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $$
BEGIN
  return query select count(distinct qa.agent_id)::integer as cnt
               from (
                      select aq.queue_id, COALESCE(aq.agent_id, csia.agent_id) as agent_id
                      from cc_agent_in_queue aq
                             left join cc_skils cs on aq.skill_id = cs.id
                             left join cc_skill_in_agent csia on cs.id = csia.skill_id
                      where aq.queue_id = _queue_id
                      group by aq.queue_id, aq.agent_id, csia.agent_id
                    ) as qa

               where qa.queue_id = _queue_id
                 and not qa.agent_id is null
                 and not exists(select * from cc_member_attempt a where a.hangup_at = 0 and a.agent_id = qa.agent_id);
END;
$$;


--
-- Name: get_count_active_resources(integer); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION get_count_active_resources(integer) RETURNS SETOF integer
    LANGUAGE plpgsql
    AS $_$
BEGIN
  RETURN QUERY SELECT count(*) :: integer
               FROM cc_member_attempt a
               WHERE hangup_at = 0
                 AND a.resource_id = $1;
END
$_$;




--
-- Name: cc_set_active_members(character varying); Type: FUNCTION; Schema: call_center; Owner: webitel
--

CREATE OR REPLACE FUNCTION cc_set_active_members(node character varying) RETURNS TABLE(id bigint, member_id bigint, communication_id bigint, result character varying, queue_id integer, queue_updated_at bigint, resource_id integer, resource_updated_at bigint, routing_id integer, routing_pattern character varying, destination character varying, description character varying, variables jsonb, name character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
  RETURN QUERY
    update cc_member_attempt a
      set state = 1
        ,node_id = node
      from (
        select
               c.id,
               cq.updated_at as queue_updated_at,
               r.updated_at as resource_updated_at,
               qr.id as routing_id,
               qr.pattern as routing_pattern,
               cmc.number as destination,
               cmc.description as description,
               cm.variables as variables,
               cm.name as member_name
        from cc_member_attempt c
               inner join cc_member cm on c.member_id = cm.id
               inner join cc_member_communications cmc on cmc.id = c.communication_id
               inner join cc_queue cq on cm.queue_id = cq.id
               left join cc_queue_routing qr on qr.id = c.routing_id
               left join cc_outbound_resource r on r.id = c.resource_id
        where c.state = 0 and c.hangup_at = 0
        order by cq.priority desc, cm.priority desc
        for update of c
      ) c
      where a.id = c.id
      returning
        a.id::bigint as id,
        a.member_id::bigint as member_id,
        a.communication_id::bigint as communication_id,
        a.result as result,
        a.queue_id::int as qeueue_id,
        c.queue_updated_at::bigint as queue_updated_at,
        a.resource_id::int as resource_id,
        c.resource_updated_at::bigint as resource_updated_at,
        c.routing_id,
        c.routing_pattern,
        c.destination,
        c.description,
        c.variables,
        c.member_name;
END;
$$;