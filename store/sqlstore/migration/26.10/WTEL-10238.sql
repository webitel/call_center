
create or replace function call_center.cc_member_set_sys_destinations_tg() returns trigger
    language plpgsql
as
$$
BEGIN
    if new.stop_cause notnull then
        new.ready_at = null;
    end if;

    if new.communications notnull and jsonb_typeof(new.communications) = 'array' then
        if new.communications @> '[{"destination": ""}]'::jsonb then
            raise exception 'empty destination' USING ERRCODE = '23503';
        end if;

        new.sys_destinations = (select array(select call_center.cc_destination_in(idx::int4 - 1, (x -> 'type' ->> 'id')::int4, (x ->> 'last_activity_at')::int8,  (x -> 'resource' ->> 'id')::int, (x ->> 'priority')::int)
         from jsonb_array_elements(new.communications) with ordinality as x(x, idx)
         where coalesce((x.x -> 'stop_at')::int8, 0) = 0
         and idx > -1
            order by coalesce((x ->> 'priority')::int, 0) desc, (x ->> 'last_activity_at')::int8 asc nulls first ));

        new.search_destinations = ARRAY(
            SELECT x->>'destination'
            FROM jsonb_array_elements(new.communications) x
        );

        if new.stop_at isnull and coalesce(array_length(new.sys_destinations, 1), 0 ) = 0 then
            new.stop_at = now();
            new.stop_cause = 'no_communications';
        end if;

    else
        new.sys_destinations = null;
        new.search_destinations = null;
    end if;

    return new;
END
$$;