# Next Codex Session Prompt

Continue from the completed audit packet in `/Users/kevin/bspc-unify/docs/audits/`.

Read first:

1. `/Users/kevin/bspc-unify/docs/audits/FABLE_HANDOFF.md`
2. `/Users/kevin/bspc-unify/docs/audits/CODEX_DEEP_AUDIT.md`
3. `/Users/kevin/bspc-unify/docs/audits/CODEX_AUDIT_STATUS.md`

Important context:

- This workspace contains three nested Git repos: `UNIFY`, `BSPC`, and `BSPC-Coach-App`.
- Do not modify product/source files unless the user explicitly moves from audit to implementation.
- Do not print secrets, `.env` contents, tokens, raw passwords, raw keys, service-role keys, or PII.
- If implementing next, start with password recovery unless the user chooses another task.

Current verified state:

- `UNIFY`: `main...origin/main`, untracked `CODEX_HANDOFF_auth_email.md` and `auth-setup-handoff.md`, stale `.git/index.lock`.
- `BSPC`: active branch `demo/expo-go-compat`; 15 migrations; typecheck/lint/Jest pass; release preflight fails.
- `BSPC-Coach-App`: active branch `demo/device-build`; Jest/lint/functions/portal checks pass; root typecheck and dead-code checks fail.

Exact next implementation target if approved:

1. Read:
   - `/Users/kevin/bspc-unify/BSPC/ACTIVE/features/auth/components/ResetPasswordScreen.tsx`
   - `/Users/kevin/bspc-unify/BSPC/ACTIVE/features/auth/api.ts`
   - `/Users/kevin/bspc-unify/BSPC/ACTIVE/lib/supabase/client.ts`
   - `/Users/kevin/bspc-unify/BSPC/ACTIVE/app/_layout.tsx`
   - `/Users/kevin/bspc-unify/BSPC/ACTIVE/__tests__/features/auth/ResetPasswordScreen.test.tsx`
2. Implement Supabase recovery deep-link handling:
   - request reset with `redirectTo` pointing at `bspc-swim://reset-password`;
   - parse incoming `access_token`/`refresh_token` or `token_hash` + `type=recovery`;
   - establish a session with Supabase;
   - show a set-new-password UI;
   - call `supabase.auth.updateUser({ password })`;
   - add focused tests.
3. Verify with:
   - `npm run typecheck`
   - `npm run lint`
   - targeted auth tests
   - `TZ=UTC npm test -- --runInBand` if time allows.

Stopping rule:

- Stop when the selected implementation task is complete, tests are run or skipped with reasons, no secret values are printed, and the next action is obvious.
