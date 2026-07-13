# 04 — Cross-Tier Migration Sequencing (the backbone)

**PLANNING DOC ONLY.** No app code, no commits beyond this file. Schema
(`01_CANONICAL_SCHEMA.sql`) stays law. Reviewed before any execution.

## Why we're here
The clean solo migrations are spent. `group_notes` and `goals` were the only
collections that were simultaneously **sole-writer + untouched by any Cloud
Function/portal + data-layer actually tested**. Everything left is one
interdependent cluster rooted in the foundational entities (**profiles/identity,
swimmers, attendance, times**) that the 16 Cloud Functions operate on. See
`03_MIGRATION_PLAYBOOK.md` for the per-service mechanics this plan sequences.

## The key coordination insight (read first)
The canonical schema is **not yet applied to any database**, and nothing is
deployed against it. So **"split-brain" is a CUTOVER/runtime property, not a
test property.** A mocked client test and a mocked function test each pass
independently of which backend the *other* side talks to. Consequences:

- **Code migration order is test-gated and flexible** — each side stays green
  on its own mocks regardless of the other.
- **Runtime correctness requires that, at data cutover, a collection's client
  code AND every function touching it are on the same backend.**
- **Therefore: migrate code cluster-by-cluster in dependency order (below),
  keep both suites green at every commit, and defer the actual Firestore→PG
  data cutover to one coordinated step per cluster (or a single big-bang)
  AFTER the schema is applied and backfill is staged.** This "code-first,
  cutover-last" model means we do **not** need dual-write bridges in the common
  case. A bridge is only required if a *production* cutover of one cluster must
  ship before a dependent cluster's code is migrated — flagged per-step below.

## Full remaining dependency graph

### Client services → collection (✅ = migrated)
| Collection | Client writer(s) | Notes |
|---|---|---|
| group_notes | groupNotes.ts ✅ | done |
| goals | goals.ts ✅ | done |
| swimmers | swimmers.ts, profilePhoto.ts, csvImport.ts, meetResultsImport.ts | + analytics/search read |
| attendance | attendance.ts | parent app reads a derived view |
| swimmers/{id}/times | times.ts, meetResultsImport.ts | + analytics reads |
| swimmers/{id}/notes | notes.ts, aiDrafts.ts, videoDrafts.ts, swimmerVoiceNotes.ts | **4 writers** + search collectionGroup |
| swimmers/{id}/voice_notes | swimmerVoiceNotes.ts | also calls notes.addNote |
| audio_sessions (+drafts) | audio.ts, aiDrafts.ts | storage; drafts→notes |
| video_sessions (+drafts) | video.ts, videoDrafts.ts | storage; drafts→notes |
| meets (+entries) | meets.ts, meetResultsImport.ts | + search reads |
| calendar_events | calendar.ts | + search reads; parent-app schedule overlap |
| practice_plans | practicePlans.ts, workoutLibrary.ts | **shared** (templates) |
| season_plans (+weeks) | seasonPlanning.ts | **data layer UNTESTED — write tests first** |
| notification_rules | notificationRules.ts | sole client writer |
| notifications | notifications.ts | + coaches/fcmTokens array |
| parent_invites | parentInvites.ts | redeemed by a function |
| import_jobs | importJobs.ts, csvImport.ts, meetResultsImport.ts | shared — **Phase H** [D-H8] |
| aggregations | aggregations.ts (read-only) | **DO NOT migrate — recompute in PG** |

### Cloud Functions → collections (R=read, W=write, T=fires on)
| Function | Collections |
|---|---|
| triggers/onAttendanceWritten | attendance (T) → aggregations |
| triggers/evaluateNotificationRules | attendance (R), notification_rules (R), notifications (W) |
| triggers/dashboardAggregations | attendance, notes, times, video_sessions (R) → aggregations |
| triggers/onTimesWritten | times (T) |
| triggers/onNotesWritten | notes (T) |
| triggers/onVideoSessionWritten | video_sessions (T) |
| triggers/onVideoUploaded | video_sessions (storage T) |
| triggers/onAudioUploaded | audio_sessions (storage T) |
| triggers/onDraftReviewed | audio_sessions/{id}/drafts (T) |
| triggers/onNotification | notifications (T) → push |
| scheduled/dailyDigest | attendance, coaches, notes, notifications, video_sessions |
| scheduled/rebuildAggregations | swimmers (R) → aggregations |
| scheduled/syncCalendar | calendar_events (W, iCal) |
| callable/parentPortal | attendance, swimmers, times, parents (R) — **parent-portal data API** |
| callable/redeemInvite | parent_invites, parents (W) — **creates the parent↔swimmer link (D-A)** |
| callable/manageTopics | — (FCM topics only) |
| ai/extractObservations | swimmers (R) |

### Parent-portal (Next.js)
Reads almost entirely through the **`parentPortal` callable** (attendance,
swimmers, times, parents). Directly touches only `posts`. → Migrating the
callable's reads migrates the portal's data source; the portal itself barely
changes.

### Schema fan-in (why foundational-first)
- **17 tables `REFERENCES swimmers`** (meets, meet_entries, swim_results,
  personal_bests, goals, swimmer_notes, group_notes, swimmer_voice_notes,
  audio_sessions(+swimmers,+drafts), video_sessions(+swimmers,+drafts),
  season_plans(+weeks), attendance, notification_preferences, notification_jobs,
  in_app_notifications).
- **24 columns `REFERENCES profiles`** (every coach_id / actor / guardian ref).
- `is_my_swimmer()` and all family RLS resolve through **guardianships** →
  identity must exist before any parent-facing read is correct.

## Proposed migration ORDER (foundational-first)

| Ph | Cluster | One-line rationale |
|---|---|---|
| **A** | **Identity** — profiles, auth map, guardianships | 24 FKs + all RLS resolve through profiles/guardianships; nothing else lands coach_id/guardian refs correctly until this exists. |
| **B** | **swimmers** (roster root) | 17 FKs hang off it; the roster reconciliation (Coach↔BSPC) must happen here to avoid duplicate swimmers. |
| **C** | **attendance** | FK swimmers; densest function fan-in + inherited parent-app reads + two-a-day uniqueness. **Riskiest — see below.** |
| **D** | **times** | FK swimmers; PR logic + the ÷10 unit audit. |
| **E** | **notes + voice_notes** | FK swimmers; notes has 4 writers + search collectionGroup; two-pass source pointers. |
| **F** | **media** (audio/video sessions + drafts + junctions) | FK swimmers; storage + UUID[]→junction tables + note↔draft cross-pointers. |
| **G** | **notifications + rules** | evaluator READS attendance → must follow C; idempotency UNIQUE + upsert; FCM→Expo tokens. |
| **H** | **calendar + meets + plans + import_jobs** [D-H8] | Lower fan-in; can come late. season_plans needs tests written first. |
| **I** | **parent_invites + parent-portal cutover** | redeemInvite creates guardianships; portal callable now reads migrated A/B(+C/D). Parent-facing cutover. |
| **J** | **aggregations decommission** | Do NOT migrate; recompute via PG triggers/jobs *[D-J2, ratified 2026-06-10: VIEWS won — compute-on-read (00011); no triggers/jobs exist]*; retire/re-point rebuildAggregations + dashboardAggregations. |

### Per-step: function coordination + green guardrails
- **A — Identity.** Client: AuthContext/profile reads. Functions: `redeemInvite`
  (parents→profiles + guardianship write), `dailyDigest` (coaches read),
  `parentPortal` (parents read). Coordination: move client + these functions to
  resolve profiles/guardianships together; **cutover-last**. Guardrails: Coach
  client suite + functions suite (106) + **BSPC parent-app suite (774, TZ=UTC)**
  — identity underlies parent access. Backfill: **Firebase-UID→profiles.id**
  remap table; `parents.linkedSwimmerIds[]`→guardianship rows.
- **B — swimmers.** Client: swimmers.ts, profilePhoto.ts, csvImport.ts (swimmer
  writes). Functions: `extractObservations`, `rebuildAggregations`,
  `parentPortal`(swimmers). Coordination: client + functions together; cutover
  after A. Guardrails: Coach + functions + BSPC parent-app. Backfill:
  **swimmer-doc-id→swimmers.id** remap + **roster reconciliation** (usa_swimming_id,
  then name+DOB) to dedupe against existing BSPC swimmers.
- **C — attendance.** Client: attendance.ts (check-in adapter must `ON CONFLICT`
  + pass `schedule_event_id` for two-a-days, per D-B). Functions:
  `onAttendanceWritten`, `evaluateNotificationRules`, `dashboardAggregations`,
  `dailyDigest`, `parentPortal` — **5, the most of any collection; all move with
  the client**. Guardrails: Coach attendance tests + functions suite +
  **BSPC parent-app present/absent VIEW reads** (the inherited P0s we fixed —
  status nullable, parent view CASE). Backfill: dedup historical same-day
  Firestore rows; map status null/'normal'→present.
- **D — times.** Client: times.ts, meetResultsImport.ts, analytics.ts. Functions:
  `onTimesWritten`, `dashboardAggregations`(times), `parentPortal`(times).
  Backfill: **÷10 audit per source** (`time_ms % 10`), assign
  `personal_bests.course` for legacy rows.
- **E — notes + voice_notes.** Client: notes.ts, aiDrafts.ts, videoDrafts.ts,
  swimmerVoiceNotes.ts (4 writers — migrate together). Functions: `onNotesWritten`,
  `dailyDigest`(notes), `dashboardAggregations`(notes), `search` collectionGroup.
  Backfill: two-pass load for `source_*`/`posted_note_id` cross-pointers.
- **F — media.** Client: audio.ts, aiDrafts.ts, video.ts, videoDrafts.ts.
  Functions: `onAudioUploaded`, `onDraftReviewed`, `onVideoUploaded`,
  `onVideoSessionWritten`, `dailyDigest`/`dashboardAggregations`(video). Backfill:
  UUID[] selects → `audio_session_swimmers`/`video_session_swimmers` junctions.
- **G — notifications + rules.** Client: notificationRules.ts, notifications.ts.
  Functions: `evaluateNotificationRules` (reads attendance — **hard dep on C**),
  `onNotification`, `dailyDigest`(notifications). Adapter: notification writer
  upsert `ON CONFLICT (rule_id, swimmer_id, source_eval_date)` (decision #2).
  Tokens: FCM→Expo (`push_tokens`, decision #7).
- **H — calendar + meets + plans + import_jobs [D-H8].** Client: calendar.ts,
  meets.ts, meetResultsImport.ts (meets-half + jobs-half), practicePlans.ts +
  workoutLibrary.ts (shared practice_plans — migrate as a pair),
  seasonPlanning.ts (**write data-layer tests FIRST**), importJobs.ts +
  csvImport.ts jobs-half. Functions: `syncCalendar`. Backfill: remap id
  arrays/JSONB (`practice_plan_ids`, ratings keys, `meets.events`).
- **I — parent_invites + portal.** Client: parentInvites.ts. Functions:
  `redeemInvite` (guardianship creation), `parentPortal` (now reads migrated
  data). Depends on A+B. Guardrails: functions suite + parent-portal build.
- **J — aggregations.** No data migration. Recompute via PG (unbuilt
  triggers/jobs); point `aggregations.ts` reads at PG-computed views; retire the
  two aggregation CFs.
  *[D-J2, ratified 2026-06-10: "(unbuilt triggers/jobs)" resolved — the recompute landed as compute-on-read VIEWS (00011); the views wording prevails.]*

## Where the deferred backfills slot in (from NOTES.md)
| Backfill | Phase |
|---|---|
| Firebase-UID → `profiles.id` remap (+ disable `on_auth_user_created` during load) | **A** |
| `parents.linkedSwimmerIds[]` → guardianship rows (D-A) | **A** |
| swimmer-doc-id → `swimmers.id` remap + roster reconciliation | **B** |
| Attendance: historical same-day dedup; status null/'normal'→present | **C** |
| Times ÷10 audit per source; `personal_bests.course` assignment | **D** |
| Notes/drafts two-pass `source_*`/`posted_note_id` pointers | **E** |
| UUID[] → media junction tables | **F** |
| Notification idempotency upsert; FCM→Expo tokens | **G** |
| id-array/JSONB remap (practice_plan_ids, ratings keys, meets.events) | **H** |
| Aggregations: recompute in PG (NOT migrated) | **J** |

## ⚠️ SINGLE RISKIEST STEP — Phase C, attendance (review this hardest)
Five compounding risks converge here:
1. **Most split-brain functions of any collection** — 5 (`onAttendanceWritten`,
   `evaluateNotificationRules`, `dashboardAggregations`, `dailyDigest`,
   `parentPortal`) must all cut over with the client.
2. **Inherited parent-app P0s** — this is the table where we made `status`
   nullable and built the parent **present/absent derived view**. The BSPC
   parent app's *existing* reads must not regress; that suite is the guardrail,
   and it's the most COPPA-sensitive (minors' presence data).
3. **Two-a-day uniqueness (D-B)** — the check-in adapter must `ON CONFLICT` on
   the partial unique indexes and pass `schedule_event_id`; getting this wrong
   silently drops or collides AM/PM records.
4. **Historical dedup** — Firestore has duplicate same-day rows that must be
   collapsed before load, or the partial unique indexes reject the backfill.
5. **Cross-tier blast radius** — attendance feeds aggregations, notifications,
   the daily digest, AND the parent portal; an error propagates to all four.

Recommendation: when we reach C, treat it as its own mini-plan with its own
red-team pass, and stage the historical dedup + two-a-day adapter against a
throwaway DB before any cutover.

## Open questions for review (tomorrow)
- **Cutover granularity:** per-cluster cutovers (more deploys, smaller blast
  radius each) vs. one big-bang after all code is migrated (single risky
  switch). Leaning per-cluster, A→J.
- **Identity for the BSPC parent app:** it already runs on Supabase/profiles —
  confirm the Coach-side identity merges INTO that existing profiles table
  (single target), not a parallel one.
- **season_plans:** write its data-layer tests as a prerequisite to Phase H, or
  migrate it untested behind a feature it's safe to leave (no — tests first).
> ⚠️ HISTORICAL — superseded by the fresh-launch model in Director Rulings 56/57; retain as sequencing history, not executable migration instructions.
