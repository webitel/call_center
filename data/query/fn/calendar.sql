
CREATE OR REPLACE FUNCTION get_calendars(_filter text, _orderby text, _desc boolean,  _limit int,  _offset int)
  RETURNS SETOF calendar AS
$func$
DECLARE
 _empty text := '';
BEGIN
   RETURN QUERY EXECUTE FORMAT('SELECT
     *
   from calendar where ($1 = $2 OR name ILIKE $1)
   order by %I %s
   limit ($3)
   offset ($4)', _orderby, case _desc when true then 'DESC' else 'ASC' end)
   USING _filter, _empty, _limit, _offset;
END
$func$  LANGUAGE plpgsql STRICT ;

drop function get_calendars;


select *
from calendar;


explain analyze
select c.id,
       c.name,
       c.start,
       c.finish,
       c.description,
       json_build_object('id', ct.id, 'name', ct.name)::jsonb as timezone
from calendar c
       left join calendar_timezones ct on c.timezone_id = ct.id
where c.domain_id = 50 and c.id = 1
  and (
    exists(select 1
      from calendar_acl a
      where a.dc = c.domain_id and a.object = c.id and a.subject = any(array[14001]) and a.access&1 = 1)
  );

update calendar
set domain_id = 50
where 1=1;