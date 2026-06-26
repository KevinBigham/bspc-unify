# 🔄🔴 FRESH-LAUNCH FORK — DIRECTOR RULING 56 + 57 (2026-06-25)

**READ FIRST. This supersedes the migration framing in the rest of this document.** Everything below that describes a Firebase→Supabase migration, Sitting 2, identity remediation, the R54 probe, or Gate R / Gate W is **HISTORICAL and SUPERSEDED — NON-EXECUTABLE.** No Executor may run any cutover, remediation tool, Firebase probe, or Firebase deployment.

**Launch model**
```text
Fresh Supabase launch
No Firebase migration
No Sitting 2
No Firebase identity remediation
No R54 Firebase probe
No Gate R or Gate W
```
The two Firebase projects were attested empty by Kevin — an **operator attestation, NOT a repository proof.** Ruling 57 does **not** authorize deletion of either Firebase project.

**Repository topology**
```text
5070f877 = historical audit artifact; never merge
launch base = Coach main 0c0f82b
future replay order = C then D
A and B = historical Firebase transition work
```
No branch creation or cherry-pick occurs under Ruling 57.

**New binding order**
```text
core governance reconciliation
→ Coach launch branch replay C
→ Coach launch branch replay D
→ production Supabase Phase 1
→ first-super-admin bootstrap
→ scheduler rehome
→ staff-assisted beta onboarding
→ device QA / closed beta
→ invite-redemption mobile UI
→ public-launch gates
→ dead-code and Firebase cleanup
```

**First-super-admin bootstrap** — concept approved; **exact SQL and hosted execution are HELD.** The eventual transaction must require:
```text
public signup closed
exactly 1 auth user
exactly 1 profile
profile maps to that user
profile initially family/pending
zero coach_admin
zero super_admin
privileged non-user execution context
exactly 1 row updated
final exactly 1 approved super_admin
full counts rechecked before commit
no email or UUID literal in SQL/output
```

**Scheduler rehome** — design-stage; neither implementation selected nor built:
```text
dailyDigest: SQL-Cron candidate
sweepAttendanceEvaluations: SQL-Cron versus scheduled Edge Function — undecided pending parity audit
```

**Onboarding** — Closed beta: the **existing admin approval path** is the staff-assisted candidate (creates the family, links the profile, inserts swimmers, records an approval log); acceptable **only after** synthetic end-to-end proof, an operator checklist, duplicate handling, and rollback verification. **Staff never redeem a parent invite.** Public launch: the **mobile invite-redemption UI is mandatory** (the RPC is tested but has no mobile caller).

**Gate 6** — Retire migrated-family and Firebase-shutdown messaging. Retain:
```text
Supabase email provider
SMTP/delivery proof
invite template
password-reset template
redirect and deep-link allow-list
synthetic invite/reset end-to-end proof
```

**Cleanup accounting**
```text
−105 retired
−102 provisional
1103 provisional
```
Exact cleanup paths and test bars require a later deletion diff and an actual test run.

**— End fresh-launch banner (Rulings 56 + 57). Historical content follows unchanged. —**

---

# HANDOFF — BSPC-UNIFY Migration

**For: the next Claude Code session. Read this first, top to bottom, before touching anything.**
**Written: 2026-06-22, at the close of SITTING 1 (the dry-run rehearsal).**

> **TL;DR** — Two apps (a swim parent-app on Supabase/Postgres + a coach app on Firebase/Firestore)
> are being folded into ONE canonical Postgres backend. All the code is written and proven; the
> migration tooling is built. We just finished **Sitting 1 — the mandatory dry-run rehearsal on
> throwaway projects.** It PASSED, and it earned its keep: it caught and fixed one cutover-blocking
> bug before any real family's data could be touched. **The next real step is SITTING 2 — the actual
> cutover with real data — but that does NOT start until the DIRECTOR (a separate chat) blesses the
> new baseline and schedules it.** Do not start Sitting 2 on your own.

---

## 0. Who you are, who's in the room

- **You = Claude Code, the EXECUTOR seat.** You do the hands-on work: propose exact commands, run them
  only after explicit approval, preserve outputs, keep the test bars green.
- **There is a separate DIRECTOR chat.** The director sets policy, ratifies decisions (`[DECIDE]` items),
  audits each sitting's report against the rules, and writes the next copy-paste prompt. When in doubt
  about scope or a judgment call, the answer is "surface it to the director," **never** "improvise."
- **Kevin = the founder, and he is a non-coder, live at the keyboard.** Explain everything in plain
  English. Tell him exactly what to copy/paste and where, one step at a time. He drives; you guide.

---

## 1. What this project is (30 seconds)

`/Users/kevin/bspc-unify/` holds **three separate git repos** (the parent folder is NOT a repo):

| Repo | What it is | npm root(s) | GitHub |
|------|-----------|-------------|--------|
| **BSPC** | Swim **parent** app (Expo/React Native), already on **Supabase/Postgres** | `BSPC/ACTIVE` | `github.com/KevinBigham/BSPC` |
| **BSPC-Coach-App** | **Coach** app (Expo) + Next.js parent-portal + Cloud Functions, on **Firebase/Firestore** | repo root, `functions/`, `parent-portal/` | `github.com/KevinBigham/BSPC-Coach-App` |
| **UNIFY** | The migration design + logbook repo (this folder) | n/a (docs) | `github.com/KevinBigham/bspc-unify` |

**Goal:** move the Coach App's Firestore data layer onto the BSPC canonical Postgres schema, behind the
existing service interfaces, **keeping both test suites green throughout.** Business logic and UI do not
change — only the data layer underneath. Both apps are **pre-launch** (no production users yet); the repos
are the source of truth.

---

## 2. EXACT STATE RIGHT NOW

**Repo heads (all clean, all pushed to GitHub):**

| Repo | HEAD | Meaning |
|------|------|---------|
| **BSPC** | `880aed8` | **FROZEN** — do not touch without an explicit ruling. Byte-identical to its proven runs. |
| **BSPC-Coach-App** | `0c0f82b` | The Sitting-1 fix (mediaConsent date coercion). **NEW baseline.** |
| **UNIFY** | `b0866da` (+ this HANDOFF commit) | The logbook through Sitting-1 close. |

**Green test bars (this is the law — never advance with red):**

| Suite | Count | How to run |
|-------|-------|-----------|
| BSPC parent app (jest) | **835** — green **only under `TZ=UTC`** | `cd BSPC/ACTIVE && TZ=UTC npm test -- --runInBand` |
| BSPC pgTAP (DB tests) | **343** (Files=15) | needs local Supabase up + migrations applied — see §7 |
| Coach client (jest) | **1199** (111 suites) | `cd BSPC-Coach-App && npm test -- --runInBand` |
| Coach Functions (jest) | **115** | `cd BSPC-Coach-App && npm --prefix functions test -- --runInBand` |

**The whole migration is code-complete.** Phases A–K (identity, swimmers, attendance, times, notes, media,
notifications, calendar/meets/plans, parent invites, aggregations, UI sweep) all landed and are proven. The
"build era" is closed. What remains is **operation** — running the cutover tools against real data.

**The four cutover tools** (all in `BSPC-Coach-App/scripts/`, all gated plan-only-by-default behind HARD-STOP
headers; they only write with `--execute` + an explicit target):
1. `probe-firebase-inventory.ts` — read-only census of Firebase → builds the keep/drop sheet.
2. `provision-identities.ts` — creates the Supabase auth users.
3. `backfill-identity-graph.ts` — builds profiles + roles + coach_groups + (deferred) guardianships.
4. `backfill-roster.ts` — builds the swimmer roster + the swimmer map.

Each tool is split into a thin I/O **shell** (`*.ts`) and a zero-import pure **plan** module (`*-plan.ts`)
that owns the logic and carries the jest pins.

---

## 3. What just happened — SITTING 1 (the dry-run)

We ran the **entire migration spine on 100% synthetic data against throwaway projects**: a LOCAL Supabase
(localhost = safest) + a fresh throwaway Firebase project (`bspc-throwaway`, Spark tier). Full readback is
banked in `NOTES.md` (search `=====BEGIN SITTING-1 CLEAN RE-RUN READBACK=====`).

**Outcome: PASSED — and it caught a real bug.**

- The safety gate worked on the first try: Kevin's first downloaded key resolved to the **real** project
  (`bspc-coach-app`). We HARD-STOPPED, he deleted it and made a genuine throwaway. **Nothing real was touched.**
- The dry-run surfaced **one cutover-blocking defect**: `backfill-roster` read `mediaConsent` **raw**, so a
  live Coach doc's `mediaConsent.date` / `expiresAt` (Firestore `Timestamp`s) hit the `timestamptz` columns
  as `{_seconds,_nanoseconds}` and **aborted the INSERT for every consented swimmer** (28/30 demo swimmers
  failed; only the 2 with no consent inserted — the diagnostic signature).
- **The fix** (Coach `a5925aa` → `0c0f82b`): added `isoStringOrNull` + `normalizeExportedConsent` to
  `backfill-roster-plan.ts` (the pure module), `readSwimmerExport` now uses it. `reconcile.ts` (BSPC) was
  **unchanged** — it always expected strings; the export side was under-converting. +8 regression pins
  (`backfill-roster-plan.test.ts` 43 → 51); Coach jest **1191 → 1199**.
- A **pristine clean re-run then passed every criterion**: 3 auth users, 3 profiles
  (super_admin/coach_admin/family), 14 coach_groups, 32 swimmers created + 35 mapped, audits clean, the
  deferred step-6a guardianship landed (Demo Parent → BSPC Demo 01), both smoke logins OK, and RD-D1
  (name-only collision), RD-D2 (ambiguous → data-fix), and RD-D5 (Masters group) all fired as designed.
- **Teardown done:** throwaway Firebase deleted by Kevin, local Supabase stopped, transient scripts removed,
  throwaway key removed.

---

## 4. WHAT'S NEXT — your job ⛔ SUPERSEDED (Rulings 56 + 57)

> **Historical / non-executable.** Sitting 2 is cancelled; there is no cutover. The current "what's next" is the fresh-launch binding order in the banner at the top of this file. Do **not** act on the Sitting-2 sequence below.

**Do NOT start Sitting 2 yourself.** The sequence is:

1. **The DIRECTOR blesses the new Coach baseline** `0c0f82b` / 1199 as the frozen head (replacing `a5925aa` / 1191).
2. **The DIRECTOR schedules SITTING 2 — the REAL cutover** (UNIFY `06_FIREBASE_RUNBOOK.md`, PART B).
3. Then you (executor) run it with Kevin live, command-by-command, propose-and-wait, exactly per the spine in §6.

If Kevin asks you to "continue," your honest answer is: **the rehearsal is done and clean; the next move is
the director's call** (bless baseline → schedule Sitting 2). You can help him prep (re-confirm green bars,
read the runbook, line up his real super_admin uid and the account announcement), but the real cutover is a
deliberate, director-scheduled, Kevin-live operation — not something to kick off casually.

---

## 5. THE LAWS still in force — read before touching anything

These are not optional. They held all through the build and the dry-run; they hold harder for the real cutover.

**Safety / data (absolute):**
- **KEY-SAFETY:** before running ANY tool or seed, FIRST print the Firebase `project_id` it will resolve
  (from the key file — print **only** the project_id, never secrets) AND the Supabase URL it will target,
  and have Kevin confirm them. For a dry-run both must be throwaways. For Sitting 2 they are the REAL
  projects — which is exactly why every command needs his explicit go.
- **NEVER run `seed-roster.ts` or `seed-meets.ts`** — they are hard-wired to the repo-root
  `google-service-account.json`, which is the **REAL** key. Every legitimate tool run points
  `FIREBASE_ADMIN_KEY_PATH` at the intended (throwaway, or at cutover the real) key explicitly.
- **Never read, print, paste, or commit** `.env` files, service-account files, private keys, or real
  roster/minor data. **Never put real minors'/students'/swimmers' data** in fixtures, docs, agent context,
  or reports. If you find secrets or PII, STOP and report only path / category / action (redacted).
- **Never `git add .` or `git add -A`.** Show files first, stage explicitly by path.

**Process:**
- **Propose each exact command and WAIT for Kevin's explicit "yes/go" before running it. Never batch-run**
  the cutover operations. (Running the local test bars to confirm green is safe/read-only.)
- **Record sanitized tool output in `UNIFY/NOTES.md`** — inspect every output for secrets, PII, account identifiers, roster data, and media metadata first; record sanitized output only (sensitive findings as path/category or count/status only; never a secret, UID, email, minor, or roster value). `NOTES.md` is an append-only logbook.
- **Tests are the source of truth — never advance with red tests.** Both repos' suites are the bar.
- **The canonical schema (`UNIFY/01_CANONICAL_SCHEMA.sql`) is law.** If code wants something the schema
  lacks, propose a migration — don't hack around it.
- **One service / one change at a time. Ratify `[DECIDE]` items (in words, with the director) before code.**
- **Any gap or surprise = numbered decisions for the director, never a silent fix.**
- **Commit messages end with:** `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

## 6. The Sitting-2 spine ⛔ SUPERSEDED & NON-EXECUTABLE (Rulings 56 + 57 — no cutover; historical record only)

> The cutover spine below must **not** be run. Fresh Supabase launch; no Sitting 2. Retained for the historical record.

*(original heading:)* **6. The Sitting-2 spine (the REAL cutover — for when the director schedules it)**

This is the operation, in order, per `06_FIREBASE_RUNBOOK.md` PART B. **Sitting 2 is NOT a dry-run — it
touches real data. Maximum care, propose-and-wait on every step.**

1. **§B0 probe** — run `probe-firebase-inventory.ts` (read-only) → produces the **keep/drop sheet** (which
   Firebase collections/files migrate vs. are dropped). ⚠️ This is the **one tool that has not had a live
   run yet** (it was built but never executed; the dry-run didn't exercise it). It is read-only and the
   lowest-risk tool — but treat its first live run with appropriate attention.
2. **§B1 file copy** — storage migration (have ≥500MB of Supabase storage provisioned first; practice-plans
   need path remap + row rewrite on both halves).
3. **Identity spine:**
   - `provision-identities --execute` (creates auth users; OD-6 = fresh credentials, no password import).
   - `backfill-identity-graph --execute --super-admin-uid=<Kevin's real uid>` (NM-1: Kevin is the sole
     super_admin; step-6a guardianships **defer** until the roster map exists).
   - `backfill-roster` — plan first; resolve any real name-only collisions via `--reviewed-collision=<docId>`
     (create-as-new only, never a match) and any real ambiguities via a **source-data fix + idempotent
     re-run** (there is no override channel for ambiguity — that's by design); then `--execute`.
   - `backfill-identity-graph` **RE-RUN** — now the deferred step-6a guardianships land.
4. **Audits** — `auditSwimmerMap`, `auditIdentityMap`, `auditGuardianships`, and the §6.1 probe (every parent
   uid resolves a non-empty profile). All must be clean.
5. **§B2 data manifests** — goals (§B2.1) and group_notes (§B2.2); out-of-domain tag / unmapped coach = STOP.
6. **Go live** — the app-side swap is already code-landed (AuthContext, portal, etc.). Smoke-test: one coach
   login + one parent-portal login + parent→swimmer resolution.
7. **Announcement precondition** — Kevin sends the account announcement to families **before** disabling
   Firebase sign-in (06 §B6 step 1). Only then disable Firebase sign-in.
8. **§B6 decommission** — collapse Functions C1..C6 (retire the four tools' tests; the Functions bar retires),
   delete the `scripts/` tooling, then delete the Firebase project.

The RD-D rules govern roster edge cases: **D1** name-only collision → `--reviewed-collision` flag, create-as-new
only; **D2** ambiguous → fix source data + re-run (no override); **D3** `created_by` via the identity map (miss
= NULL + reported); **D4** idempotent (a mapped doc is skipped; a created swimmer is never re-created); **D5**
practice-group domain is the 8-value end-state incl. 'Masters'.

---

## 7. Environment & toolchain (how to even run the bars)

- **Node** v24.16.0, **npm** 11.13.0. Install deps with `npm ci`. **The Coach App root needs
  `npm ci --legacy-peer-deps`** (BSPC/ACTIVE and functions/ are plain `npm ci`).
- **Local Supabase** (for pgTAP + as the dry-run substrate) runs on Docker via **colima**. After a reboot:
  1. `colima start` (FIRST — Docker won't be up otherwise).
  2. `cd BSPC/ACTIVE && supabase start -x vector,logflare`
     — the `vector` container can't bind-mount the docker socket under colima/virtiofs, and **`-x vector,logflare`**
     is the working exclusion on supabase CLI 2.105 (an older note says `-x vector,analytics`, but "analytics"
     is an invalid container name on 2.105 — use `logflare`).
  3. `supabase migration up --local` **before** running pgTAP (a new migration's columns won't exist otherwise).
  4. `npm run test:rls` (or `npx supabase test db --local`) for the 343 pgTAP tests.
- **supabase CLI** = the brew binary (2.105.x); `npx supabase` resolves to it (it's not in node_modules).
- The cutover tools need env vars: `FIREBASE_ADMIN_KEY_PATH` (the service-account key path),
  `BSPC_MIGRATION_SUPABASE_URL` + `BSPC_MIGRATION_SUPABASE_SERVICE_ROLE_KEY` (the target Postgres). No defaults.
- Disabling/re-enabling the `on_auth_user_created` trigger on `auth.users` requires the
  **`supabase_admin`** superuser role (`psql -U supabase_admin`) — `postgres` is NOT the owner and will get
  "must be owner".

---

## 8. Gotchas that have already bitten (don't relearn these)

- **TZ:** BSPC jest is green **only under `TZ=UTC`**. Two `meets/transforms.test.ts` tests
  (`getMeetStatus`) fail in a western evening timezone — pre-existing, not a regression.
- **Coach pre-commit formatter:** `lint-staged` (eslint --fix + prettier --write) **restyles files at commit
  time.** Always cite committed-tree line numbers via `git show HEAD:<file>`, and re-run the suite on the
  committed tree after a commit if the hook touched files.
- **Confirmed-harmless flake (NOT a regression):** `src/contexts/__tests__/AuthContext.test.tsx`
  "cleans up push subscriptions before sign out" occasionally flakes under full-parallel jest load (~458ms
  async cleanup). Passes solo and on re-run. Ignore it; don't chase it.
- **Coach `tsc`** carries ~104 pre-existing error lines (mock-pattern tests). **The Coach bar is jest-only** —
  don't chase tsc mid-task; just confirm a change contributes zero new lines.
- **pgTAP `ALTER PUBLICATION` membership is pinned EXACTLY in TWO tests** — pgTAP 011 AND 014:19 — they must
  update together with any future membership change (currently 25 tables).
- **zsh:** a bare `=====` in an `echo` trips `=`-expansion — quote it. Compound-command `cd` persists across
  `&&` — PWD-prove every cited bar run.
- **`seed-demo-data.ts` can't run standalone** (line ~276 `group: undefined` + a `getFirestore()` without
  `ignoreUndefinedProperties`). It's a convenience seeder, **NOT on the cutover path.** Logged to fix
  whenever convenient (see §9). At dry-run we reused its exported `buildDemoWrites()` from a transient wrapper.

---

## 9. Open / deferred items

- **The §B0 firebase-inventory probe has not had a live run.** It's read-only and runs first at Sitting 2.
  If the director wants extra assurance before the real cutover, a tiny throwaway probe-only run could be
  done — but the throwaway is already deleted, so that would mean standing up a fresh one.
- **`seed-demo-data.ts` standalone bug** (above) — convenience-seeder only, fix whenever convenient.
- **Decommission test math:** the +8 Sitting-1 regression pins live in `backfill-roster-plan.test.ts`, which
  is itself one of the carve-out tool tests that retires at §B6.5. The retirement delta is **−105**, and the
  floor is the **formula — canonical Coach client bar at decommission − 105** (current arithmetic `1199 − 105 = 1094`;
  the old `−106 / 1093` is **rejected** — it was a back-calculated target). RATIFIED (Director Ruling 03 §1);
  accounting only — deletion is one named change after cutover + data verification.

---

## 10. Where the real detail lives (pointer map)

- **`UNIFY/NOTES.md`** — the append-only logbook (6,600+ lines). The full Sitting-1 record + verbatim
  readback is in the last ~200 lines. Every phase's landing log is here.
- **`UNIFY/00_TERRAIN.md`** — the data-model reconciliation map (start here for "why does the schema look
  like this").
- **`UNIFY/01_CANONICAL_SCHEMA.sql`** — the canonical schema = law. Appendix A documents the storage buckets.
- **`UNIFY/02_SCHEMA_REDTEAM.md`** — the adversarial schema review.
- **`UNIFY/03_MIGRATION_PLAYBOOK.md`** / **`04_CROSS_TIER_SEQUENCING.md`** — per-service mechanics + phase order.
- **`UNIFY/05_PHASE_A_IDENTITY.md`** — §6 is the auth-cutover mini-plan; **§6.5 step 1 is the dry-run spec**
  we just executed.
- **`UNIFY/06_FIREBASE_RUNBOOK.md`** — PART A (history) + **PART B = the real-cutover runbook** (§B0..§B6).
- **`UNIFY/07`–`12`** — the per-phase plans (attendance, times, notes, media, notifications, calendar/meets).
- **Memory files** (`~/.claude/projects/-Users-kevin-bspc-unify/memory/`) — `bspc-unify-project`,
  `bspc-unify-rules`, `bspc-unify-green-baseline`, `bspc-unify-migration-progress`. These auto-load each
  session; they mirror this handoff's state at a higher altitude.

---

## 11. Resume checklist (the first things to do next session)

1. **Read this file, then skim the tail of `NOTES.md`** (the Sitting-1 readback) and the
   `bspc-unify-migration-progress` memory.
2. **Confirm the repos are clean and match GitHub:** `880aed8` (BSPC), `0c0f82b` (Coach), latest (UNIFY).
3. **Confirm green bars if you're about to do work** (TZ=UTC for BSPC; `--legacy-peer-deps` for Coach root).
4. **Ask Kevin where the director landed:** has the new baseline (`0c0f82b`/1199) been blessed? Is Sitting 2
   scheduled? Don't start the real cutover without that.
5. **When Sitting 2 is greenlit:** open `06_FIREBASE_RUNBOOK.md` PART B, re-read the §5 laws above, and run
   the spine in §6 — Kevin live, propose-and-wait, **sanitized** outputs to `NOTES.md` (inspect for secrets/PII/roster/media-metadata first), real-data care.

**Bottom line: the hard build is done and the rehearsal proved it works. The next milestone is the real
cutover — deliberate, director-scheduled, Kevin-live. Be careful, be plain-spoken with Kevin, and surface
anything surprising instead of fixing it silently.**
