# 00 — TERRAIN: Data-Model Reconciliation Map

**Status:** Design artifact for review. **No SQL written, no app code changed.**
This is the survey we agree on *before* drafting `UNIFY/01_CANONICAL_SCHEMA.sql`.

**What this maps:** the two apps that must collapse onto one canonical Postgres backend.

| App | Backend | Role | Source of truth read for this doc |
|---|---|---|---|
| **BSPC** (`BSPC/`) | Supabase / Postgres | Parent-facing, information-first | `BSPC/ACTIVE/supabase/migrations/00001_initial_schema.sql` |
| **BSPC-Coach-App** (`BSPC-Coach-App/`) | Firebase / Firestore (+ Next.js parent-portal, 16 Cloud Functions) | Coach-facing write tools | `src/services/*.ts`, `src/types/*.ts`, `src/config/constants.ts`, `firestore.rules`, `firestore.indexes.json`, `functions/src/**`, `parent-portal/**` |

**Citation format:** Coach-App paths are relative to `BSPC-Coach-App/`. Postgres citations are line numbers in `00001_initial_schema.sql`. `CF` = written/read by a Cloud Function.

**Strategic framing (one paragraph, to confirm):** Because the canonical schema is `.sql`, **Postgres/Supabase is the target backend** and the Coach App's Firestore data layer migrates onto it behind its existing service interfaces. This is *not* a merge of two equal apps. BSPC's parent-facing schema is already relational and largely stands; the Coach App carries a **much larger write-side model** (notes, goals, practice/season planning, media + AI drafts, imports, aggregations) plus its **own identity model** (`coaches` + `parents`). The canonical schema will therefore be roughly **BSPC's schema, kept, + a large coach-side addition, + a reconciled identity/roster core where the two overlap.** Both test suites stay green throughout.

---

## §0 Collection / Table census (at a glance)

**Coach-App Firestore — ~~23~~ 32 collection paths (25 ★ + 7 ⚠)** (★ = actively used, ⚠ = declared in rules/types but **no implementation found**):

> **[Corrected 2026-06-11 — GAP-A ruling, GAP-CLOSURE round; the e71050a
> amend-in-place idiom]** The census below ENUMERATES **32 paths (25 ★ +
> 7 ⚠)** — the old "23" was 06 §B2's manifest-table organization leaking
> into this header (the same 32 paths cover exactly 23 manifest ROWS:
> parent+child collections share rows, and the five never-implemented ⚠
> paths share one). The OPERATIVE reading is the enumerated list — the
> landed §B0 probe is built on these 32 names
> (`scripts/probe-firebase-inventory-report.ts`, superset-safe).

```
coaches ★                              parent_invites ★
swimmers ★                             parents ★ (CF-write only)
  swimmers/{id}/notes ★                notifications ★ (CF-write only)
  swimmers/{id}/times ★                notification_rules ★
  swimmers/{id}/goals ★                import_jobs ★
  swimmers/{id}/voice_notes ★          group_notes ★
  swimmers/{id}/medical ⚠ (rules only) aggregations ★ (CF-write only)
attendance ★                          messages ⚠ (type only, unused)
audio_sessions ★                      coach_chat ⚠ (rules only, unused)
  audio_sessions/{id}/drafts ★         workout_library ⚠ (rules only; practice_plans
video_sessions ★                          with isTemplate=true is used instead)
  video_sessions/{id}/drafts ★        practice_plans ★ (also holds dashboard-PDF docs)
meets ★                               season_plans ★
  meets/{id}/entries ★ (read-only)      season_plans/{id}/weeks ★
  meets/{id}/relays ⚠ (type only)     calendar_events ★
  meets/{id}/live_events ⚠ (rules)      calendar_events/{id}/rsvps ★
  meets/{id}/splits ⚠ (rules)
```

**BSPC Postgres — 22 tables:** `families`, `profiles`, `swimmers`, `schedule_events`, `raw_schedule_snapshots`, `imported_schedule_events`, `schedule_overrides`, `schedule_change_log`, `announcements`, `meets`, `push_tokens`, `notification_preferences`, `notification_jobs`, `in_app_notifications`, `swim_results`, `personal_bests`, `team_records`, `hall_of_fame`, `attendance`, `glossary_terms`, `time_standards`, `feedback`.

**Shared enums (Coach App, `src/config/constants.ts`):**
- `GROUPS` (L1–9): `Bronze, Silver, Gold, Advanced, Platinum, Diamond, Masters`
- `COURSES` (L17): `SCY, SCM, LCM`
- `STANDARD_LEVELS` (L109): `B, BB, A, AA, AAA, AAAA`
- `AGE_GROUPS` (L112): `10&U, 11-12, 13-14, 15-16, 17-18`
- `NOTE_TAGS` (L47–67): 19 values (`technique`, stroke names, `starts`, `turns`, … `general`)
- `MEET_STATUSES` (L126): `upcoming, in_progress, completed, cancelled`
- `CALENDAR_EVENT_TYPES` (L115): `practice, meet, team_event, fundraiser, social`

---

## §1 Coach-App Firestore collections — fields, shape, and who touches them

> Firestore convention: timestamps are `Timestamp`; dates that need range queries are stored as `YYYY-MM-DD` **strings**; coaching docs heavily **denormalize** display fields (`swimmerName`, `coachName`, `timeDisplay`).

### `coaches` — coach identity / auth
**Shape** (`src/types/firestore.types.ts:13–30`): doc id **= Firebase Auth uid**; `email`, `displayName`, `role: 'admin' | 'coach'`, `groups: Group[]` (which groups this coach owns), `notificationPrefs: { dailyDigest, newNotes, attendanceAlerts, aiDraftsReady: boolean }`, `fcmTokens: string[]`, `createdAt`, `updatedAt`.
**Touched by:** `src/contexts/AuthContext.tsx` (create on first login), `src/services/notifications.ts:56,64` (FCM token add/remove).
**Notable:** No "family/parent" role here — parents live in a separate `parents` collection. `role` enum is **{admin, coach}** only.

### `swimmers` — roster
**Shape** (`src/types/firestore.types.ts:53–77`): `firstName`, `lastName`, `displayName`, `dateOfBirth: Timestamp`, `gender: 'M'|'F'`, `group: Group`, `active: boolean`, `usaSwimmingId?`, `profilePhotoUrl?`, `strengths: string[]`, `weaknesses: string[]`, `techniqueFocusAreas: string[]`, `goals: string[]` (denormalized id list), `parentContacts: { name, phone, email, relationship }[]`, `meetSchedule: string[]`, `mediaConsent?: { granted: boolean, date: Timestamp, expiresAt?, grantedBy?, notes? }`, `doNotPhotograph?: boolean`, `createdBy` (coach uid), `createdAt`, `updatedAt`.
**Touched by:** `src/services/swimmers.ts:23,38,51`, `csvImport.ts:151,176`, `analytics.ts:36,121`, `profilePhoto.ts:27,44`.
**Notable:** **No `familyId` / parent FK** — parent linkage is held on the `parents` doc, not here. Carries the entire coaching profile (strengths/weaknesses/focus/consent).

### `swimmers/{id}/notes` — coaching notes
**Shape** (`src/types/firestore.types.ts:94–104`): `content`, `tags: NoteTag[]`, `source: 'manual'|'audio_ai'|'video_ai'|'voice_inline'`, `sourceRefId?` (→ audio draft / voice_note), `coachId`, `coachName`, `practiceDate: string (YYYY-MM-DD)`, `createdAt`.
**Touched by:** `notes.ts:33,51,64`; created from AI drafts in `aiDrafts.ts:82,138` and `videoDrafts.ts:47`; from voice in `swimmerVoiceNotes.ts:109`.

### `swimmers/{id}/times` — swim times
**Shape** (`src/types/firestore.types.ts:79–92`): `event: string`, `course: Course`, **`time: number` (hundredths of a second**, e.g. 6523 = 1:05.23), `splits?: number[]` (hundredths per 50), `timeDisplay: string`, `isPR: boolean`, `meetName?`, `meetDate?: Timestamp`, `source: 'manual'|'sdif_import'|'hy3_import'`, `createdAt`, `createdBy`.
**Touched by:** `times.ts:30,56,71,110` (PR auto-flag is atomic — adding a time un-flags the prior PR), `meetResultsImport.ts:65,130`, `analytics.ts:60`.
**Notable:** **Units = hundredths of a second.** PR is a per-time boolean flag, not a separate table.

### `swimmers/{id}/goals`
**Shape** (`src/types/firestore.types.ts:318–332`): `event`, `course`, `targetStandard?: StandardLevel`, `targetTime?: number (hundredths)`, `targetTimeDisplay?`, `currentTime?`, `currentTimeDisplay?`, `notes?`, `achieved: boolean`, `achievedAt?`, `createdAt`, `updatedAt`.
**Touched by:** `goals.ts:22,36,49,66`.

### `swimmers/{id}/voice_notes`
**Shape** (`src/types/voiceNote.ts:5–13`): `swimmerId`, `coachId`, `storagePath: string` (e.g. `audio/swimmers/{id}/{date}/{noteId}.m4a`), `durationSec: number`, `createdAt`, `transcription: string | null`. (Service also stamps `practiceDate`/`coachName` per `swimmerVoiceNotes.ts:67–100`.)
**Touched by:** `swimmerVoiceNotes.ts:73,90,124,129` — doc created before upload; `storagePath`/`transcription` filled in asynchronously; offline retry queue in AsyncStorage.

### `swimmers/{id}/medical` ⚠
Declared in `firestore.rules:43–47` (read: coach; **write: admin only**). **No service reads/writes it** in current code. Shape unknown.

### `group_notes` — practice-level notes (not swimmer-specific)
**Shape** (`src/services/groupNotes.ts:19–28`): `content`, `tags: NoteTag[]`, `group: Group`, `practiceDate: string`, `coachId`, `coachName`, `createdAt`.
**Touched by:** `groupNotes.ts:41,55,68`.

### `attendance`
**Shape** (`src/types/firestore.types.ts:106–121`; `src/services/attendance.ts:55–67`): `swimmerId`, `swimmerName`, `group: Group`, `practiceDate: string (YYYY-MM-DD)`, `arrivedAt: Timestamp`, `departedAt?: Timestamp`, `status?: 'normal'|'excused'|'sick'|'injured'|'left_early'` (null until checkout), `note?`, `markedBy` (coach uid), `coachName`, `createdAt`.
**Touched by:** `attendance.ts:28,40,55,76,95` (`batchCheckIn` chunks at 400 to respect Firestore's 500-write batch limit), `analytics.ts`.
**Notable:** **No `scheduleEventId`** — attendance is keyed by `(swimmerId, practiceDate)`, not by a schedule row. Check-in/check-out timestamps, plus a 5-value status.

### `audio_sessions` (+ `/drafts`)
**Session** (`src/types/firestore.types.ts:175–189`; `audio.ts:44–66`): `coachId`, `coachName`, `storagePath`, `duration` (sec), `practiceDate: string`, `group?: Group|null`, `selectedSwimmerIds: string[]` (non-empty), `status: 'queued'|'uploading'|'uploaded'|'transcribing'|'extracting'|'review'|'posted'|'failed'`, `transcription?: string|null`, `errorMessage?`, `createdAt`, `updatedAt`.
**Draft** (`src/types/firestore.types.ts:191–203`; `aiDrafts.ts`): `swimmerId`, `swimmerName`, `observation`, `tags: NoteTag[]`, `confidence: number (0–1)`, `approved?: boolean`, `reviewedBy?`, `reviewedAt?`, `postedNoteId?`, `createdAt`.
**Touched by:** `audio.ts:28,44,71`; `aiDrafts.ts:25,59,94,106,160` (approval converts a draft → a swimmer note).
**Notable:** COPPA/SafeSport consent is enforced **at draft-approval** via `assertCanTagSwimmer()` (`src/utils/mediaConsent.ts`), not at session create.

### `video_sessions` (+ `/drafts`)
**Session** (`src/types/firestore.types.ts:205–231`; `video.ts:102–113`): `coachId`, `coachName`, `storagePath`, `thumbnailPath?`, `duration`, `practiceDate: string`, `group?`, `taggedSwimmerIds: string[]`, `selectedSwimmerIds?: string[]`, `status: 'queued'|'uploading'|'uploaded'|'extracting_frames'|'analyzing'|'review'|'posted'|'failed'`, `frameCount?`, `errorMessage?`, `createdAt`, `updatedAt`.
**Draft** (`src/types/firestore.types.ts:233–256`; `videoDrafts.ts:7–21`): `swimmerId`, `swimmerName`, `observation`, `diagnosis`, `drillRecommendation`, `phase: 'stroke'|'turn'|'start'|'underwater'|'breakout'|'finish'|'general'`, `tags`, `confidence`, `approved?`, `reviewedBy?`, `reviewedAt?`, `createdAt`.
**Touched by:** `video.ts:35,51,80,118`; `videoDrafts.ts:23,58`.
**Notable:** consent enforced **at session create** (`video.ts:99`) AND at draft approval.

### `practice_plans` — also stores dashboard-PDF metadata docs
**Plan** (`src/types/firestore.types.ts:276–293`): `title`, `description?`, `group?`, `isTemplate: boolean`, `public?: boolean`, `templateSourceId?`, `date?: string`, `coachId`, `coachName`, `totalDuration: number (min)`, `tags?: string[]`, `ratings?: Record<coachId, number>`, `sets: PracticePlanSet[]`, `createdAt`, `updatedAt`.
  - `PracticePlanSet` (L269–273): `order`, `name`, `category: SetCategory`, `description?`, `items: PracticePlanItem[]`.
  - `PracticePlanItem` (L259–265): `order`, `reps`, `distance`, `stroke`, `interval?`, `description?`, `focusPoints: string[]`.
**PDF-doc variant** (`src/types/practicePlan.ts:5–15`): same collection, discriminated by `documentType: 'dashboard_pdf'` + `storagePath`, `filename`, `uploadedAt`, `sizeBytes`, `pageCount`.
**Touched by:** `practicePlans.ts:46,67,77,84,90,134`; `workoutLibrary.ts:55,81,113,120,131,149` (the "workout library" is **`practice_plans` filtered by `isTemplate=true`**, not the `workout_library` collection).
**Notable:** owner-scoped by `coachId` in `firestore.rules:74–82`; 8 composite indexes on `(isTemplate, public, group, tags, …)`.

### `season_plans` (+ `/weeks`)
**Plan** (`src/types/firestore.types.ts:411–423`): `name`, `group: Group`, `startDate`, `endDate`, `phases: SeasonPhase[]`, `totalWeeks`, `coachId`, `coachName`, `createdAt`, `updatedAt`.
  - `SeasonPhase` (L386–395): `name`, `type: 'base'|'build1'|'build2'|'peak'|'taper'|'race'|'recovery'`, `startDate`, `endDate`, `weeklyYardage`, `focusAreas: string[]`, `notes?`.
**Week** (`src/types/firestore.types.ts:398–409`): `weekNumber`, `startDate`, `endDate`, `phase: SeasonPhaseType`, `targetYardage`, `actualYardage?`, `practiceCount`, `notes?`, `practicePlanIds: string[]` (→ practice_plans).
**Touched by:** `seasonPlanning.ts:20,34,45,55,64,71` (delete cascades to `weeks`).

### `meets` (+ `/entries`; `/relays`, `/live_events`, `/splits` declared-unused)
**Meet** (`src/types/meet.types.ts:6–23`; `meets.ts:22–46`): `name`, `location`, `course: Course`, `startDate: string (YYYY-MM-DD)`, `endDate?`, `status: MeetStatus`, `events: MeetEvent[]` (nested: `number`, `name`, `gender`, `ageGroup?`, `isRelay`), `groups: Group[]` (empty = all), `notes?`, `sanctionNumber?`, `hostTeam?`, `coachId`, `coachName`, `createdAt`, `updatedAt`.
**Entry** (`src/types/meet.types.ts:33–52`): `meetId`, `swimmerId`, `swimmerName`, `group`, `gender`, `age`, `eventName`, `eventNumber`, `seedTime?` (hundredths), `seedTimeDisplay?`, `finalTime?`, `finalTimeDisplay?`, `place?`, `heat?`, `lane?`, `isPR?`, `createdAt`.
**Touched by:** `meets.ts:22,29,42,49,59`; entries patched by `meetResultsImport.ts:172`. Entry creation was removed in a feature-prune sprint → **`entries` is read-only now**.
**Unused:** `relays` (`meet.types.ts:54–76`, no service), `live_events` / `splits` (rules only, no type/service).

### `calendar_events` (+ `/rsvps`)
**Event** (`src/services/calendar.ts:62–80`; `src/types/firestore.types.ts:336–356`): `title`, `description?`, `type: CalendarEventType`, `startDate: string`, `startTime?: 'HH:MM'`, `endDate?`, `endTime?`, `location?`, `groups: Group[]` (empty = all), `recurring?: { frequency: 'weekly'|'biweekly'|'monthly', dayOfWeek?: 0–6, until? }`, `coachId`, `coachName`, `createdAt`, `updatedAt`.
**RSVP** (`calendar.ts:86–105`; `src/types/firestore.types.ts:358–369`): `eventId`, `swimmerId`, `swimmerName`, `status: 'going'|'maybe'|'not_going'`, `parentName?`, `note?`, `updatedAt`.
**Touched by:** `calendar.ts:20,34,51,62,75,82,86,96`; read by `search.ts`.

### `parent_invites`
**Shape** (`src/types/firestore.types.ts:371–383`; `parentInvites.ts:21–66`): `code: string` (8+ char, uppercased), `swimmerId`, `swimmerName`, `coachId`, `coachName`, `redeemed: boolean`, `redeemedBy?` (parent uid), `redeemedAt?`, `expiresAt: Timestamp` (7-day default), `createdAt`.
**Touched by:** `parentInvites.ts:21,62`; redeemed by **CF** `functions/src/callable/redeemInvite.ts:21–86`. Revoke = soft (sets `redeemed=true`).

### `parents` — **CF-write only**
**Shape** (`functions/src/callable/redeemInvite.ts:49–78`; `parentPortal.ts:4–9,84–90`): doc id **= parent uid**; `email`, `displayName`, `linkedSwimmerIds: string[]`, `createdAt`, `updatedAt`.
**Touched by:** created/appended by `redeemInvite` (CF); read by `parentPortal` (CF). Parent→swimmer linkage is an **array on the parent doc**.

### `notifications` — **CF-write only**
**Shape** (`src/types/firestore.types.ts:305–314`): `coachId`, `title`, `body`, `type: 'daily_digest'|'ai_drafts_ready'|'standard_achieved'|'general'`, `data?: Record<string,string>`, `read: boolean`, `ruleId?`, `swimmerId?`, `evalDate?`, `createdAt`.
**Touched by:** read + mark-read by `notifications.ts:104`; written by CF `evaluateNotificationRules.ts:59–82`, `scheduled/dailyDigest.ts:31–39`. Rule-triggered ids are deterministic: `rule_{ruleId}_{swimmerId}_{evalDate}`.

### `notification_rules`
**Shape** (`src/types/firestore.types.ts:434–447`; `notificationRules.ts:25–62`): `name`, `trigger: 'attendance_streak'|'missed_practice'|'pr_achieved'|'time_standard_met'|'birthday'|'custom'`, `enabled: boolean`, `config: { threshold?, group?: Group, message? }`, `coachId`, `createdAt`, `updatedAt`.
**Touched by:** client CRUD `notificationRules.ts:39–62`; evaluated by CF `evaluateNotificationRules.ts:89–100` (only `attendance_streak` + `missed_practice` are live).

### `import_jobs`
**Shape** (`src/types/firestore.types.ts:449–466`; `importJobs.ts:18–50`): `type: 'csv_roster'|'sdif'|'hy3'|'cl2'`, `fileName`, `storagePath`, `status: 'processing'|'complete'|'failed'`, `errorMessage?`, `summary: { recordsProcessed, swimmersCreated, swimmersUpdated, timesImported, errors[] }`, `coachId`, `createdAt`, `updatedAt?`.
**Touched by:** `importJobs.ts:18,33,45`; `csvImport.ts:134,222` (→ writes `swimmers`); `meetResultsImport.ts:73,205` (→ writes `swimmers/{id}/times`, patches `meets/{id}/entries`).
**Import targets:** CSV roster → `swimmers`; HY3/SDIF results → `swimmers/{id}/times` (matched to roster by `usaSwimmingId`, else case-insensitive name) + optional `meets/{id}/entries` patch.

### `aggregations` — **CF-write only, client read-only**
**Shape varies by doc id** (`functions/src/triggers/*`, `src/types/firestore.types.ts:123–163`):
- `attendance_{swimmerId}`: `totalPractices`, `last30Days`, `last90Days`, `attendancePercent30/90`, `lastPracticeDate`, `updatedAt`.
- `swimmer_{swimmerId}`: `prsByEvent: Record<'event_course', {time, timeDisplay, date}>`, `noteCount`, `lastNoteDate?`, `updatedAt`.
- `dashboard_attendance`: `countsByDate: Record<date, number>` (84-day), `updatedAt`.
- `dashboard_activity`: `items: {id,type,text,coach,timestamp}[]` (≤15), `updatedAt`.
**Touched by:** read in `aggregations.ts`; written by triggers `onAttendanceWritten`, `onTimesWritten`, `onNotesWritten`, `dashboardAggregations`, and scheduled `rebuildAggregations` (4 AM).

### Declared-but-unimplemented ⚠
- `messages` (`src/types/firestore.types.ts:295–303`): type only, **no collection code**.
- `coach_chat` (`firestore.rules:181–183`): rules only, **no type/service**.
- `workout_library` (`firestore.rules:186–188`): rules only; superseded by `practice_plans` templates.

---

## §2 BSPC Postgres tables — columns, types, FKs, CHECK constraints

> All ids `UUID PK DEFAULT gen_random_uuid()`. All have RLS enabled (L360–381). `auth.users` is Supabase's built-in. Timestamps `TIMESTAMPTZ DEFAULT NOW()`.

**Enums** (L13–16): `user_role {family, coach_admin, super_admin}`; `account_status {pending, approved, deactivated}`; `urgency_level {urgent, normal, fyi}`; `attendance_status {present, absent}`.

| Table | Columns (type) | FKs | CHECK / UNIQUE |
|---|---|---|---|
| **families** (L23) | `name`, `created_at`, `updated_at` | — | — |
| **profiles** (L31) | `user_id` (UUID, **UNIQUE**), `email`, `full_name`, `role` (user_role, dflt family), `account_status` (dflt pending), `family_id`, `push_enabled` (bool), `deck_mode` (bool) | `user_id`→auth.users (CASCADE), `family_id`→families (SET NULL) | `user_id` UNIQUE |
| **swimmers** (L46) | `family_id` (**NOT NULL**), `first_name`, `last_name`, `practice_group`, `date_of_birth` (DATE), `is_active` (bool) | `family_id`→families (CASCADE) | `practice_group IN (Diamond, Platinum, Advanced, Gold, Silver, Bronze, Swim Lessons)` (L51) |
| **schedule_events** (L59) | `practice_group`, `title`, `start_time`/`end_time` (TIMESTAMPTZ), `location` (dflt 'Blue Springs Aquatic Center'), `is_cancelled` (bool), `cancellation_reason`, `notes` | — | `practice_group IN (…7 groups…)` |
| **raw_schedule_snapshots** (L74) | `raw_html`, `source_url`, `scraped_at`, `is_valid` | — | — |
| **imported_schedule_events** (L83) | `snapshot_id`, `practice_group`, `title`, `start_time`/`end_time`, `location` | `snapshot_id`→raw_schedule_snapshots (CASCADE) | — |
| **schedule_overrides** (L95) | nullable mirror of schedule_event fields, `created_by` | `schedule_event_id`→schedule_events (CASCADE), `created_by`→auth.users | — |
| **schedule_change_log** (L111) | `change_type`, `change_summary`, `previous_data`/`new_data` (JSONB) | `schedule_event_id`→schedule_events (SET NULL) | `change_type IN (created, updated, cancelled, restored)` |
| **announcements** (L122) | `title`, `body`, `urgency` (urgency_level), `target_group`, `is_pinned`, `expires_at`, `created_by` | `created_by`→auth.users | `target_group IS NULL OR IN (…7 groups…)` |
| **meets** (L136) | `name`, `location`, `address`, `start_date` (DATE), `end_date` (DATE), `warmup_time` (TIME), `event_start_time` (TIME), `what_to_bring`, `notes`, `commit_url` | — | — |
| **push_tokens** (L153) | `user_id`, `expo_push_token`, `platform`, `is_active` | `user_id`→auth.users (CASCADE) | `platform IN (ios, android)`; UNIQUE`(user_id, expo_push_token)` |
| **notification_preferences** (L164) | `user_id` (UNIQUE), `push_enabled` | `user_id`→auth.users (CASCADE) | `user_id` UNIQUE |
| **notification_jobs** (L172) | `title`, `body`, `deep_link`, `target_group`, `target_user_id`, `is_urgent`, `status`, `sent_at` | `target_user_id`→auth.users | `status IN (pending, sent, failed)` |
| **in_app_notifications** (L186) | `user_id`, `title`, `body`, `deep_link`, `is_read` | `user_id`→auth.users (CASCADE) | — |
| **swim_results** (L197) | `swimmer_id`, `event_name`, **`time_ms` (INTEGER)**, `meet_id`, `date` (DATE), `is_personal_best` | `swimmer_id`→swimmers (CASCADE), `meet_id`→meets (SET NULL) | — |
| **personal_bests** (L209) | `swimmer_id`, `event_name`, **`time_ms`**, `achieved_at` (DATE), `meet_id` | `swimmer_id`→swimmers (CASCADE), `meet_id`→meets (SET NULL) | UNIQUE`(swimmer_id, event_name)` |
| **team_records** (L220) | `event_name`, `time_ms`, `holder_name`, `year_set` (INT), `age_group`, `notes` | — | — |
| **hall_of_fame** (L232) | `swimmer_name`, `college`, `graduation_year` (INT), `notes` | — | — |
| **attendance** (L242) | `swimmer_id`, `schedule_event_id`, `status` (attendance_status), `marked_by` | `swimmer_id`→swimmers (CASCADE), `schedule_event_id`→schedule_events (**NOT NULL, CASCADE**), `marked_by`→auth.users | `status` enum {present, absent}; UNIQUE`(swimmer_id, schedule_event_id)` |
| **glossary_terms** (L253) | `term` (UNIQUE), `definition`, `category` | — | `term` UNIQUE |
| **time_standards** (L261) | `standard_name`, `event_name`, `age_group`, `gender`, `time_ms`, `course`, `season_year` (INT) | — | `gender IN (M, F)`; `course IN (SCY, SCM, LCM)` |
| **feedback** (L273) | `user_id`, `subject`, `body` | `user_id`→auth.users (CASCADE) | — |

**Triggers:** `update_updated_at()` on profiles/families/swimmers/schedule_events/announcements/meets (L325–330). `handle_new_user()` auto-inserts a `profiles` row (role=family, status=pending) on `auth.users` insert (L336–353).

---

## §3 Concept map — Coach collection ↔ Postgres table, with exact disagreements

Legend: 🟢 mostly aligned · 🟡 same concept, shape differs · 🔴 hard conflict (a decision must be made) · ⚪ exists in one app only (see §4).

### 3.1 Identity & people 🔴
| Concept | Coach App | Postgres | Where they DISAGREE |
|---|---|---|---|
| Coach/admin user | `coaches` (doc id=uid; `role: admin\|coach`; `groups[]`; `fcmTokens[]`; `notificationPrefs{}`) | `profiles` (`role: family\|coach_admin\|super_admin`; `account_status`; `family_id`; `push_enabled`/`deck_mode`) | **Two role enums** (`admin/coach` vs `family/coach_admin/super_admin`). Coach app keeps coaches and parents in **separate** collections; Postgres puts everyone in `profiles`. Doc-id-=-uid vs surrogate `id` + `user_id` FK. `coaches.groups[]` (a coach's owned groups) has **no Postgres column**. `account_status`/`deck_mode` have **no Coach field**. |
| Parent user | `parents` (doc id=uid; `linkedSwimmerIds: string[]`) — CF-written | `profiles` where `role='family'`, joined to `families`, swimmers via `swimmers.family_id` | **Parent→swimmer is an array** on the parent doc (Coach) vs **FK chain** `profile.family_id → families ← swimmers.family_id` (Postgres). Coach has **no `families` grouping**; one parent doc directly owns N swimmer ids. |
| Family unit | *(none — no family entity)* | `families` table | ⚪ Postgres-only grouping layer. |

### 3.2 Swimmer / roster 🟡
| Field (Coach `swimmers`) | Field (Postgres `swimmers`) | Disagreement |
|---|---|---|
| `firstName`, `lastName`, `displayName` | `first_name`, `last_name` | casing; **no `displayName`** in Postgres |
| `group: Group` | `practice_group` (CHECK 7 vals) | name differs; **enum value conflict — see 3.8** |
| `active` | `is_active` | name only |
| `dateOfBirth: Timestamp` | `date_of_birth: DATE` | type (Timestamp vs DATE) |
| `gender: 'M'\|'F'` | *(absent)* | ⚪ Coach-only |
| `usaSwimmingId?` | *(absent)* | ⚪ Coach-only (also the import match key) |
| `profilePhotoUrl?` | *(absent)* | ⚪ Coach-only |
| `strengths[]`, `weaknesses[]`, `techniqueFocusAreas[]` | *(absent)* | ⚪ Coach-only coaching profile |
| `mediaConsent{}`, `doNotPhotograph?` | *(absent)* | ⚪ Coach-only (COPPA/SafeSport gate) |
| `parentContacts[]`, `meetSchedule[]`, `goals[]` | *(absent)* | ⚪ Coach-only denormalized arrays |
| `createdBy` (coach uid) | *(absent)* | ⚪ Coach-only |
| *(linked via `parents.linkedSwimmerIds`)* | `family_id` **NOT NULL** FK | 🔴 **Coach swimmers have no family link**; Postgres **requires** one. Migration must synthesize families/links. |

### 3.3 Swim times & PRs 🔴
| Concept | Coach `swimmers/{id}/times` | Postgres `swim_results` + `personal_bests` | Disagreement |
|---|---|---|---|
| Time value | `time: number` **hundredths of a second** | `time_ms: INTEGER` **milliseconds** | 🔴 **UNIT MISMATCH** (×10). Coach README mandates hundredths; Postgres stores ms. One must change. |
| Event | `event` (e.g. "100 Free", `EVENTS` enum) | `event_name` (free text) | enum vs free text; name casing |
| Course | `course: SCY\|SCM\|LCM` | *(absent on results)* | ⚪ Coach-only on results (Postgres only has course on `time_standards`) |
| Meet ref | `meetName?` (string) + `meetDate?` | `meet_id` FK → meets | 🟡 denormalized string vs FK |
| PR | `isPR: boolean` flag on each time | separate `personal_bests` table (UNIQUE per swimmer+event) | 🟡 flag-per-row vs dedicated table |
| Splits, `timeDisplay`, `source` | present | *(absent)* | ⚪ Coach-only |

### 3.4 Attendance 🔴
| Concept | Coach `attendance` | Postgres `attendance` | Disagreement |
|---|---|---|---|
| Key | `(swimmerId, practiceDate string)` | `(swimmer_id, schedule_event_id)` UNIQUE | 🔴 **Coach has no `schedule_event_id`**; keyed by a date string. Postgres requires a schedule-row FK (NOT NULL). |
| Status | `'normal'\|'excused'\|'sick'\|'injured'\|'left_early'` (optional) | `present\|absent` enum (required) | 🔴 5-value vs binary |
| Timestamps | `arrivedAt`, `departedAt` (check-in/out) | *(none)* | ⚪ Coach-only |
| Denormalized | `swimmerName`, `group`, `coachName`, `note` | *(none; FK-normalized)* | shape |
| `marked_by` | `markedBy` (coach uid) | `marked_by`→auth.users | 🟢 aligns |

### 3.5 Meets 🔴 (same name, near-disjoint purpose)
| Concept | Coach `meets` (+entries) | Postgres `meets` | Disagreement |
|---|---|---|---|
| Purpose | **competition management** | **parent info card** | 🔴 different entities sharing a name |
| Shared | `name`, `location`, dates | `name`, `location`, `start_date`/`end_date` | `startDate` string vs `start_date` DATE |
| Coach-only | `course`, `status` (MeetStatus), `events[]`, `groups[]`, `sanctionNumber`, `hostTeam`, `coachId`; `entries`/`relays` subcollections | — | ⚪ |
| Postgres-only | `address`, `warmup_time`, `event_start_time`, `what_to_bring`, `commit_url` | — | ⚪ |
| Entries | `meets/{id}/entries` (psych-sheet rows w/ seed/final times) | *(loosely `swim_results.meet_id`)* | 🔴 no real counterpart |

### 3.6 Practice schedule / calendar 🔴
| Concept | Coach `calendar_events` (+rsvps) | Postgres `schedule_events` (+ scrape pipeline) | Disagreement |
|---|---|---|---|
| Origin | coach-authored events, `recurring{}` rules | **scrape → import → override → effective + change_log** | 🔴 two different scheduling philosophies |
| Grouping | `groups: Group[]` (multi, empty=all) | one `practice_group` per row | 🟡 array vs single |
| Time | `startDate`+`startTime` ('HH:MM' strings) | `start_time`/`end_time` TIMESTAMPTZ | 🟡 split strings vs timestamptz |
| Type | `type: practice\|meet\|team_event\|fundraiser\|social` | *(implicitly all practices)* | ⚪ Coach-only |
| Cancellation | *(via recurring/edit)* | `is_cancelled` + `cancellation_reason` + change_log | ⚪ Postgres-only pipeline |
| RSVPs | `calendar_events/{id}/rsvps` | *(none)* | ⚪ Coach-only |

### 3.7 Notifications 🟡
| Concept | Coach App | Postgres | Disagreement |
|---|---|---|---|
| Push token | `coaches.fcmTokens[]` (FCM, array on user doc) | `push_tokens` rows (`expo_push_token`, `platform`) | 🔴 **FCM vs Expo**, array-field vs table |
| In-app feed | `notifications` (CF-written; `read`; `type` enum) | `in_app_notifications` (`is_read`; `deep_link`) | 🟡 `read`/`is_read`; different `type` model |
| Prefs | `coaches.notificationPrefs{4 bools}` | `notification_preferences.push_enabled` + `profiles.push_enabled` | 🟡 granular vs single toggle |
| Queue/dispatch | *(CF triggers + daily digest)* | `notification_jobs` (pipeline queue) | 🟡 different dispatch model |
| Rule engine | `notification_rules` + `evaluateNotificationRules` | *(none)* | ⚪ Coach-only |

### 3.8 Shared enum conflicts 🔴
| Enum | Coach App (`src/config/constants.ts`) | Postgres | Conflict |
|---|---|---|---|
| **Practice groups** | `Bronze, Silver, Gold, Advanced, Platinum, Diamond, Masters` (L1–9) | `Diamond, Platinum, Advanced, Gold, Silver, Bronze, Swim Lessons` (CHECK) | 🔴 **7 each, but differ on the 7th: `Masters` (Coach) vs `Swim Lessons` (Postgres).** Canonical set needs both ⇒ likely 8 groups. |
| Course | `SCY, SCM, LCM` | `SCY, SCM, LCM` (time_standards) | 🟢 match |
| Gender | `'M' \| 'F'` | `M, F` (time_standards) | 🟢 match (but swimmers table lacks gender) |
| Standard level | `B, BB, A, AA, AAA, AAAA` enum | `time_standards.standard_name` **free text** | 🟡 enum vs free text |
| Age group | `10&U, 11-12, 13-14, 15-16, 17-18` | `time_standards.age_group`/`team_records.age_group` free text | 🟡 enum vs free text |

### 3.9 Date/time & style conventions 🟡
- **Dates:** Coach uses Firestore `Timestamp` + `YYYY-MM-DD` strings; Postgres uses `TIMESTAMPTZ` / `DATE` / `TIME`. Every date field needs a conversion rule.
- **Denormalization:** Coach docs copy `swimmerName`/`coachName`/`timeDisplay` inline; Postgres is FK-normalized. Canonical schema should normalize and let the app project display fields.
- **Ownership:** Coach scopes many docs by `coachId`; Postgres scopes by RLS over `profiles.role`. The coach-ownership semantics (e.g. private practice plans) must map onto RLS policies.

---

## §4 Concepts that exist in only ONE app

**Postgres (BSPC) only — parent-facing & ops:**
- `families` (grouping layer) · `announcements` (urgency/target_group/pinned) · `glossary_terms` · `time_standards` (reference table) · `team_records` · `hall_of_fame` · `feedback`.
- **Schedule scrape pipeline** (4 tables): `raw_schedule_snapshots`, `imported_schedule_events`, `schedule_overrides`, `schedule_change_log`.
- `account_status` state machine (pending/approved/deactivated) · `deck_mode` flag · Commit integration (`meets.commit_url`) · Expo push tokens.

**Coach App only — coaching write-side:**
- Coaching profile on swimmer: `gender`, `usaSwimmingId`, `profilePhotoUrl`, `strengths`, `weaknesses`, `techniqueFocusAreas`, `mediaConsent`, `doNotPhotograph`, `parentContacts`.
- `swimmers/{id}/notes` + `group_notes` (coaching notes — **note: BSPC's `CLAUDE.md` explicitly lists "Coach notes (individual swimmer)" as removed**).
- `swimmers/{id}/goals` (target standards/times).
- `swimmers/{id}/voice_notes`; `audio_sessions`(+drafts); `video_sessions`(+drafts); AI-draft review workflow + consent gate (**BSPC explicitly removed photo/video**).
- `practice_plans` (+ dashboard PDFs); `season_plans`(+weeks); `workout_library` enum (**BSPC removed coach-managed workouts & season planning**).
- `meets/{id}/entries` (+unused relays/live_events/splits); meet `status`/`events[]`/`sanctionNumber`.
- `calendar_events` typing + `recurring` + `rsvps`.
- `notification_rules` + rule engine; `aggregations` (CF-precomputed); `import_jobs` + CSV/HY3/SDIF importers.
- `parent_invites` invite flow; `parents` collection; `coaches.groups[]` coach-group ownership; `swimmers/{id}/medical` (declared).
- Declared-unused: `messages`, `coach_chat`, `workout_library`.

> ⚠ **Scope flag for review:** several Coach-App concepts (individual coach notes, coach-managed workouts, season planning, photo/video) are on BSPC's *explicitly-removed* list (`BSPC/CLAUDE.md` "What's Explicitly Removed"). The canonical schema can still **host** this data for the Coach App without the **parent app** surfacing it — but we should confirm that's the intent (host-but-don't-expose) rather than accidentally reviving removed parent features.

---

## §5 The Next.js parent-portal and its overlap with the BSPC parent app

**What it is** (`BSPC-Coach-App/parent-portal/`): Next.js 15 + React 19, Firebase Auth (email/password). It talks to the backend **only through Cloud Functions callables** (`functions/src/callable/parentPortal.ts`, `redeemInvite.ts`) — no direct Firestore reads — and parent identity lives in the `parents` collection.

**Routes/features:**
- `/` — login/signup + invite-code redemption (`parent-portal/src/app/page.tsx`).
- `/dashboard` — linked-swimmer cards + invite redemption (`.../dashboard/page.tsx`).
- `/swimmer/[id]` — three tabs (`.../swimmer/[id]/page.tsx`): **Overview** (PR count, strengths, goals), **Times** (table w/ PR badges), **Attendance** (28-day grid).

**Data access (all via callables):**
- `getParentPortalDashboard()` → parent profile + linked-swimmer summaries (`parentPortal.ts:161–173`).
- `getParentSwimmerPortalData(swimmerId)` → one swimmer + 50 newest times + 30 newest attendance + **empty `schedule: []`** (`parentPortal.ts:175–220`); enforces `swimmerId ∈ parent.linkedSwimmerIds` (`:188–190`) and strips coach-private fields (`:84–127`).
- `redeemInvite(code)` → links swimmer to parent (`redeemInvite.ts:4–86`).

**Overlap with the standalone BSPC parent app:**

| Parent-facing feature | Coach-App parent-portal | BSPC parent app | Notes |
|---|---|---|---|
| Today dashboard | ✗ | ✓ | portal shows swimmer cards, not a daily "what's next" |
| Schedule / practice times | ✗ (stubbed `schedule: []`) | ✓ | portal reserves the type but returns nothing |
| Swim times / results | ✓ | ✓ | both show times; portal reads Firestore, BSPC reads Postgres |
| Attendance view | ✓ (28-day grid) | ✓ | overlap |
| Personal records | ✓ | ✓ (`personal_bests`) | overlap |
| Strengths / goals | ✓ | ✗ | portal surfaces coach-side profile |
| Meets directory | ✗ | ✓ | portal only shows meet name on a time row |
| Announcements | ✗ | ✓ | — |
| Commit Swimming link | ✗ | ✓ | — |
| Glossary / standards / records / hall-of-fame | ✗ | ✓ | — |
| Invite-code signup | ✓ | ✗ (open signup + admin approval) | 🔴 **two different parent-onboarding models** |

**Verdict:** The parent-portal is a **thin, read-only subset** of the BSPC parent app's surface (times + attendance + PRs + goals), fed from Coach-App Firestore via callables, with **no schedule, meets, announcements, or Commit**. The BSPC parent app is the richer, canonical parent experience. Two strategic implications for the canonical schema:
1. **Parent-onboarding conflict:** portal uses invite codes (`parent_invites` → `parents.linkedSwimmerIds`); BSPC uses open signup + admin approval (`account_status` + `families` + admin-linked swimmers). The canonical model must pick one (or support both) parent→swimmer linkage path.
2. **Surface consolidation (decision, not schema):** once both apps read one Postgres backend, the portal can either be **retired** in favor of the BSPC parent app, or **rebuilt against canonical Postgres + RLS (family role)**. This is a product call to confirm before we design the parent-facing RLS.

---

## §6 Cross-cutting conflicts to ratify before `01_CANONICAL_SCHEMA.sql`

These are the decisions the canonical schema bakes in. **Per the project rules, I'm surfacing the tradeoffs rather than guessing.** Recommendations are starting points, not commitments.

1. **Time units (🔴 blocking).** Hundredths-of-a-second (Coach, ~all logic + README invariant + tests) vs `time_ms` milliseconds (Postgres). → *Lean: canonicalize on hundredths and migrate the 3 Postgres `time_ms` columns, because the Coach App has far more time-handling logic + tests that assume hundredths.* Need your call.
2. **Practice-group enum (🔴 blocking).** Need a single set. Union = `Diamond, Platinum, Advanced, Gold, Silver, Bronze, Swim Lessons, Masters` (8). → *Lean: 8-value union.* Confirm whether `Masters` and `Swim Lessons` should truly coexist.
3. **Identity model (🔴 blocking).** Collapse `coaches` + `parents` into one `profiles`-style table with the `family/coach_admin/super_admin` role enum, mapping Coach `admin→super_admin?` / `coach→coach_admin`. Keep `coaches.groups[]` as a new join (coach↔group). Confirm role mapping.
4. **Parent ↔ swimmer linkage (🔴 blocking).** `families` + `swimmers.family_id` (Postgres) vs `parents.linkedSwimmerIds[]` (Coach). → *Lean: keep the relational `families` model; migration synthesizes a family per parent-invite link.* This also decides #1 in §5.
5. **Attendance model (🔴 blocking).** Reconcile date-keyed check-in/out + 5-value status (Coach) with schedule-event-linked binary present/absent (Postgres). → *Lean: make `schedule_event_id` nullable and add `practice_date`, `arrived_at`, `departed_at`, and a widened status enum; keep present/absent as a derived/compatible subset for the parent app.*
6. **Meets (🔴).** One superset `meets` table (parent-info columns + competition columns + nullable `status`/`course`) vs splitting into `meets` (info) + `meet_events`/`meet_entries`. → *Lean: one `meets` superset + `meet_entries` child table.*
7. **Schedule (🟡).** Keep BSPC's scrape pipeline as canonical, and fold Coach `calendar_events` in as either (a) additional event `type`s on a unified events table, or (b) a separate `calendar_events` table alongside `schedule_events`. Affects RSVPs.
8. **Push (🟡).** Expo vs FCM tokens — both clients are Expo/RN, so → *Lean: standardize on Expo push + `push_tokens`; drop `coaches.fcmTokens[]`.* Confirm the Coach App can move to Expo push.
9. **Host-but-don't-expose (scope).** Confirm the canonical schema should host Coach-only data (notes/goals/media/plans) that BSPC deliberately removed from the **parent** surface — i.e. it lives in the DB for the coach app, gated from parents by RLS. (See §4 flag.)
10. **Standards/age-group enums (🟡).** Promote `StandardLevel`/`AgeGroup` to enums or keep `time_standards` free-text. → *Lean: keep free-text columns, validate in app.*

**Recommended next artifact:** once you ratify §6, I'll draft `UNIFY/01_CANONICAL_SCHEMA.sql` as *BSPC's schema, extended* — additive coach-side tables + the reconciled core (identity, swimmers, times, attendance, meets) — with a companion migration-mapping note. No app code changes until the schema is law and both test suites have a green baseline.
> ⚠️ HISTORICAL — superseded by the fresh-launch model in Director Rulings 56/57; retain as design evidence, not executable migration instructions.
