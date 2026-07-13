# Ruling 65 scheduler design — proposed for Director decision

- Date: 2026-07-12
- Status: proposed; **no implementation authorized**
- Governing ruling: Director Ruling 65
- Goal: remove Firebase scheduling from the launch end state while preserving
  digest consent/parity, attendance-sweep idempotency, and calendar safety.

## Executive recommendation

Use Supabase Cron (`pg_cron`) as the one scheduling control plane, but choose
the execution home per job:

| Job | Schedule | Recommended execution home | Decision |
|---|---|---|---|
| `dailyDigest` | hourly dispatcher; execute once at 20:00 America/Chicago | PostgreSQL function called directly by `pg_cron` | **pg_cron SQL** |
| `sweepAttendanceEvaluations` | every 5 minutes | Supabase Edge Function invoked by `pg_cron` + `pg_net` | **scheduled Edge Function** |
| `syncCalendar` | disabled; eventual daily schedule only after feed approval | Supabase Edge Function invoked by `pg_cron` + `pg_net` | **Edge Function later, not launch-enabled** |

Supabase documents that Cron jobs may run SQL/database functions directly or
invoke an Edge Function over HTTP. Cron is backed by `pg_cron`, and run state is
recorded in `cron.job_run_details`. Supabase recommends no more than eight
concurrent jobs and ten minutes per job; this design has at most three jobs and
requires each run to stay well below those bounds.

Primary references:

- [Supabase Cron](https://supabase.com/docs/guides/cron)
- [Scheduling Edge Functions](https://supabase.com/docs/guides/functions/schedule-functions)
- [Securing service-to-service Edge Function calls](https://supabase.com/docs/guides/functions/auth)
- [`pg_net` behavior and response retention](https://supabase.com/docs/guides/database/extensions/pg_net)
- [Edge Function runtime limits](https://supabase.com/docs/guides/functions/limits)

## Why the jobs split

### `dailyDigest` — direct SQL

The current job is relational work only: count same-day attendance, notes, and
videos; enumerate staff from `profiles`; apply `notification_preferences` with
the existing missing-row-means-enabled rule; then insert one sanitized,
team-wide summary per recipient. Moving that logic into a `security definer`
PostgreSQL function removes a network hop and keeps consent selection adjacent
to the authoritative tables.

Required parity pins:

- recipients come from approved `coach_admin` and `super_admin` profiles, not
  preference rows;
- `digest_enabled = false` opts out, while a missing preference row remains
  enabled;
- attendance counts distinct swimmers for the local practice date and excludes
  absences;
- body data remains team-wide counts only—no swimmer names or note text;
- one logical digest per staff user per America/Chicago calendar day.

The current Firebase function assumes a single scheduler fire and permits
duplicates. The replacement must add a durable execution key such as
`daily_digest:<local-date>` and a recipient uniqueness key for that run. This
tightens operational safety without changing consent or message content.

Because Supabase Cron schedules are UTC-oriented, the cron dispatcher should
run hourly and let the SQL function compute `now() at time zone
'America/Chicago'`. It executes only when the local hour is 20 and the daily
execution key is absent. This avoids a fixed-UTC schedule drifting by one hour
across daylight-saving changes.

### `sweepAttendanceEvaluations` — scheduled Edge Function

The sweep's ten-minute window is simple SQL, but its evaluator is mature
TypeScript business logic shared with notification-rule tests. Rewriting that
evaluator in PL/pgSQL would create a second rules engine and an avoidable parity
risk. Port the callable core to a Supabase Edge Function, retain the existing
deterministic notification IDs/upserts, and invoke it every five minutes from
Cron through `pg_net`.

Required parity pins:

- select attendance created in the prior ten minutes;
- re-evaluation is safe at least once and produces no duplicate notification;
- batch size and runtime remain bounded below Edge Function limits;
- a retry sees the same deterministic result;
- no rule payload, swimmer identifier, or minor data enters logs or error
  telemetry.

The Edge Function should return only sanitized counts: inspected, evaluated,
created, unchanged, failed. The durable run ledger—not the HTTP response
body—is the operational source of truth.

### `syncCalendar` — Edge Function, held dark

Calendar sync fetches and parses an external ICS feed, so SQL is the wrong
execution surface. Its existing raw-UID upsert and non-destructive update rules
fit an Edge Function. However, Ruling 65 keeps this job disabled until Kevin
approves a real feed, its public-versus-secret classification, and the exact
schedule.

Before activation, the implementation must:

- bind the feed URL as a secret and never log it;
- redact remote response bodies and event identifiers;
- preserve coach-edited fields and never delete missing feed events;
- prove replay idempotency against the approved feed shape;
- cap fetch size, parse count, per-run work, and timeout;
- use the same durable run/attempt model as the attendance sweep.

No placeholder or self-skipping production schedule is proposed.

## Scheduler foundation

Implementation should introduce one small `scheduler_runs` table shared by all
three jobs:

- `job_name`, `scheduled_for`, and unique `execution_key`;
- `status`: `claimed`, `succeeded`, `retryable`, `dead`;
- `attempt_count`, `started_at`, `heartbeat_at`, `finished_at`;
- sanitized counters and `error_class` only—never raw messages or identifiers;
- optional `pg_net_request_id` for correlation, not as the durable record.

Claims must be atomic. A stale lease may be reclaimed after a documented
timeout. Each job defines a bounded maximum attempt count and exponential
backoff. A terminal `dead` row is visible to the admin/ops query and alerting
path; it is never silently marked successful.

`cron.job_run_details` proves that Cron launched work, while `scheduler_runs`
proves application completion. This distinction matters because `pg_net`
queues requests only after transaction commit, keeps response records for a
limited period by default, and uses unlogged internal request/response tables.

## Secrets and authorization

For Edge Function invocations:

1. Create a dedicated named Supabase secret key for scheduler automation.
2. Store the project URL and that key in Supabase Vault through a separately
   authorized, target-printed operation; never put values in migrations.
3. Have `pg_cron` read the named Vault secrets and call `net.http_post`.
4. Configure each scheduler Edge Function for service-to-service secret auth,
   accepting only the dedicated automation key.
5. Use the platform-provided privileged Supabase client inside the function;
   never accept a user JWT for scheduler endpoints.

Repository SQL may reference Vault secret names only. Production creation,
rotation, and schedule activation are separate Kevin-gated commands.

## Observability and alerts

- Dashboard: latest `scheduler_runs` per job, age since success, retry count,
  and dead-run count.
- Logs: job name, execution key hash, attempt, duration, and count-only result.
- Alert: no success beyond two expected intervals, any dead run, or repeated
  authentication/timeout failures.
- Retention: keep sanitized run metadata long enough to cover launch review;
  never persist raw exception payloads, feed URLs, notification bodies, or IDs.

### Captured candidate scope: Edge Function Sentry coverage (legacy BSPC #6)

Preserve the concept of backend exception capture when scheduler code moves to
Supabase Edge Functions. The implementation candidate is a small shared
PII-scrubbing wrapper that tags only environment, function name, job name,
execution-key hash, and error class before forwarding unexpected failures to a
separate backend Sentry project. It should fold into the first Edge scheduler
implementation because an unobserved new runtime is not launch-ready. This does
not revive the stale Firebase shim or authorize a DSN deployment; secrets and
live telemetry remain separately gated.

### Captured candidate scope: push retry/DLQ (legacy BSPC #7)

Preserve the proposed exponential retry, bounded attempts, dead-letter state,
dead-token handling, and admin replay concepts for `notification_jobs`.
Scheduler invocation reliability **does** fold into Ruling 65 through
`scheduler_runs`, leases, retries, and terminal `dead` state. Push-delivery
retry/DLQ **does not** fold into the scheduler rehome implementation: it is a
separate Family notification-delivery state machine with different duplication
and per-token semantics. Carry it as a candidate follow-on after the scheduler
home is settled; do not mix its schema/admin UI into the first rehome PR.

## Rollout and rollback

1. Merge this design only after Director ruling.
2. Implement the run ledger and `dailyDigest` SQL with pgTAP; keep schedules
   absent.
3. Implement the attendance Edge Function with parity fixtures and local
   invocation tests; keep schedules absent.
4. In staging, create Vault secrets and schedules via separately authorized
   commands, then prove expected counts, consent, idempotency, retries, and
   alerting.
5. Disable the matching Firebase schedule before enabling its Supabase
   replacement. Never intentionally dual-run without the execution-key proof.
6. Observe at least the Director-approved window, then remove the Firebase
   scheduler exports/runtime/config in its own protected Coach mission.
7. Rollback by unscheduling the named Cron job. Preserve run rows and code for
   investigation; do not delete evidence during rollback.

`syncCalendar` follows a later, separate activation path after feed approval.

## Director decisions requested

1. Ratify direct SQL for `dailyDigest` and an Edge Function for
   `sweepAttendanceEvaluations`.
2. Ratify the shared `scheduler_runs` reliability foundation.
3. Ratify Edge Sentry coverage as required scope of the first Edge scheduler
   implementation, with live DSN configuration still separately gated.
4. Ratify push retry/DLQ as a preserved but separate Family follow-on.
5. Keep `syncCalendar` dark pending a feed-specific ruling.

No code, migration, secret, schedule, deploy, or production command is
authorized by this document.
