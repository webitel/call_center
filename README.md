# call_center

### Shared Email distributor

Email assignment uses the shared C algorithm of `cc_sql` 1.5 through a separate
Email entry, `cc_sys_distribute_email`, in its own transaction. Generic
`cc_distribute` does not select Email and shares no reservations with it. The
public `cc_email_distribute(integer, interval)` signature and four result columns
remain compatible; see [How emails are assigned](#how-emails-are-assigned) and the
[SQL contract](docs/email-shared-distributor-contract.md).

Apply shared prepare/validate/runtime and lifecycle from this release before
`email_status_sync.sql` and the Inbox route migration. Follow the
[EM-24 runbook](docs/email-routing-upgrade.md#em-24-status-sync-upgrade).
Status sync keeps the shared selection and metric hooks, adds the Thread lock,
fallback and snapshot publisher. Clean schema contains the final EM-24 objects.

Priority is a nonnegative int32; High is temporarily 10 until the business value
is set. Internal and external state stays `waiting`. Generic SQL keeps the
release definitions; the generic C aggregate no longer counts Email towards the
busy state of other channels. `Intercept` does not touch Email attempts.

EM-23 and EM-24 use the same five-array C entry. Apply/try_assign each have one
signature with default empty failed-pair arrays. EM-24 keeps the first durable
route intent, including priority, Sticky agent, Extra permission and initial From.
Keep distribution and lifecycle flags off
until the complete compatible release passes its verification.

### Rollout prerequisites

Default priority remains 0; boosts never lower a larger Flow priority. Granted
Extra permission and the no-implicit-Sticky-history rule remain unchanged.
Resume/direct transfer use of Extra remains the existing technical policy.
Existing priority 100 may come from Flow and must not be bulk-rewritten.

The clean schema retains the known legacy Online login/preset discrepancy.
Resolve it separately before clean rollout; do not apply unrelated generic
migrations as an Email fix. Historical allocator checks do not verify the final
five-array C interface, restart, concurrency or performance. Keep production
Email flags off until the matching release passes those checks.

`EmailJoinToQueue` accepts `priority` (0–2147483647, default 0), `sticky_agent_id`
(default 0: no candidate), `extra_email_count` (per-letter permission, default
false) and `from_address` (initial inbound From). Negative priority is
rejected before writes with gRPC `InvalidArgument` and stable ID
`store.sql_member.email_join.invalid_priority`. The
`int32` field bounds the upper end. Apply the SQL preparation before deploying
the updated service, then deploy Flow; an older SQL function still rejects
priority above 100.
Negative `sticky_agent_id` returns `InvalidArgument` with the existing generic
ID `store.sql_member.email_join.invalid` (`EmailJoinInvalidArguments`), also
used by the SQL-store mapping for invalid arguments; no new error ID is added.
The address is trimmed and lowercased, and an unusable address produces no
`destination.number` lookup key. The Thread ID remains in `destination.thread_id`.

`cc_email_join` stores the initial routing parameters and result. A valid replay,
even with changed routing parameters or a now-unavailable agent, returns the
stored result without updating the attempt. Reusing an event for another domain
or Thread is still an error. A different event for an already active Thread
returns that attempt without changing its routing. Sticky candidates must match
the domain, team, enabled skills and allowed Email channel; limits and online
presence are separate allocator checks, not permanent eligibility conditions.

Agent `email_count` defaults to 1 for new database records; existing values are
preserved. `extra_email_count` defaults to 0. Both are nonnegative `smallint`
limits. Attempts separately store `email_extra_allowed` and nullable
`email_slot_type` (`base`/`extra`); an unassigned waiting attempt occupies no slot.
`SaveToHistory` preserves `destination`, including `destination.number`, using
its unchanged column mapping. Extra permission and slot type remain only on
current attempts; they are not added to history.

See [the upgrade runbook](docs/email-routing-upgrade.md) before applying the
updated schema. Do not rerun only the original EM-21 migrations after this update.

L4 follow-up: the full schema includes the two Email address indexes
`cc_member_attempt_email_number_idx` and `cc_member_attempt_history_email_number_idx`.
Existing installations apply `26.dev/email_last_bridged_indexes.sql` with psql
outside a transaction after routing update/validation. It uses concurrent build
and recovery of interrupted invalid indexes; see the runbook for precautions.
Only L4 is included: no Extra-head index (L1) or head cache (P1-1).
The index definitions have prior cloud-test evidence; this local follow-up and
its recovery script have not been rerun, as requested. Earlier local catalog
parity results describe the snapshot before these two indexes, not this revision.

## Inbound Email distribution

An Inbound Email Queue (queue type 11) receives email-service Threads through
`EmailJoinToQueue`, called by the `joinQueue` application of `flow_manager`. The
call creates a new `waiting` Email attempt (`channel = 'email'`) or returns the
existing active attempt of the Thread, which may already be assigned, and
returns immediately. Agents are assigned later and asynchronously by the Email
shared C algorithm through a separate Email transaction.
`call_center` then keeps the lifecycle of the attempt until it leaves to
`cc_member_attempt_history`.

### How emails are assigned

Every instance runs the Email poller when `email_distribution` is enabled. Each
cycle calls `call_center.cc_email_distribute` in one short transaction; the
transaction advisory lock lets one instance work, while others return `busy`.
Go supplies lock/statement timeouts and a work budget equal to half the statement
timeout. Disabling Email polling leaves the generic engine unchanged.

Stage 1 reports calendar/configuration outcomes independently of the maintenance
cursor. Sticky upkeep visits queues with `can_prepare_sticky`, including
`no_agent`, using a soft quarter-budget threshold and at most
`min(email_distribution_queue_batch, 128)` actionable updates per visited queue.
A single SQL operation may exceed that threshold; the outer statement timeout
remains authoritative. Upkeep may take several cycles.

The LOGGED `cc_email_distribution_cursor` retains only the last maintenance
queue ID (and singleton key). Its position survives call_center restart and is
updated once with the transaction, including a softly stopped cycle. It neither
orders assignments nor stores operators, attempts or slots. The runtime migration
removes the old head function and agent cursor after replacing their caller;
clean schema omits both. PostgreSQL crash/failover durability of the UNLOGGED
attempt table is unchanged.

`cc_sys_distribute_email` chooses pairs with private per-call reservations.
Queue order is domain, queue priority descending, the oldest currently
assignable waiting letter, then queue ID. Effective Sticky, per-letter slot
permission and cycle skips determine whether a letter may contribute to queue
age. Blocked Sticky does not gain queue precedence through age alone. Team
Strategy orders eligible agents; their letter is selected by waiting seconds
from persisted `joined_at` plus effective priority, then `joined_at`/attempt ID.
The score uses numeric arithmetic. Queue FIFO/LIFO/Strict FIFO do not apply.

The SQL wrapper validates C rows and prepares selected Sticky attempts under
the existing helper's locks. A routing-field change discards the remainder of
that C batch and triggers bounded reselection; the helper's boolean is not a
mutation flag. Only `cc_email_apply_distributed`/`cc_email_try_assign` can apply
the selected pair, with authoritative eligibility/capacity checks and metric
refresh in the same transaction. C selection itself does not occupy a slot.

`email_distribution_queue_batch` caps successful assignments from each queue
across the whole cycle. Failed applications add cycle-local attempt/agent pairs;
other agents may still take the letter, with the last released agent as fallback.
Vanished rows or repeated Sticky changes skip the attempt for that cycle. Failures
do not consume the queue limit. Further C calls permit an agent to fill
several allowed slots. New assignments, skips or failed pairs permit another round; empty
selection, no progress or exhausted time stops. Failed cycles roll back and
back off; `busy` and a soft `time_limit` are not failures. The poller keeps no
local attempt state, and call_center restart does not reset persisted waiting,
ownership, slots or Sticky deadlines.

Candidate/capacity calls, effective Sticky and the assignable-age query can
still scan substantial backlogs. Bounded outputs do not establish bounded work
or full fairness. EXPLAIN/load/concurrency checks remain step-6 rollout gates.

A queue assigns only while its calendar is open. Missing/invalid calendars or
no enabled skills keep letters waiting and produce configuration diagnostics.
Queue priority remains ahead of age; the shared score applies within the
selected agent's eligible letters, without a Sticky-first boost.

An agent can take an email of the queue when the agent is:

- `online` with the `email` channel online, and `email` is in `allow_channels`;
- in the queue team, if the queue has one;
- holding a matching enabled skill within the capacity range of the queue, also
  allowed by the online skill preset of the agent, if any;
- below the base limit `email_count`, or below `extra_email_count` when that
  letter has `email_extra_allowed`. A zero base limit does not disable Extra.
  Offered, active and post-processing emails count; postponed emails do not.

Base and Extra use separate counts of unfinished assigned Email attempts across
all queues. Each new assignment chooses base first, otherwise permitted Extra;
freeing a base slot never promotes an already assigned Extra email. Both limits
may be lowered without releasing existing assignments. An unclassified active
assignment makes new capacity checks fail closed rather than disappearing from
the count.

With `payload.email_auto_release_sec` of the queue above `0`, the offer gets a
deadline, read at assignment, so a later change of the queue applies to new
offers only. An email whose offer expired goes first to another agent and back
to the same one only when no other agent can take it.

Among eligible agents the configured Team Strategy applies, followed by Email
`last_offering_at` (NULL first) and agent ID. Unknown Strategy names use the
shared C default (`last_offering_at`); Email also accepts `longest-idle-time`.
Take records `last_bridged_at`, and slot transitions refresh idle metrics in the
same transaction. Assignment locks the agent before
its Email channel, retains a matching skill pair/online preset, and rechecks
presence and per-letter capacity. One conditional update sets `offering`, agent,
team and `email_slot_type`; only a successful update changes channel
`last_offering_at`. Channel `state` and `attempt_id` do not change. A failed
assignment does not mark the agent unusable for later Extra-enabled letters.

The queue view's Email `free` counter reflects potential base or Extra capacity,
not a guarantee that a particular letter may use Extra. The allocator checks
the actual letter permission and does not use that counter as authority.

Sticky requires queue `sticky_agent` and an explicit eligible candidate from
JoinQueue. No candidate means general routing: neither JoinQueue nor the
allocator searches Thread history, and `email_sticky_history_sec` no longer
controls that lookup. Flow's Email `lastBridged` supplies the candidate separately.

Permanent eligibility is domain/team/allowed Email/enabled skills, without a
numeric limit or online-state predicate. No configured slot type for this letter
(zero base and either no Extra permission or zero Extra limit) cancels Sticky
immediately without raising priority. A permanently ineligible candidate also
falls back without a new priority increase.

For an eligible candidate with a configured slot type, R1–R8 apply:

- Sticky disabled or no candidate: general routing, unchanged priority (R1/R2).
- Online with online Email channel and a permitted free slot: assign (R3/R6).
- Online but all permitted slots occupied: wait until timeout (R4/R7).
- Unavailable and `payload.sticky_ignore_status` absent/false: immediately fall
  back with `greatest(priority, 10)` (R5). This changes original EM-21, which
  also waited for offline candidates by default.
- Unavailable and `payload.sticky_ignore_status = true`: wait for online state
  and capacity until timeout (R8). Timeout falls back with `greatest(priority, 10)`.

R3/R6 identify the permitted Sticky recipient, not a scheduling override.
Sticky competes with that candidate's other eligible letters by waiting seconds
plus effective priority, with joined_at/ID ties.
Higher-priority general work can go first, so Sticky may time out even if its
candidate was previously online with a free slot. Serving Sticky ahead of higher
priority would require a separate business decision; no such boost is applied.

Waiting keeps the Flow priority and occupies no slot. `sticky_until` starts once
in an open calendar, using `payload.sticky_agent_sec` (default 30 seconds).
All Email routing helpers read it through `cc_email_sticky_wait_sec`: a JSON
number with an integral value in the signed-int32 range is accepted; positive
values are used as seconds, and zero/negative values normalize to 0 (no wait).
Missing/null keys, other JSON types, fractional values and values outside
-2147483648–2147483647 fall back to 30 seconds without failing the cycle.
Explicit zero/valid negative seconds allow only an immediate available-candidate
opportunity, not continued capacity waiting; an unsuccessful opportunity falls
back on the next upkeep pass. Restart never extends a recorded deadline, and
calendar closure does not pause it. No assignments happen outside the calendar;
expiry is resolved when the queue next opens. Fallback never restarts candidate
lookup, and the former candidate may still win normal routing later.

### Email attempt lifecycle

| State | Agent | Slot | Leaves by |
|---|---|---|---|
| `waiting` | none | no | assignment |
| `offering` | assigned | yes | Take, Return, auto-release, logout |
| `active` | assigned | yes | Postpone, Complete, Return, logout |
| `postponed` | kept | no | Resume, wake-up, deadline, Return, logout |
| `processing` | kept | yes | Complete, new email, deadline |
| `leaving` | kept | no | moved to history by `SaveToHistory` |

Every return to the queue (Return, auto-release, logout or auto-offline, a
wake-up or deadline without a slot) keeps the attempt and its `joined_at`, so
waiting time and SLA do not restart, makes it High (`greatest(priority, 10)`) and drops
its agent. Its sticky decision is already made. Only a postponed email that
cannot go back to its agent keeps it as Sticky candidate, by the rules above:
the queue is sticky, the agent is eligible, has a slot type for the email and
is online or `sticky_ignore_status` is set. The email is High in either case;
the Sticky timer starts once in an open calendar.

Agents and Flows change an attempt through `cc.MemberService`:

- `EmailAttemptTake` — `offering` to `active`;
- `EmailAttemptPostpone` — `active` to `postponed` until `postponed_until`
  (Unix ms) or for `postpone_for_sec`, at most `payload.email_postpone_max_sec`
  ahead (30 days by default) and within `email_postponed_count` of the agent
  (unset means no limit, `0` disables postponing);
- `ResumeAttempt` with the Email fields — `postponed` to `active` when the agent
  and its `email` channel are online, it may take emails of the queue as for
  the allocator (skills of its online preset included) and has a free slot (base
  first, Extra only with the email's Extra permission); otherwise nothing
  changes;
- `EmailAttemptReturn` — `offering`, `active` or `postponed` back to the queue;
- `EmailAttemptComplete` — `active` to `processing` when the queue has
  `processing` (deadline `processing_sec`), otherwise to `leaving` with result
  `processed`; `processing` to `leaving` with `processed`;
- `AttemptRenewalResult` with the Email fields — extends the `processing`
  deadline, within the prolongations of the queue.

An agent sends `attempt_id`, `agent_id`, `expected_version` and `command_id`; a
Flow sends `email_event_id` only (Postpone and Resume), and `call_center` finds
the attempt of the Thread. `call_center` tells the form by the fields, keys a
Flow command by `<email_event_id>:<operation>` and refuses mixed forms. A
command applies only to the current `version`; a repeated `command_id` returns
the first response with `replayed`, the same id with other arguments is a
conflict. A transition takes the agent, its `email` channel and the attempt in
this order when it may take a slot, so slots and the postponed limit are never
exceeded.

Every transition writes the full attempt to `cc_email_attempt_outbox` in its
transaction; `sequence` is the `projection_version` of the Thread. The publisher
sends the rows to email-service (see below).

| Error id | gRPC code |
|---|---|
| `cc.email_attempt.invalid_argument` | `InvalidArgument` |
| `cc.email_attempt.not_found` | `NotFound` |
| `cc.email_attempt.wakeup_required`, `owner_mismatch`, `invalid_state`, `agent_offline`, `agent_ineligible` | `FailedPrecondition` |
| `cc.email_attempt.version_conflict`, `serialization_conflict`, `deadlock` | `Aborted` |
| `cc.email_attempt.command_id_conflict`, `cc.email_wakeup.event_conflict` | `AlreadyExists` |
| `cc.email_attempt.slot_exhausted`, `postponed_limit_exhausted`, `prolongation_exhausted` | `ResourceExhausted` |
| `cc.email_attempt.lock_timeout`, `unavailable` | `Unavailable` |
| `cc.email_attempt.app_error` | `Internal` |

Command, wake-up and join locks wait at most `email_command_lock_timeout`.

### Snapshots for email-service

email-service keeps the status, queue, agent and `postponed_until` of a Thread
as a projection of these rows. The publisher sends every row of
`cc_email_attempt_outbox` as a `cc.email.attempt.snapshot` event to the
`cc.email.events` exchange with the routing key `cc.email.attempt.snapshot.v1`;
the contract and the topology are described in `docs/events.md` of
webitel-emails. A wake-up that finds no active attempt writes the
`inbound_reopened` marker, a row without an attempt.

The publisher runs on every node when `email_attempt_publisher` is on, which is
off by default. A node claims ready rows with a lease, publishes them outside
the transaction with persistent messages, `mandatory` and broker confirms, and
marks them published only after the confirm. A broker or topology failure
gives the claimed rows back without spending attempts and pauses the
publisher. A row may be sent twice; email-service ignores a snapshot that is
not newer than its projection, so publishing order does not matter.

Published rows without `command_id` are deleted after
`email_attempt_outbox_retention`. Rows of operator and Flow commands are kept,
since a repeated command returns their response; unpublished rows are never
deleted.

### Wake-up by a new email

`flow_manager` calls `EmailWakeUp` for every inbound email event before its
Flow, also without one. A `postponed` attempt of the Thread goes back to work
when the allocator could give it to its agent, with the slot chosen as on
Resume, otherwise to the queue (`woken` or `queued`); a `processing` one goes
back to `active` (`reopened`). Other states give `noop`, a Thread without an
attempt `not_active`. `cc_email_wakeup` keeps the result of every event and is
never cleaned, so a repeated event returns it and wakes nothing; an event of
another Thread is `cc.email_wakeup.event_conflict`. The Flow applications
`postpone` and `resume` work only after the wake-up of their event. `resume`
changes nothing when that wake-up left the attempt `active` and no `postpone` of
the event followed (`projection_version` 0); `cc_email_wakeup` keeps this
response, so a repeat returns it with `replayed`. If the attempt changed after
the wake-up before the first such `resume`, it is `invalid_state`.

For `not_active` the wake-up also returns `fallback_queue_id`, the queue of the
last finished Email attempt of the Thread, found among `leaving` attempts and in
`cc_member_attempt_history`, and writes the `inbound_reopened` marker that opens
the Thread as New in email-service. Both are kept with the result, so a repeated
event returns the same queue and writes no second marker. `call_center` does not
join the queue itself; `flow_manager` decides. The wake-up and `EmailJoinToQueue`
take one lock per Thread first, so a marker never follows the snapshot of an
attempt created at the same time.

### Deadlines, logout and auto-offline

With `email_lifecycle` enabled, every instance runs a watcher like the
allocator: one short transaction per cycle on database time, so a restart
changes no deadline. A cycle returns expired offers to the queue, moves expired
`processing` to `leaving` with result `processing_timeout` and wakes expired
postponed emails as a new email would, without `cc_email_wakeup`. It also
returns the emails of agents whose `status` is `offline` but still hold some,
for example when another path set the status. Each kind takes at most
`email_lifecycle_batch` rows, earliest first; a row locked by another
transaction waits for the next cycle, so several instances do not repeat a
transition.

Logout and auto-offline call `cc_agent_set_offline` instead of `SetStatus`.
When the status really changes to `offline`, the `offering`, `active` and
`postponed` emails of the agent go back to the queue in the same transaction;
`processing` stays until its result or deadline. An attempt in `wait_agent`
keeps the status and the emails, as before; this is logged with the outcome
`status_not_changed_wait_agent`, while the cache and the offline event of the
agent are still updated, as before. `pause` and `break_out` return nothing.

### Compatibility

Email attempts have no node, member, resource or `agent_call_id`, so
`GetTimeouts`, `CleanAttempts`, `GetChannelTimeout`, `RenewalProcessing` and
the reporting of other channels do not touch them, and `SaveToHistory` moves a
`leaving` Email attempt with the usual columns. `DistributeInfoByUserId` of
`engine` reports an agent holding an email as distributing, so a call with
`cancel_distribute` sends `CancelAgentDistribute`, which cancels call attempts
only. `cc_agent_set_channel_waiting` for `email` refuses while the agent holds
an unfinished email, as for other channels.

### Configuration

| Flag | Environment | Default | Meaning |
|---|---|---|---|
| `email_distribution` | `EMAIL_DISTRIBUTION` | `false` | Run isolated Email cycles using shared C selection |
| `email_distribution_interval` | `EMAIL_DISTRIBUTION_INTERVAL` | `1s` | Pause between cycles |
| `email_distribution_queue_batch` | `EMAIL_DISTRIBUTION_QUEUE_BATCH` | `50` | Assignments per queue in one cycle |
| `email_distribution_lock_timeout` | `EMAIL_DISTRIBUTION_LOCK_TIMEOUT` | `1s` | `lock_timeout` of a cycle |
| `email_distribution_statement_timeout` | `EMAIL_DISTRIBUTION_STATEMENT_TIMEOUT` | `10s` | `statement_timeout` of a cycle |
| `email_lifecycle` | `EMAIL_LIFECYCLE` | `false` | Run the lifecycle watcher |
| `email_lifecycle_interval` | `EMAIL_LIFECYCLE_INTERVAL` | `1s` | Pause between watcher cycles |
| `email_lifecycle_batch` | `EMAIL_LIFECYCLE_BATCH` | `100` | Due attempts of each kind in one cycle |
| `email_lifecycle_lock_timeout` | `EMAIL_LIFECYCLE_LOCK_TIMEOUT` | `1s` | `lock_timeout` of a watcher cycle |
| `email_lifecycle_statement_timeout` | `EMAIL_LIFECYCLE_STATEMENT_TIMEOUT` | `10s` | `statement_timeout` of a watcher cycle |
| `email_command_lock_timeout` | `EMAIL_COMMAND_LOCK_TIMEOUT` | `1s` | `lock_timeout` of an Email command, wake-up or join |
| `email_attempt_publisher` | `EMAIL_ATTEMPT_PUBLISHER` | `false` | Publish `cc_email_attempt_outbox` to email-service |
| `email_attempt_publisher_interval` | `EMAIL_ATTEMPT_PUBLISHER_INTERVAL` | `1s` | Pause between publisher cycles |
| `email_attempt_publisher_batch` | `EMAIL_ATTEMPT_PUBLISHER_BATCH` | `100` | Rows claimed in one cycle |
| `email_attempt_publisher_lease` | `EMAIL_ATTEMPT_PUBLISHER_LEASE` | `30s` | Lease of claimed rows |
| `email_attempt_publisher_confirm_timeout` | `EMAIL_ATTEMPT_PUBLISHER_CONFIRM_TIMEOUT` | `5s` | Bounds connecting, each network write and the broker confirm of one row |
| `email_attempt_outbox_retention` | `EMAIL_ATTEMPT_OUTBOX_RETENTION` | `168h` | Age of published rows without `command_id` to delete |

Queue `payload` keys: `email_auto_release_sec` (`0` or unset keeps an offer; an
invalid value counts as unset and is logged as `payload_invalid`),
`email_postpone_max_sec` (default 2592000), `sticky_agent_sec` (default 30) and
`email_sticky_history_sec`; they are whole seconds, and an invalid value of any
of them counts as unset. Agents have `email_count` and `email_postponed_count`.

Startup fails when a batch is not positive, a duration is below 1 ms, a lock
timeout is not below its statement timeout or the publisher lease is not longer
than its confirm timeout.

Startup logs include interval, queue batch, the requested half-statement-timeout
`max_duration` budget, lock timeout and statement timeout. These are configured
budgets, not evidence of actual SQL/binary versions. A cycle with assignments
is logged at info level, other cycles at debug level.
`assigned` counts successful assignments; `no_agent_queues` counts distinct
positive queue IDs with at least one `no_agent` outcome in that cycle, not
failed attempts or queues with no operators at all. A queue can have both
assignments and `no_agent` outcomes and is counted once in `no_agent_queues`.
Repeated rows do not increase this queue count; missing/invalid IDs are ignored.
The log also includes calendar/configuration outcomes and cycle latency. A
queue without enabled skills or with an invalid calendar and a cycle that
reached its time limit are logged as warnings, a failed cycle as an error with
its `outcome`: `lock_timeout`, `statement_timeout`, `context_timeout` or
`error`; each at most once in 5 minutes. After a failed cycle the pause is twice
the interval and doubles with each next failure up to 1 minute, or the interval
if it is longer, less up to 10% at random but never below the interval; it
returns to the interval after the next successful cycle. A skipped busy cycle
or a reached time limit is not a failure.

A watcher cycle with transitions is logged at info level, other cycles at debug
level, with `released`, `processing_timeouts`, `postponed_woken`,
`postponed_queued`, `offline_returned`, `lock_skipped` and the latency; its
failures and time limit are logged like those of the allocator.

A publisher cycle that published rows is logged at info level with `claimed`,
`confirmed` (by the broker), `published` (marked in the database) and the
latency, other cycles at debug level. Once a minute it deletes old rows and logs
`deleted`, `backlog` and `oldest_pending_age`. A broker failure gives the rest
of the batch back for 5 seconds and backs off like a failed allocator cycle;
rows the broker confirmed but the database did not mark are sent again after
their lease, and that cycle backs off too. Failures are logged as warnings at
most once in 5 minutes each.

### Rollout and limits

Follow the [EM-24 runbook](docs/email-routing-upgrade.md#em-24-status-sync-upgrade):
matching extension 1.5, shared prepare/validate/runtime, lifecycle, then status
sync and Inbox route migrations. Use the files from this release and stop Email
writers throughout the upgrade; older SQL must not be replayed over the result.

Deploy email-service with the compatible snapshot consumer, engine with the
Email limits, then all call_center nodes with distribution/lifecycle/publisher
flags off, then Flow. Enable the flags only after the integration checks. Enable
the publisher last; while it is off, unpublished snapshots wait in the outbox.

Run the migrations with `PGOPTIONS='-c lock_timeout=5s'` and keep AMQP heartbeats
enabled. PostgreSQL and service restarts, concurrency and performance remain
release checks; the former smoke does not verify the final five-array API.

`cc_member_attempt` is an unlogged table. A restart of `call_center` keeps the
attempts, but a crash or failover of PostgreSQL loses them, together with the
`waiting`, assigned and postponed emails and their deadlines. The logged
`cc_email_join`, `cc_email_wakeup` and `cc_email_attempt_outbox` still refer to
the lost attempts.
