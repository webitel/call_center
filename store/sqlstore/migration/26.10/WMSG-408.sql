create or replace function call_center.cc_distribute_im_to_agent(_node_name character varying, _queue_id bigint, _agent_id integer, _thread_id character varying, destination_ jsonb, variables_ jsonb, bucket_id_ integer) returns record
    language plpgsql
as
$$
declare
    _domain_id int8;
    _queue_updated_at int8;
    _team_updated_at int8;
    _agent_updated_at int8;
    _team_id_ int;
    _q_type smallint;
    _qparams jsonb;
    _attempt record;
BEGIN
    select q.domain_id,
           q.updated_at,
           q.type,
           call_center.cc_queue_params(q)
    from call_center.cc_queue q
    where q.id = _queue_id
    into _domain_id, _queue_updated_at, _q_type, _qparams;

    if not _q_type = 9 then
        raise exception 'queue type not inbound IM';
    end if;

    select a.team_id,
           t.updated_at,
           (a.updated_at - extract(epoch from u.updated_at))::int8
    from call_center.cc_agent a
        inner join call_center.cc_team t on t.id = a.team_id
        inner join directory.wbt_user u on u.id = a.user_id
    where a.id = _agent_id
      and a.domain_id = _domain_id
      and a.status = 'online'
    for update of a
    into _team_id_, _team_updated_at, _agent_updated_at;

    if _team_id_ isnull then
        raise exception 'agent [%] not found or offline', _agent_id;
    end if;

    insert into call_center.cc_member_attempt (domain_id, channel, state, queue_id, member_id, bucket_id, member_call_id,
                                               destination, node_id, agent_id, team_id, queue_params, queue_type)
    values (_domain_id, 'im', 'waiting', _queue_id, null, bucket_id_, _thread_id::varchar,
            destination_, _node_name, _agent_id, _team_id_, _qparams, 6)
    returning * into _attempt;

    return row(
        _attempt.id::int8,
        _attempt.queue_id::int,
        _queue_updated_at::int8,
        _attempt.destination::jsonb,
        coalesce((variables_::jsonb), '{}'::jsonb),
        (destination_->>'destination')::varchar,
        _team_updated_at::int8,

        _thread_id::varchar,
        call_center.cc_view_timestamp(now())::int8,
        _attempt.list_communication_id::int8,
        _agent_updated_at::int8
    );
END;
$$;
