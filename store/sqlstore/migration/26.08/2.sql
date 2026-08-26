create or replace function "call_center"."cc_attempt_cancel_release_agent"(
    p_attempt_id int8,
    p_agent_hold_sec int8
)
returns table (
    last_state_change timestamp with time zone,
    no_answers int4
)
language sql
volatile
as $$
with updated_attempt as (
    update "call_center"."cc_member_attempt"
    set leaving_at = now(),
        last_state_change = now(),
        result = case when offering_at is null and resource_id is not null then 'failed' else 'abandoned' end,
        state = 'leaving'
    where id = p_attempt_id
    returning last_state_change, agent_id, channel
),
updated_agent as (
    update call_center.cc_agent_channel c
    set state = 'waiting',
        joined_at = ua.last_state_change,
        timeout = null,
        attempt_id = null,
        queue_id = null
    from updated_attempt ua
    where c.agent_id = ua.agent_id
      and c.channel = ua.channel
      and ua.agent_id is not null
    returning c.no_answers
)
select
    ua.last_state_change,
    ag.no_answers
from updated_attempt ua
left join updated_agent ag on true;
$$;
