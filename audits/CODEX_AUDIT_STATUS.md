# CODEX Audit Status

Last updated: 2026-07-05

## Current Audit Phase

Complete. Audit packet written under `/Users/kevin/bspc-unify/docs/audits/`.

## Commands Run

### Instruction / Scout

- Read `/Users/kevin/Downloads/codex_audit_prompt_pack/projects/bspc-unify/CODEX_AUDIT_PLAN.md`.
- Read shared prompt-pack files: `00_START_WITH_PLAN_COMMAND.txt`, `01_GENERIC_GOAL_COMMAND.txt`, `CODEX_AUDIT_PLAN_TEMPLATE.md`, `RUN_ORDER_CHECKLIST.md`.
- `pwd`
- `git status --short --branch` at workspace root: failed because `/Users/kevin/bspc-unify` is not a Git repo.
- `find . -maxdepth 3 -name .git -type d`
- `git -C UNIFY status --short --branch`
- `git -C BSPC status --short --branch`
- `git -C BSPC-Coach-App status --short --branch`
- `git -C <repo> branch --all --verbose --no-abbrev`
- `git -C <repo> log --oneline --decorate -n 12`
- File/folder maps with `find`, `rg --files`, `rg -n`, package script summaries with `node -e`.

### Targeted Evidence Reads

- Repo guidance/docs: `UNIFY/Mission.md`, `UNIFY/README.md`, `BSPC/CLAUDE.md`, `BSPC-Coach-App/AGENTS.md`, `BSPC-Coach-App/README.md`.
- Auth/reset files: `BSPC/ACTIVE/features/auth/components/ResetPasswordScreen.tsx`, `BSPC/ACTIVE/features/auth/api.ts`, `BSPC/ACTIVE/lib/supabase/client.ts`, `BSPC/ACTIVE/lib/hooks/useAppInitialization.ts`, `BSPC/ACTIVE/app/_layout.tsx`.
- Schema/config files: `UNIFY/01_CANONICAL_SCHEMA.sql`, `BSPC/ACTIVE/supabase/config.toml`, `BSPC/ACTIVE/supabase/migrations/00014_phase_k_add_bshs_group.sql`, `BSPC/ACTIVE/supabase/migrations/00015_meet_schedule_photo_bucket.sql`.
- Coach/portal/functions files: `BSPC-Coach-App/src/config/supabase.ts`, `BSPC-Coach-App/functions/src/config/supabase.ts`, `BSPC-Coach-App/parent-portal/src/lib/supabase.ts`, `BSPC-Coach-App/functions/src/index.ts`, scheduled job files, `extractMeetSchedule.ts`.
- Secrets/credential hygiene searches were redacted and did not print `.env` contents.

### Verification

- `npm run typecheck` in `BSPC/ACTIVE`: passed.
- `npm run lint` in `BSPC/ACTIVE`: passed.
- `TZ=UTC npm test -- --runInBand` in `BSPC/ACTIVE`: passed, 117 suites / 836 tests.
- `npm run release:check:staging` in `BSPC/ACTIVE`: failed on missing env/config and placeholder policy/support metadata.
- `npm run typecheck` in `BSPC-Coach-App`: failed with 102 TypeScript errors.
- `npm run lint:errors` in `BSPC-Coach-App`: passed.
- `npm run sync:functions-shared:verify` in `BSPC-Coach-App`: passed.
- `npm test -- --runInBand` in `BSPC-Coach-App`: passed, 115 suites / 1161 tests.
- `npm --prefix functions test -- --runInBand` in `BSPC-Coach-App`: passed, 14 suites / 136 tests.
- `npm --prefix functions run build` in `BSPC-Coach-App`: passed.
- `npm --prefix parent-portal run typecheck`: passed.
- `npm --prefix parent-portal run lint`: passed with deprecation/plugin warnings.
- `npm --prefix parent-portal run build`: passed.
- `npm run madge:circular` in `BSPC-Coach-App`: passed, 299 files processed, no circular dependency found.
- `npm run quality:dead-code` in `BSPC-Coach-App`: failed with one unused file, two unlisted Firebase dependencies, and four unused exported types.
- `npm run test:rls` skipped: Supabase CLI exists, but Docker was unavailable/not running.

## Files Read

See `CODEX_DEEP_AUDIT.md` for the evidence-backed file list by finding. Major files read include:

- `/Users/kevin/bspc-unify/UNIFY/Mission.md`
- `/Users/kevin/bspc-unify/UNIFY/README.md`
- `/Users/kevin/bspc-unify/UNIFY/CODEX_HANDOFF_auth_email.md`
- `/Users/kevin/bspc-unify/UNIFY/auth-setup-handoff.md`
- `/Users/kevin/bspc-unify/UNIFY/01_CANONICAL_SCHEMA.sql`
- `/Users/kevin/bspc-unify/BSPC/CLAUDE.md`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/app.json`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/package.json`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/config.toml`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/features/auth/components/ResetPasswordScreen.tsx`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/features/auth/api.ts`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/lib/supabase/client.ts`
- `/Users/kevin/bspc-unify/BSPC/ACTIVE/features/admin/api.ts`
- `/Users/kevin/bspc-unify/BSPC-Coach-App/AGENTS.md`
- `/Users/kevin/bspc-unify/BSPC-Coach-App/README.md`
- `/Users/kevin/bspc-unify/BSPC-Coach-App/eas.json`
- `/Users/kevin/bspc-unify/BSPC-Coach-App/src/config/supabase.ts`
- `/Users/kevin/bspc-unify/BSPC-Coach-App/functions/src/config/supabase.ts`
- `/Users/kevin/bspc-unify/BSPC-Coach-App/parent-portal/src/lib/supabase.ts`
- `/Users/kevin/bspc-unify/BSPC-Coach-App/functions/src/index.ts`

## Confirmed Findings

- Workspace root is not a Git repo; `UNIFY`, `BSPC`, and `BSPC-Coach-App` are separate Git repos.
- `UNIFY` has untracked auth handoff docs and a stale `.git/index.lock`.
- `BSPC` active branch `demo/expo-go-compat` is ahead of `main` with migrations `00014` and `00015`.
- `BSPC-Coach-App` active branch `demo/device-build` is ahead of `main` with device-demo, meet-schedule-photo/AI, and UI changes.
- Password reset is likely broken end-to-end: the family app can send a reset email but has no recovery-token consumption or password-update flow.
- `UNIFY/01_CANONICAL_SCHEMA.sql` still defines an 8-value `practice_group` enum; active app/constants and migration `00014` use 9 values including BSHS.
- `BSPC-Coach-App/eas.json` commits a `device-demo` profile with Supabase URL and publishable key values.
- Demo account credentials are present in tracked docs and Maestro flows, with raw values not copied here.
- `BSPC/ACTIVE` local typecheck/lint/Jest pass; release preflight fails.
- `BSPC-Coach-App` Jest/lint/functions/portal checks pass, but root typecheck and dead-code gates fail.

## Open Questions

- Which branches are launch truth: `BSPC/main` vs `BSPC/demo/expo-go-compat`, and `BSPC-Coach-App/main` vs `BSPC-Coach-App/demo/device-build`?
- Has the live Supabase project `fqjfunuqbojouyuopnuv` received the complete current migration set?
- Are the documented demo credentials still live against the production-intended Supabase backend?
- Should Coach continue to deploy Firebase scheduled/HTTPS functions for launch, or should scheduler rehome happen before launch?

## Next Steps

1. Fix family-app password recovery deep-link handling and test it end to end.
2. Decide branch/schema truth and reconcile `UNIFY`, `BSPC`, and Coach docs/config accordingly.
3. Remove/rotate exposed demo credentials if live.
4. Fix Coach root typecheck and dead-code gates.
5. Complete BSPC release metadata/env/EAS readiness.

## What Remains Unfinished

- No live Supabase state was queried.
- No production/dashboard settings were verified directly.
- pgTAP/RLS suite was not run because Docker was unavailable.
- No EAS/Firebase/Supabase deploy commands were run.
