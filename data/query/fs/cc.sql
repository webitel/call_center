-- top-down

SELECT system,
       name,
       status,
       contact,
       no_answer_count,
       max_no_answer,
       reject_delay_time,
       busy_delay_time,
       no_answer_delay_time,
       tiers.state,
       agents.last_bridge_end,
       agents.wrap_up_time,
       agents.state,
       agents.ready_time,
       tiers.position           as tiers_position,
       tiers.level              as tiers_level,
       agents.type,
       agents.uuid,
       external_calls_count,
       agents.last_offered_call as agents_last_offered_call,
       1                        as dyn_order
FROM agents
       LEFT JOIN tiers ON (agents.name = tiers.agent)
WHERE tiers.queue = 'support@10.10.10.25'
  AND (agents.status = 'Available' OR agents.status = 'On Break' OR agents.status = 'Available (On Demand)')
  AND tiers.position > 0
  AND tiers.level = 0
UNION
SELECT system,
       name,
       status,
       contact,
       no_answer_count,
       max_no_answer,
       reject_delay_time,
       busy_delay_time,
       no_answer_delay_time,
       tiers.state,
       agents.last_bridge_end,
       agents.wrap_up_time,
       agents.state,
       agents.ready_time,
       tiers.position           as tiers_position,
       tiers.level              as tiers_level,
       agents.type,
       agents.uuid,
       external_calls_count,
       agents.last_offered_call as agents_last_offered_call,
       2                        as dyn_order
FROM agents
       LEFT JOIN tiers ON (agents.name = tiers.agent)
WHERE tiers.queue = 'support@10.10.10.25'
  AND (agents.status = 'Available' OR agents.status = 'On Break' OR agents.status = 'Available (On Demand)')
  AND tiers.level > 0
ORDER BY dyn_order asc, tiers_level, tiers_position, agents_last_offered_call



--round-robin
SELECT system,
       name,
       status,
       contact,
       no_answer_count,
       max_no_answer,
       reject_delay_time,
       busy_delay_time,
       no_answer_delay_time,
       tiers.state,
       agents.last_bridge_end,
       agents.wrap_up_time,
       agents.state,
       agents.ready_time,
       tiers.position           as tiers_position,
       tiers.level              as tiers_level,
       agents.type,
       agents.uuid,
       external_calls_count,
       agents.last_offered_call as agents_last_offered_call,
       1                        as dyn_order
FROM agents
       LEFT JOIN tiers ON (agents.name = tiers.agent)
WHERE tiers.queue = 'support@10.10.10.25'
  AND (agents.status = 'Available' OR agents.status = 'On Break' OR agents.status = 'Available (On Demand)')
  AND tiers.position > (SELECT tiers.position
                        FROM agents
                               LEFT JOIN tiers ON (agents.name = tiers.agent)
                        WHERE tiers.queue = 'support@10.10.10.25'
                          AND agents.last_offered_call > 0
                        ORDER BY agents.last_offered_call DESC
                        LIMIT 1)
  AND tiers.level = (SELECT tiers.level
                     FROM agents
                            LEFT JOIN tiers ON (agents.name = tiers.agent)
                     WHERE tiers.queue = 'support@10.10.10.25'
                       AND agents.last_offered_call > 0
                     ORDER BY agents.last_offered_call DESC
                     LIMIT 1)
UNION
SELECT system,
       name,
       status,
       contact,
       no_answer_count,
       max_no_answer,
       reject_delay_time,
       busy_delay_time,
       no_answer_delay_time,
       tiers.state,
       agents.last_bridge_end,
       agents.wrap_up_time,
       agents.state,
       agents.ready_time,
       tiers.position           as tiers_position,
       tiers.level              as tiers_level,
       agents.type,
       agents.uuid,
       external_calls_count,
       agents.last_offered_call as agents_last_offered_call,
       2                        as dyn_order
FROM agents
       LEFT JOIN tiers ON (agents.name = tiers.agent)
WHERE tiers.queue = 'support@10.10.10.25'
  AND (agents.status = 'Available' OR agents.status = 'On Break' OR agents.status = 'Available (On Demand)')
ORDER BY dyn_order asc, tiers_level, tiers_position, agents_last_offered_call



