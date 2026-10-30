# Email routing schema upgrade

## EM-24 status-sync upgrade

Use a matching five-array `cc_sql` 1.5 binary and the SQL files from this EM-24
release. Stop Email writers on all nodes and keep distribution, lifecycle and
snapshot publisher flags off throughout the upgrade.

1. From an EM-21 database, resolve the extension/catalog prerequisite below,
   then follow shared prepare → validate → runtime → lifecycle. From adapted
   EM-23 with those prerequisites present, start at step 2; do not reapply the
   shared files over lifecycle.
2. Apply `email_status_sync.sql` with `ON_ERROR_STOP`, outside an enclosing
   transaction. Its initial guard checks the matching extension and adapted
   lifecycle before DDL. It preserves agent/Email-channel locks and metrics on
   wake-up, adds the Thread lock and fallback queue, and keeps snapshot v1.
3. Apply `email_route.sql` after `email_service_inbox.sql`. Its Inbox CHECK accepts
   nonnegative int32 priority; pending/fallback defaults and frozen Flow intents
   remain unchanged. The route-parameter CHECK is added NOT VALID, then validated
   in a separate statement after the DDL commits. Other existing CHECKs still
   validate inline. Both files use CONCURRENTLY indexes and must not be wrapped
   in another transaction.
4. Deploy email-service with the compatible snapshot consumer first, engine with
   Email limits, then every call_center node with its flags off, then Flow.
   Flow needs both the widened SQL range and the fallback-aware wake-up API.
5. Enable distribution/lifecycle only after release verification and enable the
   snapshot publisher last. Until then its rows stay in the outbox.

Repeat only the EM-24 files over a completed EM-24 schema; lifecycle and earlier
shared/routing files would restore older definitions and are rejected or forbidden.
An old EM-23/EM-24 database without the shared prerequisites needs a separately
reviewed upgrade to preserve its data, or an isolated development rebuild. Keep
writers stopped after a partial failure; these migrations are not atomic overall.

## EM-24 overrides

`cc_email_join_to_queue(uuid, bigint, bigint, integer, integer, integer, boolean, text)`
keeps its four result columns and accepts nonnegative int32 priority. Join and
wake-up take the same Thread advisory lock `(1162690900, hashtext(domain:thread))`
before reserving their event. Replays return the stored result and route values.

`cc_email_wakeup_thread(uuid, bigint, bigint)` returns `wakeup_result`,
`wakeup_attempt_id`, `wakeup_attempt_state`, `wakeup_attempt_version`,
`wakeup_replayed`, `wakeup_fallback_queue_id`. A `not_active` wake-up records one
`inbound_reopened` marker and the last finished queue; replay keeps both. Active
attempts keep the EM-23 slot/metric rules, including processing rechecks.

`cc_email_attempt_snapshot` keeps its signature and fixes `agent_user_id` when
writing the outbox row. Snapshot v1, projection version, publisher leases and
confirmed-delivery/retry semantics stay unchanged. The Inbox stores priority,
Sticky, Extra permission and initial From once; route retries use those values.

## EM-23 shared distributor upgrade

For an upgrade from EM-21, after resolving the extension source state below:

1. Stop Email writers on all nodes and keep distribution/lifecycle flags off.
2. Install the matching `cc_sql` 1.5 binary and version SQL atomically, reconnect
   callers, then update the extension in a fresh connection as described below.
3. Apply shared prepare, validate and runtime from this release in that
   order. The original EM-21 files target the previous three-array interface.
4. Apply `store/sqlstore/migration/26.dev/email_attempt_lifecycle.sql` with
   `ON_ERROR_STOP` outside an enclosing transaction. It contains CONCURRENTLY
   indexes and generated gexec commands; on failure keep writers stopped.
5. Continue with status-sync/route migrations above before deploying the complete
   EM-24 release and enabling its flags.

Lifecycle checks the shared objects, validated priority CHECK and old-allocator
cleanup before DDL. It adds only EM-23 changes and can be repeated with those
prerequisites present. It replaces each three-argument apply/try_assign entry
without CASCADE in its own transaction with one five-argument function; defaults
preserve calls with three arguments. The lifecycle migration is maintained only
in call_center.

An older EM-23 database without the shared prerequisites is rejected. Do not
run EM-21 prepare/runtime over it: use an isolated clean rebuild for development,
or a separately reviewed upgrade if its data must be kept. Unadapted EM-24 is
also rejected; do not remove the guard. Never replay EM-21 files after lifecycle.

## Shared distributor upgrade

Use the files from this release. Identify the source extension/catalog first:

- `cc_sql` 1.4: install the matching binary and version SQL, reconnect callers,
  then update to 1.5 before shared preparation.
- `cc_sql` 1.5 with the old three-array Email signature: use a separately reviewed
  schema conversion or an isolated development rebuild. Updating 1.5 to itself
  does not replace its catalog entry.
- `cc_sql` 1.5 with the five-array signature: verify the matching binary and
  catalog prerequisites; no extension version update is needed.

Order for an existing EM-21 database starting with `cc_sql` 1.4:

| # | Step | Notes |
|---|---|---|
| 1 | Install `cc_sql` 1.5: binary, control file, version SQL | Every PostgreSQL server of the database; see atomic replacement below |
| 2 | `ALTER EXTENSION cc_sql UPDATE TO '1.5'` | In a fresh connection; registers `cc_sys_distribute_email` |
| 3 | `email_shared_distributor_prepare.sql` | Own transaction |
| 4 | `email_shared_distributor_validate.sql` | After step 3 commits, outside a transaction |
| 5 | `email_shared_distributor_runtime.sql` | Last; own transaction |
| 6 | Complete the target release's SQL before deploying services | EM-24 also needs lifecycle → status sync → Inbox/route; then deploy `call_center` before `flow_manager` |

- Before step 1 stop Email writers on all nodes and keep `email_distribution`
  off. The starting schema must contain the release generic SQL and the EM-21
  prerequisites: routing update, its validation and the address indexes.
- Files are in `store/sqlstore/migration/26.dev/`; the extension repository keeps
  identical copies in `webitel/migration/email/`. Apply one copy with
  `psql -v ON_ERROR_STOP=1 -f`.
- Prepare and runtime reject a schema with EM-23/EM-24 objects; such a database
  needs the adapted release.
- Runtime checks the extension-owned five-array Email signature of `cc_sql` 1.5
  and the prepared objects, including `cc_email_pair_available`, then replaces
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
The matching `flow-schema.sql` contains the final Inbox/route model; do not
replay historical Inbox migrations over a clean full-schema installation.

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
  `webitel/reusable-configs` (`clang/workflows/postgres/extension.yml.njk`).
  The current generated list includes both 1.4↔1.5 scripts; verify that the
  upstream template preserves them before the next file-sync.
- Restart, concurrency, performance and other-channel regression checks remain
  release gates. Verify the final five-array interface on the target PostgreSQL,
  TimescaleDB and binary build; historical smoke is not acceptance of this release.

## EM-21 prerequisites

For an existing database that predates the routing update, apply the existing
Email prerequisites in order: `email_queue_join.sql`,
`email_agent_distribution.sql`, `email_routing_update.sql`,
`email_routing_validate.sql`, then `email_last_bridged_indexes.sql`. Skip files
already completed; never replay this baseline over lifecycle or status sync.
All paths are relative to `store/sqlstore/migration/26.dev/`. Use psql with
`ON_ERROR_STOP`, outside an enclosing transaction; the validation follows the
routing DDL commit and index maintenance uses CONCURRENTLY and psql gexec.

The first routing update refuses existing Email attempts when adding the slot
model, including leaving rows not yet archived. Stop Email writers on all nodes,
back up the database and inspect this prerequisite before applying it. Do not
bypass the guard or delete attempts: their join/wake-up journals, outbox and
projection must stay consistent. Preserving such attempts requires a separately
reviewed conversion. Existing limits, history and journal results are retained.

For address indexes, inspect existing definitions as well as validity/readiness:
IF NOT EXISTS does not verify their shape. Serialize index maintenance and rerun
the index file after resolving a failed concurrent build.

## Clean Online prerequisite

The full schema retains the known legacy Online problem: the five-argument
`cc_set_agent_online` calls a nonexistent four-argument `cc_agent_set_login`,
and login definitions still refer to the old `skill_preset`. Matching definitions
exist in `26.08/1.sql`, but that migration also contains unrelated changes and
must not be applied wholesale as an Email fix. Resolve the discrepancy separately
before clean rollout. This transition leaves those functions unchanged.
