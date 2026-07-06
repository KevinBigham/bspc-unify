# Fable Handoff

Last updated: 2026-07-05

## 1. Fable TL;DR

This audit found one confirmed implementation blocker and several launch-readiness blockers. The most urgent fix is the BSPC family app password reset flow: the app requests a reset email but has no route code that consumes Supabase recovery tokens and calls `supabase.auth.updateUser({ password })`.

The repo is three nested repos, not a monorepo. Current checked-out branches are not the same as the older Mission bars: `BSPC` is on `demo/expo-go-compat` with 15 migrations and `BSPC-Coach-App` is on `demo/device-build`. Tests mostly pass on those active branches, but Coach root typecheck is red and BSPC release preflight is red.

## 2. Highest-Confidence Findings

1. **Password recovery is not end-to-end implemented.**
   - `BSPC/ACTIVE/features/auth/components/ResetPasswordScreen.tsx:13` renders only the reset-email request screen.
   - `BSPC/ACTIVE/features/auth/api.ts:39` calls `resetPasswordForEmail(email)` with no `redirectTo`.
   - `BSPC/ACTIVE/lib/supabase/client.ts:48` sets `detectSessionInUrl: false`.
   - Repo search found no `updateUser`, `verifyOtp`, or `exchangeCodeForSession` implementation in `BSPC/ACTIVE`.

2. **Schema truth has drifted onto `BSPC/demo/expo-go-compat`.**
   - `BSPC` active branch: `demo/expo-go-compat`.
   - `BSPC/ACTIVE/supabase/migrations` has 15 files, including `00014_phase_k_add_bshs_group.sql` and `00015_meet_schedule_photo_bucket.sql`.
   - `UNIFY/01_CANONICAL_SCHEMA.sql:82` still has 8 practice-group enum values, while `BSPC/ACTIVE/constants/practice-groups.ts:12` and Coach constants include BSHS.

3. **UNIFY auth handoff docs are untracked and blocked by a stale lock.**
   - `git -C UNIFY status --short --branch` shows `?? CODEX_HANDOFF_auth_email.md` and `?? auth-setup-handoff.md`.
   - `UNIFY/.git/index.lock` exists as a zero-byte file dated Jun 29 19:07.

4. **Credential hygiene needs launch action.**
   - `BSPC/CLAUDE.md:280` has demo accounts with passwords.
   - `BSPC/ACTIVE/docs/launch-runbook.md:67` and `BSPC/ACTIVE/.maestro/demo-account-smoke.yaml:12` also contain demo credentials.
   - `BSPC-Coach-App/eas.json:15` has a `device-demo` build profile with Supabase client values. Values are intentionally not copied here.

5. **Local verification is mixed.**
   - BSPC app: typecheck, lint, and Jest pass; release preflight fails.
   - Coach app: lint, Jest, functions test/build, parent portal typecheck/lint/build, sync verify, and madge pass; root typecheck and dead-code gates fail.

## 3. Highest-Risk Unresolved Questions

1. Is live Supabase project `fqjfunuqbojouyuopnuv` fully migrated, or still in the pre-schema state described by the auth handoff?
2. Are the demo credentials in tracked docs still valid against the live backend?
3. Which branches are the intended launch branches?
4. Should Firebase Functions remain part of launch, or is scheduler rehome required first?
5. Should `00014`/`00015` be promoted into canonical `UNIFY` before more app work?

## 4. Top 5 Decisions Fable Should Make

1. Make password recovery the first implementation task unless there is contrary live evidence.
2. Declare launch truth for `BSPC` and `BSPC-Coach-App` branches.
3. Decide whether BSHS and `meet-schedule-photos` are now canonical schema.
4. Decide whether exposed demo accounts should be rotated/disabled before any wider testing.
5. Decide whether Coach Proposal B config hardening is required before deploying functions.

## 5. Top 5 Implementation Tasks For Claude Code

1. Add recovery-link handling to `BSPC/ACTIVE`: parse `bspc-swim://reset-password` tokens, establish session, show set-new-password UI, call `supabase.auth.updateUser({ password })`, and test both token formats Supabase may emit.
2. Add unit tests and a Maestro/synthetic checklist for reset-link tap -> set password -> sign in.
3. Reconcile schema docs/migrations: update `UNIFY/01_CANONICAL_SCHEMA.sql` or explicitly mark active migrations as branch-only pending decisions.
4. Remove/rotate documented demo credentials if live, then replace tracked docs/flows with placeholders or test-only fixtures.
5. Fix Coach root typecheck and dead-code gates before treating `demo/device-build` as shippable.

## 6. What Codex Verified

- Workspace topology, branch state, untracked files, stale lock, migration count, app configs, reset flow code, Coach/portal/functions Supabase clients, scheduled functions, CI/release files, and local verification command results.
- No source/product files were changed.
- No secrets, `.env` contents, raw passwords, or raw keys were copied into the audit packet.

## 7. What Codex Could Not Finish

- Did not inspect production Supabase directly.
- Did not run pgTAP because Docker was unavailable.
- Did not verify EAS/Firebase dashboard state or live auth email state.
- Did not test on-device deep links.

## 8. Files Fable Should Inspect First If It Spends More Tokens

1. `/Users/kevin/bspc-unify/BSPC/ACTIVE/features/auth/components/ResetPasswordScreen.tsx`
2. `/Users/kevin/bspc-unify/BSPC/ACTIVE/features/auth/api.ts`
3. `/Users/kevin/bspc-unify/BSPC/ACTIVE/lib/supabase/client.ts`
4. `/Users/kevin/bspc-unify/UNIFY/CODEX_HANDOFF_auth_email.md`
5. `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/migrations/00014_phase_k_add_bshs_group.sql`
6. `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/migrations/00015_meet_schedule_photo_bucket.sql`
7. `/Users/kevin/bspc-unify/BSPC-Coach-App/functions/src/config/supabase.ts`
8. `/Users/kevin/bspc-unify/BSPC-Coach-App/eas.json`

## 9. Recommended Fable Prompt

Review `/Users/kevin/bspc-unify/docs/audits/`, then choose the next single implementation task. Prioritize confirmed launch blockers over speculative cleanup. Do not print or copy raw secret values, demo passwords, `.env` contents, service-role keys, tokens, or PII. The likely first task is implementing and testing BSPC family-app Supabase password recovery deep-link handling.
