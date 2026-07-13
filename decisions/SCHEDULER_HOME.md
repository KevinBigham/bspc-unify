# Scheduler-home decision memo

- Date: 2026-07-12
- Status: awaiting Director/Kevin ruling
- Recommendation: keep the two launch schedulers on Firebase Functions for v1; do not export `syncCalendar`.

| Job | V1 recommendation | Evidence / tradeoff |
|---|---|---|
| `dailyDigest` | Firebase scheduled Function | Already reads canonical Supabase tables, honors `digest_enabled`, has parity tests, and is in the exact-two export surface. Rehoming adds launch risk without changing data ownership. |
| `sweepAttendanceEvaluations` | Firebase scheduled Function | Existing idempotent service logic and tests are mature; a SQL rewrite would duplicate business logic. |
| `syncCalendar` | Disabled/not exported | No approved production feed. Keep its merge/upsert tests as a follow-on proof, but never deploy a self-skipping placeholder. |

Consequences if approved: retain the minimum Firebase Functions config/runtime with a documented reason during #95; remove portal/media/callable exports; pin Node 22; provision only the exact scheduler secrets and deploy target through a Kevin-gated runbook. Revisit Supabase Edge Functions after launch when operational data justifies the move.

Alternatives rejected for v1: `pg_cron` would move application logic and service credentials into SQL/network extensions; scheduled Edge Functions are viable but create a new deployment/observability surface immediately before beta.
