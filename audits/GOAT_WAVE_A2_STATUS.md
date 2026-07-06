# GOAT Wave A2 Status - Meet-Day Command Center v1

Date: 2026-07-06
Status: COMPLETE with pgTAP blocked by unavailable local Docker

## Branches

- BSPC family app: `demo/expo-go-compat`
- Coach app: `demo/device-build`

## Premise Checks

- Coach meet surface found:
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/app/(tabs)/meets.tsx`
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/app/meet/[id].tsx`
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/app/meet/new.tsx`
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/src/services/meets.ts`
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/src/types/meet.types.ts`
- Phase G notification infrastructure found:
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/app/notification-rules.tsx`
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/src/services/notificationRules.ts`
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/src/services/notifications.ts`
  - `/Users/kevin/bspc-unify/BSPC-Coach-App/functions/src/notifications/evaluator.ts`
- Existing heat/entry model found in `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/migrations/00009_phase_h_calendar_meets_plans.sql`: `meet_entries` already carries swimmer/event/heat/lane fields, so Wave 2 added sessions/check-ins/warmups only.
- Notification family-target gap: existing Coach meet entries do not expose a family `targetUserId`. The route uses the closest Phase G primitive, `notification_jobs`, and skips intents without `targetUserId`. Delivery remains behind `MEET_ALERTS_ENABLED`, default OFF.

## Commits

- Coach app: `5a1b483 Add meet-day command center`
- BSPC family app: `dc45120 Add meet-day local schema`

## Files

- Coach command center UI: `/Users/kevin/bspc-unify/BSPC-Coach-App/src/components/MeetDayCommandCenter.tsx`
- Coach meet tab wiring: `/Users/kevin/bspc-unify/BSPC-Coach-App/app/meet/[id].tsx`
- Pure heats-out engine: `/Users/kevin/bspc-unify/BSPC-Coach-App/src/meet-day/heatsOut.ts`
- Meet-day services: `/Users/kevin/bspc-unify/BSPC-Coach-App/src/services/meetDay.ts`, `/Users/kevin/bspc-unify/BSPC-Coach-App/src/services/meetAlerts.ts`
- Tests: component, service, and pure-engine Jest tests under `/Users/kevin/bspc-unify/BSPC-Coach-App/src/**/__tests__/`
- Local-only migration: `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/migrations/00016_meet_day_command_center.sql`
- pgTAP coverage: `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/tests/database/016-meet-day-command-center.test.sql`
- Publication pins updated: `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/tests/database/011-notifications-walls.test.sql`, `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/tests/database/014-aggregation-views.test.sql`

## Verification

- Before Wave 2:
  - BSPC family app: `npm run typecheck && npm run lint && TZ=UTC npm test -- --runInBand` PASS, 120 suites / 864 tests / 10 snapshots.
  - Coach app inherited Wave 0 exit bar: `npm run typecheck && npm run lint:errors && npm test -- --runInBand` PASS, 117 suites / 1172 tests / 1 snapshot.
- Targeted Wave 2 Coach tests: `npm test -- --runInBand src/components/__tests__/MeetDayCommandCenter.test.tsx src/services/__tests__/meetDay.test.ts src/services/__tests__/meetAlerts.test.ts src/meet-day/__tests__/heatsOut.test.ts` PASS, 4 suites / 20 tests.
- After Wave 2, Coach app: `npm run typecheck && npm run lint:errors && npm test -- --runInBand` PASS, 121 suites / 1192 tests / 1 snapshot.
- After Wave 2, BSPC family app: `npm run typecheck && npm run lint && TZ=UTC npm test -- --runInBand` PASS, 120 suites / 864 tests / 10 snapshots.
- Functions tests: not run; functions were not touched.
- **pgTAP/RLS: SKIPPED LOUDLY.** `npm run test:rls` failed before tests executed with `LegacyDbConnectError` / failed local Postgres connection. Docker is unavailable: `docker info` cannot connect to `/Users/kevin/.colima/default/docker.sock` because the socket does not exist.

## Kevin-Gated Items

1. **First:** start local Docker/Colima and run `npm run test:rls` from `/Users/kevin/bspc-unify/BSPC/ACTIVE`.
2. Review and apply local migration `00016_meet_day_command_center.sql` only after the Tier 0 DB truth probe is complete.
3. Ratify the Wave 2 schema additions into `/Users/kevin/bspc-unify/BSPC/UNIFY/01_CANONICAL_SCHEMA.sql`.
4. Add/confirm the family target-user mapping for meet entries before alert delivery is enabled.
5. Create or confirm a Phase G custom rule with `config.kind = "meet_heats_out"`.
6. Enable `MEET_ALERTS_ENABLED` only after review, then run exactly one live delivery test.

## Hard-Rule Confirmation

- No pushes.
- No deploys.
- No production migrations.
- No Supabase dashboard operations.
- No EAS, Firebase, DNS, App Store, or Google Play actions.
- No new dependencies.
