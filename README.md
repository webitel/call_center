# call_center

### Email routing update: implementation status

Business clarification recorded on 2026-10-23: default priority is 0; the
accepted proposal for the system High threshold is 10 (`greatest(priority, 10)`),
without lowering a larger Flow priority. The technical range remains 0–100;
High is not an absolute maximum. Granted Extra permission is preserved across
Postpone/Return/Transfer. Missing Flow Sticky candidate means normal routing
with no implicit Thread-history lookup; that rule is already implemented.
The upgrade SQL and full schema use High 10 in preparation, effective route
and head selection. Step 7.2.1 completed the targeted High-10 checks on both
clean and upgrade paths, including repeat application and full Email-function
parity. Historical 4.4 results cover the previous High-100 snapshot only;
7.2.1 is the evidence for the current threshold, not full rollout acceptance.
Resume/direct transfer use of Extra remains the existing technical policy,
not a separate business confirmation.
Do not bulk-rewrite weight 100: it may come from Flow.

The system High literal has four routing sites in both `email_routing_update.sql`
and `call_center-schema.sql`: two in `cc_email_sticky_prepare` (R5/timeout), one
in `cc_email_sticky_route`, and one in the fallback branch of `cc_email_agent_head`.
Preserve these sites and the full function definitions verified in 7.2.1
in later-stage overrides. Do not change priority validation's
upper bound 100. No additional SQL helper is introduced for this constant.

Implementation steps 4.1–4.3 cover storage, extended JoinQueue, base/Extra
assignment, explicit-candidate Sticky and cross-queue priority selection.
They are not rollout acceptance. The agreed narrowed component verification
4.4 was completed on 2026-10-23 using PostgreSQL 18.6: local clean/upgrade,
routing/Sticky/capacity checks, bounded EXPLAIN measurements and deterministic
multi-cycle and status/limit races. Extended load/fairness, concurrency and full
Call/Chat/IM/Task end-to-end regression remain mandatory production gates;
the local step-7 scope was narrowed as recorded below. Keep inbound polling
and `email_distribution` off in production until
those gates and the remaining release prerequisites pass. No production-ready
performance or starvation guarantee is claimed by the component checks.

### Local verification summary — 2026-10-23

- 7.2.2: actual RabbitMQ → Inbox → Flow → CC gRPC → allocator passed routing,
  replay and error checks. Online RPC also passed in a separate repeat with
  two existing `26.08/1.sql` function definitions temporarily applied in the
  isolated database; the original definitions were restored afterward.
- Known prerequisite: the full schema still has an old Online login call and
  `skill_preset` references. It is not aligned with those two migration
  functions. No repair was made; a successful repeat does not prove the
  unmodified clean schema supports Online. Resolve before clean rollout.
- Narrowed 7.3: 20 agents, 8 nonempty queues, 2,000 waiting letters; three
  cycles made 120 assignments without slot overflow (143–299 ms per cycle,
  including harness assertions). One-slot concurrent allocator check passed.
  This is not sustained-load/fairness or production performance acceptance.
- Local 7.4: 12 Chat/Rabbit tests, actual Agent API and eight Task-store cases
  passed. Two Email assignments preserved exact non-Email attempts, channel
  rows and Queue-view rows. Generic `cc_distribute` executed with `cc_sql`.
  Existing Task assignment explicitly ignores active Email in its busy guard;
  tested non-Email guards remain unchanged. This is not full channel E2E.

Local stack: PostgreSQL 18.6 / TimescaleDB 2.30.2 / `cc_sql` 1.4, isolated
fixtures, AMD64 emulation. Production parity is not established. Baseline
Call-manager limitations and Flow/engine findings remain unresolved; no blanket
baseline acceptance or rollout/merge approval is implied. Workspace evidence:
`tmp/Emails_Routing_Step7_2_1_Verification.md`,
`tmp/Emails_Routing_Step7_2_2_Online_Verification.md`,
`tmp/Emails_Routing_Step7_3_Verification.md`,
`tmp/Emails_Routing_Step7_4_Verification.md`; these are workspace artifacts,
not files shipped with this service repository. The routing update plan lists
remaining review and production gates. Keep production polling/allocator off.

The primary verification environment must use production-compatible `cc_sql`
and TimescaleDB; record exact versions and any environment differences. PG16
is optional only if supporting it is a separately confirmed requirement, not
the acceptance gate or a replacement for PostgreSQL 18.6 verification.

`EmailJoinToQueue` accepts `priority` (0–100, default 0), `sticky_agent_id`
(default 0: no candidate), `extra_email_count` (per-letter permission, default
false) and `from_address` (initial inbound From). An out-of-range priority is
rejected before writes with gRPC `InvalidArgument` and stable ID
`store.sql_member.email_join.invalid_priority`; SQL also validates the range.
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
allocator, which is separate from the generic distribution of calls and chats.
`call_center` then keeps the lifecycle of the attempt until it leaves to
`cc_member_attempt_history`.

### How emails are assigned

Every instance runs the allocator when `email_distribution` is enabled. Each
cycle calls `call_center.cc_email_distribute` in one short transaction; a
transaction-scoped advisory lock lets one instance work at a time, the others
skip the cycle. The first phase is a round-robin maintenance pass over queues,
with a soft threshold of one quarter of the cycle work budget and at most
`min(email_distribution_queue_batch, 128)` actionable Sticky updates per visited
queue. The threshold is checked between iterations; a single SQL query can
overrun it. Upkeep may take several cycles, not necessarily just one.
Assignment then visits online agents in rounds; for each agent,
`cc_email_agent_head` selects the best permitted letter across all eligible open
queues. Queue priority and strategy do not rank those letters.

`cc_email_distribution_cursor` is a LOGGED single-row table, initialized by the
first allocator cycle, with the last visited queue and agent IDs and no foreign
keys. It is updated once in a completed or softly stopped cycle. The next cycle
starts after those IDs (wrapping by ID), including across process restart.
The cursor changes visitation order only, never an agent's priority/FIFO order.
It commits with assignments and rolls back with a failed cycle; it is not an
attempt or slot ledger and does not make UNLOGGED attempts durable after a
PostgreSQL crash. No external scheduler or local queue session is used.

Each agent visit produces at most one successful assignment, but its actual
recipient can be another candidate for that letter. This is not a limit of one
assignment per actual recipient per round.

`email_distribution_queue_batch` caps assignments from each queue per cycle
and failed/reselected head attempts per agent visit. Once an agent's best queue
reaches that cap, the agent waits for a later cycle instead of taking
lower-priority work from another queue. If several agents can take the same
letter, the fewest assigned emails / oldest offer / agent-ID ordering applies
among candidates for whom that letter is also the current best choice.

Locked/changed heads are skipped within the cycle, not permanently reserved or
removed. A pending Sticky fallback is ranked using its effective priority even
before the maintenance pass reaches it, then prepared under row lock and
reselected before assignment. This avoids ranking priority-10 fallback work
below a lower-priority general letter merely because upkeep was batched.
An Extra-only agent can skip a base-only head without hiding permitted Extra work.

The fallback branch materializes candidate routing once per queue, Sticky agent
and Extra permission within one head query. It reuses `cc_email_sticky_route`
without a letter deadline, then applies each letter's deadline and effective
priority separately. Cancellation still keeps priority; R5/timeout still raises
it to at least 10 without lowering a larger Flow priority. This is query-local work, not a cache between assignments or
cycles. Final preparation and eligibility/capacity checks under locks are unchanged.
Grouping and finding fallback letters can still scan the Sticky backlog; this
optimization removes repeated candidate checks, not all backlog-dependent work.

These limits bound selected heads, visits and updates, not all rows the planner
may scan. Backlog cost, fairness and any additional concurrent indexes require
component verification in step 4.4 and extended EXPLAIN/load/concurrency gates
in step 7 before production enablement. In particular, measure
repeated head selection across candidate agents and queues, and the fifth head
branch's route/filter/sort over pending Sticky rows. Neither bounded scans nor
absence of starvation is established by this implementation. Any head cache
must invalidate all affected agents, not only the assignment recipient; cached
calendar results cannot replace authoritative checks under assignment locks.
Removing pending R5/cancelled candidates from effective-priority comparison
would change behavior and needs separate approval. As a safeguard, a cycle
stops itself after half of its statement timeout, checked between queues,
attempts and agent candidates, and commits what it assigned;
the rest waits for the next cycle. A lock or statement timeout instead rolls the
whole cycle back. The allocator keeps no local state, so a restarted instance
only continues with the `waiting` attempts left in the database.

A queue assigns only while its calendar is open. A missing or invalid calendar,
or a queue without enabled skills, keeps its emails waiting and is logged as a
configuration error. Across all queues available to a particular agent, letters
rank by numeric priority descending, then `joined_at` and attempt ID ascending.
An unavailable queue or waiting Sticky candidate does not rank ahead of work
that is actually eligible for that agent.

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

Among eligible agents the fewest total emails wins, then earliest
`last_offering_at` (NULL first), then agent ID. Assignment locks the agent before
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
Sticky competes with that candidate's other eligible letters by priority/FIFO.
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
FIFO and SLA do not restart, makes it High (`greatest(priority, 10)`) and drops
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
  (`0` disables postponing);
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
| `email_distribution` | `EMAIL_DISTRIBUTION` | `false` | Run the Email allocator |
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

A cycle with assignments is logged at info level, other cycles at debug level.
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

1. Apply SQL using the upgrade runbook, including the separate CHECK-validation
   step and `email_last_bridged_indexes.sql`. Do not apply only the original
   `email_agent_distribution.sql`, which would restore the old functions.
2. Apply `email_attempt_lifecycle.sql` with `psql -v ON_ERROR_STOP=1 -f` outside
   a transaction after them. It redefines allocator functions, so the earlier
   routing files must not be repeated after it. Then apply
   `email_status_sync.sql` the same way; it redefines the wake-up, join and
   snapshot functions of `email_attempt_lifecycle.sql`, which must not be
   repeated after it. Apply `email_route.sql` the same way after
   `email_service_inbox.sql`; it adds the route of an event to the Inbox of
   `flow_manager`, with the JoinQueue values and the initial From it repeats.
3. Release `engine` with the base, Extra and postponed Email limits of agents,
   then every `call_center` node with the allocator, the watcher and the
   snapshot publisher off, then `flow_manager` once no node runs the old
   `call_center`.
4. Give agents `email` in `allow_channels` and the intended base/Extra limits.
5. Enable `email_distribution` and `email_lifecycle` only after the remaining
   integration gates and release prerequisites pass.
6. Enable `email_attempt_publisher` only after email-service with its consumer
   is deployed and the stage 12 concurrency check has passed; turning it off
   rolls back, unpublished rows wait in the outbox.

Run the migrations with `PGOPTIONS='-c lock_timeout=5s'` and repeat them on a
lock timeout, and keep heartbeats on in the AMQP URL.

Keep the allocator and the watcher off in production for now. An assigned email
is not yet announced to Workspace, Workspace has no read API or commands for it,
and the snapshot publisher (`email_attempt_publisher`) is off by default: enable
it only after email-service with its consumer is deployed and the rollout checks
pass.

`cc_member_attempt` is an unlogged table. A restart of `call_center` keeps the
attempts, but a crash or failover of PostgreSQL loses them, together with the
`waiting`, assigned and postponed emails and their deadlines. The logged
`cc_email_join`, `cc_email_wakeup` and `cc_email_attempt_outbox` still refer to
the lost attempts.
