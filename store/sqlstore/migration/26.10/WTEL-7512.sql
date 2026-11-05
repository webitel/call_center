-- WTEL-7512: drop the duplicate timezone Europe/Kiev, move every record that uses it to Europe/Kyiv
do
$$
declare
    kiev constant text := 'Europe/Kiev';
    kyiv constant text := 'Europe/Kyiv';
    kiev_id integer;
    kyiv_id integer;
    promote bigint[];
begin
    -- 1. offset groups (every state): Kyiv takes Kiev's place, so names[1] stays on the same zone
    update flow.calendar_timezone_offsets
    set names = array_replace(names, kiev, kyiv)
    where kiev = any (names);

    -- 2. find both timezone rows; lock the Kiev one so nothing new can reference it meanwhile
    select id into kiev_id from flow.calendar_timezones where sys_name = kiev for update;
    select id into kyiv_id from flow.calendar_timezones where sys_name = kyiv;

    -- 3a. only Kyiv, or already migrated: nothing to re-point
    if kiev_id is null then
        return;
    end if;

    -- 3b. only Kiev: rename the row in place, its id and every reference stay
    if kyiv_id is null then
        update contacts.contact_timezone
        set zone_name = replace(zone_name, kiev, kyiv)
        where timezone_id = kiev_id;

        update flow.calendar_timezones
        set sys_name = kyiv,
            name = replace(name, kiev, kyiv)
        where id = kiev_id;

        return;
    end if;

    -- 3c. both exist: re-point every reference to Kyiv, then drop the Kiev row

    -- locations, calendars, domains, triggers
    update flow.region set timezone_id = kyiv_id where timezone_id = kiev_id;
    update flow.calendar set timezone_id = kyiv_id where timezone_id = kiev_id;
    update directory.wbt_domain set timezone_id = kyiv_id where timezone_id = kiev_id;
    update call_center.cc_trigger set timezone_id = kyiv_id where timezone_id = kiev_id;

    -- contacts: (contact_id, timezone_id) is unique, so a contact holding both zones cannot be re-pointed
    -- remember the contacts whose Kiev row is the primary one and who also have a Kyiv row
    select array_agg(k.contact_id)
    into promote
    from contacts.contact_timezone k
             join contacts.contact_timezone y on y.contact_id = k.contact_id and y.timezone_id = kyiv_id
    where k.timezone_id = kiev_id
      and k."primary";

    -- drop the Kiev row of every contact that already has a Kyiv row
    delete
    from contacts.contact_timezone k
    where k.timezone_id = kiev_id
      and exists(select 1
                 from contacts.contact_timezone y
                 where y.contact_id = k.contact_id
                   and y.timezone_id = kyiv_id);

    -- the kept Kyiv row inherits "primary" from the dropped Kiev row
    update contacts.contact_timezone
    set "primary" = true
    where timezone_id = kyiv_id
      and contact_id = any (promote);

    -- contacts that had only Kiev: re-point and fix the stored name
    update contacts.contact_timezone
    set timezone_id = kyiv_id,
        zone_name = replace(zone_name, kiev, kyiv)
    where timezone_id = kiev_id;

    -- queue members: the big table, last
    update call_center.cc_member set timezone_id = kyiv_id where timezone_id = kiev_id;

    -- nothing references Kiev any more
    delete from flow.calendar_timezones where id = kiev_id;
end
$$;
