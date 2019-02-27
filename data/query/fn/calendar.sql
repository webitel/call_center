
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
