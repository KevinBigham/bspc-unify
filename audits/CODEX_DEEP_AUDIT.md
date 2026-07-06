# Codex Deep Audit

Last updated: 2026-07-05

## 1. Executive Summary

This repository is a launch workspace for a two-app Blue Springs Power Cats swim-club product. It contains three independent Git repos under one folder: `UNIFY` for source-of-truth docs/schema, `BSPC` for the family mobile app and Supabase backend, and `BSPC-Coach-App` for the coach app, parent portal, and Firebase Functions. Evidence: `UNIFY/Mission.md:44-57`.

The highest-confidence launch blocker is password recovery. The BSPC family app can request a reset email, but no code path found consumes a Supabase recovery deep link, establishes a recovery session, lets the user set a new password, or calls `supabase.auth.updateUser({ password })`. Evidence: `BSPC/ACTIVE/features/auth/components/ResetPasswordScreen.tsx:13-108`, `BSPC/ACTIVE/features/auth/api.ts:39-42`, `BSPC/ACTIVE/lib/supabase/client.ts:43-49`.

The second major issue is branch/schema truth. `BSPC` is checked out on `demo/expo-go-compat`, which has 15 migrations including BSHS and a new meet-schedule-photo bucket, while `BSPC/main` remains at `880aed8` and `UNIFY/01_CANONICAL_SCHEMA.sql` still defines only the older 8-value practice-group enum. Evidence: `UNIFY/01_CANONICAL_SCHEMA.sql:82-83`, `BSPC/ACTIVE/supabase/migrations/00014_phase_k_add_bshs_group.sql:1-15`, `BSPC/ACTIVE/supabase/migrations/00015_meet_schedule_photo_bucket.sql:1-21`.

Local verification is mixed: BSPC family app typecheck/lint/Jest passed, but release preflight failed; Coach app Jest/lint/functions/portal checks passed, but root typecheck and dead-code gates failed.

## 2. What This Project Is Trying To Become

The product is a fresh Supabase launch for families and coaches, not a Firebase migration. `UNIFY/Mission.md:9-12` says the goal is to move from code-complete/local-green to App Store and Google Play while safely serving families with minor children, and that legacy Firebase data migration is cancelled.

The three surfaces are:

- Family app: `BSPC/ACTIVE`, Expo/RN, family-facing information and limited admin tools.
- Coach app: `BSPC-Coach-App`, Expo/RN, coach write tools.
- Parent portal: `BSPC-Coach-App/parent-portal`, Next.js.

The shared backend is intended to be one Supabase/Postgres backend. Evidence: `UNIFY/Mission.md:46-57`.

## 3. Current Architecture

Current architecture is split across three repos:

- `UNIFY`: governance, canonical SQL, runbooks, launch docs.
- `BSPC/ACTIVE`: Expo family app, Supabase migrations/functions/tests.
- `BSPC-Coach-App`: Expo coach app, Firebase Functions, Next parent portal.

The family app Supabase client uses `expo-secure-store` on native and `localStorage` on web, with persisted auth sessions and URL-session detection disabled. Evidence: `BSPC/ACTIVE/lib/supabase/client.ts:1-49`.

The Coach app and portal are now Supabase clients too:

- Coach mobile client: `BSPC-Coach-App/src/config/supabase.ts:1-20`.
- Coach Functions service-role client: `BSPC-Coach-App/functions/src/config/supabase.ts:1-11`.
- Parent portal client: `BSPC-Coach-App/parent-portal/src/lib/supabase.ts:1-9`.

Coach Functions are still Firebase Functions v2. Exports include media processing, stuck-session sweeps, attendance evaluation, daily digest, invite redemption, parent portal data, calendar sync, and meet-schedule extraction. Evidence: `BSPC-Coach-App/functions/src/index.ts:15-28`.

## 4. File/Folder Map

Top-level audited counts excluding `.git`, `node_modules`, and package locks:

- `UNIFY`: 28 files.
- `BSPC`: 431 files.
- `BSPC-Coach-App`: 550 files.

Important current paths:

- `UNIFY/01_CANONICAL_SCHEMA.sql`: canonical schema doc, but not fully current with active branch.
- `BSPC/ACTIVE/supabase/migrations`: 15 migration files on active branch.
- `BSPC/ACTIVE/supabase/tests/database`: 15 pgTAP files.
- `BSPC-Coach-App/functions/src`: Firebase Functions source.
- `BSPC-Coach-App/parent-portal/src`: parent portal.

Largest/high-attention source artifacts include `UNIFY/NOTES.md`, `UNIFY/01_CANONICAL_SCHEMA.sql`, `BSPC-Coach-App/app/swimmer/[id].tsx`, `BSPC-Coach-App/functions/src/ai/swimKnowledge.ts`, and `BSPC/ACTIVE/supabase/tests/database/*.sql`.

## 5. Main Data Flows

Auth/session:

- Family app signs users in/up through `features/auth/api.ts`. Evidence: `BSPC/ACTIVE/features/auth/api.ts:9-42`.
- Profile lookup reads `profiles` by `user_id`. Evidence: `BSPC/ACTIVE/features/auth/api.ts:44-56`.
- App initialization listens for Supabase auth state and fetches profile. Evidence: `BSPC/ACTIVE/lib/hooks/useAppInitialization.ts:34-55`.

Password reset:

- Family app requests a reset email and shows "Check Your Email"; no set-password flow exists in the inspected code. Evidence: `BSPC/ACTIVE/features/auth/components/ResetPasswordScreen.tsx:19-49`.

Admin approval:

- Family app admin flow fetches pending profiles and client-side creates family, approves profile, and inserts swimmers. The code comments say this should be an Edge Function in production but currently works through RLS. Evidence: `BSPC/ACTIVE/features/admin/api.ts:46-96`.

Coach invite flow:

- Coach creates parent invite rows in Supabase. Evidence: `BSPC-Coach-App/src/services/parentInvites.ts:60-88`.
- Redemption is server-side through Firebase callable `redeemInvite`, which calls Postgres RPC `redeem_parent_invite`. Evidence: `BSPC-Coach-App/functions/src/callable/redeemInvite.ts:14-68`.

Scheduler/Functions:

- Coach `dailyDigest` writes in-app notification rows from Postgres counts. Evidence: `BSPC-Coach-App/functions/src/scheduled/dailyDigest.ts:15-84`.
- `syncCalendar` is still a Firebase scheduled function and reads `CALENDAR_ICS_URL` from env. Evidence: `BSPC-Coach-App/functions/src/scheduled/syncCalendar.ts:34-73`.

## 6. Best Existing Strengths

- Strong test density: local Jest passed for BSPC family app, Coach app, and Coach Functions.
- RLS/pgTAP investment exists: 15 database test files under `BSPC/ACTIVE/supabase/tests/database`.
- Clear governance docs exist in `UNIFY`, especially Mission and runbooks.
- The apps are moving toward API abstraction boundaries: family auth/admin calls are centralized in `features/*/api.ts`, and Coach services route through Supabase service modules.
- Parent portal production build passes and is small enough to reason about quickly.

## 7. Biggest Risks And Weaknesses

1. **Password recovery is not launch-ready.** This is directly called out as required by `UNIFY/Mission.md:213-219` and unfinished by `UNIFY/CODEX_HANDOFF_auth_email.md:132-136`.

2. **Branch truth is unclear.** `UNIFY/Mission.md:89-97` describes older branch states, but current repo state is `BSPC/demo/expo-go-compat` and `BSPC-Coach-App/demo/device-build`, both ahead of their `main` branches.

3. **Schema truth is split.** `UNIFY/01_CANONICAL_SCHEMA.sql:82-83` has 8 practice groups; active app constants and migration `00014` have BSHS.

4. **Credential/demo hygiene needs active handling.** Tracked files contain demo account credentials and a Coach EAS device profile contains Supabase client values. Values are intentionally omitted from this report.

5. **Coach root typecheck is red.** This blocks treating `demo/device-build` as a clean release branch even though runtime Jest suites pass.

## 8. Bugs Or Likely Bugs

### Password Reset Cannot Complete

The reset screen only asks for email and sends the request. `resetPasswordForEmail` is called without a redirect target, the Supabase client disables URL-session detection, and no searched implementation handles recovery tokens or password update. Evidence: `BSPC/ACTIVE/features/auth/components/ResetPasswordScreen.tsx:19-49`, `BSPC/ACTIVE/features/auth/api.ts:39-42`, `BSPC/ACTIVE/lib/supabase/client.ts:48`.

Impact: users can receive reset emails but likely cannot complete "tap link -> set new password" on device.

### Coach Root Typecheck Failures

`npm run typecheck` in `BSPC-Coach-App` failed with 102 TypeScript errors. First failures include missing `subscribeToGroupTopics`, references to `User.uid`/`User.displayName` after Supabase auth migration, missing Firebase modules in legacy scripts, and many test mock typing issues.

Impact: branch is not TypeScript-clean even though Jest passes.

### Release Preflight Fails

`npm run release:check:staging` in `BSPC/ACTIVE` fails on missing env/config and placeholder metadata. The checker enforces required env keys and public metadata. Evidence: `BSPC/ACTIVE/scripts/release-check.js:4-10`, `BSPC/ACTIVE/scripts/release-check.js:86-120`, `BSPC/ACTIVE/app.json:43-50`, `BSPC/ACTIVE/docs/app-store-metadata.md:101-105`, `BSPC/ACTIVE/docs/privacy-policy.md:147-154`.

## 9. Missing Tests Or Validation Gaps

- No test found for Supabase password-recovery link consumption or password update.
- `BSPC/ACTIVE/__tests__/features/auth/ResetPasswordScreen.test.tsx` only covers render, disabled state, success after `resetPassword`, and error display.
- pgTAP/RLS was not run in this audit because Docker was unavailable, despite the 15 database tests existing.
- No live/device test was run for `bspc-swim://reset-password`.
- No live verification of Supabase Auth URL configuration was performed.

## 10. Security/Privacy Concerns

- Demo account credentials are present in tracked BSPC docs and Maestro flows. Evidence: `BSPC/CLAUDE.md:280-282`, `BSPC/ACTIVE/docs/launch-runbook.md:67-68`, `BSPC/ACTIVE/.maestro/demo-account-smoke.yaml:12-14`. Raw values are not copied here.
- `BSPC-Coach-App/eas.json:15-20` has a `device-demo` profile with Supabase URL and publishable key values. Publishable keys are client-side by design, but committing a live production-intended project reference plus demo credentials raises abuse risk if RLS or auth states are wrong.
- `BSPC-Coach-App/functions/src/config/supabase.ts:8-11` has placeholder fallback config for service-role client. Existing branch `proposal-b-config-hardening` contains a safer lazy/fail-closed param/secret pattern.
- Privacy policy still contains placeholder contact email according to release preflight. Evidence: `BSPC/ACTIVE/docs/privacy-policy.md:147-154`.

## 11. Performance Concerns

- No performance benchmarks were run.
- React Native apps rely on local query caching and many subscription patterns; no obvious hot path was deeply profiled.
- `BSPC-Coach-App/functions/src/https/extractMeetSchedule.ts:18-19` allows a large base64 payload (~15MB raw inflated), and runs Vertex AI work with 512MiB/120s. This is intentional for schedule-photo extraction but should be monitored for cost/timeouts if used heavily.

## 12. UX/Product Concerns

- Password recovery is a dead-end UX until a set-password screen exists.
- Parent invite redemption is implemented server-side in Coach Functions, but the BSPC family app route map has no invite/redeem route under `BSPC/ACTIVE/app`. Evidence: file map under `BSPC/ACTIVE/app` has auth/tabs/admin/content screens only.
- App Store metadata still has placeholder Privacy Policy and Support URLs. Evidence: `BSPC/ACTIVE/docs/app-store-metadata.md:101-105`.
- BSPC metadata says "View all 7 practice groups" while current constants include 9 groups including Masters, Swim Lessons, and BSHS. Evidence: `BSPC/ACTIVE/docs/app-store-metadata.md:25-27`, `BSPC/ACTIVE/constants/practice-groups.ts:12-14`.

## 13. Code Quality Concerns

- Coach root typecheck failure is the largest code-quality issue.
- Coach dead-code check fails:
  - unused file `src/components/charts/AttendanceHeatmap.tsx`;
  - unlisted `firebase/app` dependency used by legacy scripts;
  - unused exported types in `aiDrafts`, `meetScheduleExtraction`, and `notifications`.
- Coach app services retain several transitional comments and legacy compatibility parameters. That is understandable during migration but increases review burden.
- BSPC admin approval path comments say production should use an Edge Function, but the current client performs multi-step writes directly. Evidence: `BSPC/ACTIVE/features/admin/api.ts:46-96`.

## 14. Dependency/Configuration Concerns

- Node runtime used in this audit was `v24.16.0`, while docs/CI expect Node 20. Local pass/fail results should be rechecked under Node 20 before release.
- Coach dead-code check reports unlisted Firebase dependencies for `scripts/create-coach.ts` and `scripts/seed-calendar.ts`.
- `BSPC/ACTIVE/supabase/config.toml:8-10` lists only `schema_paths = ["./migrations/00001_initial_schema.sql"]` even though active branch has 15 migration files. This may be harmless local config, but it is a drift smell and should be reviewed before relying on generated schema operations.
- Coach parent portal lint uses deprecated `next lint` and warns the Next plugin is not detected.

## 15. Git/Branch/Release Risks

- Workspace root is not a Git repo; audit docs live outside the three nested repos.
- `UNIFY` is on `main...origin/main` with untracked auth handoff docs and stale `.git/index.lock`.
- `BSPC` active branch is `demo/expo-go-compat`, while `main`/`origin/main` remain at `880aed8`.
- `BSPC-Coach-App` active branch is `demo/device-build`, while `main`/`origin/main` are at `ba71612`.
- `UNIFY/Mission.md:89-97` describes older branch/head expectations, so it should not be treated as current Git truth without reconciliation.
- Release workflows exist for BSPC and Coach, but local release preflight is red for BSPC.

## 16. Highest-Leverage Improvements

1. Implement and test Supabase password recovery deep-link handling in `BSPC/ACTIVE`.
2. Decide launch branches and reconcile `UNIFY` docs/schema with active branch migrations.
3. Remove/rotate documented demo credentials if live.
4. Port or apply Coach Proposal B config hardening to remove placeholder service-role fallbacks.
5. Fix Coach root TypeScript errors and dead-code gate.

## 17. Quick Wins

- Delete or refresh stale `UNIFY/.git/index.lock` when doing Git work in `UNIFY` (not done by this audit).
- Commit or intentionally discard the two untracked UNIFY auth handoff docs after review.
- Replace BSPC App Store metadata placeholder URLs and privacy contact placeholder.
- Update metadata copy from "7 practice groups" to current group count if BSHS/Swim Lessons/Masters are launch truth.
- Add `EXPO_PUBLIC_CLOUD_FUNCTIONS_BASE_URL` to Coach env docs or decide the meet-schedule extraction endpoint is not launch-bound.

## 18. Medium-Term Upgrades

- Move BSPC admin family approval to an Edge Function or RPC with transaction/rollback semantics, matching the code comment.
- Add a schema drift check comparing `UNIFY/01_CANONICAL_SCHEMA.sql` and actual migrations.
- Add a "no live demo credentials in tracked docs" check.
- Run pgTAP in CI or document the exact local Docker/Supabase requirement.
- Decide whether Coach Firebase scheduled jobs should remain or be rehomed.

## 19. Long-Term GOAT-Level Evolution

- Treat `UNIFY` as a living generated source of truth: canonical schema, migration inventory, app constants, runbooks, and tests should be mechanically checked for drift.
- Build an end-to-end launch gate that combines app typecheck/lint/Jest, pgTAP, release metadata, EAS config, Supabase function config, and credential hygiene.
- Replace broad docs with status dashboards that name exact launch blockers and owners.
- Add synthetic device-level flows for auth recovery, invite redemption, pending approval, and admin approval.

## 20. Specific Recommendations For The Next Coding Session

Start with password reset:

1. Add `redirectTo` to reset email request targeting `bspc-swim://reset-password`.
2. Add a reset-link handler that accepts Supabase recovery token formats.
3. Establish session through Supabase auth.
4. Show password/new-password confirmation form.
5. Call `supabase.auth.updateUser({ password })`.
6. Add unit tests and one manual/synthetic device checklist.
7. Run `npm run typecheck`, `npm run lint`, and targeted auth tests, then `TZ=UTC npm test -- --runInBand` if time allows.

## 21. Verification Commands Run And Results

Passed:

- `BSPC/ACTIVE`: `npm run typecheck`
- `BSPC/ACTIVE`: `npm run lint`
- `BSPC/ACTIVE`: `TZ=UTC npm test -- --runInBand` -> 117 suites / 836 tests passed
- `BSPC-Coach-App`: `npm run lint:errors`
- `BSPC-Coach-App`: `npm run sync:functions-shared:verify`
- `BSPC-Coach-App`: `npm test -- --runInBand` -> 115 suites / 1161 tests passed
- `BSPC-Coach-App/functions`: `npm test -- --runInBand` -> 14 suites / 136 tests passed
- `BSPC-Coach-App/functions`: `npm run build`
- `BSPC-Coach-App/parent-portal`: `npm run typecheck`
- `BSPC-Coach-App/parent-portal`: `npm run lint` with warnings about `next lint` deprecation and plugin config
- `BSPC-Coach-App/parent-portal`: `npm run build`
- `BSPC-Coach-App`: `npm run madge:circular` -> no circular dependencies

Failed:

- `BSPC/ACTIVE`: `npm run release:check:staging` -> missing required env/config and placeholder metadata.
- `BSPC-Coach-App`: `npm run typecheck` -> 102 TypeScript errors.
- `BSPC-Coach-App`: `npm run quality:dead-code` -> unused file, unlisted Firebase deps, unused exported types.

Skipped:

- `BSPC/ACTIVE`: `npm run test:rls`, because Docker was unavailable/not running.
- Any production Supabase/Firebase/EAS command.

## 22. Things Not Fully Audited

- Live Supabase database state, dashboard Auth settings, SMTP state, Resend state.
- Whether demo credentials still work live.
- Real-device deep link handling.
- Store account, legal/privacy review, app submission readiness beyond local metadata checks.
- Full code review of every service and RLS policy.
- Dependency vulnerability audit.
