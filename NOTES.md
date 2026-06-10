# UNIFY — NOTES

Running log of tradeoffs/decisions made while drafting, per the project rule
"write the tradeoff here and ask rather than guess." Each item is tagged so you
can scan: **[DECIDE]** = wants your call · **[FYI]** = choice made, flagging it ·
**[FOLLOWUP]** = deferred work (not in the schema DDL).

---

## Implementation notes from `01_CANONICAL_SCHEMA.sql` (drafted 2026-05-30)

These are downstream consequences of the ratified §6 decisions, plus modeling
calls the ratification didn't spell out.

### Constraint changes beyond the literal §6 text
- **[FYI] `swimmers.family_id` relaxed to NULLABLE** (decision #4). Required so the
  coach roster can exist before any parent is linked. Parent RLS is unaffected —
  a NULL `family_id` simply never matches `is_my_swimmer()`, so unlinked swimmers
  stay invisible to families and visible to staff. This is a real loosening of a
  BSPC `NOT NULL`; calling it out explicitly.
- **[SETTLED #1] Attendance uniqueness = `UNIQUE NULLS NOT DISTINCT
  (swimmer_id, practice_date, schedule_event_id)`** (PG15+). Kevin confirmed the
  team runs two-a-days (Diamond/Platinum/Advanced, AM+PM same date). Distinct
  non-NULL `schedule_event_id`s allow multiple rows per day; the Coach App's NULL
  `schedule_event_id` collides under NULLS NOT DISTINCT, preserving its
  one-per-day behavior. **VERIFIED green:** the Coach App attendance tests
  (`src/services/__tests__/attendance.test.ts`,
  `test/critical-ops/attendance.criticalOp.test.ts`) mock `firebase/firestore`
  and assert only on write-payload shape + batch call-counts; none create two
  same-day rows for one swimmer, so the DB key can't break them. See the adapter
  caveat under FOLLOWUP.
- **[SETTLED #2] `in_app_notifications` now has
  `UNIQUE(rule_id, swimmer_id, source_eval_date)`** so a rule firing twice doesn't
  double-notify (replaces the Coach App's deterministic id). Non-rule
  notifications (NULL `rule_id`) stay distinct under default NULL handling.
  Writers must upsert ON CONFLICT (FOLLOWUP).

### Modeling choices
- **[FYI] Nested structures stored as JSONB**, not shredded into child tables:
  `practice_plans.sets` (sets→items), `season_plans.phases`, `meets.events`,
  `practice_plans.ratings`, `swimmer_coach_profile.parent_contacts`,
  `calendar_events.recurring`, `aggregations.payload`. Faithful to the Firestore
  docs and avoids 3-level join explosions, but these lose relational
  queryability/constraints. `meet_entries` and `season_plan_weeks` *are* real
  tables (they're queried/joined). The one most arguable is `practice_plans.sets`
  — flag if you'd rather have `practice_plan_sets` + `practice_plan_items`.
  **[SETTLED #4] Kept JSONB.**
- **[FYI] `swimmer_coach_profile` is staff-only**, so the parent portal's
  "strengths" surface is **not** served by the canonical schema yet (goals *are*,
  via a family-read policy). This follows your "parents stay on derived views /
  keep walls strict" steer. If you want parents to see strengths, we add a
  parent-safe view exposing only `strengths` (+ goals) — say the word.
  **[SETTLED #3] Kept staff-only.**
- **[FYI] `meet_entries` is staff-only** for now (parents can't see their child's
  heat/lane/seed). Not COPPA-sensitive, so easy to relax to family-read-own later
  if the parent app wants a meet psych-sheet.
- **[FYI] Media multi-selects kept as `UUID[]`** (`audio/video_sessions.*_swimmer_ids`)
  rather than join tables, matching the Firestore arrays. The per-swimmer FK lives
  on the `*_drafts` children, which is the link that actually matters. These tables
  are staff-only regardless, and the consent gate is enforced in app logic.
- **[FYI] Enums replaced BSPC's `TEXT CHECK`** for `practice_group`, `course`,
  `gender`, etc. Cleaner and self-documenting, but adding a future group/value
  needs `ALTER TYPE ... ADD VALUE`. (Current `practice_group` = the ratified 8.)
- **[FYI] RLS refactored to SECURITY DEFINER helpers** (`is_staff()`,
  `is_super_admin()`, `is_my_swimmer()`). Semantics match BSPC's inline `EXISTS`
  policies, and it also fixes BSPC's latent self-referential recursion risk on
  `profiles`. One-liner policies throughout.
- **[FYI] Mixed FK targets:** new coach-side tables reference `profiles(id)` for
  coach ownership; existing BSPC tables keep `auth.users(id)` for
  `created_by`/`marked_by`. Left existing columns alone to minimize churn to the
  parent app's tested behavior. Can standardize on `profiles(id)` if you prefer.

### Data backfill (NOT in this DDL — separate migration step)
- **[FOLLOWUP] Time-unit conversion (#1):** existing BSPC `time_ms` → `time_hundredths`
  is **divide by 10** (ms = hundredths × 10). Swim times are centisecond-precision
  so this is lossless, but the backfill script must do it; the DDL only renames/retypes.
- **[FOLLOWUP] Identity backfill (#3):** map Coach `coaches` docs → `profiles`
  (`admin→super_admin`, `coach→coach_admin`), `coaches.groups[]` → `coach_groups`,
  `coaches.notificationPrefs` → `notification_preferences`. Map `parents` docs +
  `linkedSwimmerIds[]` → synthesized `families` + `swimmers.family_id` (#4).
- **[FOLLOWUP] Aggregations:** the `aggregations` table is a read-model store; its
  population must move from Firestore Cloud Function triggers to Postgres
  triggers/scheduled jobs. Not written yet — design after the core tables land.
- **[FOLLOWUP] Attendance check-in adapter (open-decision #1 consequence):** the
  Coach App's `checkIn`/`batchCheckIn` are blind `addDoc`s with no dedup and write
  NO `schedule_event_id`. When their data layer is swapped to Postgres: (a) the
  adapter must use `ON CONFLICT` / catch the unique violation so a double tap stays
  "one record" (today Firestore silently allows a duplicate); and (b) the coach
  check-in flow must start passing a `schedule_event_id` before it can actually log
  AM vs PM separately — the schema supports two-a-days, the coach UI does not yet.
- **[FOLLOWUP] Notification writer upsert (#2):** the rule engine / digest writer
  must `INSERT ... ON CONFLICT (rule_id, swimmer_id, source_eval_date) DO UPDATE`,
  matching the Coach App's prior deterministic-id overwrite semantics.

### Confirmations to bank
- **[SETTLED #5] Omitted as dead/unimplemented:** `messages`, `coach_chat`,
  `workout_library`, and meet `relays`/`live_events`/`splits`. Kevin confirmed no
  near-term plan for messaging/chat or those meet subcollections — dropped.

---

## Open decisions — SETTLED 2026-05-30 (ratified by Kevin)
1. Attendance two-a-days — **AMEND**: key is now `UNIQUE NULLS NOT DISTINCT
   (swimmer_id, practice_date, schedule_event_id)` (PG15+). Coach App tests
   verified green; check-in adapter caveat tracked under FOLLOWUP.
2. Notification idempotency — **ADD** `UNIQUE(rule_id, swimmer_id, source_eval_date)`;
   writers upsert ON CONFLICT (FOLLOWUP).
3. `strengths` visibility — **KEEP** `swimmer_coach_profile` staff-only.
4. `practice_plans.sets` — **KEEP** JSONB.
5. Dead collections — **DROP** (messages, coach_chat, workout_library, meet
   relays/live_events/splits).

No open decisions remain. The schema's shape is settled and ready for review as "law."

---

## Red-team fixes applied — D-A, D-B, all batches (2026-05-30)

Applied to `01_CANONICAL_SCHEMA.sql` per `02_SCHEMA_REDTEAM.md`. Schema-only; not run.

### D-A — GUARDIANSHIPS model (replaces singular swimmers.family_id)
- New `guardianships(guardian_profile_id ↔ swimmer_id, relationship, is_primary)` is now the access primitive. `swimmers.family_id` is **removed**. `families`/`profiles.family_id` remain only as a guardian *household* grouping.
- `is_my_swimmer()` resolves via guardianships **and requires the guardian's `account_status = 'approved'`** — this centrally enforces BSPC's "pending parents get no swimmer-specific data" rule.
- `guardianships` writes are **staff-only / via the SECURITY DEFINER invite-redemption RPC**; a family user can never self-insert a link (would be a P0-1-class access grant). This is the COPPA wall's new hinge.
- Parent-app impact (APP migration): queries filtering swimmers by `family_id` and `approveFamily()` (which created a family + swimmers) must move to creating guardianship links. RLS already grants the equivalent access.

### D-B — attendance two-a-days via partial unique indexes + RESTRICT
- Removed `UNIQUE NULLS NOT DISTINCT` (and its **PG15 dependency**). Now: `attendance_day_key UNIQUE (swimmer_id, practice_date) WHERE schedule_event_id IS NULL` + `attendance_event_key UNIQUE (..., schedule_event_id) WHERE schedule_event_id IS NOT NULL`; `schedule_event_id ON DELETE RESTRICT`.
- **Coach App attendance tests re-confirmed green:** they mock `firebase/firestore` and assert on write-payload shape + batch call-counts only; they never touch DB uniqueness, and the NULL-event partial index preserves one-row-per-day for Coach App writes.

### Judgment calls made during the fix (flagging for your awareness)
- **`is_active_account()` instead of the red-team's `is_approved()` (P1-8).** BSPC explicitly grants *pending* parents limited access (announcements + schedule) — gating those behind `is_approved()` would regress that. So team-wide reads (schedule, calendar, meets, announcements team-wide, reference tables) use `is_active_account()` = *not deactivated* (pending allowed, deactivated blocked). Swimmer-specific data still requires `approved` via `is_my_swimmer()`. Net: stricter than before for deactivated, unchanged for pending, correct for approved.
- **Actor-ref standardization.** `created_by` / `marked_by` / `reviewed_by` / `coach_id` now all reference `profiles(id)` (was a mix of `auth.users`/`profiles`). Removes the P0-8 dual-remap landmine. Per-user own-row tables (`push_tokens`, `notification_preferences`, `in_app_notifications`, `feedback`) keep `user_id → auth.users(id)` because their RLS is `user_id = auth.uid()`.
- **`personal_bests.course` made NOT NULL** (P1-13) so `(swimmer, event, course)` dedups cleanly — backfill must assign a course to legacy BSPC PBs (likely `'SCY'`).
- **Media multi-selects normalized** (P1-4): `audio_session_swimmers` and `video_session_swimmers(kind)` junctions replace the `UUID[]` arrays; `kind='tagged'` is the consent-gated set with FK integrity (no stale swimmer ids).
- **SQL ordering fix (apply-time correctness):** SECURITY DEFINER helpers + `attendance_parent_view` are defined AFTER their tables (else `check_function_bodies` rejects them); the note↔draft and `in_app_notifications.rule_id` FKs are added in a deferred `ALTER` section to break create-order cycles.

### Deferred P2s (with reason)
- **P2-1 / P2-2** (parent sees own-child `media_consent`/`created_by`; `coach_id` on meets/calendar): RLS can't hide columns — resolve via **parent-facing VIEWS** in the APP migration.
- **P2-5** aggregations recompute, **P2-8** enum hygiene, **P2-9** recurring-event expansion, **P2-10** `ratings` JSONB key rewrite, **P2-6** name/location relaxation (partially done — `swimmers.last_name` now nullable): **BACKFILL / APP**.
- **P2-11** `template_source_id` cycle guard: low priority, deferred.

### Backfill FOLLOWUPs (updated; still a separate deliverable — NOT in the DDL)
- **Guardianships:** map each Coach `parents.linkedSwimmerIds[]` to direct `guardianships(redeemer_profile, swimmer)` rows (the union-find from the red-team is now unnecessary — N:M is native). Roster-reconcile Coach swimmers to existing BSPC swimmers (usa_swimming_id/name+DOB) to avoid duplicate swimmer rows.
- **Identity:** disable `on_auth_user_created` during backfill (else it inserts conflicting `family/pending` profiles); build the Firebase-UID → `profiles.id` remap (single target now, since actor refs are standardized on profiles); remap ids inside arrays/JSONB (`practice_plan_ids`, `ratings` keys, `meets.events`) and the new junction tables.
- **Times:** ÷10 audit (`time_ms % 10`) per-source before merge; assign `personal_bests.course` for legacy rows.
- **Attendance:** dedup historical Firestore duplicate same-day rows before load (RESTRICT/partial keys will reject dups); map `status` null/`'normal'` → `'present'`.
- **Aggregations:** do NOT migrate; recompute via Postgres triggers/jobs (unbuilt).
- **Notes/drafts:** two-pass load for the `source_*`/`posted_note_id` cross-pointers.

---

## Phase A transitional divergence — `swimmers.family_id` (OD-1, ratified 2026-06-08)

**[FYI] The live BSPC DB intentionally diverges from canonical during Phase A.**
Kevin ratified the **transitional** strategy (OD-1): Phase A adds `guardianships`,
the SECURITY DEFINER RLS helpers, `coach_groups`, and the `enforce_profile_self_update`
guard **alongside** the existing `swimmers.family_id` model
(`BSPC/ACTIVE/supabase/migrations/00002_phase_a_identity.sql`, additive only —
nothing altered/dropped). Existing `family_id`-based RLS keeps working.

Canonical (`01_CANONICAL_SCHEMA.sql`) has `swimmers.family_id` **removed**; the live
DB keeps it for now. This is a deliberate, time-boxed divergence.

- **[FOLLOWUP] Planned convergence step (post–Phase A code-side work, before/with the
  cutover):** (1) backfill `guardianships` from `swimmers.family_id`; (2) switch BSPC
  reads (`fetchFamilySwimmers`, `approveFamily`) and RLS policies from `family_id` to
  `is_my_swimmer()`/guardianships; (3) update the `family_id`-based pgTAP tests; (4)
  a final migration **drops `swimmers.family_id`**. Only after (1)–(4) does the live
  DB match canonical on this point.
- Other ratified Phase A decisions: **OD-3** new accounts require approval (BSPC's
  gated provisioning wins; no auto-approve). **NM-5** auto-admin-on-first-login is
  removed. **NM-1** super_admin assigned deliberately (Kevin = super_admin; remaining
  Coach "admins" → `coach_admin` — the live list must be pulled from the `coaches`
  collection at backfill time for Kevin to confirm; not derivable from code).
  **OD-6** password cutover = aim for Firebase→Supabase import, forced-reset fallback,
  decided at cutover with a dry-run (does not block code-side work) — **superseded
  2026-06-09: SETTLED as NO import, see below**. **OD-2**/**OD-4**:
  safe handling chosen — dailyDigest deferred whole to Phase G; redeemInvite stays
  Phase I with A→I run back-to-back (revisit at I).

### Pre-existing 00001 profiles RLS recursion — FOUND & FIXED (2026-06-08)
- **[FIXED] Latent infinite recursion in BSPC `profiles` RLS.** `00001`'s
  `profiles_select_admin` / `profiles_update_admin` used a self-referential
  `EXISTS (SELECT 1 FROM profiles ...)`, which raises *"infinite recursion detected
  in policy for relation profiles"* on ANY authenticated read touching `profiles`
  (directly or via another table's policy subquery — swimmers, announcements, etc.).
  Discovered the first time pgTAP ran on real Postgres (4 of 5 RLS files failed;
  baseline 00001-only failed identically → pre-existing, not caused by Phase A).
  Exactly the "latent self-referential recursion risk on profiles" canonical NOTES
  flagged. **Fixed in `00002_phase_a_identity.sql`** by rewriting ONLY those two
  policies to the SECURITY DEFINER `is_staff()` helper (RLS-bypassing, recursion-
  free, semantically identical). Verified: all 5 pgTAP files, 31 tests PASS. The
  remaining inline `EXISTS`-on-profiles admin policies are deferred to the
  convergence sweep (NOT done now). **Open: Kevin is checking whether the deployed
  prod DB actually has this recursion or diverges from repo `00001`.**
- **[PROCESS] BSPC "green" now means BOTH jest AND pgTAP.** The "774 green" baseline
  was **jest-only**, and jest **mocks Supabase** — so RLS bugs (like the recursion
  above) are invisible to it and only surface under pgTAP (`npm run test:rls`, needs
  Docker/colima + local Supabase). Going forward, a BSPC change is not "green" until
  **both** the jest suite (774+) **and** the pgTAP suite (31+) pass. (Coach App +
  functions remain jest-only — no DB/RLS layer of their own.)

### [SETTLED 2026-06-09] AuthContext migration can't be partial — `coach.uid` semantics (raised 2026-06-08)
Discovered while starting code-side commit 2 (Coach `AuthContext` → Supabase):
- **The auth-provider swap and the identity-doc read are INSEPARABLE.** `profiles`
  has **no `firebase_uid` column** (canonical keys identity on `auth.users.id`).
  So you cannot read a coach's Supabase `profiles` row while the session is still
  Firebase Auth (a Firebase UID matches no `profiles.user_id`). Migrating the
  identity read therefore *requires* moving the session to Supabase Auth too.
- **Blast radius:** 36 files call `useAuth()`. Most read `coach` (the `Coach`
  object); ~15 use **`coach.uid` as a Firestore write-key** — `attendance.markedBy`,
  video/audio `coachId`, `import`, notification-rules, etc. Several are
  COPPA-relevant (attendance presence, media ownership).
- **Consequence:** the moment `AuthContext` resolves identity from Supabase,
  `coach.uid` changes meaning from *Firebase UID* → *Supabase UUID* (profiles.id or
  user_id) for every downstream writer — while those writers still target Firestore
  until their own phases. jest stays green (mocks), but it commits us to cutting the
  identity cluster over together (matches 04's "identity cluster moves as one").
- **Options:**
  (a) **Migrate AuthContext now (code-first), `coach.uid` := profiles.id**, accept
      the half-state until the coordinated cutover; downstream services keep their
      mocked tests green and adopt the UUID at their phases. Most aligned with the
      plan + 04, but it's the riskiest single change and touches COPPA flows.
  (b) **Defer AuthContext to the coordinated identity cutover step** and do the
      lower-risk code-side identity work first (parent-portal `auth.ts`, the
      `parentPortal` function identity gate, backfill scaffolding), so the auth
      provider flips as part of the cluster, not in isolation.
  (c) **Add a transitional `profiles.firebase_uid` column** (a schema migration) so
      the identity read can be resolved during a Firebase-session window without a
      full provider swap — smaller immediate blast radius, but adds a transient
      column to canonical-track and a dual-key period.
- **Recommendation: (b)** — defer the AuthContext provider swap to the cluster
  cutover; do parent-portal/auth.ts + parentPortal-gate + backfill scaffolding now
  (all keep three suites + pgTAP green with small blast radius). Revisit (a) vs (c)
  when we stage the identity cutover. **SETTLED 2026-06-09 — Kevin ratified Option (b):** the AuthContext provider swap is DEFERRED to the coordinated identity-cluster cutover. Proceeding now with the lower-risk code-side identity work: parent-portal `auth.ts`, the `parentPortal` function identity gate, and the backfill scaffolding (`migration_identity_map` + pure mapping unit tests).

### Phase A Option (b) code-side work — LANDED 2026-06-09 (same session)
All three ratified pieces committed, every suite green:
1. **parent-portal `auth.ts`** — profile read split into `lib/profile.ts`, resolving
   `profiles` by `user_id` + deriving `linkedSwimmerIds` from `guardianships` via a
   new portal Supabase client (`NEXT_PUBLIC_SUPABASE_URL`/`_ANON_KEY`, placeholder-safe).
   `auth.ts` re-exports the frozen `ParentProfile`; the Firebase session provider is
   untouched pending cutover. Coach suite 968→973. (Coach `b642056`)
2. **`parentPortal` callable identity gate** — new `functions/src/identity.ts`
   `resolveParentIdentity` via service-role client (`SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`);
   the Firestore `parents/{uid}` read is gone; data payloads stay on Firestore until
   B/C/D. All four behavioral assertions preserved verbatim. Functions 106→109. (Coach `2805bda`)
3. **Backfill scaffolding** — `BSPC/ACTIVE/migration/identity/`: transient
   `migration_identity_map` DDL (§3.2; deliberately NOT in `supabase/migrations/`),
   pure mapping fns (role map #3, NM-4 placeholder carry, NM-6 dangling drop+report)
   + §9 audits, README with the staged cutover run order. Provisioning runner
   deferred on OD-6. BSPC jest 774→792, pgTAP 31/31. (BSPC `41515ce`)

**New green bar: BSPC 792 (TZ=UTC) + pgTAP 31 · Coach 973 · functions 109.**
Remaining in Phase A, all cutover-coupled by design: AuthContext provider swap
(option (b)), dailyDigest enumeration source (OD-4: deferred whole to G),
redeemInvite RPC (designs in A, lands in I).

---

## Ratifications — 2026-06-09 (post–Phase A session)

### [SETTLED] OD-6 — cutover credentials: NO password-hash import
Kevin ratified: do **NOT** import Firebase password hashes. Both apps are
pre-launch with **zero real users**, so there is nothing to import — at the
identity cutover, accounts are provisioned with **fresh Supabase credentials**
(forced reset / invite path per the plan). The hash-import machinery (Firebase
scrypt parameter export, hash-format conversion, import dry-run) is **skipped
entirely**. This unblocks the §9 provisioning-runner design
(`BSPC/ACTIVE/migration/identity/README.md` step 3), which was waiting on this
decision: the runner simply creates auth users (email + temporary/reset
credential), records `(firebase_uid, user_id)` in `migration_identity_map`,
and never touches password material.

### [SETTLED] Sequencing — continue code-first into Phase B (swimmers)
Kevin ratified: proceed **code-first into Phase B (swimmers roster)** per
`04_CROSS_TIER_SEQUENCING.md`. The identity-cutover mini-plan is staged
**later**, at the point 04 calls for it — consistent with the code-first,
cutover-last model (no dual-write bridges needed pre-launch).

---

## Phase B (swimmers roster) — code-side LANDED 2026-06-09 (same session)

All of 04's Phase B scope committed, every suite green at every commit.
(Also landed: `06_FIREBASE_RUNBOOK.md` — the standalone go-live checklist.)

**Schema (BSPC `00003_phase_b_swimmers.sql` + pgTAP `006`, commit `c4bfe1c`):**
additive/widening only. swimmers gains the Coach-app columns (display_name,
gender TEXT CHECK, usa_swimming_id, profile_photo_url, do_not_photograph,
the five media_consent_* columns, created_by); `family_id` relaxed to
NULLABLE (canonical decision #4 — coach roster exists before parents; NULL
never matches family RLS); practice_group CHECKs (swimmers + coach_groups)
widened to the ratified 8 (+ 'Masters'); staff-only `swimmer_coach_profile`
companion (strengths/weaknesses/technique_focus_areas/meet_schedule/
parent_contacts JSONB) with is_staff() RLS + updated_at trigger; canonical
indexes. pgTAP 31→45 (14 new: shape, NULL-family visibility wall, scp
staff-only wall, gender CHECK, consent defaults).

- **[FYI] `media_consent_granted_by_name TEXT` is an addition over canonical**
  (PROPOSED canonical amendment): the Coach App records the consenting
  guardian as a free-text NAME; canonical's `media_consent_granted_by` is a
  profiles FK, which cannot hold that pre-cutover. Live carries BOTH columns
  (FK stays NULL until guardians are profiles). Canonical 01 should gain the
  same column at the next schema ratification.
- **[FYI] Parents can technically SELECT the new consent/created_by columns
  on their own swimmer's row** (RLS is row-level; this is exactly deferred
  P2-1/P2-2 — resolve via parent-facing views in the APP migration).

**Coach client (commits `725cc2b`, `224165d`, `3a340e9`):** swimmers.ts,
profilePhoto.ts (row-write only; storage binaries stay Firebase until F),
csvImport.ts (swimmer creation; import_jobs bookkeeping stays Firestore until
its phase). Frozen interfaces; realtime parity watches BOTH swimmers and
swimmer_coach_profile (coach-eyes edits used to live on the same doc).
A 4th test dependent surfaced and was re-pointed: `test/critical-ops/
roster.criticalOp.test.ts` (its two "payload includes timestamps" assertions
inverted per playbook — DB owns created_at/updated_at). Client 973→983.

- **[FYI] Legacy `Swimmer.goals: string[]` is now DERIVED ON READ** from the
  goals table (`goals(event_name)` embed) and never written — canonical has
  no swimmer.goals storage. Doc/DOCX export keeps a goals section (now fed by
  live goals rows instead of the stale denormalized strings). The backfill
  inverse is `legacyGoalsToGoalRows`.
- **[FYI] `created_by` is written from `coach.uid` (still the Firebase UID
  under Option (b))** — value semantics flip to profiles.id at the identity
  cutover; pre-launch there are no real rows to remap.

**Functions (commits `86c9e24`, `19b866c`, `8f6f2f7`):** parentPortal swimmer
reads (summaries via one `in()` preserving linked order; detail embeds
staff-only strengths + derives portal goals strings; all four COPPA
sanitization assertions verbatim; times/attendance stay Firestore until C/D),
extractObservations roster reads (drafts write stays until F),
rebuildAggregations roster enumeration (recompute internals stay until
C/D/E/J). Functions 109→114.

**Backfill scaffolding (BSPC commit `0821a0c`):** `migration/roster/` —
transient `migration_swimmer_map` DDL (NOT in supabase/migrations),
`reconcileRoster` (ratified order: usa_swimming_id exact → name+DOB;
ambiguous STOPS the runner; same-name-unconfirmed-by-DOB creates new but is
reported as a collision for human review), fill-NULLs-only merge patch
(**BSPC row wins every conflict; Coach consent/photo-block always carries**),
legacy-goals→goals rows, swimmer-map audit (no doc mapped twice, no two docs
collapsed onto one swimmer). The completed map is the NM-6 swimmer resolver
for guardianship building. BSPC jest 792→811 (+19).

**New green bar: BSPC 811 (TZ=UTC) + pgTAP 45 · Coach 983 · functions 114.**

Remaining for Phase B at cutover (not code): run the reconciliation/backfill,
and the OD-1 convergence items unchanged (family_id drop, last_name NOT NULL
relax, TEXT→enum) stay convergence-step work. Next per 04: **Phase C
(attendance) — flagged the single riskiest step; treat as its own mini-plan
with a red-team pass.**
