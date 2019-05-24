SELECT id, 'name', md5(random()::text), 'name2'
      ,md5(random()::text),md5(random()::text)
      ,NOW() - '1 day'::INTERVAL * (RANDOM()::int * 100)
      ,NOW() - '1 day'::INTERVAL * (RANDOM()::int * 100 + 100)
FROM generate_series(1,100) id;



select sum(r.id) from  (
                select log(id) as id
                from generate_series(1, 10000000) id
              ) as r;

select *
from calendar;

--agents

--calendar
insert into cc_agent(name)
SELECT md5(random()::TEXT)::varchar(20)
FROM generate_series(1,1000) id;


select *
from cc_agent;


--calendar
insert into calendar(timezone, name)
SELECT 'Europe/Kiev', md5(random()::TEXT)::varchar(20)
FROM generate_series(1,100) id;

insert into calendar_accept_of_day (calendar_id, week_day)
select c.id, a.c
from calendar c
left join (
            SELECT id as c
FROM generate_series(1,7) id
            ) as a on true;
;

--queue
insert into cc_queue (type, strategy, enabled, calendar_id, priority)
select 1, md5(random()::TEXT)::varchar(5), true, id,  (RANDOM()::float * 100)::int
from calendar;

--cc_member

insert into cc_member (queue_id, priority)
SELECT 1, (RANDOM()::float * 100)::int
FROM generate_series(1,50000) id;

insert into cc_member_communications (member_id, number, priority)
select m.id, md5(random()::TEXT)::varchar(10), (RANDOM()::float * 100)::int
from cc_member m
left join (
            SELECT (RANDOM()::float * 100)::int as p, md5(random()::TEXT)::varchar(10) as n
FROM generate_series(1, 3) id
            ) as a on true
where m.id > 10;



insert into cc_list_communications (list_id, number)
SELECT 1, md5(random()::TEXT)::varchar(25)
FROM generate_series(1,1000000)
on conflict do nothing ;


SELECT floor(random() * (2-5+1) + 5)::int;

explain analyse
select *
from cc_list_communications
where list_id = 1 and number = 'dsadsada';