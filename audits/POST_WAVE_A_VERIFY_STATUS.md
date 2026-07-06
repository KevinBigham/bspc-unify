# Post-Wave A Verify Status

Date: 2026-07-06
Status: COMPLETE, local-only

## Scope

This pass closed the post-Wave A local verification gaps without touching production.

- Restored the local Supabase/pgTAP bar after Docker/Colima became available.
- Added a local grant-closure migration so pgTAP exercises RLS policies instead of dying at table/function privilege gates.
- Wrote the Kevin-gated production truth-probe script.
- Replaced tracked demo-account credentials with runtime `${DEMO_*}` placeholders across the active family app docs, Maestro flows, and seed comments.

No pushes, deploys, production migrations, live dashboard operations, EAS/Firebase/DNS/App Store/Google Play actions, or live prod probes were performed.

## Files Added

- `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/migrations/00017_app_role_rls_grants.sql`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/scripts/audit-prod-schema.ts`

## Key Local Fix

`00017_app_role_rls_grants.sql` grants app-role table privileges for RLS-enabled public tables:

- `authenticated`: `SELECT`, `INSERT`, `UPDATE`, `DELETE`
- `anon`: `SELECT` only, so anon policy tests return zero rows instead of permission errors
- `attendance_check_in(...)`: `EXECUTE` for `authenticated` and `service_role`, while `anon` remains denied

Views remain explicitly granted per view, preserving the parent-view and aggregation-view contracts.

## Why 00017 Was Needed

Postgres table privileges and RLS policies are two separate gates: RLS can only answer after the role is allowed to run the statement at all.
The existing migrations defined the row-level walls but left app roles without ordinary `SELECT`/write privileges on RLS-protected public tables, so pgTAP hit `permission denied` before it could prove the policies.
`00017_app_role_rls_grants.sql` closes that privilege gap by giving `authenticated` the app DML surface, giving `anon` read access that still resolves to zero rows through policy denial, and restoring the intended authenticated execute grant for `attendance_check_in`.
Without it, local RLS verification would stay red, the new `016` meet-day suite would abort before policy checks, and production clients using the same roles would risk hard permission failures instead of clean RLS-governed behavior.

## Prod Truth Probe

`scripts/audit-prod-schema.ts` was written but not run.

It refuses to execute unless `CONFIRM_PROD_SCHEMA_AUDIT=go` is set. It uses an env-provided Postgres connection and emits a sanitized JSON report covering:

- migration ledger vs local migration files
- `handle_new_user()` strict/tolerant fingerprint
- RLS enabled state for public tables
- storage bucket inventory, including `meet-schedule-photos`
- auth users without profile rows, count plus hashed samples only
- configured throwaway user existence only, with no email/PII output

## Credential Hygiene

The active family app tree no longer contains the scanned raw demo-account tokens in:

- `/Users/kevin/bspc-unify/BSPC/CLAUDE.md`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/docs/*.md`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/.maestro/*.yaml`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/seed.sql` comments

Maestro now reads:

- `${DEMO_FAMILY_EMAIL}`
- `${DEMO_FAMILY_PASSWORD}`
- `${DEMO_ADMIN_EMAIL}`
- `${DEMO_ADMIN_PASSWORD}`

Live rotation/disablement remains Kevin-gated and was not performed.

## Measured Bars

### BSPC Family App

Before local grant fix:

| Command | Result |
| --- | --- |
| `npm run test:rls` | FAIL, `Files=16, Tests=157, Result: FAIL`; table privileges blocked RLS assertions and `016` aborted early |
| `npm run test:rls` after table grants only | FAIL, `Files=16, Tests=358, Result: FAIL`; `007` exposed missing `attendance_check_in` execute grant; `016` passed |

After local grant fix and hygiene/script edits:

| Command | Result |
| --- | --- |
| `npm run typecheck` | PASS |
| `npm run lint` | PASS |
| `npm run test:rls` | PASS, `Files=16, Tests=377, Result: PASS`; includes `016-meet-day-command-center.test.sql` |

### Coach App

No Coach app files were touched in this post-verify pass, so no new Coach bar was run. The inherited Wave A final bar remains the last measured Coach result: `npm run typecheck && npm run lint:errors && npm test -- --runInBand` PASS, `123` suites / `1199` tests / `1` snapshot.

## Kevin-Gated Checklist

1. Review `00017_app_role_rls_grants.sql` before any live schema application.
2. Run the prod truth probe only after explicitly saying `go`, inspect the sanitized JSON for secrets/PII before copying any result into `UNIFY/NOTES.md`.
3. Run the live demo-account rotation/disablement separately; this pass changed tracked files only.
4. Provide `${DEMO_*}` env values from an untracked shell/env source before running Maestro.
5. Delete the live throwaway test user only after the truth probe confirms its state.
6. Apply/reconcile live migrations only after the truth probe and Kevin review; this pass performed no production migration.
7. Push or open PRs only after explicit Kevin instruction; this pass performed no GitHub write.
