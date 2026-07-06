# Paste-Ready Prompt — BSPC Password Recovery (First Patch)

Copy everything below the line into a fresh Claude Code session started in `/Users/kevin/bspc-unify`.

---

Implement end-to-end Supabase password recovery in the BSPC family app. This is the ratified first patch from `docs/audits/FABLE_GOAT_REVIEW.md` (§15–16). Work only in `/Users/kevin/bspc-unify/BSPC/ACTIVE`, on a new branch off `demo/expo-go-compat` (that branch is the launch line — do NOT branch off `main`).

## Current broken state (verified 2026-07-05)

- `features/auth/components/ResetPasswordScreen.tsx` only requests the reset email; `features/auth/api.ts:39` calls `resetPasswordForEmail(email)` with no `redirectTo`; `lib/supabase/client.ts:48` sets `detectSessionInUrl: false`; there is no code anywhere in `BSPC/ACTIVE` that consumes recovery tokens, calls `updateUser`, `verifyOtp`, or `exchangeCodeForSession`.
- The app scheme is `bspc-swim` (app.json). The Supabase project's redirect allow-list already contains `bspc-swim://reset-password` and `bspc-swim:///reset-password`, and Site URL is temporarily `bspc-swim://reset-password` (see `UNIFY/CODEX_HANDOFF_auth_email.md` §5) — so reset emails already deep-link to the app; the app just ignores the tokens.
- **Critical trap:** the root-layout auth guard at `app/_layout.tsx:63-73` redirects any authenticated user out of the `(auth)` group into `/(tabs)`. A recovery deep link establishes a session, so without a recovery-mode flag the user gets yanked into the app before setting a new password. Your implementation MUST handle this; it is the main way this patch fails silently.

## Implementation (small, single-purpose commits, in this order)

1. **`features/auth/api.ts`** (rule #15: all Supabase calls live here):
   - `resetPassword(email)`: add `{ redirectTo: RESET_PASSWORD_REDIRECT }` where `RESET_PASSWORD_REDIRECT = "bspc-swim://reset-password"` (exported constant).
   - Add `updatePassword(newPassword: string)` → `supabase.auth.updateUser({ password: newPassword })`, throw on error.
   - Add `setSessionFromTokens(accessToken, refreshToken)` → `supabase.auth.setSession(...)`.
   - Add `verifyRecoveryToken(tokenHash)` → `supabase.auth.verifyOtp({ type: "recovery", token_hash: tokenHash })`.
   - Add `exchangeCodeForSession(code)` → `supabase.auth.exchangeCodeForSession(code)`.

2. **New `lib/auth/recovery-link.ts`** — a pure parser `parseRecoveryLink(url: string)` returning a discriminated union. Supabase recovery links land in three shapes depending on flow/template; handle all three, plus errors:
   - Fragment tokens (implicit flow, the default for this client): `bspc-swim://reset-password#access_token=...&refresh_token=...&type=recovery` → `{ kind: "tokens", accessToken, refreshToken }`. Note tokens may also arrive as query params on some paths — check both fragment and query.
   - Token hash: `?token_hash=...&type=recovery` → `{ kind: "token_hash", tokenHash }`.
   - PKCE code: `?code=...` → `{ kind: "code", code }`.
   - Error params: `error_code`/`error_description` (e.g. `otp_expired`) in fragment or query → `{ kind: "error", errorCode, description }`.
   - Anything else → `{ kind: "none" }`. Only treat the URL as recovery if its path/host matches `reset-password`.

3. **Recovery mode state** — `stores/auth-store.ts`: add `isPasswordRecovery: boolean` + `setPasswordRecovery(v)`; include it in `reset()`.

4. **Deep-link consumption** — new `useRecoveryDeepLink()` hook in `lib/hooks/useAppInitialization.ts`, wired in `app/_layout.tsx` alongside the existing init hooks. It must handle BOTH `Linking.getInitialURL()` (cold start) and the `Linking.addEventListener("url", ...)` event (warm start). On a recovery URL: set `isPasswordRecovery = true` **before** establishing the session, then establish the session via the matching api.ts wrapper, then route to `/(auth)/set-new-password`. On `kind: "error"`, route to set-new-password with an `expired` param so the screen shows the friendly expired state. Never log token material — not even at debug level.

5. **Guard fix** — in the `app/_layout.tsx` redirect effect: when `isPasswordRecovery` is true, do NOT redirect an authenticated user out of the `(auth)` group; if they are outside it, send them to `/(auth)/set-new-password`. Normal behavior resumes once the flag clears.

6. **New screen** — thin route `app/(auth)/set-new-password.tsx` (<50 lines, rule #1) rendering `features/auth/components/SetNewPasswordScreen.tsx`:
   - New password + confirm fields (secure entry, accessibility labels per existing screens), min length 6 (matches the Supabase dashboard setting), mismatch validation, 4 async states (rule #7).
   - Submit → `updatePassword(...)` → on success: `setPasswordRecovery(false)`, track an analytics event via the existing typed-events pattern (`AnalyticsEvents`), toast/confirm, then route to `/(tabs)` (session is already live).
   - Expired/invalid-link state: friendly message + button to `/(auth)/reset-password` to request a new link.
   - Style with the existing UI primitives (`Text`, `Button`, `Card`) and NativeWind classes, matching `ResetPasswordScreen.tsx`.

7. **Auth listener** — in `useAuthStateListener`, on the `PASSWORD_RECOVERY` event set the recovery flag (belt-and-braces alongside the URL hook).

## Tests (Jest + RNTL, mock at the api layer like `__tests__/features/auth/ResetPasswordScreen.test.tsx` — never spy on raw supabase)

- `recovery-link` parser: all four kinds + non-recovery URL + malformed input.
- `SetNewPasswordScreen`: renders; mismatch blocks submit; short password blocks; success calls `updatePassword` and clears recovery flag; api failure shows error; expired variant renders resend path.
- `features/auth/api.ts`: new test with a mocked supabase client asserting `resetPasswordForEmail` receives the `redirectTo` option, and that the new wrappers call the right auth methods.
- Update nothing by snapshot `-u`; snapshot changes must be deliberate.

## Verify

```bash
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run typecheck
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run lint
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && TZ=UTC npx jest __tests__/features/auth lib/auth --runInBand
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && TZ=UTC npm test -- --runInBand   # full bar; document the new test count vs 836
```

Then write `docs/recovery-device-checklist.md`: the manual synthetic e2e for Kevin (throwaway account → request reset in-app → tap emailed link on iPhone → set password → sign in with it), with a sanitized pass/fail line destined for `UNIFY/NOTES.md`. Note for the checklist: Expo Go does not own the `bspc-swim` scheme — the device proof needs a dev/internal build.

## Hard rules

- Branch off `demo/expo-go-compat`; never commit to `main`; do not push, deploy, or run anything against production Supabase.
- Never print or commit secrets, demo passwords, tokens, or key strings; never log recovery token material.
- Stage files by exact path (no `git add -A`). Husky/lint-staged must pass; no `--no-verify`.
- Commit messages: terse present-tense subject + `Co-Authored-By:` trailer per repo convention.
- Stop when: implementation + tests green, full suite count documented, device checklist written, and nothing has been pushed.
