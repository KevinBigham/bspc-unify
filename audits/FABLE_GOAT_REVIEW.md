# Fable GOAT Review — BSPC Launch Ecosystem

**Author:** Claude (Fable 5) — review of Codex's audit packet, 2026-07-05
**Inputs:** `FABLE_HANDOFF.md`, `CODEX_DEEP_AUDIT.md`, `CODEX_AUDIT_STATUS.md`, `NEXT_CODEX_SESSION_PROMPT.md`, plus targeted source verification (auth cluster, release preflight, migrations 00014/00015, UNIFY Mission + auth handoffs, Coach Supabase configs, eas.json structure with values redacted, git branch state).
**Method:** No fresh full-workspace audit. No subagents. No source changes. No secrets printed.

---

## 1. Executive judgment: what BSPC Unify is trying to become

BSPC Unify is the **last operational mile** of a two-app swim-club product: a family app (`BSPC/ACTIVE`), a coach app + parent portal + Firebase Functions (`BSPC-Coach-App`), and a governance repo (`UNIFY`) — all converging on **one canonical Supabase Postgres backend**, launching **fresh** (no Firebase data migration; that plan is cancelled per Director Rulings 56+57 and `UNIFY/Mission.md`). The destination is App Store + Google Play, safely serving families with minor children, with Kevin as sole super-admin and a lawyer-gated COPPA posture.

The product is not "code-complete and locally green" as Mission.md asserts — that framing was true of the *frozen* baselines (`BSPC@880aed8`, Coach `main@ba71612`). Real life has since moved onto two unmerged, apparently-unpushed demo branches that carry genuine production fixes and two new migrations, running against a live Supabase project that was schema-less six days ago and was populated by an unrecorded process. **The project's actual state is: working device demo on top of an undocumented foundation.** The job now is to make truth match reality, then close the four confirmed gaps (recovery flow, backend verification, credential hygiene, release plumbing) in that order.

## 2. Current launch readiness: **YELLOW**

Not yellow-green. Reasons, weighed:

**What's genuinely strong (why not red):**
- Test discipline is exceptional for a project this size: BSPC 836 Jest green, Coach 1161 green, Functions 136 green, portal builds, no circular deps. 343 pgTAP assertions exist for RLS.
- The email pipeline (Resend + `auth.bspowercats.com` DNS + Supabase SMTP) is **verified live** per `UNIFY/CODEX_HANDOFF_auth_email.md` — a hard piece of Milestone 1 already done.
- Both apps demonstrably run on a real device against the live backend (the demo Kevin carries).
- Governance quality (Mission.md milestones, human-only carve-outs, secret hygiene) is better than most funded teams.

**Why yellow, not yellow-green:**
1. **Password recovery is a confirmed dead-end** — a hard gate for M1 ("synthetic reset proven") and M7 ("recovery proven on prod before disabling old sign-in"). Verified in source: request-only screen, no `redirectTo`, `detectSessionInUrl: false`, zero `updateUser`/`verifyOtp`/`exchangeCodeForSession` call sites.
2. **The live backend's state is unverified and undocumented.** On 2026-06-29 project `fqjfunuqbojouyuopnuv` had *no tables* and a patched, error-swallowing `handle_new_user()`. By 2026-07-05 demo logins work — so schema was applied somehow, by someone, with no logbook entry, unknown migration count (13? 15?), unknown trigger version, a possibly-live throwaway test user, and pgTAP never run against it. Every RLS guarantee is currently an assumption.
3. **Branch truth is split three ways**: Mission.md describes heads that are stale; `main` in both repos lacks real fixes that only exist on local demo branches; the canonical schema file contradicts the shipped migration set.
4. **Release preflight is red** and pgTAP was skipped (no Docker) — the release machine has never been exercised end-to-end.
5. **The true long pole is human**: COPPA lawyer review (Gate 1) hasn't started, and store accounts/listings are Kevin-only.

None of these is architectural. All are closable. That's what keeps this yellow rather than red.

## 3. What Codex got right

1. **Password recovery as the #1 confirmed implementation target.** I independently verified all four legs of the claim. The finding, the impact statement, and the priority are correct.
2. **Branch/schema drift is real and material.** Verified: BSPC `demo/expo-go-compat` is 7 commits ahead of `main` (including migrations 00014/00015); Coach `demo/device-build` is 8 ahead (including the identity-map fix `685ec74` and the device-demo EAS profile). `UNIFY/01_CANONICAL_SCHEMA.sql` still shows 8 practice groups vs the shipped 9.
3. **Release preflight analysis is accurate.** `scripts/release-check.js` fails on exactly what Codex said: missing required env keys and three placeholders (Privacy Policy URL "[To be created…]", Support URL "[To be created…]", `privacy@bspowercats.com` contact). Verified in `docs/app-store-metadata.md:101-105` and `docs/privacy-policy.md:154`.
4. **Credential hygiene flags are legitimate**: demo account credentials in tracked docs and Maestro flows; a committed `device-demo` EAS profile carrying live Supabase URL + publishable key (structure confirmed with values redacted).
5. **Secret discipline was exemplary** — the packet describes locations and categories without ever copying values. That's the right pattern and this review preserves it.
6. **Honest boundaries.** Codex was explicit about what it could not verify (live DB, Docker/pgTAP, device deep links, dashboards) instead of extrapolating. The open-questions list is the right list.
7. **The `00014` migration itself is high quality** — it even documents and closes a pre-existing constraint gap (two sites never widened for Masters). The drift problem is documentation lag, not sloppy schema work.

## 4. What Codex may have missed or overstated

**Missed — these change the plan:**

1. **The root-layout auth guard will fight the recovery flow.** `BSPC/ACTIVE/app/_layout.tsx:63-73` redirects any authenticated user out of the `(auth)` group into `/(tabs)`. The moment a recovery deep link establishes a session, `isAuthenticated` flips true and the user is **yanked off the set-password screen into the app, still holding their forgotten password**. A naive implementation of Codex's task list would "work" (session established, no crash) while silently failing its purpose. The patch must add a recovery-mode flag to the auth store and teach the guard to respect it. This is the single trickiest part of the fix and the packet never mentions it.
2. **The live-DB truth gap deserves blocker status, not open-question status.** Codex filed "is `fqjfunuqbojouyuopnuv` fully migrated?" under unresolved questions. Given the auth handoff's documented state (no `profiles` table on 6/29, tolerant trigger applied, throwaway user created, pre-schema users have no profile rows) and a working demo six days later, the correct reading is: **the production database was mutated by an unrecorded process and nothing about it is proven.** This is a launch blocker in its own right and the cheapest one to close (a read-only probe script).
3. **The auth-state listener has no `PASSWORD_RECOVERY` handling.** `useAppInitialization.ts:34-56` treats every session identically (identify → fetch profile). The recovery event needs distinct routing, and pending-approval profile logic must not intercept a recovering user.
4. **`main` is not actually the safe fallback.** BSPC `demo/expo-go-compat` contains `cb0e77b` — a fix for quick announcements 23502-ing against a NOT NULL FK — and Coach `demo/device-build` contains the identity-map RLS-boundary fix. Falling back to `main` would *reintroduce shipped bugs*. Branch reconciliation is a promotion, not a cleanup.
5. **Both demo branches appear to exist only on this machine** (neither shows in `origin/*`). The entire working product state has a bus factor of one laptop. Pushing them (no deploy implied) is the highest ROI-per-second action available.
6. **A nuance that softens the `redirectTo` finding:** the Supabase **Site URL is currently set to `bspc-swim://reset-password`** (per the auth handoff), and Site URL is the fallback redirect for `{{ .ConfirmationURL }}`. So today's reset emails likely *already deep-link into the app* — which then does nothing with the tokens. The missing piece is overwhelmingly **token consumption**, not the email side. (Still add explicit `redirectTo`; don't depend on a placeholder Site URL that Action Item 3 says will change.)

**Overstated (mildly — priority, not fact):**

7. **Release preflight red is not an engineering emergency.** It fails on placeholders whose real values are Kevin-gated (public privacy-policy URL, support URL, contact email — all downstream of the lawyer gate) plus env keys that are absent by design on a dev machine. The checker is *working correctly*. Treat it as the launch dashboard, not as work to "fix" now. The only engineering item hiding in it: metadata still says "7 practice groups" (should be 9).
8. **Coach root typecheck (102 errors) is hygiene debt, not a launch decision-driver.** By Codex's own description the errors sit in legacy scripts, stale `User.uid`/`displayName` references, and test-mock typings — while 1161 runtime tests pass. It must be green before the Coach line is called shippable, but it should not compete with recovery or backend truth for the next session.
9. **pgTAP "skipped because Docker" deserved louder framing**: one of the five green bars in Mission.md has not been verified at all in this cycle, on a branch that added two migrations. That's a bar-integrity issue, not a footnote.

## 5. Top 3 launch blockers

1. **Password recovery cannot complete end-to-end** (BSPC family app). Hard gate for M1 and M7; explicitly part of Kevin's required launch ordering (prove recovery **before** disabling old sign-in). Pure coding, no human dependency.
2. **Live backend state is unverified.** Unknown migration set, unknown trigger version, possible orphan/pre-schema auth users, throwaway test user possibly live, RLS never probed against prod. Everything else (recovery included) is built on this foundation.
3. **Source-of-truth fracture.** Launch code lives on two unpushed local branches; Mission.md, canonical schema, and green-bar table all describe a world that no longer exists. Until branch/schema truth is declared, every other workstream risks landing on the wrong base.

(The COPPA lawyer engagement is the *calendar* long pole but is human-only — it belongs on Kevin's checklist, started in parallel, not on the engineering blocker list.)

## 6. Top 3 auth/security/privacy risks

1. **Live demo credentials in tracked docs and Maestro flows, against a live backend with open signup.** Compounded by the auth handoff's leftovers: possibly-still-tolerant `handle_new_user()`, a throwaway confirmed user, and any pre-schema users with no profile rows (invisible to profile-based RLS logic). Action: rotate/disable demo accounts, verify trigger state, delete throwaway user, replace tracked credentials with placeholders injected at run-time.
2. **The recovery flow itself, once built, is a security surface.** Deep-link tokens arrive via a custom URL scheme (interceptable by any app registering the scheme on Android); handle expired/`error_code` params, never log token material, prefer `token_hash`+`verifyOtp`/PKCE `code` handling where available, and clear the recovery state after one use. The route-guard bypass (item 4.1) is also a correctness-of-security issue: a half-working flow trains users to abandon resets.
3. **Coach Functions service-role client constructs with placeholder fallbacks** (`functions/src/config/supabase.ts:8-11`) — a fail-open pattern that can mask misconfiguration at deploy time; the fail-closed fix already exists unmerged on `proposal-b-config-hardening`. Adjacent: committed live project URL + publishable key in `eas.json` `device-demo` is client-safe *by design* but only as strong as RLS — which is currently unverified (risk #2 in §5).

## 7. Top 3 schema/branch/release-management risks

1. **"Canonical schema is law" is currently false.** `UNIFY/01_CANONICAL_SCHEMA.sql` (8 groups, 13-migration worldview) vs shipped `00014` (9 groups, plus two constraint-gap fixes) and `00015` (new storage bucket + policy). Either ratify 00014/00015 into canon (correct call — they're live in the demo) or formally mark them branch-only. Ambiguity here poisons pgTAP, app constants, and store metadata simultaneously.
2. **Unknown prod migration ledger.** If the live DB was populated via ad-hoc SQL rather than `supabase db push`, the migration-history table won't match the files, and the next push may double-apply or skip. Must be inspected read-only before any future migration lands.
3. **The release pipeline has never run green end-to-end**: preflight red, pgTAP unrun this cycle, `supabase/config.toml` `schema_paths` listing only migration 00001, Node 24 used locally vs Node 20 in CI/docs, metadata saying 7 groups. Individually trivial; collectively they mean the first real release attempt will hit a wall of small surprises.

## 8. Decision: what goes first

**Password recovery first.** Then backend truth-probe + branch/schema ratification as the immediate second wave (they're mostly decision + documentation and can start the same day). Release preflight third (it's blocked on Kevin-gated URLs anyway). Coach typecheck fourth (hygiene, batchable).

Why recovery beats the alternatives:
- **vs release preflight first:** preflight's red items are placeholders awaiting lawyer/hosting outputs Kevin doesn't have yet. Greening it now is impossible without inventing URLs; the one code-adjacent item (7→9 groups copy) rides along with schema ratification.
- **vs Coach typecheck first:** zero user-facing impact, no launch-gate linkage, errors concentrated in legacy scripts/mocks, and the runtime suites are green. It's a half-day of cleanup best done when the Coach line is being promoted to `main`.
- **vs schema/branch reconciliation first:** genuinely the closest call, and it *is* wave two. But reconciliation is 80% decision ("demo branches are the launch line") + documentation, needs Kevin's ratification, and touches no user-visible defect. Recovery is a confirmed dead-end in a flow Mission.md marks as a public-launch gate, is pure coding, and lands identically regardless of how reconciliation resolves — because it's built on the branch that *will* win (`demo/expo-go-compat` already carries fixes `main` needs).

## 9. Recommended launch branch/source-of-truth sequence

1. **Declare the launch lines:** `BSPC/demo/expo-go-compat` and `BSPC-Coach-App/demo/device-build` are the launch branches. `main` in both repos is a historical baseline that is *behind on real fixes*. Record as a Director Ruling.
2. **Push both demo branches to origin** (backup, not deploy — Kevin or next approved session; this review didn't push per rules).
3. **Land the recovery patch** on `demo/expo-go-compat` (see §15/§16).
4. **Ratify schema:** fold 00014/00015 into `UNIFY/01_CANONICAL_SCHEMA.sql`, fix `supabase/config.toml` `schema_paths`, run pgTAP under Docker, extend group-related pgTAP if needed, update metadata copy 7→9 groups.
5. **Probe the live DB read-only** (Kevin's "go" per Mission ground rules): migration history vs files, `handle_new_user()` version, RLS-enabled on all tables, bucket inventory, orphan `auth.users` without profiles, throwaway user. Sanitized results to `UNIFY/NOTES.md`.
6. **Merge demo → main via PR** in each repo once bars re-run green; retire the "five green bars" table in Mission.md in favor of *measured* current counts (BSPC 836+, Coach 1161, Functions 136, pgTAP 343, portal build) on the launch lines.
7. **Refresh Mission.md "Current state"** and commit the two untracked UNIFY handoff docs (requires clearing the stale `.git/index.lock` — left untouched during this review per instructions; it's a documented sandbox artifact, safe for Kevin to remove when doing UNIFY git work).

## 10. Ranked improvement board

Full board with ROI/risk/effort/confidence/first-files in **`FABLE_PRIORITY_BOARD.md`**. Top of the board: P0-1 password recovery, P0-2 live-DB probe script, P0-3 push demo branches (Kevin, ~1 minute), P1 credential rotation + schema ratification + demo→main promotion.

## 11. 2-hour plan

All inside `BSPC/ACTIVE`, branch off `demo/expo-go-compat`:

1. (~15 min) `features/auth/api.ts`: add `redirectTo` constant to `resetPassword`; add `updatePassword()`, `setSessionFromTokens()`, `verifyRecoveryToken()` wrappers (rule #15: no raw Supabase in components).
2. (~25 min) `lib/auth/recovery-link.ts`: pure parser for the three link shapes — fragment `access_token`/`refresh_token`+`type=recovery`, query `token_hash`+`type=recovery`, query `code` — plus `error_code`/`error_description` extraction. Pure function → trivially testable.
3. (~30 min) Recovery state + guard fix: `isPasswordRecovery` in `stores/auth-store.ts`; `useRecoveryDeepLink()` hook (initial URL + `url` event) in `useAppInitialization.ts`; root-layout guard routes recovering users to set-new-password instead of `(tabs)`.
4. (~30 min) `app/(auth)/set-new-password.tsx` (thin route) + `features/auth/components/SetNewPasswordScreen.tsx`: password + confirm, min-length 6 (matches dashboard), calls `updatePassword`, clears flag, routes onward; expired-link state with "request a new link" path.
5. (~20 min) Tests for parser + screen; `npm run typecheck && npm run lint` + targeted Jest.

## 12. 2-day plan

**Day 1 — recovery complete.** The 2-hour plan, then: api-layer tests (assert `redirectTo` passed), auth-listener recovery-event test, full `TZ=UTC npm test -- --runInBand` (document new bar), Maestro/manual device checklist doc for the synthetic reset (Kevin taps the real email link on his phone — the M1 proof), update `ResetPasswordScreen` copy if needed. Commit in small units per Mission convention.

**Day 2 — truth wave.**
1. Write the read-only prod probe script (`scripts/audit-prod-schema.ts` per Mission M1) — runnable only on Kevin's "go".
2. Schema ratification: canonical SQL update, `config.toml` fix, Docker up, `npm run test:rls` (verify the 343 bar on the launch branch), metadata 7→9 copy fix.
3. Credential hygiene: draft the rotation/disable plan for demo accounts, replace tracked credentials with `${DEMO_*}` placeholders in docs/Maestro (execution of the live rotation is Kevin-gated).
4. Kevin actions teed up: push both demo branches, run the probe, tap the reset link, delete throwaway user.

## 13. 2-week GOAT roadmap

**Week 1 — one truth, all bars green on it.**
- Recovery merged and device-proven against the live project (M1 recovery gate ✅).
- Demo branches pushed; demo→main PRs merged in both repos; Director Ruling records the launch lines; Mission.md current-state rewritten with measured bars.
- Canonical schema ratified (00014/00015 in canon); pgTAP green under Docker locally **and wired into CI** so the bar can't silently rot again.
- Live-DB probe run (read-only); findings recorded; `handle_new_user()` restored to strict if schema confirmed; throwaway user deleted; demo credentials rotated.
- Coach root typecheck → 0 errors; dead-code gate green; `proposal-b-config-hardening` merged (fail-closed Functions config).

**Week 2 — the M4–M7 arc.**
- Staff-assisted onboarding proof on a throwaway project (M4): family → profile link → swimmers → guardianship → approval log, idempotent + rollback.
- Invite-redemption mobile UI (M6): screen + `/invite/:token` deep link (reusing the deep-link infrastructure the recovery patch just built — deliberate sequencing dividend).
- Device QA loop (M5): EAS internal builds both apps, Maestro smoke on-device, one full practice logged crash-free, Sentry clean.
- Release preflight greening to the extent Kevin's inputs exist (hosted policy/support URLs after lawyer draft; real contact email); store asset drafts.
- Hand Kevin a single consolidated human-only checklist with the lawyer engagement flagged as the calendar-critical item to start **now**.

**GOAT definition of done for the fortnight:** one declared launch branch per repo, every green bar measured and enforced in CI on that branch, recovery + invite flows proven on real hardware against a verified backend, and the only remaining work being items that legally require Kevin.

## 14. What not to spend time on yet

- **Scheduler rehome implementation (M3)** — draft the A/B decision memo only; jobs currently function; the choice needs Kevin/Director input.
- **Firebase remnant cleanup (M8)** — explicitly last; touching it now risks the working Functions.
- **Admin approval → Edge Function refactor** — right medium-term call, zero launch-gate linkage; RLS covers it for the closed-beta population.
- **Release preflight env-key greening on dev machines** — those keys are meant to come from Kevin at build time.
- **Parent portal `next lint` modernization, dead-code polish beyond the gate, performance profiling, DMARC/inbound MX** — real, small, later.
- **Rewriting historical UNIFY docs (00–20)** — Mission.md already marks them HISTORICAL; a one-line banner per file at most, during M8.
- **`UNIFY/.git/index.lock`** — untouched per instructions; one `rm` for Kevin when he next does UNIFY git work (documented in the auth handoff §10).

## 15. The single best first patch

**BSPC family-app password recovery, end-to-end**, on `demo/expo-go-compat`: explicit `redirectTo` → deep-link token consumption (all three Supabase link shapes + error params) → recovery session → **guard-aware** set-new-password screen → `supabase.auth.updateUser({ password })` → tests + device checklist. It is the only confirmed user-facing dead-end, a hard M1/M7 gate, pure coding with no human dependency, and it builds the deep-link plumbing M6 (invite redemption) will reuse. The one non-obvious requirement — and the reason a naive patch fails — is the root-layout auth guard interaction (§4.1).

## 16. Paste-ready implementation prompt

See **`FABLE_NEXT_PATCH_PROMPT.md`** — self-contained, includes the guard fix, all three token formats, test plan, verification commands, and stop rules.
