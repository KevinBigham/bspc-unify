# 12 — PHASE H (calendar + meets + plans): mini-plan + red-team

**STATUS: PLANNING ONLY — the scoping tripwire FIRED. No Phase H code exists.
This document ends in [DECIDE] blocks for Kevin (§7). Nothing in §5 executes
until those are ratified.**

Inputs read end to end before writing this: 04 §H + the client-services and
backfill tables; 00_TERRAIN §3.5/§3.6 + the Coach/BSPC inventories; canonical
01 (schedule/calendar/meets/meet_entries L233–379, plans L553–606, import_jobs
L695–712, enums L73–111, indexes, RLS L1089–1135); live BSPC migrations
00001–00008 + RLS as landed; Coach `calendar.ts`, `meets.ts`,
`practicePlans.ts`, `workoutLibrary.ts`, `seasonPlanning.ts`, `importJobs.ts`,
`search.ts`, `meetResultsImport.ts`, `csvImport.ts` (jobs half),
`functions/src/scheduled/syncCalendar.ts` (+ icalParser tests); `firestore.rules`
+ `storage.rules` verbatim; the full BSPC app meets/schedule surface
(features/meets, features/schedule, features/admin, calendar-feed Edge
Function); every H type (`firestore.types.ts`, `meet.types.ts`,
`practicePlan.ts`); NOTES.md banked items A→G.

---

## §0 WHY THE TRIPWIRE FIRED

1. **Canonical's walls for `practice_plans` and `import_jobs` contradict the
   ratified within-staff no-widening doctrine (D-F4).** Canonical 01 says
   `FOR ALL USING (is_staff())` for both (L1132, L1135). The live Firestore
   walls are **per-coach**: practice_plans read = own OR `public == true`,
   write = own only, no reassign; import_jobs read = own OR admin, write =
   own only, delete = admin. Landing canonical as written would let any coach
   read any coach's private plans and imports — exactly the widening D-F4
   forbade ("the no-widening doctrine applies within staff too"). The wall IS
   the model; this needs a canonical amendment, not an execution detail
   (→ D-H1).
2. **Canonical `calendar_events` cannot host `syncCalendar`'s writes.** The
   live sync job upserts iCal events keyed by `icalUid` with
   `coachId: 'ical_sync'` (a string sentinel) plus `source`, `rawRrule`,
   `syncedAt`. Canonical has `coach_id UUID NOT NULL REFERENCES profiles
   ON DELETE RESTRICT` and **none** of those four columns. As written, the
   sync function's rows are unrepresentable (→ D-H3).
3. **A genuine wall-widening question only Kevin can answer.** Canonical grants
   `calendar_events` SELECT to every active account (parents + pending) and
   gives families RSVP write on their own swimmers (L1096, L1100–1101). Today
   those rows are coach-only (`isCoach()` in firestore.rules). Canonical is
   ratified law (P1-8 classified calendar as team-wide content), but the
   F/G-era no-widening doctrine postdates it and says "not one bit wider."
   The two ratified principles conflict; Kevin arbitrates (→ D-H5).
4. **The D-F4 bank does not match reality on import FILES.** D-F4 re-banked
   "practice-plan PDFs and import files … per-coach-private today." Half
   precise: the PDFs are real and per-coach (`storage.rules`:
   `practice_plans/{coachId}/**`, owner-only, 25MB, PDF-only). The import
   files **do not exist**: no code anywhere uploads to `imports/**` — the
   only DocumentPicker in the app is the practice-PDF uploader; `csvImport`
   records the constant `'manual/pasted-roster.csv'` (the roster is pasted
   text, not a file) and `meetResultsImport` records `'manual/meet-results.*'`
   fallbacks. The `imports/**` storage rule guards a path nothing ever wrote.
   Resolving a ratified bank line against contradicting reality is a decision,
   not a judgment call (→ D-H2b, the D-G2 absence-parity precedent).
5. **04 assigns `import_jobs` to no phase at all.** It sits in 04's
   client-services table ("importJobs.ts, csvImport.ts, meetResultsImport.ts —
   shared") but appears in no phase row; D-F4's "re-bank to H **with their
   data**" implies the rows come to H. Pulling a collection into a phase's
   scope is Kevin's call to confirm, plainly, not a silent blend (→ D-H8).

Secondary findings that sharpened the plan but did not alone fire it: the
`rateWorkout` cross-coach feature is provably broken today (RH-7); the
calendar month window uses a lexical `"-31"` date string that is an invalid
PG date literal (RH-4); RSVPs are blind `addDoc`s against a canonical UNIQUE
(RH-5); the realtime publication proof pins EXACTLY 14 tables and H adds 8
(RH-12).

---

## §1 TERRAIN — what exists today, both apps

### 1a. Coach App services (the swap subjects)

- **calendar.ts** — `subscribeEvents(month)` (string range `>= "YYYY-MM-01"`,
  `<= "YYYY-MM-31"`, order startDate asc), `subscribeEventsRange(start,end)`,
  `subscribeEventsForDate(date)` (==); `addEvent(data, coachUid)` (addDoc,
  `coachId := coachUid`, coachName arrives inside `data`); `updateEvent`
  (partial + updatedAt); `deleteEvent`; `subscribeRSVPs(eventId)`
  (subcollection, order updatedAt desc); `submitRSVP(eventId, data)` —
  **blind addDoc, duplicates per (event, swimmer) possible**; pure helpers
  (`sortEventsChronologically`, type color/label maps). 19 jest tests.
- **meets.ts** — `subscribeMeets(cb, max=50)` (order startDate desc, limit),
  `subscribeUpcomingMeets` (>= today, asc, limit 20), `updateMeet`,
  `deleteMeet`. **No meet-creation function exists anywhere in the app**
  (meets arrive via console/by hand; the import only PATCHES entries).
  `subscribeEntries(meetId)` — read-only legacy psych-sheet rows (entry
  authoring was feature-pruned); `generatePsychSheet` pure. 13 jest tests.
- **practicePlans.ts** — `subscribePracticePlans(cb, {isTemplate?, group?,
  max?, coachId?})`: server filters isTemplate/coachId, **group is filtered
  client-side**, dashboard-PDF docs excluded client-side
  (`documentType === 'dashboard_pdf'`), order createdAt desc;
  `addPracticePlan(plan, coachUid)` (`coachId := coachUid`);
  `updatePracticePlan`; `deletePracticePlan`;
  `createDashboardPracticePlanPdf` (same collection, discriminator
  `documentType: 'dashboard_pdf'`, fields coachId/date/storagePath/filename/
  uploadedAt/sizeBytes/pageCount — **no title**);
  `uploadDashboardPracticePlanPdf` → Firebase Storage
  `practice_plans/{coachId}/{date}/{filename}` via uploadBytesResumable with
  onProgress percent; `subscribeTodayPracticePlan(coachId)` (documentType ==
  dashboard_pdf AND coachId AND date == today; newest uploadedAt wins,
  client-sorted); `duplicateAsTemplate`; yardage helpers. 21 jest tests.
- **workoutLibrary.ts** — the "workout library" IS `practice_plans` filtered
  `isTemplate == true` (the dead `workout_library` collection was dropped,
  SETTLED #5). `subscribeWorkouts(filters)` (isTemplate + optional
  coachId/group server-side; yardage client-side) — comment: coachId
  "REQUIRED at production call sites" to satisfy the rules;
  `subscribePublicWorkouts` (isTemplate + **`public == true`** + group +
  tags array-contains-any, order updatedAt desc);
  `setPlanPublicStatus` (writes field **`public`** — canonical name is
  `is_public`); `tagWorkout` (tags only, **no updatedAt stamp**);
  `rateWorkout` (`ratings.${coachId} = n`, a coach-uid-keyed map);
  `searchWorkouts` (one-shot getDocs, fetch-then-filter title/description).
  16 jest tests.
- **seasonPlanning.ts** — `subscribeSeasonPlans(coachId)` (eq coachId, order
  startDate desc — **the UI scopes to own; the wall does not**);
  `createSeasonPlan` (addDoc; plan carries coachId + coachName);
  `updateSeasonPlan`; `deleteSeasonPlan` (**client-side cascade**: deletes
  every weeks subdoc, then the plan); `subscribeWeekPlans(planId)` (order
  weekNumber asc); `upsertWeekPlan(planId, week)` (update if `week.id`, else
  addDoc — id-based, NOT weekNumber-based; **weeks carry no updatedAt**);
  pure helpers (`calculateSeasonYardage`, `calculateTaperProgress`,
  `getCurrentPhase`, `generateWeekPlans`). **19 jest tests — ALL on the pure
  helpers. The data layer has ZERO tests** (04's "write data-layer tests
  FIRST" mandate is live).
- **importJobs.ts** — `subscribeImportJobs(coachId)` (eq coachId, order
  createdAt desc), `createImportJob`, `updateImportJob`. 3 jest tests.
  Writers: csvImport (type csv_roster, storagePath = the pasted-roster
  constant), meetResultsImport (sdif/hy3, manual-* fallbacks).
- **search.ts meets/calendar halves** (notes half landed in E) —
  `searchMeets(term, max=50)` / `searchCalendarEvents(term, max=50)`: fetch
  newest `max` docs, filter client-side (name/location; title/location).
  Frozen fetch-then-filter semantics, the searchNotes precedent. 13 tests
  in the file (notes half + these).
- **meetResultsImport.ts meets-half** (times half landed in D) — when
  `meetId` is provided: per record, query `meets/{id}/entries` where
  `swimmerId == X && event == rec.event`, update `finalTime` (hundredths) +
  `finalTimeDisplay` + updatedAt on every match; failures swallowed into
  `result.errors` so imported times survive. Legacy entries DO carry
  `swimmerId` (Firestore swimmer doc ids).
- **functions/scheduled/syncCalendar.ts** — daily 06:00; fetches
  `CALENDAR_ICS_URL` (the BSPC public website's Google Calendar ICS); parses
  VEVENTs; upserts each into Firestore `calendar_events` with doc id
  `ical_<djb2(uid)>`; payload: title/description/type(inferred)/startDate/
  location/`groups: []`/`coachId: 'ical_sync'`/`coachName: 'iCal Sync'`/
  `source: 'ical_sync'`/`icalUid`/`rawRrule`/syncedAt/updatedAt (+ optional
  startTime/endDate/endTime/recurring). set(merge:true). Two comment-vs-code
  facts verified: hand-edits to payload fields ARE clobbered nightly (the
  merge only protects fields NOT in the payload), and createdAt is rewritten
  every run (the "fence" the comment describes does not exist). Has a full
  jest suite (stableId determinism + payload shape ×8) + icalParser tests.

### 1b. The live walls, verbatim (what no-widening measures against)

| Surface | Firestore/storage rule today |
|---|---|
| practice_plans | read: `isCoach() && (public == true \|\| coachId == uid)`; create: own; update: own AND stays own; delete: own |
| import_jobs | read: `isAdmin() \|\| (isCoach() && coachId == uid)`; create: own; update: own AND stays own; delete: `isAdmin()` |
| calendar_events (+rsvps) | read/write: `isCoach()` — coach-shared |
| meets (+entries) | read/write: `isCoach()` — coach-shared |
| season_plans (+weeks) | read/write: `isCoach()` — coach-shared |
| storage `practice_plans/{coachId}/**` | read/write: `auth.uid == coachId` (owner-only by path; **no isCoach() check** — a parent could technically write under their own uid segment today); write caps 25MB + `application/pdf` |
| storage `imports/**` | read/write: `isCoach()`, 50MB, no mime cap — **dead capability, nothing ever writes it** |

Firestore `isAdmin()` maps to canonical `is_super_admin()` (Phase A role map:
admin→super_admin, coach→coach_admin).

### 1c. BSPC side (already canonical-shaped; mostly NOT H subjects)

- **meets**: table per 00001 (13 parent-info columns); RLS today
  `meets_select_all USING (TRUE)` + `meets_manage_admin` (inline EXISTS,
  coach_admin+super_admin — the is_staff() set). Readers:
  `features/meets/api.ts` fetchUpcomingMeets/fetchPastMeets/fetchMeet
  (select *, date-windowed). **No BSPC writer exists** (admin-managed by
  hand). Jest: 7 API + hook/component tests. **pgTAP: ZERO coverage today.**
- **schedule_events + the 4 scrape-pipeline tables**: BSPC-native, already
  canonical-identical, zero Coach-app coupling, scrape tables have zero app
  code. **NOT Phase H subjects** — "calendar" in H means the Coach
  `calendar_events` model only. The BSPC `calendar-feed` Edge Function
  (schedule_events → iCal OUT) is unrelated to Coach `syncCalendar` (public
  Google Calendar ICS → calendar_events IN); neither replaces the other.
- BSPC has **zero references** to calendar_events, practice_plans,
  season_plans, meet_entries, import_jobs (verified by sweep).

### 1d. Canonical delta — the field maps and misfits

- **calendar_events**: groups → `practice_group[]` array (house: TEXT[] +
  `<@` CHECK); recurring JSONB passthrough; `coach_id NOT NULL → profiles
  RESTRICT` + **no source/ical_uid/raw_rrule/synced_at columns** (the D-H3
  amendment); coachName dropped (derive via embed). `start_date DATE` —
  the month-window `"-31"` literal is invalid PG (RH-4).
- **calendar_event_rsvps**: real table, `UNIQUE(event_id, swimmer_id)`,
  swimmer_id FK CASCADE; swimmerName dropped (derive); parent_name TEXT
  kept; rsvp_status domain (going/maybe/not_going).
- **meets**: superset of both apps (BSPC 13 cols + course/status/events
  JSONB/groups[]/sanction_number/host_team/`coach_id` nullable SET NULL).
  Coach startDate string → start_date DATE (calendar-string discipline).
  Each app reads its own slice; both see both rows post-cutover (RH-8).
- **meet_entries**: real table; swimmer_id **NOT NULL** FK; seed/final
  `*_hundredths` (Coach values are already hundredths — UNIT RULE: verbatim,
  no conversion code may exist outside 00005); swimmerName +
  seedTimeDisplay/finalTimeDisplay dropped (derive); **no updated_at column**
  (the import's stamp drops); practice_group/gender/age nullable-ish per
  canonical.
- **practice_plans**: public → `is_public`; group → `practice_group`
  (client-side group filter in subscribePracticePlans stays client-side —
  frozen semantics); date → `plan_date`; totalDuration →
  `total_duration_min`; coachName dropped; ratings JSONB (coach-uid-keyed —
  keys remap at backfill; live writes keep `coach.uid` keys, the B
  created_by value-semantics precedent); sets JSONB passthrough; the
  dashboard-PDF discriminator becomes the canonical columns document_type/
  storage_path/filename/uploaded_at/size_bytes/page_count; **title NOT NULL
  vs PDF rows having no title → `title := filename`** (RH-16);
  template_source_id self-FK SET NULL (P2-11 cycle guard stays deferred).
- **season_plans / season_plan_weeks**: group → practice_group; coachName
  dropped; phases JSONB passthrough; weeks = real table with
  `UNIQUE(season_plan_id, week_number)` + `phase` domain
  (base/build1/build2/peak/taper/race/recovery = the app's SeasonPhaseType
  exactly); practicePlanIds → `practice_plan_ids UUID[]` (best-effort refs);
  **no updated_at on weeks** (matches the app's no-stamp behavior).
- **import_jobs**: fileName → file_name; storagePath → storage_path
  (nullable; vestigial values preserved); summary JSONB passthrough;
  errorMessage → error_message; type/status domains
  (csv_roster/sdif/hy3/cl2 ; processing/complete/failed).
- **Enums**: house style = TEXT + CHECK in live migrations (canonical's
  enum types convert at OD-1 like every prior phase).
- **Realtime publication**: every H service subscribes — calendar_events,
  calendar_event_rsvps, meets, meet_entries, practice_plans, season_plans,
  season_plan_weeks, import_jobs = **+8 tables, publication grows 14 → 22**,
  and pgTAP 011's exact-membership proof updates in the SAME commit (RH-12).

### 1e. Banked items pulled into scope, by name

| Banked item | Source | Disposition in H |
|---|---|---|
| Meet + calendar searches (`searchMeets`, `searchCalendarEvents`) | E landed log ("stay Firestore until H") | IN SCOPE — §5 commit 8 |
| `meets/{id}/entries` finalTime sync | D landed log ("stays Firestore until H") | IN SCOPE — §5 commit 5 (meetResultsImport meets-half) |
| Practice-plan PDF FILES (per-coach-private) | D-F4 re-bank | IN SCOPE — practice-plans bucket + within-staff storage walls (D-H2a) |
| Import FILES | D-F4 re-bank | **Nothing exists to move** — no uploader was ever written; absence is parity (D-G2 precedent). No imports bucket is created (D-H2b) |
| `import_jobs` rows (+ importJobs.ts, csvImport/meetResultsImport jobs-halves) | D-F4 "with their data"; 04 left it phase-less | PROPOSED IN SCOPE (D-H8) |
| seasonPlanning data-layer tests FIRST | 04 §H mandate | IN SCOPE — §5 commit 1, before any swap |
| id-array/JSONB backfill remaps (practice_plan_ids, ratings keys, meets.events) | 04 backfill table | IN SCOPE — manifest only, HARD STOP |

**Scope-confirmation statement (04 vs the handoff-era bank):** 04's H =
"calendar + meets + plans" (calendar.ts, meets.ts, meetResultsImport,
practicePlans+workoutLibrary as a pair, seasonPlanning tests-first,
syncCalendar). The handoff-era description ("leftover searches +
per-coach-private files") adds the two search halves and the D-F4 file bank.
They differ materially in TWO places, stated plainly: (1) `import_jobs` —
04 assigns it no phase; D-F4's "with their data" pulls it to H; this plan
proposes H and asks (D-H8). (2) "import files" — the bank presumed files
that have never existed; this plan records their absence as parity (D-H2b)
rather than building dead infrastructure. Everything else is the union of
both lists with no conflict. Out of scope, named: BSPC schedule_events +
scrape pipeline (BSPC-native, already canonical), `aggregations` reads (J),
parent_invites (I), the dead `workout_library`/`messages`/`coach_chat`/meet
`relays`/`live_events`/`splits` collections (SETTLED #5), recurring-event
expansion (P2-9, an APP/UI concern — `recurring` JSONB passes through).

### 1f. Test inventory at the line

Coach jest 1034 (calendar 19, meets 13, practicePlans 21, workoutLibrary 16,
seasonPlanning 19 pure-only, importJobs 3, search 13, meetResultsImport 13 —
all currently Firestore-mocked except meetResultsImport's times half);
Functions 125 (syncCalendar 8 + icalParser); BSPC 835 + pgTAP 209 (meets:
zero proofs today). No criticalOp file covers an H collection.

---

## §2 RED-TEAM REGISTER (RH-1 … RH-16)

- **RH-1 (the headline)** — canonical staff-wide RLS on practice_plans +
  import_jobs = within-staff widening, forbidden by ratified D-F4. Fix: D-H1
  canonical amendment (per-coach policies + the `is_my_profile()` helper),
  pgTAP proving **staff-A vs staff-B** — the project's first within-staff
  wall proofs.
- **RH-2** — PG RLS *filters* where Firestore rules *reject*: an
  under-constrained Firestore list query errors today; the same query under
  per-coach RLS would silently return own+public rows. The swap keeps every
  caller-passed filter (`coachId`, isTemplate, public) as real query params;
  RLS is the wall, not the scope. Pinned per service.
- **RH-3** — syncCalendar's rows are unrepresentable in canonical
  calendar_events (sentinel coach, missing ical columns) → D-H3 amendment:
  `coach_id` NULLABLE + `source TEXT`, `ical_uid TEXT UNIQUE`,
  `raw_rrule TEXT`, `synced_at TIMESTAMPTZ`. The upsert key becomes the
  plain `ical_uid` UNIQUE — a column-list conflict target, so supabase-js
  `onConflict` handles it client/function-side (NOT the G expression-index
  class; no RPC needed). The `'ical_sync'` sentinel dies; provenance lives
  in `source`.
- **RH-4** — `subscribeEvents` month window uses `<= "YYYY-MM-31"`: a valid
  lexical string bound in Firestore, an **invalid date literal** in PG
  (Feb 31 errors). Rewrite: `gte start_date {month}-01` + `lt` first of next
  month — provably identical on real dates (no real date in a month exceeds
  its last day; lexical "-31" admitted none either). Pinned with a February
  test.
- **RH-5** — submitRSVP is a blind addDoc (duplicate (event, swimmer) docs
  possible today) vs canonical `UNIQUE(event_id, swimmer_id)` → upsert
  `onConflict('event_id,swimmer_id')` updating status/parent_name/note +
  re-stamping updated_at. Re-RSVP = one row, refreshed — the D-C2/RC-12
  "atomic, strictly better" class. pgTAP proves the key; jest pins the
  upsert call shape.
- **RH-6** — calendar read wall: coach-only today vs canonical
  active-account read + family RSVP write. Kevin's call (D-H5); whichever
  way, pgTAP 012 pins the exact wall (active/pending/deactivated/anon ×
  read/write).
- **RH-7** — `rateWorkout`/`tagWorkout` against ANOTHER coach's public
  template are **denied by today's rules** (update requires ownership) —
  the cross-coach rating feature has never functioned. Per-coach RLS
  preserves the denial exactly (D-H6 = parity-deny, the D-G2 "absence is
  parity" precedent; healing it = a `rate_workout` SECURITY DEFINER RPC,
  banked as post-cutover product if wanted).
- **RH-8** — merged meets cross-visibility: post-cutover each app's list
  shows the other's rows (BSPC rows have NULL course/status/events; Coach
  rows have NULL address/warmup/what_to_bring/commit_url). UI-safe on both
  sides (nullable rendering verified: Coach status helpers default-branch;
  BSPC detail renders optional fields conditionally). Pre-launch data =
  test rows only. FYI-bundle.
- **RH-9** — meet_entries.swimmer_id NOT NULL vs legacy Firestore entry docs
  carrying Firestore swimmer ids → backfill resolves via the roster map;
  unresolvable swimmerId **REPORT + STOP** (never skip). Seed/final times
  are Coach-native hundredths: **insert verbatim; the RD-5 UNIT RULE stands
  (no ÷ code outside 00005)**.
- **RH-10** — weeks `UNIQUE(season_plan_id, week_number)` vs Firestore's
  dup-tolerant addDoc: the id-based upsertWeekPlan flow is preserved 1:1;
  `generateWeekPlans` emits sequential numbers so legitimate flows never
  collide; a duplicate-number insert that Firestore silently allowed now
  fails loudly (strictly better, pinned). `deleteSeasonPlan`'s client-side
  weeks cascade collapses to ONE delete (DB CASCADE — the house pattern).
- **RH-11** — seasonPlanning's data layer is untested: 04 mandates
  **pin-first** — a tests-only commit against the CURRENT Firestore
  implementation, then the swap lands under those pins (§5 commits 1 → 6).
- **RH-12** — pgTAP 011 pins the publication set EXACTLY (14). 00009 adds 8
  subscribed tables; **011's membership proof updates in the same commit**
  or the bar goes red. Modifying that proof is not a deletion — the subject
  (exact membership) is unchanged; the pinned set grows. Named here for the
  record.
- **RH-13** — import FILES don't exist (§0.4): no imports bucket, no file
  walls, no copy-manifest line beyond "verify `imports/**` listing is empty;
  non-empty → REPORT, never auto-copy" (the fcmTokens precedent).
  `import_jobs.storage_path` stays a nullable vestigial TEXT column.
- **RH-14** — the practice-plans file tier (D-H2a): private bucket
  `practice-plans`, today's caps mirrored exactly (25MB, `application/pdf`);
  storage.objects walls = `is_staff() AND owner-segment` — **one bit
  stricter than today's storage rule**, which never checked isCoach() (a
  parent could write under their own uid segment; the canonical wall closes
  that hole — the P1-8/pending-hole class, named not silent). Upload via the
  F `mediaUpload` helper (signed upload URL + XHR PUT, onProgress contract
  preserved); playback/open via fresh signed URLs. Pre-cutover the swapped
  code doesn't run in production (code-first, cutover-last — the F
  precedent); at the file copy, the owner path segment rewrites
  firebase-uid → auth user id via the identity map.
- **RH-15** — live BSPC meets policies vs canonical: `meets_select_all
  USING (TRUE)` (even deactivated accounts read meets today) vs canonical
  `is_active_account()`; `meets_manage_admin` inline-EXISTS vs `is_staff()`
  (same principal set — the G jobs-policy verification pattern). D-H7:
  align in 00009 with pgTAP proving the narrowing (deactivated → 0) and the
  same-set refactor, rather than leaving it to the convergence sweep —
  because 00009 itself makes the Coach columns parent-visible on this table
  and should land with the canonical wall, not the looser one.
- **RH-16** — `title NOT NULL` vs dashboard-PDF rows having no title:
  `title := filename` at write and at backfill (harmless, visible nowhere —
  the PDF card renders filename). Also: `subscribePracticePlans`'s
  client-side PDF exclusion becomes the server-side filter
  `document_type IS NULL` — observable result identical (pinned); the
  client-side `group` filter stays client-side (frozen semantics).
- Trigger note (no number): house `update_updated_at` triggers go on
  calendar_events, meets, practice_plans, season_plans, import_jobs
  (rsvps keep DEFAULT-only updated_at refreshed by the upsert's explicit
  SET, matching today's stamp). One observable delta, named: `tagWorkout`
  writes no updatedAt today, but the DB trigger will bump it — a tag edit
  can reorder `subscribePublicWorkouts` (updatedAt desc). Immaterial and
  faithful-to-canonical; in the FYI bundle.

---

## §3 ALREADY PINNED (no decision needed — prior ratifications apply)

- Swap mechanics per the playbook: realtime parity (immediate first fire,
  full re-emit, live flag, channel-seq names), DB-owned timestamps with
  inverted pins, derive-on-read for every dropped denorm (coachName ×4,
  swimmerName ×2, display strings), frozen service signatures (`void` unused
  params), fetch-then-filter searches stay fetch-then-filter.
- D-B7/G idiom: `coach_id` written verbatim from the frozen `coachId` param
  (coach.uid); value semantics flip at the identity cutover; backfill remaps.
- HARD STOP: no row backfill, no file copy runs now — manifests only.
- House domains: TEXT + CHECK in live migrations; canonical enums at OD-1.
- Deletion norm: expected ZERO test deletions this phase (no H subject code
  dies — syncCalendar, both searches, and all six services keep their
  subjects; manageTopics-style retirements don't exist here). Any surprise
  deletion gets named per the norm.
- D-C5 has no H surface (no presence-meaning attendance reads in these
  services; digest/evaluator landed in G).
- meet_entries unit rule restated from D: hundredths verbatim, ÷ nowhere.

---

## §4 THE DECISIONS — D-H1 … D-H8 (options + recommendation)

**D-H1 — practice_plans + import_jobs walls become per-coach (canonical
amendment).**
(a) Amend canonical: add `is_my_profile(p UUID)` SECURITY DEFINER helper
(`EXISTS (SELECT 1 FROM profiles WHERE id = p AND user_id = auth.uid())`);
practice_plans: SELECT `is_staff() AND (is_my_profile(coach_id) OR
is_public)`, INSERT staff + own, UPDATE own + stays-own (WITH CHECK), DELETE
own; import_jobs: SELECT `is_super_admin() OR (is_staff() AND
is_my_profile(coach_id))`, INSERT staff + own, UPDATE own + stays-own,
DELETE `is_super_admin()`. pgTAP proves staff-A cannot read staff-B's
private plan/import, CAN read B's public template, cannot reassign, cannot
rate/tag B's rows; parents/pending/anon all zero.
(b) Keep canonical staff-wide — violates ratified D-F4; rejected on its face.
(c) Per-coach for plans, staff-wide for import_jobs — contradicts the live
import_jobs rule (owner+admin) for no benefit.
**Recommend (a), verbatim-mirror of today's rules.** season_plans stays
staff-shared (that IS today's wall — the asymmetry is real and preserved).

**D-H2 — the file tier.**
(a) PDFs: private bucket `practice-plans`, 25MB + application/pdf caps
mirrored, walls = `is_staff() AND owner-path-segment` (one named
hole-closing bit stricter than today, RH-14), upload via the F helper,
signed-URL reads, copy manifest rewrites the owner segment via the identity
map. **Recommend yes.**
(b) Imports: NO bucket, NO walls, NO copy line (nothing has ever written
`imports/**`; absence is parity — D-G2 verbatim class). The Firebase
`imports/**` rule dies with storage.rules at cutover (RF-4 family).
**Recommend yes — recorded as the correction to D-F4's premise.**

**D-H3 — calendar_events hosts the iCal sync (canonical amendment).**
Add `source TEXT`, `ical_uid TEXT UNIQUE`, `raw_rrule TEXT`,
`synced_at TIMESTAMPTZ`; relax `coach_id` to NULLABLE (ON DELETE SET NULL,
P1-1 spirit preserved for real coaches; synced rows carry coach_id NULL +
source='ical_sync'). syncCalendar swaps to one PG upsert
`onConflict('ical_uid')` with the same field list (clobber semantics
faithfully preserved); the djb2 docId machinery retires with Firestore
(its tests re-point to the upsert payload; subjects kept). created_at stops
churning (today's code rewrites it every run despite its comment; PG
ON CONFLICT UPDATE doesn't touch it — a healed bug, named, invisible to all
readers). Alternative — a dedicated sync table + view union — adds a JOIN to
every calendar read for zero wall benefit. **Recommend the amendment.**

**D-H4 — RSVP write becomes the canonical upsert.** `submitRSVP` →
`upsert(..., onConflict: 'event_id,swimmer_id')`; re-RSVP updates
status/parent_name/note + updated_at on the ONE row per swimmer per event.
Duplicates that Firestore tolerated become impossible (the D-C2 atomic
class); backfill collapses any existing dup pairs keeping latest updatedAt
+ REPORTS each collapse. **Recommend yes.**

**D-H5 — the calendar/RSVP parent arms (the genuine widening question).**
Canonical law says calendar_events SELECT for every active account (pending
included) + family RSVP read/write on own swimmers. Today's wall: coach-only.
No parent UI exists in either app for calendar or RSVPs.
(a) **Land canonical as written** — the walls match the ratified law and the
BSPC team-wide-content philosophy (pending parents already read
schedule_events + announcements); the grant is dormant until a parent
calendar feature ships. It IS a wall widening vs Firestore, on the record.
(b) **Staff-only now** — the no-widening doctrine read literally; the
family/pending arms land later WITH the parent calendar feature as a
one-line policy swap + proofs (the D-G2/D-G4 "capability follows product"
pattern). Diverges from canonical law until then (canonical gets a
[SCOPE-DEFERRED] annotation, not a rewrite).
**Recommend (b)** — every F/G precedent ("not one bit wider," "capability
without product = don't grant") points there, and the cost of adding the
arms later is one migration + pgTAP delta. Counter-argument honestly stated:
(a) is the literal ratified schema and the content class (practices, meets,
socials) is exactly what BSPC already shows pending parents. Kevin's call.

**D-H6 — rateWorkout/tagWorkout cross-coach: parity-deny.** Today's rules
deny rating/tagging another coach's public template (the feature never
functioned). Per-coach RLS preserves the denial; the cross-coach rating RPC
(`SECURITY DEFINER`, is_public-gated, one JSONB key per coach) is **banked
as a named post-cutover product line item** alongside coach push and
ai_drafts_ready. **Recommend parity-deny.**

**D-H7 — live meets policy alignment lands in 00009.** SELECT
`USING (TRUE)` → `is_active_account()` (deactivated lose read — the
accepted P1-8 narrowing class, proven); `meets_manage_admin` inline-EXISTS →
`is_staff()` (same principal set, verified like the G jobs-policy refactor).
Done now because 00009 itself adds the Coach columns to this
parent-readable table. **Recommend yes** (alternative: leave for the
convergence sweep — but then deactivated accounts read the new Coach fields
in the interim).

**D-H8 — import_jobs lands in Phase H** (scope confirmation per §0.5 /
§1e): importJobs.ts swap + csvImport/meetResultsImport jobs-halves +
per-coach walls (D-H1) + backfill manifest line. 04 left it phase-less;
D-F4 says "with their data"; H is where its file-sibling lives and where
its writers' last Firestore halves retire. **Recommend yes.** (Alternative:
its own micro-phase — pure ceremony, three small files.)

**FYI bundle to accept with the plan** (named, no separate decisions):
month-window rewrite proof (RH-4); pdf `title := filename` (RH-16);
weeks-key 23505 strictly-better + single-DELETE cascade (RH-10); entries
display-string + updatedAt-stamp drops (canonical has neither);
search null-mapping (BSPC rows surface `course`/`status` as '' in Coach
search results — frozen result shape); publication 14 → 22 with the 011
proof update (RH-12); ratings keys stay coach.uid until cutover (B
precedent); syncCalendar created_at-churn heals (D-H3); merged-meets
cross-visibility (RH-8); trigger-owned updated_at now bumps on tagWorkout
(§2 trigger note); subscribePracticePlans PDF-exclusion moves server-side,
group filter stays client-side (RH-16).

---

## §5 COMMIT SEQUENCE (executes only after §7 ratification; one green commit
each; all four bars at every commit; RC-3 throughout)

1. **Coach seasonPlanning DATA-LAYER pins (tests only)** — pin the CURRENT
   Firestore behavior of all six data functions (query shapes, payloads,
   client-side cascade, id-based week upsert). 04's mandate; no product code
   changes. Coach bar rises.
2. **BSPC `00009_phase_h_calendar_meets_plans.sql` + pgTAP `012` (+ the 011
   publication-set update, same commit)** — calendar_events (+D-H3 sync
   columns, D-H5 walls) + calendar_event_rsvps (UNIQUE key, D-H5 walls) +
   meets superset columns + D-H7 policy swap + meet_entries + practice_plans
   (+ is_my_profile(), D-H1 walls) + season_plans + season_plan_weeks (key +
   phase domain) + import_jobs (D-H1 walls) + house updated_at triggers +
   indexes per canonical + practice-plans bucket + D-H2a storage walls +
   publication +8. pgTAP 012 proves: shapes (columns_are = the SELECT
   contracts), CHECK domains, FKs + referential actions, the within-staff
   walls (staff-A/staff-B on plans + imports: private invisible, public
   template readable, no reassign, no cross-rate), parent/pending/anon
   zeros everywhere (or the D-H5(a) arms if so ratified), RSVP + weeks
   uniqueness, bucket caps + storage walls (incl. the closed parent-segment
   hole), meets principal-set proofs (deactivated 0; staff write set
   unchanged), publication EXACTLY 22.
3. **Coach calendar.ts swap** — subscribes (month-window rewrite RH-4,
   range, for-date) + addEvent/updateEvent/deleteEvent + subscribeRSVPs +
   submitRSVP upsert (D-H4); realtime parity ×2 channels; pure helpers
   untouched; tests re-pointed + new pins (Feb window, upsert onConflict,
   eq-absence where RLS scopes).
4. **Coach meets.ts swap** — subscribes/update/delete + subscribeEntries →
   meet_entries (swimmer embed for names); psych-sheet pure fns untouched;
   null-tolerant rendering pinned for BSPC-origin rows.
5. **Coach meetResultsImport meets-half** — the entries finalTime patch →
   `meet_entries` update keyed (meet_id, swimmer_id, event_name);
   display-string + stamp drops; swallow-and-report semantics verbatim.
6. **Coach practicePlans.ts + workoutLibrary.ts (the pair, one commit)** —
   all subscribes/CRUD with the D-H1 field maps (public→is_public etc.);
   PDF row creation (title := filename) + `subscribeTodayPracticePlan`;
   PDF upload → practice-plans bucket via the F helper (path layout
   preserved under the bucket); rateWorkout/tagWorkout/setPlanPublicStatus/
   searchWorkouts re-pointed (parity-deny pinned per D-H6); RH-2 filter
   discipline pinned.
7. **Coach seasonPlanning.ts swap under the commit-1 pins** — plans + weeks
   CRUD; single-DELETE cascade; id-based week upsert preserved.
8. **Coach search.ts meets+calendar halves** — frozen fetch-then-filter on
   canonical tables; null-mapping pinned.
9. **Coach importJobs.ts + csvImport/meetResultsImport jobs-halves (D-H8)**
   — subscribe/create/update on canonical import_jobs; vestigial
   storage_path strings preserved verbatim.
10. **Functions syncCalendar re-point (D-H3)** — one upsert
    onConflict('ical_uid'); env contract unchanged (CALENDAR_ICS_URL);
    skip-when-unconfigured + non-destructive + clobber semantics pinned;
    stableId tests re-pointed to the new key (subjects kept).
11. **`migration/h/README.md` (manifests only, HARD STOP) + NOTES landed
    log** — backfill order: meets reconcile (name+start_date match,
    ambiguity REPORT+STOP, superset-fill merge — the roster-reconcile
    pattern) → meet_entries (roster map + meet map; unresolvable STOP;
    hundredths verbatim) → calendar_events (icalUid → ical_uid;
    'ical_sync' coachId → NULL + source; recurring/rawRrule passthrough) →
    rsvps (dup-pair collapse keep-latest + REPORT) → practice_plans
    (ratings keys + templateSourceId remaps; pdf title synthesis) →
    season_plans/weeks (practice_plan_ids remap) → import_jobs (coachId →
    profiles.id). File copy: `practice_plans/{firebaseUid}/…` →
    `practice-plans/{user_id}/…` (identity-map segment rewrite);
    `imports/**` verify-empty (non-empty → REPORT, never auto-copy).

Expected deletions: **zero** (every subject survives). Expected bar: pgTAP
+(012's proofs) and 011's publication count edit; Coach + Functions counts
rise; BSPC jest unchanged.

---

## §6 RED-TEAM DISPOSITION

| RH | Resolved by |
|---|---|
| RH-1 | D-H1 + §5.2 proofs |
| RH-2 | §5.3/6/7/9 filter-discipline pins |
| RH-3 | D-H3 + §5.2/§5.10 |
| RH-4 | §5.3 month rewrite + Feb pin |
| RH-5 | D-H4 + §5.2 key proof + §5.3 |
| RH-6 | D-H5 (Kevin) + §5.2 wall proofs |
| RH-7 | D-H6 parity-deny + §5.6 pins |
| RH-8 | FYI bundle + §5.4 null-tolerance pins |
| RH-9 | §5.11 manifest STOP rules + unit rule |
| RH-10 | §5.2 key proof + §5.7 pins |
| RH-11 | §5.1 before §5.7 |
| RH-12 | §5.2 same-commit 011 update |
| RH-13 | D-H2b + §5.11 verify-empty line |
| RH-14 | D-H2a + §5.2 storage proofs |
| RH-15 | D-H7 + §5.2 principal-set proofs |
| RH-16 | §5.2 shape + §5.6 title pin |

---

## §7 [DECIDE] — for Kevin (everything else above executes as written once
these are called)

1. **D-H1** — amend canonical: per-coach walls on practice_plans
   (+ is_public read arm) and import_jobs (+ super_admin arms), via
   `is_my_profile()`; season_plans stays staff-shared (today's wall).
   **Recommend yes (a).**
2. **D-H2** — (a) practice-plans bucket with per-coach storage walls one
   named bit stricter than today (parent-segment hole closed); (b) NO
   imports bucket — import files never existed; absence is parity, recorded
   as the correction to D-F4's premise. **Recommend yes to both.**
3. **D-H3** — amend canonical calendar_events: + source / ical_uid UNIQUE /
   raw_rrule / synced_at, coach_id nullable; syncCalendar upserts on
   ical_uid. **Recommend yes.**
4. **D-H4** — RSVP becomes upsert on UNIQUE(event_id, swimmer_id); dups
   impossible; backfill collapses + reports. **Recommend yes.**
5. **D-H5** — calendar_events + rsvps parent/family arms: (a) land
   canonical's active-read + family-RSVP walls now (a named widening vs
   Firestore, dormant until a parent UI exists) vs (b) staff-only now,
   arms ship with the parent calendar feature (no-widening literal;
   canonical annotated as deferred). **Recommend (b); honest case for (a)
   stated in §4.**
6. **D-H6** — cross-coach rating/tagging stays denied (parity with a
   feature that never functioned); rate_workout RPC banked as a named
   post-cutover product line item. **Recommend yes.**
7. **D-H7** — align live meets policies in 00009 (TRUE-select →
   is_active_account, proven narrowing; admin-inline → is_staff(), proven
   same-set). **Recommend yes.**
8. **D-H8** — import_jobs (rows + service + both writer-halves) is IN
   Phase H. **Recommend yes.**
9. **FYI bundle** (§4 end) — accept as named.
