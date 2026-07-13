# Director Ruling 66 — approve the Ruling 65 scheduler design

- Date: 2026-07-12
- Status: in force
- Decision owner: Director / Kevin
- Supersedes: none; ratifies the execution design required by Ruling 65
- Evidence reviewed: `decisions/SCHEDULER_HOME_R65_DESIGN.md`; Coach scheduler source and parity tests; legacy BSPC PRs 6 and 7 capture notes

## Decision

Approve all five decisions in the Ruling 65 design: `dailyDigest` executes as a
direct `pg_cron` PostgreSQL function; `sweepAttendanceEvaluations` executes as a
`pg_cron`-invoked Supabase Edge Function; `syncCalendar` remains dark pending a
feed-specific ruling; the shared `scheduler_runs` reliability foundation is
required; Edge Sentry ships with the first Edge implementation; and push
retry/DLQ remains a separate Family-train mission after scheduler rehome.

## Scope

This authorizes local and shadow-only implementation of the `scheduler_runs`
foundation, daily-digest SQL, attendance-sweep Edge Function, and sanitized Edge
Sentry coverage. The result must be dark-deployable with **zero schedule objects
created**. It does not authorize a staging or production schedule, secret write,
deployment, feed configuration, or production command.

## Consequences

- Preserve digest consent, local-time semantics, and one-run/one-recipient
  idempotency.
- Preserve attendance-evaluator parity and deterministic notification upserts.
- Implement leases, bounded retries, terminal dead state, sanitized
  observability, and rollback evidence in `scheduler_runs`.
- Keep `syncCalendar` absent from the active implementation and schedule set.
- Queue push retry/DLQ as the next separate Family mission after the Ruling 65
  implementation is reviewed and merged.
- Before any schedule object is created anywhere, verify `pg_cron` and `pg_net`
  availability on the throwaway/staging project and record the sanitized result
  in `decisions/SCHEDULER_HOME_R65_DESIGN.md`.

## Human gates

Kevin owns staging/production target authorization, Vault or secret creation,
schedule creation or activation, calendar-feed approval, and every production
command. Production schedule creation is per-command and may never be bundled
with a deploy, probe, migration apply, or another write.
