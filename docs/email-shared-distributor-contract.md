# Email shared-distributor SQL contract

Interfaces between `cc_sql` 1.5 and the Email cycle of `call_center`. The
upgrade order is in the `call_center` runbook `docs/email-routing-upgrade.md`.
A byte-identical copy of this file is kept in the extension repository as
`webitel/email-shared-distributor-contract.md`.

## C selection: `cc_sys_distribute_email`

```sql
call_center.cc_sys_distribute_email(
    _queue_ids integer[],
    _queue_limits integer[],
    _skip_attempt_ids bigint[] DEFAULT '{}'::bigint[]
) RETURNS TABLE (
    agent_id integer, queue_id integer, bucket_id integer, ins boolean,
    id bigint, resource_id integer, resource_group_id integer, comm_idx integer
)
```

The function belongs to the extension (`cc_sql--1.4--1.5.sql`): VOLATILE,
CALLED ON NULL INPUT, PARALLEL UNSAFE. It is not STRICT, so NULL arrays reach
validation. Application SQL must not redeclare it.

**Input.** `_queue_ids` and `_queue_limits` are aligned one-dimensional arrays
of positive values without NULLs; queue IDs are unique. `_skip_attempt_ids`
contains positive attempt IDs. Invalid input raises SQLSTATE `22023`. An empty
queue list returns no rows. Array order does not affect the result.

**Queues.** Requested queues are rechecked against
`cc_email_distribute_stage_1.can_distribute`. They are ordered by domain, queue
priority descending, the `joined_at` of the oldest currently assignable letter,
then queue ID. A letter is assignable when it is `waiting`, unassigned, not
skipped and its effective Sticky route has an eligible agent with a permitted
slot for this letter. A queue without such a letter takes no part in the call.
`cqs.lvl`, Queue FIFO/LIFO/Strict FIFO and `manual_distribution` do not apply.

**Agents.** Candidates come from `cc_email_queue_candidates`: `online`, Email
channel online, `email` in `allow_channels`, the queue team if set, a matching
enabled skill allowed by the online preset (or no preset). Web presence is not
required. Within a queue agents are ordered by their own Team Strategy, then
Email `last_offering_at` (NULL first), then agent ID.

| Stored Strategy | Email input |
|---|---|
| `round-robin`, `top-down`, `fewest-calls`, NULL, unknown | Email `last_offering_at` (common default branch) |
| `random` | Common random rank |
| `skill-capacity` | Maximum capacity of matching enabled queue skills allowed by the preset |
| `least-talk-time` | Email `last_bridged_at`, set on Take |
| `longest-idle-agent`, `longest-idle-time` | Common idle expression; `longest-idle-time` is an Email-only alias |
| `round-robin-bucket` | Common `cc_round_robin_bucket` without buckets: equal rank, then `last_offering_at` |

**Letter.** The selected agent gets one waiting, unassigned letter of the queue
whose effective Sticky route has no candidate or this agent. With a free base
slot any letter qualifies; otherwise only a letter with Extra permission and a
free Extra slot. Order: waiting seconds plus effective priority descending
(numeric, no int32 overflow), then `joined_at`, then attempt ID. A Sticky letter
gets no extra precedence. A miss does not reserve the agent.

**Output.** The common eight-column layout. For Email `ins` is false and the
bucket/resource/group/communication columns are NULL. Within one call an agent
and an attempt appear at most once and queue counts never exceed their limits;
reservations are private to the call. The call writes nothing.

The generic `cc_sys_distribute(boolean)` never selects type 11. Its channel
aggregate excludes the Email channel row from `all_offr`,
`active_other_channels`, `max_timeout` and `out_call_task`.

## Strategy metrics

- Zero occupied Email slots map to the idle state `waiting`, otherwise `active`.
  Idle time is counted from `greatest(email_idle_since, joined_at)` of the Email
  channel row. `email_idle_since` is nullable and has no backfill.
- `cc_email_agent_strategy_refresh(agent_id, taken_at DEFAULT NULL)` clears
  `email_idle_since` while slots are occupied and sets it once when they become
  free. A non-NULL `taken_at` advances `last_bridged_at`. The caller holds the
  agent and Email channel locks; only the agent's Email row changes.

## Applying a pair: `cc_email_apply_distributed`

```sql
call_center.cc_email_apply_distributed(_attempt_id bigint, _queue_id integer, _agent_id integer)
    RETURNS TABLE (result text, queue_id integer, attempt_id bigint, agent_id integer)
```

NULL or nonpositive IDs raise `22023`. The function takes the Email advisory lock
`(1162690889, 1)` without waiting and assigns only through `cc_email_try_assign`.

| Condition | Row |
|---|---|
| Another Email cycle holds the lock | `busy`, IDs NULL |
| `cc_email_try_assign` returns true | `assigned` with queue, attempt and agent IDs; metrics refreshed in the same transaction |
| `cc_email_try_assign` returns false | `no_agent` with queue and attempt IDs, agent NULL |

Lock and query errors propagate and roll back the cycle. A repeated call cannot
overwrite an assigned attempt.

## Cycle: `cc_email_distribute(_queue_batch integer, _max_duration interval)`

The result columns `result, queue_id, attempt_id, agent_id` and the Go caller
(separate transaction, transaction-local timeouts, `SummarizeEmailCycle`) are
unchanged.

1. Validate the arguments, take `(1162690889, 1)`; if busy, return `busy`.
2. Return every non-NULL stage-1 result (`calendar_*`, `no_skills`, `no_agent`)
   with its queue ID.
3. Sticky maintenance: queues with `can_prepare_sticky`, from the `last_queue_id`
   cursor, within a quarter of the budget, at most `min(queue_batch, 128)` rows
   per queue.
4. Selection round: call C with the eligible queues, their remaining limits
   (`queue_batch` minus successful assignments in this cycle) and the cycle
   skips. A malformed C row raises an error. For a letter with a Sticky
   candidate, prepare it under lock; if its candidate, deadline or weight
   changed, drop the rest of the batch and call C again (once per attempt).
5. Apply each pair. `assigned` counts towards the queue limit; `no_agent` adds
   the attempt to the cycle skips. An empty C result returns `no_agent` for its
   queues and ends the cycle.
6. Repeat rounds while there is progress (an assignment or a new skip) and time
   remains; return `time_limit` when the budget ends. Update `last_queue_id`.

## Obligations of the EM-23/EM-24 adaptation

- `cc_email_try_assign` keeps its signature; EM-23 adds version, deadlines and
  the snapshot inside it.
- Call the metric refresh on Take (with `taken_at`) and on every slot transition:
  Postpone, Resume, wake-up, Return, auto-release, completion, processing
  timeout, logout. Replays do not move the timestamps.
- The EM-23 capacity helper keeps excluding `postponed`.
- Apply `last_released_agent_id` consistently to queue age, letter and recipient.
- Restore the `payload_invalid` diagnostic.
- EM-24: the new priority range in `cc_email_join_to_queue`, in
  `email_event_route_params_valid` and in the Flow stored-route replay.
