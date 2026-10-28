# Email shared-distributor SQL contract

EM-23 extends the C interface of `cc_sql` 1.5. Apply the matching shared
prerequisites before lifecycle, as described in the [upgrade runbook](email-routing-upgrade.md).

## C selection

```sql
call_center.cc_sys_distribute_email(
    _queue_ids integer[], _queue_limits integer[],
    _skip_attempt_ids bigint[] DEFAULT '{}'::bigint[],
    _failed_attempt_ids bigint[] DEFAULT '{}'::bigint[],
    _failed_agent_ids integer[] DEFAULT '{}'::integer[]
) RETURNS TABLE (
    agent_id integer, queue_id integer, bucket_id integer, ins boolean,
    id bigint, resource_id integer, resource_group_id integer, comm_idx integer
)
```

One extension-owned function, VOLATILE, CALLED ON NULL INPUT, PARALLEL UNSAFE.
Calls with two/three arguments resolve through defaults. Arrays are non-NULL,
one-dimensional (or empty), without NULL elements. IDs and limits are positive;
queue IDs are unique. Queue/limit and failed-attempt/agent arrays must have
matching lengths. Invalid input raises `22023`; empty queues return no rows.

C uses the shared distributor with private Email reservations and selects pairs
without writing assignments. Per call, an agent and a letter appear at most
once and queue limits are respected. Resource/bucket/communication fields are
NULL and `ins` is false. Generic distribution does not select Email.

Queue order: priority descending, oldest currently assignable letter, queue ID
(within a domain). Within a queue, agents follow their Team Strategy and letters
follow waiting seconds + effective priority, then `joined_at` and ID. Sticky
restricts the recipient without adding precedence. Base is used first; Extra
requires the letter's permission. Queue FIFO/LIFO/Strict FIFO do not apply.

## Pair eligibility

```sql
call_center.cc_email_pair_available(
    _attempt call_center.cc_member_attempt, _agent_id integer, _candidate_id integer,
    _failed_attempt_ids bigint[], _failed_agent_ids integer[]
) RETURNS boolean
```

Lifecycle replaces the basic shared-preparation predicate under the same signature. Effective
Sticky must allow the agent and the pair must not have failed in this cycle.
The last released agent is eligible only when no other eligible, not-failed pair
remains. Queue age, letter selection and locked assignment use this predicate;
C does not read lifecycle columns.

## Applying a pair

```sql
call_center.cc_email_try_assign(
    _attempt_id bigint, _queue_id integer, _agent_id integer,
    _failed_attempt_ids bigint[] DEFAULT '{}'::bigint[],
    _failed_agent_ids integer[] DEFAULT '{}'::integer[]
) RETURNS boolean

call_center.cc_email_apply_distributed(
    _attempt_id bigint, _queue_id integer, _agent_id integer,
    _failed_attempt_ids bigint[] DEFAULT '{}'::bigint[],
    _failed_agent_ids integer[] DEFAULT '{}'::integer[]
) RETURNS TABLE (result text, queue_id integer, attempt_id bigint, agent_id integer)
```

Each function has one signature; defaults preserve three-argument calls.
Invalid IDs/failed-pair arrays raise `22023`. Apply takes the Email advisory lock
`(1162690889, 1)` without waiting, assigns through try_assign and refreshes metrics
on success. Assignment rechecks eligibility/capacity under queue/calendar,
agent, Email-channel and attempt locks, writes version/deadline/snapshot and
clears `last_released_agent_id` only on success. Errors roll back the transaction.

| Apply outcome | Row |
|---|---|
| Email lock held by another transaction | `busy`, IDs NULL |
| Assigned | `assigned`, queue/attempt/agent IDs |
| Rejected | `no_agent`, queue/attempt IDs, agent NULL |

## Cycle and metrics

`cc_email_distribute(integer, interval)` keeps its four result columns and a
separate transaction. It returns calendar/configuration results and
`payload_invalid`, prepares Sticky with a bounded maintenance cursor, selects
through C and applies pairs under locks. Rejected pairs are excluded only for
this cycle; vanished rows or repeated Sticky mutations skip the letter. Progress
is an assignment, a new pair or a new skip; the cycle stops when no work/progress
remains or its time budget ends. Only successful assignments consume queue limits.

`cc_email_agent_strategy_refresh(integer, timestamptz DEFAULT NULL)` runs after
slot transitions under agent → Email channel → attempt locks. Take passes its
`bridged_at`; other transitions refresh idle state. Replays/no-ops do not move
metrics. Postpone frees the slot, processing keeps it. Version/outbox and the
original `joined_at` are preserved. High is read from `cc_email_high_priority()`.
