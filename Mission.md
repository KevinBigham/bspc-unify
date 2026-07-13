<!--
  Mission.md — the single self-contained handoff for finishing the BSPC two-app launch.
  Authored 2026-06-27 by Claude (Opus 4.8) for handoff to Codex.
  The canonical schema is law; the five green bars are the gate; one small reviewable change at a time is the method.
-->

# Mission

You are **Codex**, an autonomous coding agent finishing a two-app swim-club product for the Blue Springs Power Cats (BSPC). There are two mobile apps — a **Coach app** (staff write-tools) and a **swimmer/family app** (parent-facing, information-first) — plus a Next.js parent portal. All three talk to **one shared Supabase Postgres backend** defined by a single canonical schema. Your north star: drive the product from "code-complete, locally green" to "live in the App Store and Google Play, safely serving families with minor children," by executing a fixed sequence of operational milestones — each one a small, well-tested, reviewable change — while never touching anything that legally or financially belongs to the product owner, Kevin (a non-coder).

**The fresh-launch decision, in plain terms:** Both legacy Firebase projects were attested **empty**. There is **no data to migrate**. Everything that was once planned to copy real Firebase data into Supabase — the "Sitting 2" cutover, identity remediation, the four cutover tools (`probe-firebase-inventory`, `provision-identities`, `backfill-identity-graph`, `backfill-roster`), and Firebase decommission of real data — is **CANCELLED and already deleted from the Coach repo**. Many design docs in `UNIFY/` (numbered 00–20) were written under the OLD migration plan. When any doc describes migrating, backfilling, or remediating real Firebase data, **treat it as HISTORICAL, not as remaining work.** We are launching fresh on Supabase: empty production database, schema applied clean, then real families onboarded going forward.

---

## Ground rules for Codex

**You MAY do, without asking (just do it, then report):**
- All coding: write/edit/delete source, tests, migrations, config, docs in any of the three repos.
- Run the full local toolchain: install, build, test (jest + pgTAP), typecheck, lint, madge, knip, Maestro stubs.
- Create branches, make local commits, and open PRs (branch first — never commit straight to `main`).
- Run the apps locally against a **local or throwaway** Supabase, and a local Firebase Functions emulator.
- Draft (but not send/host) email templates, policy text, store metadata, runbook scripts — drafting is coding; *executing against production or the public* is not.

**You MUST NOT do — HARD HUMAN-ONLY CARVE-OUTS (never attempt, never block on, hand to Kevin):**

> 🚫 **Legal / privacy review.** Children's-privacy / COPPA / SafeSport analysis and sign-off needs a lawyer. You may draft outlines (`UNIFY/14_GATE1_LAWYER_BRIEF.md`, `15_PRIVACY_REWRITE_OUTLINE.md`); you may NOT decide compliance or publish a policy as authoritative.
>
> 🚫 **Store accounts & listings.** Apple Developer / Google Play account creation, identity verification, app listings, age-rating / Data Safety / Designed-for-Families forms — Kevin's legal identity. You prepare assets; Kevin submits.
>
> 🚫 **Production credentials & secrets.** Creating the production Supabase project, Firebase project, EAS project, SMTP sender, Sentry/PostHog projects, and **every real secret** (service-role key, anon key, DB password, API tokens). You consume credentials Kevin provides at run-time; you never create, read, print, paste, commit, or invent them.
>
> 🚫 **Code signing.** Certificates, provisioning profiles, EAS signing config tied to Kevin's developer accounts.
>
> 🚫 **Payment.** Any purchase, billing-plan change, or money movement.
>
> 🚫 **Anything tied to Kevin's legal identity or accounts** — founder attestations, org ownership, domain verification, sending real email to real families.
>
> 🚫 **Live production operations on real data** without an explicit, per-command "go." For any hosted command you propose the exact command, print only the **target** (Supabase URL or Firebase `project_id` — never a secret), and wait for Kevin's explicit "yes." Run once, never batch.

When you hit a carve-out, stop and surface it to Kevin with a one-line "this is yours" note. Do not improvise around it.

---

## Repo map & how they connect

Three independent git repos under `/Users/kevin/bspc-unify/`. They are NOT a monorepo; the **only** thing binding them is the single shared Supabase Postgres backend.

| Repo | Path | Role | Backend | Stack |
|---|---|---|---|---|
| **UNIFY** | `/Users/kevin/bspc-unify/UNIFY` | Design source-of-truth + **canonical Postgres schema** + migration logbook | — | Markdown + SQL |
| **BSPC** | `/Users/kevin/bspc-unify/BSPC` (live code in `ACTIVE/`) | Swimmer/family app **and the Supabase backend** (migrations + pgTAP) | Supabase/Postgres | Expo SDK 54 / RN 0.81 / Expo Router 6 |
| **BSPC-Coach-App** | `/Users/kevin/bspc-unify/BSPC-Coach-App` | Coach Expo app + temporarily Firebase-hosted schedulers pending Ruling 65 rehome; portal retired | Supabase canonical data | Expo SDK 54 + Functions (Node 22) |

**The canonical schema is law:** `/Users/kevin/bspc-unify/UNIFY/01_CANONICAL_SCHEMA.sql`. Both apps' table shapes derive from it. If app code needs a column or table the schema lacks, you **propose a migration** — you never hack around the schema.

**Where the schema physically lives & ships:** the executable migrations are in `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/migrations/` — 21 files, `00001_initial_schema.sql` … `00021_family_approval_audit_and_collision.sql`. The pgTAP suite that proves the RLS walls is in `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase/tests/database/` — 19 files through `019-meet-import-idempotency.test.sql`. **The BSPC repo is the one that owns the database.** The Coach app and parent portal are clients of that same database.

**Connection diagram:**

```
                 ┌─────────────────────────────────────────┐
                 │   Shared Supabase Postgres (one backend) │
                 │   schema = UNIFY/01_CANONICAL_SCHEMA.sql  │
                 │   migrations live in BSPC/ACTIVE/supabase │
                 └───────────────┬───────────────┬──────────┘
                  RLS + Auth      │               │   RLS + Auth
        ┌──────────────────────────┘               └────────────────────────┐
        ▼                                                                    ▼
  BSPC family app (Expo)                                       Coach app (Expo) + parent portal (Next.js)
  /Users/.../BSPC/ACTIVE                                       /Users/.../BSPC-Coach-App
  reads via RLS, never writes coach data                       writes roster/notes/times/media (staff RLS)
                                                               + Firebase Cloud Functions (schedulers, callables)
```

**Key UNIFY docs (read these before touching a milestone they cover):**
- `01_CANONICAL_SCHEMA.sql` — schema law.
- `13_PUBLISH_PLAN.md` — master publish plan, gates, milestones, the four hardening proposals A–D.
- `16_PROD_BACKEND_PROVISIONING.md` + `17_PROD_BACKEND_RUNBOOK.md` — production stand-up checklist + executable runbook.
- `14_GATE1_LAWYER_BRIEF.md` + `15_PRIVACY_REWRITE_OUTLINE.md` — privacy work for the lawyer (human-only).
- `18_DIRECTOR_ONBOARDING.md` — governance / binding-order rulings.
- `19_FAMILY_COMMS_DRAFTS.md` — announcement + email templates.
- `20_IDENTITY_REMEDIATION_SITTING.md` — **HISTORICAL** under fresh launch; only its "Kevin needs a reachable super-admin identity" concept survives, re-homed as the Supabase-native bootstrap below.
- `06_FIREBASE_RUNBOOK.md` PART B — **HISTORICAL** (Firebase data cutover, cancelled).

---

## Current state

**Launch lines and heads verified from the public remotes on 2026-07-12:**
- **BSPC family app:** `demo/expo-go-compat` @ `a4c8861` (Ruling 58 launch line), with open PR 19 based at `7bc9680` and this local mission layered on it. The local migration ledger is now `00001`–`00021` with a 19-file pgTAP suite.
- **Coach app:** `demo/device-build` @ `9405fec` (Ruling 58 launch line). It contains the Wave-A product work, Functions hardening, and the closed dead-code gate.
- **UNIFY:** `main` @ `37b20a7` before this roadmap execution pass.

The supplied workspace is an exported snapshot with no `.git` directories. Branch promotion, PR merges, protection rules, and tags must be performed in real Git clones; local evidence here must never be presented as proof that those hosted actions occurred.

**GREEN test bars — these are the bar. Never advance with any of these red:**

| Repo / suite | Bar | How counted |
|---|---|---|
| Coach client jest | **1,212 tests / 129 suites** | `npm test -- --runInBand` |
| Coach Functions jest | **191 tests / 16 suites** | `npm --prefix functions test -- --runInBand` |
| Coach isolated `date.test` | **17 tests** | runs inside the client suite; see UTC gate below |
| BSPC client jest | **924 tests / 132 suites** | `npm test -- --runInBand` |
| BSPC pgTAP | **437 assertions / 19 files** | clean local reset, then `npm run test:rls` |

**Coach Functions launch export surface** (confirmed by code and exact-set test): `sweepAttendanceEvaluations` and `dailyDigest` only. Ruling 64 deleted the two portal callables; other deferred handlers remain source modules until their specific disposition is authorized. Ruling 65 requires both schedulers to leave Firebase before launch closure.

These bars were freshly measured locally on 2026-07-12 after restoring the public launch branches. Production, staging, device, legal, DNS, store, beta, and hosted Git state remain separate gates; local green bars do not imply launch readiness.

---

## Working agreement

1. **Tests are the bar.** Every change ends with all relevant suites at or above their green bar. A red bar = STOP and fix (or revert) before doing anything else. No "I'll fix the test later."
2. **One change at a time.** Each milestone is a sequence of small, single-purpose commits — one service, one migration, one config edit. Never bundle multi-surface changes. Each commit is independently reviewable and reversible.
3. **Canonical schema is law.** `UNIFY/01_CANONICAL_SCHEMA.sql` governs table shapes. Need a new column? Propose a migration in `BSPC/ACTIVE/supabase/migrations/` (next number in sequence) **plus** its pgTAP coverage in `supabase/tests/database/`. Never work around the schema in app code.
4. **Stage explicitly, never `git add -A` / `git add .`.** Add files by exact path. This prevents accidentally committing `.env`, secrets, generated junk, or PII.
5. **Never touch real secrets or PII.** Never read, print, paste, or commit `.env`, `.env.local`, service-account JSON, private keys, or any real swimmer/family/minor data. Before any command that could emit such data, inspect output for secrets/PII first; record only **sanitized** summaries (path/category/count/status) in `UNIFY/NOTES.md`.
6. **Commit-message convention.** Terse, accurate, present-tense subject. Body explains the "why" if non-obvious. **Branch first — never commit straight to `main`; open a PR for review.** End every commit message with a `Co-Authored-By:` trailer attributing the agent. The repo's prior convention (while Claude did the work) was `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`; as **Codex**, use your own equivalent (e.g. `Co-Authored-By: Codex <noreply@openai.com>`) rather than impersonating another agent.
7. **Timezone determinism gate.** Relative-date tests pin a safe midday clock or construct local calendar dates. Run both suites in the runner's normal timezone; a boundary-hour failure is a defect to fix, not a window to avoid.
8. **Husky / lint-staged is normal.** `npm install` runs `prepare` → `husky`. On `git commit`, a pre-commit hook runs `lint-staged` (ESLint `--fix` + Prettier on staged files). If the hook fails, the commit does not land — fix, re-stage, commit again. **Do not use `--no-verify`** unless explicitly told.
9. **Snapshots must stay unchanged.** Jest snapshot diffs are a deliberate gate. Never run `-u` to paper over a real change — investigate first. A snapshot change must be intentional and called out in the commit.
10. **zsh caveat.** This shell does not word-split unquoted variables the way bash does, and `=====` can trigger globbing/expansion surprises. Quote arguments; avoid bare `=====` in commands.
11. **Propose → wait → execute** for every hosted/live operation (see Ground rules). Print the target, wait for "go," run once.

---

## How to build, test, and run each repo

All commands use absolute paths. The shell resets cwd between calls, so `cd` into the repo as the first compound step.

### BSPC family app + backend — `/Users/kevin/bspc-unify/BSPC/ACTIVE`

```bash
# install
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm install

# run app (Expo)
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm start        # TUI: i / a / w
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run ios
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run android
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run web

# jest (bar = 924)
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm test
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run test:coverage   # 75% threshold

# pgTAP RLS suite (bar = 343) — needs Supabase CLI + Docker running
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm exec -- supabase --agent no start
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run test:rls   # bar = 437 / 19

# quality gates
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run typecheck
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run lint
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && npm run release:check:staging

# E2E (Maestro)
cd /Users/kevin/bspc-unify/BSPC/ACTIVE && maestro test .maestro/demo-account-smoke.yaml
```

### Coach app + Functions + parent portal — `/Users/kevin/bspc-unify/BSPC-Coach-App`

```bash
# install all three workspaces
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm ci --legacy-peer-deps
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm --prefix functions ci
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm --prefix parent-portal ci

# run
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm start                       # Coach app (Expo)
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm --prefix parent-portal run dev   # portal → localhost:3000
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm --prefix functions run serve     # Functions emulator

# jest — Coach client (bar = 1,212 / 129)
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm test -- --runInBand
cd /Users/kevin/bspc-unify/BSPC-Coach-App && TZ=UTC npm test -- --runInBand        # force UTC if near the boundary

# jest — Functions (bar = 191 / 16)
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm --prefix functions test -- --runInBand

# typecheck / lint / build
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm run typecheck
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm run lint:errors
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm --prefix functions run build
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm --prefix parent-portal run build

# whole-repo gate (typecheck + lint + both jest suites + functions build + portal + madge + custom checks)
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm run quality

# hygiene
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm run madge:circular   # no output = pass
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm run quality:dead-code
cd /Users/kevin/bspc-unify/BSPC-Coach-App && npm run sync:functions-shared:verify
```

> **Note on the functions↔app shared code:** `notificationRules` logic is mirrored into `functions/` by `scripts/sync-functions-shared.js`. If you edit the source, run `npm run sync:functions-shared` and verify with `:verify` — CI gates on it.

---

## The work — ordered milestones

Execute these in order. Each is its own branch off `fresh-launch-cd` (Coach) or a fresh branch off the BSPC baseline, merged only when its acceptance criteria are green. Several wait on a human dependency — start the coding that *doesn't* depend on the human, and stop cleanly at the gate.

> **Pre-flight (do once, before Milestone 1):** confirm all five green bars on a clean checkout. If any bar is red on `fresh-launch-cd` / the BSPC baseline as-is, that is the first bug to fix — do not start milestones on a red tree.

---

### Milestone 1 — Production Supabase Phase 1 stand-up

**Goal:** A real, empty production Supabase project with the full canonical schema applied, RLS active on every table, storage buckets created with correct policies, auth + email templates configured, and a synthetic password-reset proven end-to-end. No real family data yet.

**Concrete coding tasks:**
- **Verify the migration set is clean and idempotent against an empty DB.** Run the full 13-migration push on a *throwaway* Supabase project first (`npm exec -- supabase --agent no db push` from `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase`). Fix any migration that fails on a truly-empty database (the schema was authored partly under the migration era — assert no migration silently assumes pre-existing Firebase-derived rows).
- **Write a read-only schema/RLS/bucket audit script** (e.g. `BSPC/ACTIVE/scripts/audit-prod-schema.ts` or SQL in `supabase/tests/`) that asserts: 13 migrations present; RLS enabled on all `public` tables; the 4 storage buckets exist and are **private** with the documented size limits (media-audio 100 MB, media-video 500 MB, profile-photos 5 MB, practice-plans 25 MB); storage RLS policies present. This script is reused as the Phase-1 exit check.
- **Stage (do not send) the auth email templates** — invite + password-reset — as files/text in the repo (and into `19_FAMILY_COMMS_DRAFTS.md`). Configuring them in the dashboard and setting the redirect/deep-link allow-list is a Kevin/runbook step.
- **Write the synthetic end-to-end recovery test procedure** as a runnable checklist script: throwaway account → trigger reset (custom SMTP) → tap link on a real device → set password → sign in → confirm deep-link. Record pass/fail (sanitized) in `UNIFY/NOTES.md`.
- **Deploy the 4 BSPC edge functions** (`send-notification`, `approve-family`, `cleanup-tokens`, `calendar-feed`) — drafted/tested locally; the live `npm exec -- supabase --agent no functions deploy` runbook step is gated on Kevin's "go."

**Human dependency:** Kevin creates the production Supabase project (US region, Postgres 17), provides URL + keys at run-time, configures the SMTP sender and dashboard auth settings, and gives "go" before any command runs against the real project. **Do not create the project or any secret.**

**Acceptance criteria:**
- All 13 migrations apply cleanly to an empty throwaway DB; audit script passes (RLS on every table, 4 private buckets, storage policies present).
- BSPC bars still green: `TZ=UTC npm test` = 835, `npm run test:rls` = 343.
- Synthetic reset checklist documented and dry-run-proven on the throwaway project.
- `UNIFY/16_PROD_BACKEND_PROVISIONING.md` exit checklist fully checked (sanitized notes only).

---

### Milestone 2 — First super-admin bootstrap

**Goal:** Kevin becomes the single `super_admin` via a **Supabase-native** bootstrap (no Firebase, no data migration), with public signup closed and exactly one promotion.

**Concrete coding tasks:**
- Write a privileged bootstrap procedure (SQL or a small service-role script under `BSPC/ACTIVE/scripts/`) that:
  1. asserts public signup is closed and exactly **1** `auth.users` row exists;
  2. asserts exactly **1** `profiles` row, linked to that user, currently `role='family'` / `account_status='pending'`;
  3. asserts **zero** existing `coach_admin` and **zero** `super_admin`;
  4. `UPDATE`s exactly that one row to `role='super_admin'`, `account_status='approved'` — **exactly 1 row affected**;
  5. re-checks counts (exactly one approved super_admin, no other staff) before commit;
  6. prints **no email and no UUID literal** — sanitized confirmation only.
- Add tests proving the guard logic: pre/post row counts, "refuses if >1 user," "refuses if a super_admin already exists," "exactly one row updated." No email/UUID in test names or output.

**Human dependency:** Kevin creates his own Supabase auth account (email + password — his identity) and gives "go" to run the promotion live. You draft + test; Kevin runs against production with you reading sanitized output.

**Acceptance criteria:**
- Bootstrap script + tests committed and green.
- Dry-run on a throwaway project yields exactly one approved super_admin from a one-user/one-pending-profile starting state, and refuses every guard-violating starting state.
- No email/UUID emitted anywhere.

---

### Milestone 3 — Scheduler rehome

**Goal:** Decide and implement where the recurring jobs run, now that there's no Firestore. The candidates: `dailyDigest`, `sweepAttendanceEvaluations`, and `syncCalendar` (plus the attendance-rule evaluator `evaluateAttendanceRules` it feeds).

**Concrete coding tasks:**
- For each scheduled job, draft **both** delivery options and a parity test: (A) Supabase `pg_cron` / SQL function, vs (B) a scheduled Supabase Edge Function (or keep it as a Firebase scheduled Function re-pointed at Postgres). The jobs are: `functions/src/scheduled/dailyDigest.ts`, `functions/src/scheduled/sweepAttendanceEvaluations.ts`, `functions/src/scheduled/syncCalendar.ts`.
- `dailyDigest` reads recent attendance/notes/videos-in-review from Postgres, enumerates staff (`profiles` where role in coach_admin/super_admin) gated on `digest_enabled`, and inserts per-coach `in_app_notifications`. Prove the query parity against the canonical tables; apply the absent-exclusion filter on attendance counts.
- `sweepAttendanceEvaluations` re-evaluates recently-changed attendance rows idempotently (upsert with the expression-index conflict target). Prove idempotency: running twice produces one row, not duplicates.
- `syncCalendar` fetches the public iCal feed and upserts `calendar_events` keyed on `ical_uid` (UNIQUE), `coach_id = NULL`, merge-true so hand-edits survive — already designed; this is a re-point/move, not a rewrite.
- Present the two options per job to Kevin/Director for selection; implement the chosen one; keep the Functions jest bar green either way.

**Human dependency:** Kevin confirms the existing Firebase project supports scheduled Functions + Cloud Scheduler (read-only `project_id` check, billing-plan status only) **if** option B-on-Firebase is chosen; selects the delivery model. Any billing-plan change is Kevin-only.

**Acceptance criteria:**
- Chosen scheduler implemented; Functions jest = 115 (or the exact new count if the rehome adds/removes tests — count documented and intentional).
- Idempotency + query-parity tests green for digest and sweep.
- No scheduled job deploys to production before the Firebase-capability prerequisite is confirmed (if Firebase-hosted) or the Supabase cron is staged (if Supabase-hosted).

---

### Milestone 4 — Staff-assisted beta readiness

**Goal:** A proven, repeatable path for staff to onboard a real family (no public self-signup yet): create family → link profile → insert swimmers → record approval → resolve guardianships, all idempotent and rollback-tested.

**Concrete coding tasks:**
- Implement/verify the staff onboarding flow end-to-end against the canonical tables: `families` insert, `profiles.family_id` link, `swimmers` insert, `guardianships` insert (the access primitive — never client-inserted; via the SECURITY-DEFINER path), and an approval-log entry.
- Build the roster-seeding path via `BSPC-Coach-App/scripts/seed-roster.ts` (CSV → `swimmers`), **not** the demo-data script. Confirm rows land with correct fields and RLS visibility.
- Write a synthetic end-to-end onboarding proof against a throwaway Supabase: full flow + rollback; **duplicate-family handling** (re-run is idempotent or fails with a clear error); **swimmer name-collision detection**.
- Verify the Coach app surfaces the onboarded family correctly (roster, attendance, times) and the parent portal shows only that family's own swimmers.

**Human dependency:** OD-3 (new-account provisioning policy — admin-approve parents vs auto-approve; coach provisioning) is an **open governance decision** that gates the exact approval semantics. Surface it; implement the approved policy.

**Acceptance criteria:**
- Synthetic onboarding + rollback proof passes on a throwaway project, including duplicate and collision cases.
- Coach client + Functions bars green; BSPC bars green; pgTAP family-access tests (`001`, `005`, `006`, `015`) green.
- Operator checklist for staff onboarding written into the runbook.

---

### Milestone 5 — Device QA / closed beta

**Goal:** Both mobile apps run on real iOS and Android hardware against real (staging/prod) Supabase, with a full practice logged crash-free.

**Concrete coding tasks:**
- Populate the env matrix per surface (values from Kevin at build-time, never committed): BSPC mobile (`EXPO_PUBLIC_SUPABASE_URL`, `..._ANON_KEY`, Sentry DSN, PostHog key/host, EAS project id), Coach mobile (`EXPO_PUBLIC_SUPABASE_URL`, `..._ANON_KEY`, Sentry DSN), Coach Functions (`SUPABASE_URL` non-secret param, `SUPABASE_SERVICE_ROLE_KEY` via Firebase Secret Manager).
- Run `eas init` for BSPC to link it to EAS (match Coach's `owner`); commit the resulting `app.json`/`eas.json` projectId edits.
- Drive dev/internal EAS builds for both apps; run the Maestro smoke flows on-device (`BSPC/ACTIVE/.maestro/demo-account-smoke.yaml`; Coach `e2e/` stubs — flesh out at least a login+navigate smoke).
- Device test: log one full practice in the Coach app (check-in → attendance → notes → times) with no crash; verify offline persistence (airplane-mode toggle) and Supabase session cold-start restore.
- Confirm Sentry captures cleanly and no unhandled crashes appear during the beta loop.

**Human dependency:** Kevin's Apple Developer enrollment + Google Play account (for internal-test distribution), EAS credentials, real device. Sentry/PostHog project creation is Kevin's.

**Acceptance criteria:**
- Both apps install and run on a physical iPhone (iOS 15+) and Android (9+) against staging/prod.
- One full practice logged crash-free; Maestro smoke green on-device; Sentry clean for the session.
- All local bars still green.

---

### Milestone 6 — Invite-redemption mobile UI

**Goal:** A working in-app screen for parents to redeem an invite and have their guardianship created. The RPC exists and is tested; there is **no mobile caller yet**. This is a hard public-launch gate.

**Concrete coding tasks:**
- Build the invite-redemption screen in the family app (Expo) under `BSPC/ACTIVE/features/family/` (or a new `features/invites/`), wiring the existing `redeemInvite` RPC: enter/scan code → call RPC → on success, guardianship row exists and the swimmer appears.
- Add deep-link handling for `/invite/:token` in `BSPC/ACTIVE/app/_layout.tsx` (and the Coach app's deep-link config if coaches also redeem) so an emailed link opens the app and pre-fills the token.
- Cover the pending→approved transition per the OD-3 policy.
- Tests: generate invite code → enter → redeem → assert `guardianships` inserted; invalid/expired code → clear error; already-redeemed → idempotent/clear error. Use MSW to mock the RPC at the API-abstraction layer (never spy on raw Supabase).

**Human dependency:** none beyond the OD-3 policy decision from Milestone 4. This is pure coding.

**Acceptance criteria:**
- Redemption screen + deep link implemented; redemption test suite green.
- BSPC jest bar rises from 835 by the number of new tests (documented); pgTAP parent-invites tests (`013`) green.
- End-to-end: code generated by staff → redeemed in-app → guardianship + swimmer visible.

---

### Milestone 7 — Public-launch gates

**Goal:** Everything required to flip from closed beta to public launch, except the human-only legal/store items (those are tracked in the Kevin checklist).

**Concrete coding tasks:**
- **Proven recovery path:** custom SMTP verified, redirect/deep-link working, send-rate capacity confirmed, one synthetic e2e mobile reset passed (the script from Milestone 1) — re-run against production and record sanitized pass in `NOTES.md`.
- **Store assets you can produce:** generate screenshots via Maestro (`BSPC/ACTIVE/.maestro/app-store-screenshots.yaml`); draft metadata, age-rating answers, Data Safety / Designed-for-Families form *content* into `docs/app-store-metadata.md` for Kevin to submit.
- **Announcement + templates:** finalize the family announcement and invite/reset email copy in `UNIFY/19_FAMILY_COMMS_DRAFTS.md` (drafts only — Kevin sends).
- **Privacy/consent plumbing (the code half of Gate 1):** ensure media-consent and minor-photo reads are enforced in RLS/storage policies (pgTAP `007`, `010` cover the COPPA walls); wire any consent-capture flag the lawyer's architecture requires. **You do not decide compliance** — you implement the lawyer's decision.

**Human dependency (the long pole):** lawyer's COPPA/SafeSport review + policy/ToS redline (Gate 1); store accounts + listings + form submission; sending the real announcement and triggering real recovery email. **Required ordering Kevin must follow:** approve announcement → send via existing team channel **before** Firebase sign-in is disabled → prove recovery path → only then trigger real recovery + disable old sign-in.

**Acceptance criteria:**
- Recovery path proven against production (sanitized record).
- COPPA-wall pgTAP green (`007`, `010`, `009`, `011`, `012`, `013`); consent enforced in RLS/storage.
- Store assets + announcement drafts complete and handed to Kevin.
- All five bars green.

---

### Milestone 8 — Final cleanup

**Goal:** Remove Firebase remnants and dead code that no longer have a live consumer, leaving a clean Supabase-native tree.

**Concrete coding tasks:**
- Remove/retire the obsolete legacy config once production Supabase is confirmed live and verified: `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `storage.rules` (these are superseded by Supabase RLS + storage policies). Keep them only if Firebase-hosted schedulers were chosen in Milestone 3.
- Retire any Cloud Functions with no v1 consumer (the media-AI trio if Proposal C made them permanently dark; the parent-portal callables `getParentPortalDashboard`/`getParentSwimmerPortalData` once the portal reads Postgres directly).
- Update `.env.example` in both repos: drop all `FIREBASE_*` keys, keep `SUPABASE_*`. Confirm zero Firebase imports in app runtime (`grep` + madge).
- Remove dead-code flagged by `knip`; confirm `npm run madge:circular` clean.
- Finalize docs: `README.md`, `CODEBASE_GUIDE.md`, and a "launch complete" note. Mark the historical UNIFY docs clearly.

**Human dependency:** deleting the Firebase *project* itself is Kevin's call (not authorized by fresh-launch rulings) — do not do it.

**Acceptance criteria:**
- Legacy Firebase config removed (or explicitly retained with reason); zero Firebase runtime imports.
- `knip` clean; `madge:circular` clean; all bars green (Functions bar adjusts to the new export count — documented).
- Docs reflect the shipped, Supabase-native state.

---

## Definition of done

**Per-milestone:**
- [ ] **M1 Prod Supabase Phase 1** — 13 migrations clean on empty DB; RLS on every table; 4 private buckets + policies; auth/email staged; synthetic reset proven; BSPC 835 + pgTAP 343 green.
- [ ] **M2 Super-admin bootstrap** — guarded one-row promotion script + tests green; dry-run yields exactly one approved super_admin; no email/UUID emitted.
- [ ] **M3 Scheduler rehome** — chosen delivery implemented for digest/sweep/syncCalendar; idempotency + parity tests green; Functions bar green.
- [ ] **M4 Staff-assisted beta** — synthetic onboarding + rollback + duplicate/collision proofs pass; family-access pgTAP green; operator checklist written.
- [ ] **M5 Device QA** — both apps on real iOS + Android; full practice crash-free; Maestro smoke + Sentry clean.
- [ ] **M6 Invite-redemption UI** — in-app redemption screen + deep link; redemption tests green; guardianship created end-to-end.
- [ ] **M7 Public-launch gates** — recovery path proven on prod; COPPA-wall pgTAP green; consent enforced; store assets + announcement drafted for Kevin.
- [ ] **M8 Final cleanup** — Firebase remnants removed; knip + madge clean; docs current; bars green.

**Overall launch-ready:**
- [ ] Production Supabase live, schema applied, RLS proven by pgTAP against the canonical walls.
- [ ] Kevin is the sole `super_admin`; public signup gated per approved policy.
- [ ] Schedulers running on the chosen platform; daily digest + attendance sweep idempotent.
- [ ] Staff onboarding path proven; invite-redemption UI shipped.
- [ ] Both apps pass device QA; closed beta with real coaches/families completed.
- [ ] Recovery email proven end-to-end on production hardware.
- [ ] **(HUMAN)** Lawyer Gate-1 sign-off; policies hosted at public URLs; store listings live; apps submitted and approved.
- [ ] All five green bars (Coach 1103/108, Functions 115/12 (or documented post-cleanup count), BSPC 835, pgTAP 343, date 17) green at the moment of each ship.

---

## Guardrails & gotchas

- **UTC date flake (Coach):** `date.test` flakes between 00:00–01:59 UTC. Don't run the full Coach suite or `date.test` in that window; force `TZ=UTC` if you must. BSPC's 835 bar only holds under `TZ=UTC` — always set it there.
- **Husky pre-commit:** `lint-staged` runs ESLint + Prettier on commit; a failure blocks the commit. Fix and re-stage. No `--no-verify`.
- **Snapshot stability:** never `jest -u` to silence a diff. A snapshot change must be deliberate and explained.
- **Explicit staging only:** never `git add -A`/`git add .`. Stage by path. This is the main defense against committing `.env`/secrets/PII.
- **zsh quirks:** no automatic word-splitting of unquoted vars; `=====` can expand. Quote arguments.
- **Frozen pgTAP publication counts:** realtime publication membership is asserted as code in the notifications/calendar pgTAP tests (`011`, `012`). If any migration touches the publication, update the membership proof **in the same commit**, or the suite goes red. Counts are pinned in more than one test — change them together.
- **Migrations must apply to an empty DB:** under fresh launch there is no pre-existing data. Any migration that implicitly assumes Firebase-derived rows must be fixed before prod push. Test on a throwaway empty project first.
- **Firebase remnants are still wired in some paths:** Cloud Storage upload paths for audio/video may still point at Firebase; `firestore.rules` / `storage.rules` files remain in the Coach repo. Re-point or retire deliberately (Milestones 3 + 8) — don't deploy stale Firebase rules to production.
- **`firebase-admin` lingers in scripts only:** retained for tooling, not app runtime. Don't reintroduce it into `src/`/`app/`. Confirm zero Firebase runtime imports with grep + madge before declaring cleanup done.
- **service-role key is server-only:** never in any `EXPO_PUBLIC_*`, never in `.env.local` you create, never in CI secrets beyond what Kevin sets, never in logs. Coach Functions read it from Firebase Secret Manager (bound per-function, fail-closed).
- **Supabase calls go through the API-abstraction layer** (`features/*/api.ts` in BSPC; `src/services/*.ts` in Coach). Mock those with MSW in tests; never spy on raw `supabase.from(...)`.
- **No barrel `index.ts` re-exports** in BSPC — they break Fast Refresh. Import directly.
- **Commit-message trailer is mandatory** on every commit; PR-body trailer on every PR.
- **HISTORICAL docs:** `06_FIREBASE_RUNBOOK.md` PART B and `20_IDENTITY_REMEDIATION_SITTING.md` describe the cancelled data cutover. Mine them for the *concepts* that survive (e.g. super-admin reachability), not the steps.

---

## Human-only checklist (Kevin)

Codex never attempts these and never blocks waiting silently — it hands them over with a one-line "this is yours." Only **you** (or your lawyer) can do them:

- [ ] **Lawyer — Gate 1.** Engage a youth-sports / ed-tech privacy lawyer for COPPA / verifiable-parental-consent / SafeSport review; get the policy + ToS redline and a go/no-go on the compliance claims. (Codex drafts `14_GATE1_LAWYER_BRIEF.md` / `15_PRIVACY_REWRITE_OUTLINE.md`; the lawyer decides.)
- [ ] **Publish policies** at public URLs and confirm the final text (Codex can format; you sign off + host).
- [ ] **Apple Developer + Google Play accounts** — create, verify identity, set up billing; submit both app listings; fill age-rating / Data Safety / Designed-for-Families forms; provide screenshots + metadata to the stores.
- [ ] **Create the production Supabase project** (US region, Postgres 17) and provide URL + keys at run-time.
- [ ] **Create / confirm the Firebase project** (only if Firebase-hosted schedulers are chosen) and confirm it supports scheduled Functions + Cloud Scheduler; approve any billing-plan change.
- [ ] **Create the EAS, Sentry, and PostHog projects**; provide their IDs/DSNs/keys at build-time.
- [ ] **Create every real secret** — DB password, service-role key, anon key, SMTP credentials, EAS/Apple/Google tokens. Type them into provider dashboards; never paste them to Codex.
- [ ] **Register + verify the custom SMTP sender** (domain verification, send-rate capacity).
- [ ] **Code signing** — certificates, provisioning profiles, EAS signing config.
- [ ] **Create your own Supabase auth account** for the super-admin bootstrap (your email + password) and give "go" to run the one-row promotion.
- [ ] **Send the family announcement** through your existing verified team channel, in the required order: announce → send **before** old sign-in is disabled → prove recovery path → trigger real recovery email + disable old sign-in.
- [ ] **Any payment** or billing action.
- [ ] **Delete the old Firebase project** (your call — not authorized by the fresh-launch rulings).
- [ ] **Final "go" before every live production command** Codex proposes (Codex prints the target; you confirm).

---

*This Mission.md is the single self-contained handoff. The canonical schema (`UNIFY/01_CANONICAL_SCHEMA.sql`) is law; the five green bars are the gate; one small reviewable change at a time is the method; and every item on the Human-only checklist is a wall Codex will not climb. Build the last mile carefully and with maximum transparency.*
