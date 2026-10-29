# Email routing schema upgrade

## Shared distributor upgrade

Order for an existing EM-21 database:

| # | Step | Notes |
|---|---|---|
| 1 | Install `cc_sql` 1.5: binary, control file, version SQL | Every PostgreSQL server of the database; see atomic replacement below |
| 2 | `ALTER EXTENSION cc_sql UPDATE TO '1.5'` | In a fresh connection; registers `cc_sys_distribute_email` |
| 3 | `email_shared_distributor_prepare.sql` | Own transaction |
| 4 | `email_shared_distributor_validate.sql` | After step 3 commits, outside a transaction |
| 5 | `email_shared_distributor_runtime.sql` | Last; own transaction |
| 6 | Deploy `call_center`, then `flow_manager` | Older SQL and services reject priority above 100 |

- Before step 1 stop Email writers on all nodes and keep `email_distribution`
  off. The starting schema must contain the release generic SQL and the EM-21
  prerequisites: routing update, its validation and the address indexes.
- Files are in `store/sqlstore/migration/26.dev/`; the extension repository keeps
  identical copies in `webitel/migration/email/`. Apply one copy with
  `psql -v ON_ERROR_STOP=1 -f`.
- Prepare and runtime reject a schema with EM-23/EM-24 objects; such a database
  needs the adapted release.
- Runtime checks that `cc_sql` 1.5 and the prepared objects exist, replaces
  `cc_email_distribute`, then drops `cc_email_agent_head(integer, bigint[])` and
  the cursor column `last_agent_id` without CASCADE. The Sticky-maintenance
  position `last_queue_id` is kept. An error rolls back only the runtime step.
- Each file can be repeated on the EM-21 schema. After runtime do not apply
  prepare again or any historical Email SQL: older files restore the previous
  priority range and allocator.

### Clean installation

Create the extension `cc_sql` 1.5 and load `call_center-schema.sql` once as part
of the complete bootstrap with the directory, flow and storage prerequisites.
The schema already contains the final Email definitions and no old head function
or agent cursor; do not apply the upgrade files or historical Email SQL over it.
It contains `CREATE SCHEMA call_center` and uses extension-owned types, so the
bootstrap must order the schema, the extension and the dump. The extension's
base dump alone does not install the Email model.

### Atomic library replacement

Stop all callers of the extension, including generic routing. Put the new
`cc_sql.so` under a temporary name on the same filesystem as the destination,
check its checksum, owner and permissions, then rename it over the destination.
Never copy over or truncate a loaded library: in testing this crashed PostgreSQL
with `Bus error`, and crash recovery cleared the UNLOGGED attempt table. After
the rename, reconnect the sessions and pools that loaded the old library before
resuming callers. Repeat on every server that can host the database.

### Rollback

`cc_sql--1.5--1.4.sql` only drops `cc_sys_distribute_email`. It restores neither
the old binary nor the old `cc_email_distribute`, head function or agent cursor
column; returning to the old allocator needs a reviewed compatible set of them.
Do not replay old routing SQL blindly and do not delete attempts or outbox rows
as a shortcut. Stop callers and reconnect sessions for any binary replacement.

### Known limits

- High is temporarily 10 (`cc_email_high_priority()`); existing priorities are
  not rewritten.
- Check the actual `cc_team.strategy` strings: unknown names use the default
  `last_offering_at` branch; Email also accepts `longest-idle-time`.
- The extension workflow's package list is generated from
  `webitel/reusable-configs`; add both 1.4↔1.5 scripts there before the next
  file-sync.
- The EM-21 changes do not include the EM-23/EM-24 adaptation. Restart,
  concurrency, performance and other-channel regression checks remain open.

## Historical alignment — 2026-10-23

The verified snapshot used default priority 0, priority range 0–100 and four
literal High-10 sites: Sticky R5/timeout (two), effective Sticky route (one)
and the fallback head branch (one). Targeted 7.2.1 verification covered clean
and upgrade paths, repeat application, priority preservation and function/catalog
parity. Historical 4.4 results cover the previous High-100 snapshot. These are
historical component results, not verification of the preparation above or
production acceptance. Granted Extra permission and no implicit Sticky lookup
without a Flow candidate remain unchanged. Existing weight 100 is never
bulk-converted; Flow may have assigned it explicitly.

Review additions passed in 7.2.1: low-priority no-boost assertions for
R1/R2, permanent ineligibility, lost skills, unavailable slot type and R3/R6;
real full-base-slot R4/R7 with a base-only letter and 5-to-10 timeout for both
Ignore settings; explicit R8 post-timeout weight; and both equal-priority FIFO
orders for fallback 0-to-10 versus Flow 10. `available_timeout` in the SQL matrix
does not claim a full slot; the disabled-channel case omits head assertions
because its only online agent cannot receive Email. Historical 4.4 PASS alone
does not verify these assertions; 7.2.1 does. Workspace evidence:
`tmp/Emails_Routing_Step7_2_1_Verification.md` (not shipped in this repository).

**Known clean-schema prerequisite, not repaired:** the five-argument
`cc_set_agent_online` in the full schema calls a nonexistent four-argument
`cc_agent_set_login` and uses old `skill_preset` references, also present in
`cc_agent_set_login_v2`. The existing `26.08/1.sql` has aligned versions of
these two functions. Online → Email assignment passed after temporarily using
those definitions and a complete Team fixture in isolated 7.2.2; both functions
were restored afterward. This is not approval to rerun the whole generic
migration (it also has already-present DDL and other-channel changes), nor an
Email migration fix. Resolve the full-schema/migration discrepancy separately
before claiming a working clean Online path; code changes are currently deferred.

This includes schema/JoinQueue, base/Extra, explicit-candidate Sticky and the
cross-queue allocator implemented in 4.3, not permission to enable the allocator.
The narrowed component verification 4.4 was accepted on 2026-10-23 after the
approved checks. Extended performance/fairness, concurrency, environment parity
and full other-channel regression remain mandatory integration gates in step 7.
Do not change Call/Chat/IM configuration or data for this upgrade.

## Historical EM-21 baseline: before upgrading

1. Confirm the actual environment has no production Email workload. Stop inbound
   polling and Flow Email joins, the Email allocator and any later-stage lifecycle
   writers on every node. An unreleased stage number alone is not evidence.
2. Finish and archive old test Email attempts. Alternatively, separately approve
   a cleanup of an explicitly identified isolated test set, accounting for
   `cc_email_join`, Inbox/wake-up, outbox and the Email projection. Deleting only
   attempts would leave invalid replay results. This migration deletes nothing.
3. Confirm there are no rows with `channel = 'email'` in
   `call_center.cc_member_attempt`, including `leaving` rows awaiting history.
   On its first application, the migration refuses such rows before adding the
   slot-type column. Existing join journal and finished history rows are retained;
   neither is rewritten into a new attempt. History without an address does not
   participate in the later address lookup.
4. Back up the database and record deployed service/schema versions. Do not run
   this EM-21 baseline script over a database already using locally implemented
   EM-23/EM-24 overrides; adapting those overrides belongs to their later steps.

## Historical EM-21 baseline: apply

For a migration-based clean installation, first apply the existing prerequisites
and `email_queue_join.sql`, then `email_agent_distribution.sql`, using
`psql -v ON_ERROR_STOP=1 -f` outside an enclosing transaction: the original files
build indexes `CONCURRENTLY`. Finally apply:

```sh
psql -v ON_ERROR_STOP=1 -f store/sqlstore/migration/26.dev/email_routing_update.sql
```

For an installation that already applied original EM-21, apply only
`email_routing_update.sql` after the preconditions above. It contains its own
DDL transaction; do not wrap it with another transaction. A failure before its
commit rolls back the schema/function changes together. New CHECK constraints
are added `NOT VALID`, avoiding full constraint-validation scans while the DDL
transaction holds its exclusive locks. They still enforce new inserts/updates.
The initial old-attempt guard still checks the current attempt table under lock;
short exclusive DDL locks remain necessary. `lock_timeout = '5s'` limits lock
acquisition waits, not how long an acquired lock is held. Resolve contention and
rerun if lock acquisition fails.

After the DDL transaction commits, run validation as a separate step, without
an enclosing transaction:

```sh
psql -v ON_ERROR_STOP=1 -f store/sqlstore/migration/26.dev/email_routing_validate.sql
```

Each `VALIDATE CONSTRAINT` runs in its own transaction with a
`SHARE UPDATE EXCLUSIVE` lock, allowing ordinary reads and writes. The script
does not alter or scan `cc_member_attempt_history`. It validates the base/Extra
agent limits, current-attempt slot CHECK and join priority CHECK. Do not deploy
the new service or enable Email until both steps succeed. If validation fails,
the committed DDL is retained: fix the cause and rerun validation. The DDL script
does not recreate existing constraints, and already completed validations can
be repeated safely.

For a clean database initialized from the full schema, `call_center-schema.sql`
already includes this model and the new functions; do not subsequently apply
older Email files over it. Full database initialization also requires the usual
directory, flow, storage and extension prerequisites.

### L4 follow-up: Email lastBridged address indexes

After routing update and separate validation, existing installations apply:

```sh
psql -v ON_ERROR_STOP=1 -f store/sqlstore/migration/26.dev/email_last_bridged_indexes.sql
```

Use psql autocommit, not `BEGIN`, `--single-transaction` or a transactional
migration wrapper. The file uses psql `\gexec` to drop only the two named invalid
indexes, on their expected tables, as separate `DROP INDEX CONCURRENTLY`
commands; then `CREATE INDEX CONCURRENTLY IF NOT EXISTS` builds the indexes.
After a failed/interrupted build, investigate the cause and rerun the file.
A completed first index is retained if the second build fails. Serialize runs
of this migration; do not run concurrent index maintenance on these tables.

Before applying, inspect any existing indexes with these names. `IF NOT EXISTS`
does not compare definitions: a valid differently defined index or a name on
the wrong object requires investigation, not automatic replacement. After
applying, confirm both definitions match the full schema and both `indisvalid`
and `indisready` are true. A clean full-schema installation already creates the
same indexes without `CONCURRENTLY`; no extra migration is needed there.

The keys are `(domain_id, (destination->>'number'), leaving_at DESC)`;
the active-table predicate is `channel='email' AND state='leaving'`, the history
predicate is `channel='email'`. Only Email rows are indexed; lookup SQL, routing
functions, history columns and other-channel rules are unchanged. Normal DML
can continue during concurrent builds, but history is scanned and the build
adds IO/CPU load, can wait for transactions and increases Email write/index
maintenance costs. Schedule outside peak hours and monitor available disk.

Prior cloud evidence is in workspace
`tmp/em21_step7/Emails_Routing_Step7_1_Indexes.md` (not shipped with this repo).
This follow-up copies only L4 definitions, not L1. Concurrent invalid-index
recovery is adapted to top-level psql commands rather than `DROP INDEX` inside
DO. The local migration/recovery and updated schema were not executed or
retested at the user's request; prior PASS does not certify this new file.
The historical 57-entry catalog parity predates these indexes. Full rollout
gates and the known Online full-schema prerequisite remain open.

The update is repeatable. It does not convert `weight = 0/1`, reset agent values,
overwrite existing Email channel rows or delete data. Existing agents retain
their limits; if the base column has not been added yet, it is added with 0 for
existing rows before changing the default to 1 for future records. Extra defaults
to 0. `smallint` and nonnegative checks bound the limits to 0–32767. Existing
journal routing fields remain NULL when unknown; valid replays still return the
original stored result. New joins record all routing parameters.

The four-argument SQL function is replaced, in the same transaction, by one
eight-argument function with defaults. Old four-argument SQL calls therefore
resolve to the new implementation; there is no separate legacy overload.
Older RPC callers use the protobuf defaults. Deploy the database update before
the new service binary, whose joins use the new columns. History writes retain
their original column mapping: only `destination.number` is needed for the
address lookup. Extra permission and occupied slot type are not stored in
history, and this update adds no columns or constraints there.

The internal `cc_email_queue_candidates` helper now accepts queue, optional
agent and per-letter Extra permission (default false). Its old two-argument
overload is removed so defaulted calls resolve to one implementation. The
extended result includes base/Extra use and the selected slot type. The new
`cc_email_agent_capacity` helper is shared by candidates, Sticky and the queue
view; its counts span all queues. In EM-23/EM-24 adaptations, port all helper,
assignment, allocator and Sticky overrides, including the postponed exclusion;
do not restore the base-only signature/logic. The queue view's Email `free`
counter represents potential base/Extra capacity, never letter authorization.

### Historical allocator details before shared-runtime cutover

The following head/agent-cursor description belongs to the historical routing
update. The final runtime migration above removes that function/agent column;
these paragraphs are not instructions to restore them after cutover.

The update also creates `cc_email_distribution_cursor`, a LOGGED single-row table with
the last visited queue and agent IDs. The first allocator cycle initializes the
row; rerunning the migration does not reset it. No foreign keys are needed:
deleted IDs remain harmless positions from which the next traversal continues.
Cursor writes commit/roll back with assignment; they do not replace active
attempts as capacity authority. Process restart resumes visitation without
unreserving existing `offering` attempts. The row is updated once per completed
or softly stopped cycle, not a busy advisory-lock no-op. It does not make
UNLOGGED attempts durable after a PostgreSQL crash.

`cc_email_agent_head` selects the best eligible letter across an agent's queues,
including the effective priority of a pending Sticky fallback as computed by
`cc_email_sticky_route`. The selected fallback is prepared under row lock and
reselected before assignment, even if the maintenance batch has not reached it.
`cc_email_sticky_prepare` now has a fourth optional attempt ID for this targeted
preparation; its three-argument overload is removed, and old calls use the new
default. Preserve these signatures and logic when adapting later SQL overrides.

The fifth head branch now uses a query-local MATERIALIZED `sticky_routes` CTE,
grouped by Sticky agent and Extra permission for each queue. The existing route
helper is evaluated with NULL deadline and priority 0: a NULL candidate with 0
means cancellation, while an immediate High fallback returns 10. The real
letter deadline and priority are applied afterwards, preserving R5 and cancelled
candidates even beyond the upkeep batch. There is no cross-query/round cache,
new persistent table or index. The CTE does not make physical scans bounded.
Port this grouping when adapting later-stage SQL overrides; final locked
preparation and assignment rechecks remain authoritative.

The first phase, maintenance, has a soft threshold of one quarter of the cycle
work budget and up to `min(queue_batch, 128)` actionable rows per visited queue.
Time is checked between iterations, not inside an individual SQL query. Upkeep
can take multiple cycles because of time, batch limits and queue traversal;
pending fallback must still rank at its effective priority before being stored.
Agent rounds then use the remaining work budget. Each visit permits at most one
successful assignment, whose actual recipient can be another candidate and can
win again during other visits; this is not one assignment per recipient/round.
The queue batch caps assignments without demoting an agent to lower-priority
work. A hard statement timeout rolls back the entire cycle, including its cursor.
Existing queue/Sticky indexes remain in place;
there are no unmeasured new allocator indexes in this implementation. Component
measurements in 4.4 do not replace the extended scans/timeouts gate in step 7;
add a separately approved concurrent-index migration if evidence requires it.
Per-branch LIMITs do not prove bounded storage scans.

## Exceptional data preservation and rollback

Preserving old active test attempts is not part of the standard script. If a
specific environment requires it, prepare and approve a separate conversion:
in one transaction, on first addition of the slot-type column, classify existing
assigned Email attempts as `base` and convert old High to the agreed new High.
It must roll back column creation and conversion together, and must never
reconvert a legitimate new priority 1 on a rerun. Do not bypass the guard by
adding the column manually; other channels must remain untouched.

If the DDL update fails before commit, keep processing stopped, fix the cause
and rerun. For a failure after commit, use the separate validation retry above.
After a committed upgrade and new joins, do not roll back just the SQL
function or resume the old allocator: it cannot honor the new routing/slot
semantics. Keep Email writers stopped and coordinate recovery using the recorded
backup and compatible binaries; no automatic destructive downgrade is provided.

## Component verification 4.4 and mandatory integration gate 7

Implementation and verification remain separate stages. The agreed narrowed
4.4 was completed on 2026-10-23: local PostgreSQL 18.6 clean/upgrade and routing
checks, Sticky-head differential/EXPLAIN measurements, then two multi-cycle/cursor
scenarios and six status/base/Extra-limit races in independent sessions. The
earlier interrupted PG16 preparation was not acceptance evidence. Runtime SQL
did not change during the final checks; fixture-only instrumentation forced a
soft yield, and writer blocking was observed through `pg_blocking_pids`.

This is component acceptance, not production or full integration acceptance.
Extended load/fairness and concurrency, all uncovered edge cases below, target
schema/extension parity and complete Call/Chat/IM/Task lifecycle/end-to-end
regression remain mandatory before production polling/allocator is enabled.
The agreed local step 7 was narrowed: 7.3 covers three moderate-load cycles,
head/lookup EXPLAIN and one-slot allocator concurrency; 7.4 is local unit/API/SQL
regression, not full channel E2E. These remaining gates are deferred to rollout,
not waived by local completion. See the workspace routing update plan and
`tmp/Emails_Routing_Step7_3_Verification.md` / `tmp/Emails_Routing_Step7_4_Verification.md`.
The general Go suite has known `call_manager` limitations and is not
declared successful. Record which scenarios actually ran; this checklist must
not be read as a claim that every case passed in 4.4. Repeat affected checks
after changes, using fresh checksums/current code.

Use isolated PostgreSQL 18.6 with the full current Webitel schema and
production-compatible `cc_sql` and TimescaleDB. Record exact versions, extension
source/build and differences from the target deployment; a different TimescaleDB
version must be explicit, not silently treated as identical. Do not strip schema
objects or backport PG18 syntax merely to fit PG16 for the primary gate.
PG16 is an optional extra compatibility run only if its support is separately
required; it neither blocks 4.4 by default nor replaces the PG18.6 gate.
Verify clean installation, original-EM-21 upgrade, rerun, rejection
with old attempts, preservation of existing limits/history/journal, and new
agent defaults. Verify priorities -1/0/100/101, SQL and RPC error IDs/no side
effects, valid replay after state/configuration changes, cross-domain event
conflicts, same-Thread concurrent joins and unchanged Call/Chat/IM behavior.
Verify `destination.number` survives `SaveToHistory` without changing its shared
column mapping, and that no Extra/slot fields were added to history. Verify
unvalidated CHECKs reject new invalid writes, validation is repeatable, and
ordinary writes can continue during validation. Capacity, Sticky and ordering
checks cover all implementation 4.1–4.3; no partial test run is rollout acceptance.

### Step 4.2 scenarios (component checks 4.4, full integration 7)

- Base-first, independent slot counts across two queues, and no promotion after
  base is freed. Lowering a limit below use retains assignments and prevents new
  assignments of that slot type until capacity returns.
- Base 0 / Extra 1: permitted priority-0 email can assign; priority-100 email
  without Extra permission cannot. Full Extra waits for Sticky; missing permission
  or zero configured Extra immediately cancels Sticky without a priority bump.
- Parallel assignments and changed agent/team/skills/preset/limits/channel:
  no overbooking, partial assignment or channel `state`/`attempt_id` mutation.
  Locked/changed attempts and candidates are skipped without hiding later work.
- R1/R2 without history lookup or priority changes; R3/R6 available assignment;
  R4/R7 full-slot waiting; R5 immediate priority-10 fallback by default; R8
  offline waiting only with Ignore status enabled and without an occupied slot.
- Safe Sticky parsing in preparation, assignment, head selection and effective
  routing through the same helper: missing/null, strings, booleans,
  arrays/objects, fractional numbers (1.5) and out-of-int32 numbers (1e10,
  -2147483649) return 30; 0/-1/-2147483648 normalize to no wait; 1/2147483647
  retain their value. A malformed queue payload must not roll back other queues.
- Default 30-second timeout, explicit 0/valid negative no-wait opportunity, stable
  persisted deadline after restart, closed calendar before start and after start,
  expiry, disabled Sticky, removed eligibility/configured slot, no repeated lookup.
- Replays and new events for an already active Thread preserve the original
  assignment/routing. Unknown slot types/partial-upgrade assignments fail closed.
- A blocked base-only letter does not hide a later Extra-enabled letter. Queue
  `free` is only informational; generic Call/Chat/IM CASE branches stay unchanged.
- Multiple `no_agent` rows for one queue count once in `no_agent_queues`, distinct
  queues count separately, and an assigned/no-agent mix in one queue still
  counts that queue once. The Go unit tests cover these and absent/invalid IDs.

### Step 4.3 scenarios (component checks 4.4, full integration 7)

- Competing queues with inverse queue/letter priorities, priority 0/100, FIFO
  ties and stable attempt-ID ties. Verify each agent sees the highest eligible
  work among its queues, including overlapping/disjoint agent skill sets.
- Pending R5/timeout and cancelled Sticky candidates beyond the upkeep batch:
  effective priority participates before storage is prepared; preparation and
  reselection do not assign a lower-priority head or leave duplicate side effects.
- R3/R6 with higher-priority general work for the same online Sticky candidate:
  priority/FIFO wins without a Sticky boost; the Sticky letter may reach timeout.
- Queue batch exhausted for the best letter: do not demote that agent to a
  lower-priority queue. Next cycle resumes after stored agent/queue cursors;
  no-agent/offline domains and locked heads do not indefinitely hide other work.
- Zero/negative Sticky no-wait candidate gets only the current cycle's immediate
  opportunity; repeated preparation in the same cycle does not expire it early,
  and the next transaction cannot keep extending that opportunity.
- Multi-node advisory lock, cursor initialization/rerun, cursor rollback on
  forced statement/lock timeout and cursor continuity after process restart.
- EXPLAIN on substantial base-only/Extra-enabled and Sticky backlogs, including
  no usable agents, many queues/domains and many eligible agents. Measure query
  scans, stable repeated timeout behavior and starvation before accepting rollout.
- Measure repeated `cc_email_agent_head` cost for agent visits, reselection and
  competing recipients across agents × queues × backlog, including 100+ online
  agents with dozens of queues. If caching is needed, invalidate every dependent
  head when its letter, capacity, fallback or availability changes; invalidating
  only the assignment recipient is insufficient. Recheck calendars under locks.
- Measure the fifth head branch over large Sticky backlogs: route/filter/sort
  can scan many rows before LIMIT 1. Optimize without dropping pending R5 or
  cancelled candidates from effective-priority comparison. Restricting it to
  expired deadlines alone changes behavior and needs separate approval.
- Measure maintenance threshold overruns and deferred queues across cycles;
  do not assume all fallback is prepared within one cycle. Verify cursor writes
  and rollback together with assignments, not durability of UNLOGGED attempts.
- Smoke generic Call/Chat/IM/Task with the actual compatible `cc_sql`; record
  the extension source/build/version and schema-copy adaptations explicitly.
