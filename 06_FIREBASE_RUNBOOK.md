# 06 — Firebase Runbook: PART A Go-Live (historical) + PART B Decommission

> **AMENDED IN PLACE 2026-06-11 per D-CUT2 (CUT-2 round, e71050a/D-J2
> annotation precedent).** The original go-live guide is kept below as
> **PART A**, marked historical/optional — it documents the project PART B
> kills, and remains useful only if a live Firebase project must be stood
> up for the §B0 probe or the mandatory dry-run. **PART B is the
> DECOMMISSION RUNBOOK** — the step every banked pointer calls "the
> 06-runbook step" (the K landed log, the D-K2 caveat, the D-J7
> correction) lands there.

---

# PART A — Go-Live Runbook (HISTORICAL / OPTIONAL)

**You do NOT need any of this for the migration work or the test suites.**
Every jest suite mocks Firebase entirely, and the code-first migration never
talks to a live Firebase project. You need this runbook only when you want to
**run the apps for real** (Coach App on a phone/simulator, parent portal in a
browser against real data) or **deploy** the security rules and Cloud
Functions. Until then, this file is just sitting here waiting.

| You want to… | You need |
|---|---|
| Run tests / continue the migration | **Nothing.** Skip this runbook. |
| Run the Coach App or parent portal against real data | Sections 1–3 |
| Deploy Firestore/Storage rules + Cloud Functions | Sections 4–5 |
| Seed demo data | Section 6 |
| Understand what changes after the Supabase cutover | Section 7 + PART B |

Everything below was derived from the repo itself (`.firebaserc`,
`firebase.json`, `.env.example`, `README.md`) — file paths are exact.

---

## 1. Create the Firebase project (one time, ~5 minutes)

1. Go to **https://console.firebase.google.com** and sign in with the Google
   account that should own the project.
2. Click **"Create a project"** (or "Add project").
3. Project name: type **`bspc-coach`** — use this exact name. The repo's
   [`.firebaserc`](../BSPC-Coach-App/.firebaserc) is already pinned to project
   id `bspc-coach`, and its Storage rules target is pinned to the bucket
   `bspc-coach.firebasestorage.app` (which is the default bucket name a
   project with this id gets). If Firebase says the id is taken and offers
   something like `bspc-coach-1a2b3`, accept it BUT you must then edit
   `.firebaserc` to the new id in both places (the `"default"` entry and the
   storage target key/bucket name).
4. Google Analytics: **disable** it (toggle off) — the app doesn't use it.
5. Click **Create project**, wait for it to finish, click **Continue**.

## 2. Enable the three services (one time, ~5 minutes)

All of these are in the left sidebar under **Build**.

1. **Authentication** → click **Get started** → **Sign-in method** tab →
   click **Email/Password** → toggle **Enable** (leave "Email link" off) →
   **Save**. That is the only sign-in method either app uses.
2. **Firestore Database** → **Create database** → choose location
   **us-central1** (any region works, but you can never change it later) →
   choose **Start in production mode** → **Create**. Don't write any rules in
   the console — the repo's [`firestore.rules`](../BSPC-Coach-App/firestore.rules)
   get deployed in section 5.
3. **Storage** → **Get started** → same region → production mode. (Used for
   swimmer photos and audio/video uploads.)

## 3. Register the web app and paste the six values (~5 minutes)

1. Click the **gear icon** (top of left sidebar) → **Project settings** →
   scroll to **Your apps** → click the **`</>`** (Web) icon.
2. App nickname: anything, e.g. `bspc-coach-web`. Do NOT tick Firebase
   Hosting. Click **Register app**.
3. Firebase now shows a `firebaseConfig` code block with six values. Keep
   that page open.
4. In the repo, copy the template:
   ```bash
   cd BSPC-Coach-App
   cp .env.example .env
   ```
5. Open the new `.env` and fill BOTH blocks from the console values — same
   six values, two prefixes (the Expo coach app and the Next.js portal each
   read their own prefix):

   | firebaseConfig field | → root `.env` line (Coach App) | → also this line (portal) |
   |---|---|---|
   | `apiKey` | `EXPO_PUBLIC_FIREBASE_API_KEY` | `NEXT_PUBLIC_FIREBASE_API_KEY` |
   | `authDomain` | `EXPO_PUBLIC_FIREBASE_AUTH_DOMAIN` | `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN` |
   | `projectId` | `EXPO_PUBLIC_FIREBASE_PROJECT_ID` | `NEXT_PUBLIC_FIREBASE_PROJECT_ID` |
   | `storageBucket` | `EXPO_PUBLIC_FIREBASE_STORAGE_BUCKET` | `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET` |
   | `messagingSenderId` | `EXPO_PUBLIC_FIREBASE_MESSAGING_SENDER_ID` | `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID` |
   | `appId` | `EXPO_PUBLIC_FIREBASE_APP_ID` | `NEXT_PUBLIC_FIREBASE_APP_ID` |

6. **Portal gotcha:** Next.js only reads env files from its own folder, so
   the portal needs its own copy. Create **`parent-portal/.env`** containing
   just the six `NEXT_PUBLIC_FIREBASE_*` lines (paste them from the root
   `.env`). Both files are already gitignored — they must never be committed.
   (These six values are public client config by design, not secrets — but
   the habit of never committing `.env` protects the day a real secret lands
   in one.)
7. Run things locally:
   ```bash
   npm start                              # Expo coach app (from BSPC-Coach-App/)
   npm --prefix parent-portal run dev     # parent portal at localhost:3000
   ```

## 4. Install the Firebase CLI + upgrade to Blaze (only when deploying)

1. The Firebase CLI (`firebase-tools`) is **not installed on this Mac**. No
   global install needed — run it ad hoc:
   ```bash
   npx firebase-tools login      # opens a browser; sign in with the same Google account
   ```
2. **Blaze plan:** deploying Cloud Functions (the repo uses 2nd-gen functions,
   Node 20) requires the pay-as-you-go **Blaze** plan. In the console:
   bottom-left **"Spark plan — Upgrade"** → choose **Blaze** → attach a
   billing account. Pre-launch usage will round to ~$0; you can set a budget
   alert during the upgrade flow.
3. The AI draft features (`extractObservations` etc. via Vertex AI) also need
   the **Vertex AI API** enabled: console.cloud.google.com → select project
   `bspc-coach` → "APIs & Services" → enable **Vertex AI API**. Skippable
   until you care about AI drafts.

## 5. Deploy rules, indexes, and functions

From `BSPC-Coach-App/` (project id comes from `.firebaserc` automatically):

```bash
# Security rules + composite indexes + storage rules — deploy these BEFORE
# real users touch anything (production mode blocks all access until then):
npx firebase-tools deploy --only firestore:rules,firestore:indexes,storage

# The Cloud Functions (needs Blaze, section 4):
npm --prefix functions ci
npx firebase-tools deploy --only functions
```

Function environment values go in **`functions/.env`** (gitignored;
firebase-functions v6 picks up dotenv files at deploy):

- `CALENDAR_ICS_URL=` — optional; only the `syncCalendar` scheduled function
  uses it (an iCal feed URL for the team calendar). Leave unset to skip.
- Post-cutover Supabase values — see section 7.

## 6. Seeding demo data (optional, local convenience)

`npm run seed:demo` (script `scripts/seed-demo-data.ts`) writes demo docs to
the live Firebase project. It needs:

1. A **service-account JSON**: Project settings → **Service accounts** →
   **Generate new private key**. Save it as
   `BSPC-Coach-App/google-service-account.json` (the `FIREBASE_ADMIN_KEY_PATH`
   default in `.env`). **This file is a real secret** — it's gitignored;
   never commit, paste, or screenshot it.
2. `EXPO_PUBLIC_BSPC_ENV` in `.env` left as `local` is the safety belt; the
   seed script is meant for a demo project, not a real-data one.

## 7. What changes after the Supabase cutover

The migration replaces Firebase **Auth** and **Firestore** with Supabase, but
the **Cloud Functions stay hosted on Firebase** (they just read Postgres).
~~Re-homing them off Firebase is a separate, optional, post-Phase-J decision.~~
> **[D-CUT5, ratified 2026-06-11]** That decision is now made:
> COLLAPSE-FIRST, then re-home the irreducible rest. See PART B §B6 for the
> ordered retirement schedule; the functions stay Firebase-hosted only until
> their named retirement steps execute.

- **Functions deploys additionally need** (in `functions/.env`, or better,
  `npx firebase-tools functions:secrets:set SUPABASE_SERVICE_ROLE_KEY` since
  the service-role key is a real secret):
  - `SUPABASE_URL` — the Supabase project URL
  - `SUPABASE_SERVICE_ROLE_KEY` — **secret**; bypasses RLS, server-only
  (read by `functions/src/config/supabase.ts`)
- **The parent portal additionally needs** in `parent-portal/.env`:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY` — public-safe (RLS enforces access)
  (read by `parent-portal/src/lib/supabase.ts`)
- After the cutover is verified, Email/Password sign-in and Firestore in the
  Firebase console become dead weight and can be disabled — but not before;
  the HARD STOP rule applies to that whole sequence.

## Standing security rules (apply to every step above and to all of PART B)

Never commit `.env`, `parent-portal/.env`, `functions/.env`, or any
service-account JSON. Never put real swimmer/family data in a demo project.
The `EXPO_PUBLIC_*` / `NEXT_PUBLIC_*` web-config values are public by design;
the service-account JSON and `SUPABASE_SERVICE_ROLE_KEY` are not.

---

# PART B — DECOMMISSION RUNBOOK (instructions-only; nothing here runs without Kevin)

> **HARD STOP — governs every section of PART B.** Nothing in this part
> runs against any database, storage bucket, auth store, or cloud project
> without Kevin live and his explicit approval, in a dedicated cutover
> round. **Every row backfill stays behind the HARD STOP, always**
> (the migration/j standing sentence). Every sequence below is
> INSTRUCTIONS-ONLY until that round. Prerequisite: the 05 §6 auth cutover
> is verified live (its §6.5 smoke checklist passed).

## §B0 — Live-project inventory probe (STEP 0, D-CUT3 — condition-first)

The repo cannot prove whether a live Firebase project exists or holds data
(env files are unreadable by standing security rule; PART A is a
create-from-scratch guide; OD-6 recorded zero real users). **Counted facts
at execution time outrank anyone's recollection of the project's state.**
Kevin may volunteer what he knows; nothing below depends on it.

**The probe (read-only; the one sequence that runs BEFORE the keep/drop
sheet):** using the admin SDK with the service-account key (PART A §6
handling rules apply), count and record:
- per-collection document counts for ALL ~~23~~ **32** census paths
  (00_TERRAIN §0), including every ⚠ path (expected EMPTY:
  `swimmers/{id}/medical`, `meets/{id}/relays`, `meets/{id}/live_events`,
  `meets/{id}/splits`, `messages`, `coach_chat`, `workout_library`);
- per-prefix object counts for the five legacy Storage paths
  (`/audio/**`, `/video/**`, `/profiles/**`, `/imports/**`,
  `/practice_plans/**`);
- the Firebase Auth user count.

> **[Corrected 2026-06-11 — GAP-A ruling, GAP-CLOSURE round]** "ALL 23" →
> **ALL 32 census paths (25 ★ + 7 ⚠)**: the enumerated 00_TERRAIN §0 list
> is the operative census — the old "23" was this document's own §B2
> manifest-table organization (the same 32 paths in exactly 23 ROWS;
> parent+child collections share rows, the five never-implemented ⚠ paths
> share one). The landed probe counts the enumerated 32
> (`scripts/probe-firebase-inventory-report.ts`).

A small read-only probe script lands as scaffolding in the staging round
(unit-tested pure parts only); console counts are acceptable for small
sets. **The probe output table is preserved verbatim in UNIFY/NOTES.md as
the cutover record** — it is also the D-J7 "whatever test chatter" record.
If the project does not exist or a collection is EMPTY, every manifest
over it resolves to a **named no-op** in that record; nothing else changes.

## §B1 — File copy (owns object existence; closes the D-K2 caveat)

The caveat this step closes, quoted: "any pre-H row carrying a legacy
Firebase path 404s against a signed Supabase URL until the 06-runbook
file-copy step, which owns object existence."

**Pre-step (F bank, quoted):** "confirm hosted storage tier covers the
500MB video cap before the file copy."

| Legacy Firebase path | Destination bucket | Key handling |
|---|---|---|
| `/audio/**` (incl. `audio/swimmers/...` voice notes) | `media-audio` | keys preserved 1:1 — NO row rewrites (rows already store these keys) |
| `/video/**` | `media-video` | keys preserved 1:1 — NO row rewrites |
| `/profiles/**` | `profile-photos` | keys preserved 1:1 — NO row rewrites |
| `/practice_plans/{firebaseUid}/**` | `practice-plans/{auth.users.id}/...` | **folder remap via `migration_identity_map` + REWRITE the `practice_plans` rows' storage-path values to the new keys.** Without the row rewrite, `getSignedFileUrl` still 404s — the D-K2 caveat closes only when BOTH halves land. |
| `/imports/**` | **NO destination** (D-H2b absence-is-parity; FYI-D) | **verify EMPTY** — a named no-op; non-empty → REPORT, never auto-copy |

Mechanics: manifest-driven per object — list both sides, diff, copy
missing, verify (the media README's standing idiom). **Verification:**
per-bucket object count == source prefix count (from §B0); a spot
signed-URL resolve per bucket; **the dashboard todayPlan render is the
named acceptance check.** The old Firebase `storage.rules` retire WITH
this copy (RF-4 closes under D-F1(a)).

## §B2 — Backfill manifests (D-CUT4 structure; one per collection → table)

**Identity ALWAYS runs** — coach accounts must exist, and the 05 §6.1
BINDING probe demands non-empty resolution for every parents doc that
exists. The identity manifest is `migration/identity/README.md` steps 1–8
(fresh credentials per OD-6; NM-1 live-list confirm; guardianships with
dangling-link COPPA repair; audits in==out, no dangling, no duplicates),
followed by the roster manifest (`migration/roster/README.md` steps 1–7 —
reconcile, **STOP on ambiguous**, map audit) which builds the swimmer-id
resolver everything else needs. **The 6a completion loop (landed
2026-06-11, ROSTER-DRIVER round, RD2-0 ruling): after roster step 7 has
built the swimmer map, RE-RUN the steps-4–6 graph executor — its
deferred step 6a now completes the Coach-parent guardianship links
(safe by its idempotent upserts: completed steps skip) — and only then
do the identity step-7/8 audits close.**

**Every DATA manifest below runs only per the keep/drop sheet** Kevin
signs at execution with the §B0 counts in front of him; every drop becomes
a §B7 named loss. **The mandatory dry-run stands regardless:** the whole
sequence runs against a throwaway Supabase project first (the identity and
roster READMEs' standing requirement) — the machinery is rehearsed even if
the sheet drops everything. **The dry-run is SPECIFIED at 05 §6.5 step 1
(GAP-B closure, ratified 2026-06-11): synthetic fixtures ONLY — never real
swimmer/family data; real-export rehearsal is explicitly OUT.**

| Firestore collection (§B0 count) | → PG table(s) | Manifest + verification |
|---|---|---|
| `coaches` | `profiles` + `coach_groups` | identity README; NM-1 confirm; counts in==out |
| `parents` | `profiles` + `guardianships` | identity README; the 05 §6.1 probe gates; agreement audit |
| `swimmers` | `swimmers` + `swimmer_coach_profile` | roster README; match-priority reconcile; STOP on ambiguous; `auditSwimmerMap` |
| `swimmers/{id}/notes` | `swimmer_notes` | notes dir; counts in==out per swimmer; coach refs via identity map |
| `swimmers/{id}/times` | `swim_results` (**`personal_bests` via the D-D5 trigger — never hand-written**) | times dir; counts in==out; PB rows asserted trigger-built |
| `swimmers/{id}/goals` | `goals` | **FRESH manifest, §B2.1 below** |
| `swimmers/{id}/voice_notes` | `swimmer_voice_notes` (rows; files ride §B1) | notes/media dirs; counts in==out; storage keys resolve |
| `attendance` | `attendance` | attendance dir; **three-bucket dedup** — verification counts carry the named dedup adjustment, not raw in==out |
| `audio_sessions` (+`/drafts`) | `audio_sessions` + `audio_session_drafts` | media dir; counts in==out; empty-project no-op pre-named |
| `video_sessions` (+`/drafts`) | `video_sessions` + `video_session_drafts` | media dir; same |
| `meets` (+`/entries`) | `meets` + `meet_entries` | h dir; **the D-H9 run log counts coach-origin rows made parent-readable, by decision name** |
| `calendar_events` (+`/rsvps`) | `calendar_events` + `calendar_event_rsvps` | h dir; **post-backfill syncCalendar first PG run must verify ZERO net new rows (same ical_uid keys)** |
| `practice_plans` (incl. dashboard-PDF docs) | `practice_plans` | h dir; counts in==out; §B1 rewrites its storage paths |
| `season_plans` (+`/weeks`) | `season_plans` + `season_plan_weeks` | h dir; counts in==out |
| `import_jobs` | `import_jobs` | h dir; counts in==out |
| `parent_invites` | `parent_invites` | i dir; count(rows)==count(docs); **every redeemed pair exists in guardianships** |
| `notification_rules` | `notification_rules` | notifications dir; JSONB verbatim; counts in==out |
| `notifications` (CF-write) | `in_app_notifications` | notifications dir, quoted: **"the recipient mapping is the RG-7 trap — read twice: Firestore `coachId` is the recipient's AUTH identity, and `in_app_notifications.user_id` references auth.users — so `coachId` resolves through the identity map to profiles.user_id (the auth id), NOT to profiles.id"**; `type`→`category` (6-value CHECK or STOP) |
| `group_notes` | `group_notes` | **FRESH manifest, §B2.2 below** |
| `aggregations` (CF-write) | **NULL-MANIFEST** | j dir: "there is nothing to copy" — ratified twice; the 00011 views compute at read time |
| `coach_chat` ⚠ | **NO table — §B7 loss, FIRST** | D-J7 as corrected, quoted: "whatever test chatter sits in the collection dies with Firestore at the 06-runbook decommission step (named pre-launch data loss)" |
| `messages` ⚠ | none (type-only; retired at K5 under D-K3) | probe-EMPTY expected; named no-op |
| `swimmers/{id}/medical`, `meets/{id}/relays`, `meets/{id}/live_events`, `meets/{id}/splits`, `workout_library` ⚠ | none (never implemented) | probe-EMPTY expected; named no-ops |

### §B2.1 — FRESH manifest: `swimmers/{id}/goals` → `goals` (HARD STOP)

The scope round named this gap: goals migrated pre-UNIFY-discipline
(2026-05-31) with no scaffolding dir. **Correction surfaced writing this
manifest:** the roster manifest's step 5 ALREADY carries a goals half —
`legacyGoalsToGoalRows` maps the swimmer DOC's free-text `goals: string[]`
field to minimal rows (`swimmer_id` + `event_name` only), for
`created_new` swimmers only. The STRUCTURED subcollection docs
(`SwimmerGoal`: the store `goals.ts` actually serves) had no manifest
anywhere. This manifest owns them, and the two halves are sequenced:

1. **Structured docs FIRST.** For each `swimmers/{sid}/goals` doc:
   `swimmer_id` := migration_swimmer_map(sid); `event` → `event_name`;
   `course` → `course` (SCY/SCM/LCM CHECK or STOP); `targetStandard` →
   `target_standard` (B..AAAA CHECK or STOP); `targetTime` →
   `target_time_hundredths`; `currentTime` → `current_time_hundredths`;
   `notes` → `notes`; `achieved` → `achieved`; `achievedAt` →
   `achieved_at`; `createdAt`/`updatedAt` → `created_at`/`updated_at`.
   **`targetTimeDisplay`/`currentTimeDisplay` DROP** — canonical stores no
   display strings; both apps derive display on read (the RD-12 idiom).
2. **Legacy strings SECOND, dedup-gated:** roster step 5's
   `legacyGoalsToGoalRows` output inserts ONLY where no structured row
   already exists for that `(swimmer_id, event_name)` — the legacy field
   is the denormalized echo of the same goals.
3. **Verification:** `count(goals)` == structured-doc count (§B0) +
   non-redundant legacy strings; zero rows with unmapped `swimmer_id`
   (FK guarantees); zero `(swimmer_id, event_name, course, target_*)`
   exact duplicates.

### §B2.2 — FRESH manifest: `group_notes` → `group_notes` (HARD STOP)

For each `group_notes` doc (shape per groupNotes.ts/TERRAIN §1):
`content` → `content`; `tags` → `tags` (every value must sit inside the
19-value `group_notes_tags_check` domain — **an out-of-domain tag STOPS,
named**); `group` → `practice_group` (CHECK domain incl. Masters — STOP on
mismatch); `practiceDate` (string `YYYY-MM-DD`) → `practice_date` (DATE);
`coachId` (Firebase uid) → `coach_id` := **profiles.id** via
`migration_identity_map` — the FK is `ON DELETE RESTRICT`, so an unmapped
coach STOPS, named; **`coachName` DROPS** (denormalized display — derived
via the profiles join on read); `createdAt` → `created_at`.
**Verification:** counts in==out; every distinct `coachId` resolved
through the map (zero unmapped); spot-check one row's tags array
round-trips.

## §B3 — Cron (D-G6, quoted verbatim)

"Schedule `send-notification` + `cleanup-tokens` (Supabase cron) at
cutover staging with an end-to-end drain verification." Mechanism, named:
"rule-engine and digest writers NEVER enqueue `notification_jobs` — they
own their idempotent `in_app_notifications` rows directly, so the sender's
unconditional in-app insert can never duplicate them while the queue
carries only BSPC-side announcements. If coach push later rides the jobs
queue (the D-G2 product line), `notification_jobs` first gains a
`skip_in_app BOOLEAN` the sender honors." **"The drain verification must
prove it: enqueue one ordinary job AND one rule-mirroring flagged job;
assert exactly one in-app row per recipient for each (the writer-owned
row, never a sender duplicate)."**

## §B4 — Env (the F/G banks + PART A §7 lines, consolidated)

- **F bank, quoted:** set `PROCESS_SHARED_SECRET` (functions env) +
  `EXPO_PUBLIC_PROCESS_FUNCTIONS_BASE_URL` /
  `EXPO_PUBLIC_PROCESS_SHARED_SECRET` (app env) **before the media
  pipeline goes live.**
- **G bank, quoted:** "the evaluateAttendanceRules endpoint rides the SAME
  `PROCESS_SHARED_SECRET` + `EXPO_PUBLIC_PROCESS_*` env lines already
  banked at F (no new secrets)."
- `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` for the surviving
  functions via `functions:secrets:set` (PART A §7) — these lines die
  step-by-step with the §B6 retirements.
- Portal: `NEXT_PUBLIC_SUPABASE_URL` + `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  (PART A §7).
- Coach app reset-email template + redirect URL for
  `resetPasswordForEmail` (05 §6.2(iii)) — Supabase dashboard staging
  lines.

## §B5 — OD-1 convergence ordering (RESTATED; executes at the sweep, NOT here)

**Verbatim: "backfill `guardianships` → switch BSPC reads/RLS → drop
`family_id`."** The CONSOLIDATED CONVERGENCE / CUTOVER REMOVAL CHECKLIST
(NOTES, 2026-06-09, nine items) remains the authoritative work list for
that sweep; incorporated here by reference with the three ordering items
quoted in full:
- **Item 1:** "Backfill `guardianships` from `swimmers.family_id` (OD-1
  step 1; runner in `migration/identity/`, swimmer resolver =
  `migration_swimmer_map`)."
- **Item 2:** "Switch BSPC family reads (`fetchFamilySwimmers`,
  `approveFamily`) and all `family_id`-based RLS to
  `is_my_swimmer()`/guardianships (OD-1 step 2)."
- **Item 6:** "Update the `family_id`-based pgTAP tests (OD-1 step 3) and
  finally **DROP `swimmers.family_id`** (OD-1 step 4); relax
  `swimmers.last_name` NOT NULL; convert TEXT CHECK columns → canonical
  enums."
**Item 8 sequencing pin:** the transient map tables
(`migration_identity_map`, `migration_swimmer_map`) drop only AFTER the
sweep completes — the maps are the remap inputs (cutover → convergence
sweep → drop maps). The 05 §6.6 transitional arms (GAP-1/GAP-2) narrow to
guardianships-only at this sweep, alongside checklist items 3/9.

## §B6 — Firebase project death, ordered (D-CUT5 collapse plan)

1. **Disable Email/Password sign-in** — only after the 05 §6.5 smoke
   checklist passes (the PART A §7 standing sentence), **and only after
   Kevin has sent the account announcement — the Kevin-owned comms line
   (ratified 2026-06-11, R-CLOSURE round): every coach and parent is told
   the account now lives on Supabase and how to set a password (the OD-6
   paths: the landed forgot-password flow or an operator-sent invite).**
2. **Firestore rules → deny-all;** data disposition per the §B2 keep/drop
   sheet record.
3. **functions/ workspace retirement — LAST compute standing; the
   pre-declared Functions-bar event.** The bar (12 suites / 115 tests)
   declines ONLY by these named retirements and RETIRES at workspace
   death (`firebaseAdmin` mock + all suites with it):

   | Step (order: C1–C2 gated on their conditions; C3–C5 interleavable) | Retires | Bar |
   |---|---|---|
   | C1 — portal callables retire (gated on D-CUT6 direct reads live: 05 §6.6) | `parentPortal.test.ts` −18 | 115 → 97 |
   | C2 — `redeemInvite` shell retires (its caller invokes the PG RPC directly — the function is already a thin shell over it) | `redeemInvite.test.ts` −13 | 97 → 84 |
   | C3 — `dailyDigest` → Supabase cron | `dailyDigest.test.ts` −8 | 84 → 76 |
   | C4 — `syncCalendar` → Supabase cron (its iCal parser moves with it) | `syncCalendar.test.ts` −11 + `icalParser.test.ts` −20 | 76 → 45 |
   | C5 — the sweepers → Supabase cron | `sweepStuckSessions.test.ts` −3 + `sweepAttendanceEvaluations.test.ts` −3 | 45 → 39 |
   | C6 — workspace death at the AI-core re-home phase: `processAudioSession`/`processVideoSession`/`extractObservations`/`promptScoping` (9+7+9+2) + the `evaluateAttendanceRules` endpoint (12) re-home; the workspace deletes | −39 | 39 → 0; **bar RETIRES** |

   Sum of declines: 18+13+8+31+6+39 = **115** ✓. The irreducible re-home
   (C6) is its own dedicated future phase; **host choice is its own future
   [DECIDE] at that phase — Supabase Edge Functions is the default
   candidate.** The Firebase project survives FUNCTIONS-ONLY from step C5
   until C6 completes.
4. **Repo config deletions — one named commit:** `firestore.rules`,
   `storage.rules` (already retired in force by §B1),
   `firestore.indexes.json`, `firebase.json`, `.firebaserc`.
5. **scripts/ firebase seeds deletion** (create-coach, seed-demo-data,
   seed-calendar, seed-meets, seed-roster) WITH
   `scripts/__tests__/seed-demo-data.test.ts` → **Coach 1080 → 1076,
   the pre-declared −4 event (FYI-E).** check-*.sh/.mjs +
   sync-functions-shared.js survive (repo tooling, not firebase).
6. **Portal residue end-state:** `lib/firebase.ts` + the
   `parentPortal.ts` callable transport die per 05 §6.2(vii)/§6.6 timing
   (with the bank on the small-gap verdict; at C1 otherwise).
7. **The Firebase project is deleted in the console + Blaze billing
   closed — THE FINAL ACT, after the C6 re-home completes** (D-CUT5
   ratified ordering).

## §B7 — Named pre-launch data losses (consolidated; none silent)

1. **`coach_chat` — FIRST, ratified (D-J7 as corrected):** "whatever test
   chatter sits in the collection dies with Firestore at the 06-runbook
   decommission step (named pre-launch data loss)." The §B0 probe count
   is its record.
2. Every keep/drop-sheet DROP Kevin signs under D-CUT4 — each named here
   with its §B0 count at execution; the signed sheet + probe table are
   appended to the cutover record in NOTES.
3. Probe-EMPTY paths resolve as no-ops, not losses (nothing existed to
   lose); the probe table records the zeros.
