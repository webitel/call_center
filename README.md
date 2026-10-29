# call_center

### Shared Email distributor

Email assignment uses the shared C algorithm of `cc_sql` 1.5 through a separate
Email entry, `cc_sys_distribute_email`, in its own transaction. Generic
`cc_distribute` does not select Email and shares no reservations with it. The
SQL function `cc_email_distribute(integer, interval)`, its four result columns
and the Go poller are unchanged; see [How emails are assigned](#how-emails-are-assigned)
and the [SQL contract](docs/email-shared-distributor-contract.md).

| File in `store/sqlstore/migration/26.dev/` | Purpose |
|---|---|
| `email_shared_distributor_prepare.sql` | Priority 0–2147483647, `cc_email_high_priority()`, Email idle metadata, Email stage 1, apply adapter |
| `email_shared_distributor_validate.sql` | Validation of the priority CHECK |
| `email_shared_distributor_runtime.sql` | New `cc_email_distribute` body; drops the old head function and agent cursor |

Apply them after `cc_sql` 1.5 in the [runbook order](docs/email-routing-upgrade.md#shared-distributor-upgrade).
`call_center-schema.sql` already contains the final definitions for a clean
installation.

Priority is a nonnegative int32; High is temporarily 10 until the business value
is set. Internal and external state stays `waiting`. Generic SQL keeps the
release definitions; the generic C aggregate no longer counts Email towards the
busy state of other channels. `Intercept` does not touch Email attempts.

These EM-21 changes do not include the EM-23/EM-24 adaptation (Take and release
metric hooks, `last_released_agent_id`, lifecycle and outbox, durable route); the
migrations reject an EM-23/EM-24 schema. Keep `email_distribution` off until the
complete compatible release passes its verification.

### Email routing update: historical verification

The 2026-10-23 snapshot used priority 0–100 and four literal High-10 routing
sites in both `email_routing_update.sql` and the full schema. Step 7.2.1 checked
that snapshot on clean and upgrade paths, including repeat application and
Email-function parity. Historical 4.4 results cover the earlier High-100
snapshot. Neither result certifies the shared-distributor transition.

Default priority remains 0; boosts never lower a larger Flow priority. Granted
Extra permission and the no-implicit-Sticky-history rule remain unchanged.
Resume/direct transfer use of Extra remains the existing technical policy.
Do not bulk-rewrite weight 100: it may come from Flow.

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
existing active attempt of the Thread, which may already be assigned
(`offering`), and returns immediately. Agents are assigned later and
asynchronously by a separate Email polling transaction using the shared C
selection algorithm. Generic call/chat distribution keeps its own transaction
and reservations. This section describes the prepared final SQL; the runtime
migration has not been applied during this work.

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
across the whole cycle. Failed rechecks add cycle-local skipped attempt IDs;
they do not consume the queue limit. Further C calls permit an agent to fill
several allowed slots. New assignments/skips permit another round; empty
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

Base and Extra use separate counts of unfinished assigned Email attempts across
all queues. Each new assignment chooses base first, otherwise permitted Extra;
freeing a base slot never promotes an already assigned Extra email. Both limits
may be lowered without releasing existing assignments. An unclassified active
assignment makes new capacity checks fail closed rather than disappearing from
the count. The lifecycle-stage postponed exclusion is adapted with EM-23.

Among eligible agents the configured Team Strategy applies, followed by Email
`last_offering_at` (NULL first) and agent ID. Existing C default semantics for
strategy names and the Email-only idle-name alias are documented in the shared
contract. EM-23 Take/release metric hooks still require step 5. Assignment locks the agent before
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

### Configuration

| Flag | Environment | Default | Meaning |
|---|---|---|---|
| `email_distribution` | `EMAIL_DISTRIBUTION` | `false` | Run isolated Email cycles using shared C selection |
| `email_distribution_interval` | `EMAIL_DISTRIBUTION_INTERVAL` | `1s` | Pause between cycles |
| `email_distribution_queue_batch` | `EMAIL_DISTRIBUTION_QUEUE_BATCH` | `50` | Assignments per queue in one cycle |
| `email_distribution_lock_timeout` | `EMAIL_DISTRIBUTION_LOCK_TIMEOUT` | `1s` | `lock_timeout` of a cycle |
| `email_distribution_statement_timeout` | `EMAIL_DISTRIBUTION_STATEMENT_TIMEOUT` | `10s` | `statement_timeout` of a cycle |

Startup fails when the queue batch is not positive, a duration is below 1 ms or
the lock timeout is not below the statement timeout.

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

### Rollout and limits

Follow the [runbook order](docs/email-routing-upgrade.md#shared-distributor-upgrade)
for an existing EM-21 database, or the clean installation described there. Keep
Email writers and `email_distribution` off through migration and deployment:
database changes first, then `call_center`, then Flow. Older component results
are not approval of this release.

Extension SQL downgrade only removes the new C entry. After runtime cleanup,
returning to an old allocator also needs a compatible wrapper/head/cursor set;
blindly replaying the old routing migration can restore obsolete priority bounds
and selection behavior. No automated full runtime rollback is supplied here.

`cc_member_attempt` is an unlogged table. A restart of `call_center` keeps the
attempts, but a crash or failover of PostgreSQL loses them, together with the
`waiting` and assigned emails; `cc_email_join` still refers to the lost attempts.
