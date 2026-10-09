# call_center

## Inbound Email distribution

An Inbound Email Queue (queue type 11) receives email-service Threads through
`EmailJoinToQueue`, called by the `joinQueue` application of `flow_manager`. The
call creates a new `waiting` Email attempt (`channel = 'email'`) or returns the
existing active attempt of the Thread, which may already be assigned
(`offering`), and returns immediately. Agents are assigned later and
asynchronously by the Email allocator, which is separate from the generic
distribution of calls and chats.

### How emails are assigned

Every instance runs the allocator when `email_distribution` is enabled. Each
cycle calls `call_center.cc_email_distribute` in one short transaction; a
transaction-scoped advisory lock lets one instance work at a time, the others
skip the cycle. Per cycle a queue reads at most `email_distribution_queue_batch`
emails of its order and as many waiting for their agents, plus the sticky
upkeep below, through dedicated indexes, so a large backlog does not slow a
cycle down. As a safeguard, a cycle stops itself after half of its statement
timeout, checked between queues and their steps, and commits what it assigned;
the rest waits for the next cycle. A lock or statement timeout instead rolls the
whole cycle back. The allocator keeps no local state, so a restarted instance
only continues with the `waiting` attempts left in the database.

A queue assigns only while its calendar is open. A missing or invalid calendar,
or a queue without enabled skills, keeps its emails waiting and is logged as a
configuration error. Emails go High first, then oldest first; the queue
strategy is ignored.

An agent can take an email of the queue when the agent is:

- `online` with the `email` channel online, and `email` is in `allow_channels`;
- in the queue team, if the queue has one;
- holding a matching enabled skill within the capacity range of the queue, also
  allowed by the online skill preset of the agent, if any;
- below `email_count`, the agent limit of unfinished assigned emails. The
  default `0` keeps Email off for the agent.

Among them the agent with the fewest emails gets it, then the one whose last
email came earliest; within one cycle an agent gets a next email only after the
other agents with as many emails got theirs. Assignment moves the attempt to
`offering`, sets its agent and team and the `last_offering_at` of the agent
`email` channel; the channel state is not changed, because an agent can hold
several emails.

With `sticky_agent` enabled, a new email of a Thread goes to the last agent of
that Thread found in `cc_member_attempt_history`, within
`payload.email_sticky_history_sec` seconds (`0` or unset: the whole history).
The lookup is made once per email, by an open queue before it orders its emails;
an email with a previous agent gets High priority. It waits for that agent at
most `payload.sticky_agent_sec` seconds (30 by default) from the lookup, then
goes to any agent, still High. It never exceeds the limit of its agent and does
not wait for an agent that can no longer take emails of the queue.

While waiting, the email keeps its place among the High emails: it is assigned
only to its agent, and is passed over while that agent is offline or full. Per
cycle a queue looks up, ends waits for and moves at most 1 000 emails in each
step; while some are left for a next cycle, it assigns only High emails, so a
Normal email never goes before an email that may still turn out High.

### Configuration

| Flag | Environment | Default | Meaning |
|---|---|---|---|
| `email_distribution` | `EMAIL_DISTRIBUTION` | `false` | Run the Email allocator |
| `email_distribution_interval` | `EMAIL_DISTRIBUTION_INTERVAL` | `1s` | Pause between cycles |
| `email_distribution_queue_batch` | `EMAIL_DISTRIBUTION_QUEUE_BATCH` | `50` | Assignments per queue in one cycle |
| `email_distribution_lock_timeout` | `EMAIL_DISTRIBUTION_LOCK_TIMEOUT` | `1s` | `lock_timeout` of a cycle |
| `email_distribution_statement_timeout` | `EMAIL_DISTRIBUTION_STATEMENT_TIMEOUT` | `10s` | `statement_timeout` of a cycle |

Startup fails when the queue batch is not positive, a duration is below 1 ms or
the lock timeout is not below the statement timeout.

A cycle with assignments is logged at info level, other cycles at debug level,
with the numbers of assigned emails, blocked queues and the cycle latency. A
queue without enabled skills or with an invalid calendar and a cycle that
reached its time limit are logged as warnings, a failed cycle as an error with
its `outcome`: `lock_timeout`, `statement_timeout`, `context_timeout` or
`error`; each at most once in 5 minutes. After a failed cycle the pause is twice
the interval and doubles with each next failure up to 1 minute, or the interval
if it is longer, less up to 10% at random but never below the interval; it
returns to the interval after the next successful cycle. A skipped busy cycle
or a reached time limit is not a failure.

### Rollout and limits

1. Apply `store/sqlstore/migration/26.dev/email_agent_distribution.sql` with
   `psql -v ON_ERROR_STOP=1 -f` outside a transaction: it builds indexes
   `CONCURRENTLY` and can be repeated after a failure.
2. Release `engine` with the `email_count` field of agents.
3. Give the agents `email` in `allow_channels` and a positive `email_count`.
4. Enable `email_distribution` only where nothing depends on assigned emails
   being handled.

Keep the allocator off in production for now. An assigned email is not yet
announced to Workspace, cannot be opened or worked on through an API, and stays
with its agent after a timeout, logout or auto-offline.

`cc_member_attempt` is an unlogged table. A restart of `call_center` keeps the
attempts, but a crash or failover of PostgreSQL loses them, together with the
`waiting` and assigned emails; `cc_email_join` still refers to the lost attempts.
