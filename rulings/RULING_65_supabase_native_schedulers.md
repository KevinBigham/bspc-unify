# Director Ruling 65 — schedulers must be Supabase-native

- Date: 2026-07-12
- Status: in force
- Decision owner: Director / Kevin
- Supersedes: the Firebase-v1 recommendation in `decisions/SCHEDULER_HOME.md`
- Evidence reviewed: `decisions/SCHEDULER_HOME.md`; Coach Functions launch export and scheduler tests

## Decision

The scheduler home is SUPABASE-NATIVE. No new or continuing Firebase scheduler dependency may be treated as the launch end state. `syncCalendar` remains disabled until it has an approved feed and Supabase-native schedule.

## Scope

This rejects the existing memo recommendation. It authorizes a replacement design mission for `dailyDigest` and `sweepAttendanceEvaluations`; it does not authorize an unreviewed rewrite or production deployment.

## Consequences

The replacement must preserve digest consent/parity and sweep idempotency, define secrets/observability/rollback, and remove the Firebase scheduler blocker before M8 closes. The disagreement was surfaced before scheduler implementation, as required.

## Human gates

Kevin must review the replacement design and merge each protected-branch mission; production scheduling and secret configuration remain separately authorized operations.
