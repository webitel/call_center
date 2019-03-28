
drop function get_outbound_resources;
CREATE OR REPLACE FUNCTION get_outbound_resources(_filter text, _orderby text, _desc boolean,  _limit int,  _offset int)
  RETURNS SETOF cc_outbound_resource AS
$func$
DECLARE
 _empty text := '';
BEGIN
   RETURN QUERY EXECUTE FORMAT('SELECT
     *
   from cc_outbound_resource where ($1 = $2 OR name ILIKE $1)
   order by %I %s
   limit ($3)
   offset ($4)', _orderby, case _desc when true then 'DESC' else 'ASC' end)
   USING _filter, _empty, _limit, _offset;
END
$func$  LANGUAGE plpgsql STRICT ;


select *
from get_outbound_resources('', 'name', false, 10, 0);

SELECT id, "limit", enabled, priority, rps, reserve, name
			FROM get_outbound_resources('', :OrderByField::text, :OrderType, :Limit, :Offset);


drop function cc_resource_set_error;

CREATE OR REPLACE FUNCTION cc_resource_set_error(_id bigint, _routing_id bigint, _error_id varchar(50), _strategy varchar(50))
  RETURNS record AS
$$
DECLARE _res record;
  _stopped boolean;
  _successively_errors smallint;
  _un_reserved_id bigint;
BEGIN

  update cc_outbound_resource
  set last_error_id = _error_id,
      last_error_at = ((date_part('epoch'::text, now()) * (1000)::double precision))::bigint,
    successively_errors = successively_errors + 1,
    enabled = case when successively_errors + 1 >= max_successively_errors then false else enabled end
  where id = _id and "enabled" is true
  returning successively_errors >= max_successively_errors, successively_errors into _stopped, _successively_errors
  ;
  
  if _stopped is true then
    update cc_outbound_resource o
    set reserve = false,
        successively_errors = 0
    from (
      select id
      from cc_outbound_resource r
      where r.enabled is true
        and r.reserve is true
        and exists(
          select *
          from cc_resource_in_routing crir
          where crir.routing_id = _routing_id
            and crir.resource_id = r.id
        )
      order by case when _strategy = 'top_down' then r.last_error_at else null end asc,
               case _strategy
                 when 'by_limit' then r."limit"
                 when 'random' then random()
               else null
               end desc
      limit 1
    ) r
    where r.id = o.id
    returning o.id::bigint into _un_reserved_id;
  end if;
  
  select _successively_errors::smallint, _stopped::boolean, _un_reserved_id::bigint into _res;
  return _res;
END;
$$ LANGUAGE 'plpgsql';

select count_successively_error, stopped, un_reserve_resource_id from cc_resource_set_error(1, 1, 'tst', 'sadasd')
  as (count_successively_error smallint, stopped boolean, un_reserve_resource_id bigint);


select *
from cc_member_attempt
order by id desc ;

select *
from cc_outbound_resource
order by id asc ;


select id
from cc_outbound_resource r
where r.enabled is true
  and r.reserve is true
  and exists(
    select *
    from cc_queue_routing res
           inner join cc_resource_in_routing crir on res.id = crir.routing_id
    where res.id = 1
      and crir.resource_id = r.id
  )
order by case when 'top_down' = 'top_down1' then r.last_error_at else null end asc,
         case 'random'
           when 'by_limit' then r."limit"
           when 'random' then random()
         end desc
limit 1;


update cc_outbound_resource
  set last_error_id = 'aaa',
    successively_errors = successively_errors + 1,
    enabled = case when successively_errors + 1 >= max_successively_errors then false else enabled end
  where id = 1 and enabled is true
returning successively_errors, enabled ;



