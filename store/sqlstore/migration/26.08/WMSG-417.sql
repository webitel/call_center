create table if not exists call_center.cc_team_chat_tag (
    id serial primary key,
    team_id int8 not null references call_center.cc_team(id) on delete cascade,
    tag varchar(64) not null,
    created_by int8,
    created_at timestamptz not null default now(),
    updated_by int8,
    updated_at timestamptz,
    unique(team_id, tag)
);

create or replace view call_center.cc_team_chat_tag_list as
    select id, tag, team_id, created_by, created_at, updated_by, updated_at
    from call_center.cc_team_chat_tag;
