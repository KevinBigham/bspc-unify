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

---

## Phase C mini-plan WRITTEN + red-teamed — 2026-06-09 (planning only; no code)

`07_PHASE_C_ATTENDANCE.md` is the full plan (schema 00004 spec, COPPA wall
table + pgTAP 007 proof list, swap specs, commit sequence, rollback/stop
points, RC-1…RC-14 red-team register, canonical amendments A1–A3). Headline
findings: attendance is the one collection where the two live schemas
disagree on the MODEL (event-keyed marking vs date-keyed check-in); the live
table has ZERO pgTAP coverage today; parents currently `select("*")` the
table directly (the canonical staff-only-table + parent-view wall replaces
that); PostgREST cannot upsert against partial unique indexes (drives the
check-in RPC and keeping the live event UNIQUE constraint); and the parent
view needs a transitional family_id OR-arm or live families would see
nothing pre-guardianship-backfill.

### [DECIDE] Phase C decisions awaiting Kevin (details in 07 §2/§3/§5/§9)
1. **D-C1 function scope:** (a) all 5 functions' attendance reads in C, vs
   (b) C = client + parentPortal; evaluator→G, digest→G (OD-4), both
   aggregation CFs→J whole. **Recommend (b).**
2. **D-C2 check-in dedup:** (a) `attendance_check_in` SECURITY DEFINER RPC,
   (b) select-then-write adapter, (c) UNIQUE NULLS NOT DISTINCT (reopens
   D-B). **Recommend (a).**
3. **D-C4 parent status surface:** (a) portal adopts the view's
   present/absent collapse, (b) raw status passthrough to guardians.
   **Recommend (a).**
4. **D-C5 Coach reads exclude `status='absent'` rows** (BSPC-marked
   absences) to preserve the record=attended contract: yes/no.
   **Recommend yes.**
5. **Canonical amendments:** A1 `media_consent_granted_by_name` (carried
   from B), A2 event-key partial-index→constraint swap, A3 check-in RPC
   into canonical. **Recommend ratify all three.**
6. Bundled FYIs to ratify with the plan: D-C6 status value map
   ('normal'↔'present', NULL↔undefined), D-C7 marked_by stays auth.users-FK
   until convergence, RC-10 CASCADE→RESTRICT behavior change.

---

## Phase C decisions RATIFIED — 2026-06-09 (Kevin)

Every item in the [DECIDE] block above is settled; 07 executes as written,
as amended here:

- **D-C1: (b) RATIFIED** — Phase C = Coach client + parentPortal only.
  `evaluateNotificationRules` and `dailyDigest` move whole in Phase G; both
  aggregation functions (`onAttendanceWritten`, `dashboardAggregations`)
  move whole in Phase J. **Cutover-checklist line (recorded):** the
  attendance DATA cutover requires C+G+J reader code landed, or accepts
  digest/notification-rules/dashboard-aggregations dark during the window.
- **D-C2: (a) RATIFIED** — `attendance_check_in` SECURITY DEFINER RPC:
  atomic, double-tap-proof, pgTAP-tested.
- **D-C4: (a) RATIFIED** — parents get the same present/absent collapse
  everywhere (view AND portal). One wall, one rule.
- **D-C5: YES** — Coach reads exclude BSPC-marked `'absent'` rows; the
  roster means "who's here."
- **Canonical amendments A1, A2, A3: all three RATIFIED** —
  `media_consent_granted_by_name TEXT` joins canonical swimmers; canonical's
  partial `attendance_event_key` index becomes the plain
  `UNIQUE(swimmer_id, schedule_event_id)` constraint (day-side partial index
  stays); `attendance_check_in` RPC joins canonical. (01 text edit is
  convergence-sweep paperwork; 07 §3 + this entry are authoritative until
  then.)
- **Bundled FYIs accepted as noted:** D-C6 status value map, D-C7 marked_by
  stays on its current auth.users FK until convergence, RC-10
  CASCADE→RESTRICT behavior change.

---

## Phase C (attendance) CODE-SIDE LANDED — 2026-06-09 (same session as the ratifications)

Executed exactly per `07_PHASE_C_ATTENDANCE.md` §6, one green commit per
step. Every suite green throughout; no force-push/rebase/amend.

**Schema (BSPC commit `d0a1c63`):** `00004_phase_c_attendance.sql` — enum
widened to the canonical 6; `practice_date` added, backfilled from each
event's start in **explicit America/Chicago** (RC-5), then NOT NULL;
`practice_group`/`arrived_at`/`departed_at`/`note` added; `status` and
`schedule_event_id` now nullable; event FK CASCADE→**RESTRICT** (RC-10);
live `UNIQUE(swimmer_id, schedule_event_id)` KEPT as a real constraint
(RC-2b/A2) + `attendance_day_key` partial unique added; `attendance_check_in`
SECURITY DEFINER RPC (D-C2/A3) with `is_staff()` gate, `marked_by :=
auth.uid()`, per-swimmer `(swimmer_id, attendance_id, created)` return;
`attendance_parent_view` with the canonical present/absent collapse + the
**transitional family_id OR-arm** (RC-1, approved accounts only — the live
policy's pending-parent hole closes here); `attendance_select_own` DROPPED in
the SAME migration (RC-3 — no exposed commit exists). pgTAP 007 = **29
COPPA-wall proofs** (45→74): full column/enum/key shape, view column shape,
both view arms, the collapse cases, pending=0, cross-family=0, family
table-read=0/INSERT throws/UPDATE touches 0, RPC create + double-tap +
staff-only + anon revoked, event-upsert inference, RESTRICT.

- **[EXECUTION DETAIL — TR-1 transitional trigger]** 07 §3 sets
  `practice_date NOT NULL` while §5a freezes the BSPC mark/upsert payloads,
  which don't send it. The two are only simultaneously true with a derive
  step: a BEFORE INSERT trigger fills `practice_date` from the event (same
  America/Chicago rule as the backfill) when an event-keyed insert omits it.
  pgTAP-proven with the app's exact payload. Dropped at OD-1 convergence
  when the canonical app sends practice_date natively.

**BSPC parent read (commit `c0f086d`):** `fetchSwimmerAttendance` →
`attendance_parent_view` ordered by practice_date; admin event reads + both
mark upserts stay on the table unchanged (their UNIQUE inference is
pgTAP-proven). `AttendanceRecord` type gains merged-model honesty. 811→813.

**Coach client (commit `a601e01`):** `attendance.ts` → supabase. Realtime
parity per playbook on both subscribes; **reads exclude `status='absent'`
and keep checked-in NULLs (D-C5)** via `or(status.is.null,status.neq.absent)`;
swimmerName from the `swimmer:swimmers(...)` embed, coachName via a second
`profiles.in('user_id', …)` query (D-C7: no FK path yet); `checkIn`/
`batchCheckIn` → the RPC in chunks of 400 with `BatchPartialFailureError`
semantics preserved (double-tap dedup is now ATOMIC — strictly better than
Firestore, RC-12); `checkOut` → row update with the D-C6 write map
('normal'→'present'); practice_date stays a calendar string end-to-end.
Critical-ops name-snapshot assertions INVERTED (derive-on-read). 983→991.

**Functions (commit `67fbb30`):** `parentPortal` attendance payload →
canonical `select('id, practice_date, status')`, newest-first, cap 30,
authorization = linked-swimmer gate; sanitizer adopts the view's collapse
(**D-C4: one wall, one rule**) and is proven to surface exactly
id/practiceDate/status — coach notes and marker identity never leave the
staff side. All prior COPPA assertions verbatim. times stays Firestore until
D. 114→117.

**Backfill scaffolding (BSPC commit `f5936c8`):** `migration/attendance/` —
pure fns; `dedupeSameDay` three-bucket rule (RC-6: exact dups collapse
keeping earliest + lone note carried; time-disjoint same-day rows →
`needsEventAssignment` for human two-a-day event assignment; contradictions →
`conflicts`; runner STOPS on non-empty buckets); `coachAttendanceToRows`
(null/'normal'→'present', string-date passthrough, denorms dropped,
unresolvables reported); `auditAttendanceRows` (day key + enum pre-insert).
No transient map table needed. 813→831.

**New green bar: BSPC 831 (TZ=UTC) + pgTAP 74 · Coach 991 · functions 117.**

Remaining for Phase C at cutover (not code): run the dedup/backfill per the
README run order (after identity + roster maps); human review of the
two-a-day/conflict buckets. Welded to later phases, unchanged from 07 §7:
evaluator+digest→G, both aggregation CFs + status-aware recompute→J,
guardianship backfill + family-arm drop + TR-1 trigger drop + marked_by
remap→OD-1 convergence. **Cutover checklist line (D-C1): the attendance DATA
cutover requires C+G+J reader code landed, or accepts
digest/notification-rules/dashboard-aggregations dark during the window.**
Next per 04: **Phase D (times/PRs/meet results)**.

---

## CONVERGENCE / CUTOVER REMOVAL CHECKLIST — consolidated 2026-06-09

The single authoritative list of every transitional artifact that must be
removed or remapped at the OD-1 convergence step (or, where marked, after
cutover). Earlier scattered mentions remain where they were written; THIS
list is the one the convergence session works through. New transitional
artifacts MUST be added here in the phase that creates them. (TR-1 ratified
post-hoc by Kevin 2026-06-09.)

1. Backfill `guardianships` from `swimmers.family_id` (OD-1 step 1; runner
   in `migration/identity/`, swimmer resolver = `migration_swimmer_map`).
2. Switch BSPC family reads (`fetchFamilySwimmers`, `approveFamily`) and all
   `family_id`-based RLS to `is_my_swimmer()`/guardianships (OD-1 step 2).
3. **DROP the `attendance_parent_view` transitional family_id OR-arm**
   (RC-1): recreate the view guardianship-only; update the pgTAP 007
   family-arm tests to prove the live-family parent still sees rows via the
   backfilled guardianship instead.
4. **DROP TR-1**: the `attendance_derive_practice_date` BEFORE INSERT
   trigger + function, once the BSPC app's mark/upsert payloads send
   `practice_date` natively (canonical app shape). Update pgTAP 007's
   trigger-derivation test to assert the native payload instead.
5. Remap `attendance.marked_by` auth.users→profiles + relax NOT NULL→
   canonical nullable (D-C7), then re-point the Coach coachName read from
   the two-query lookup to the FK embed.
6. Update the `family_id`-based pgTAP tests (OD-1 step 3) and finally
   **DROP `swimmers.family_id`** (OD-1 step 4); relax `swimmers.last_name`
   NOT NULL; convert TEXT CHECK columns → canonical enums.
7. Sweep the remaining inline `EXISTS`-on-profiles admin policies →
   `is_staff()` (deferred from 00002).
8. After cutover completes: DROP the transient map tables
   (`migration_identity_map`, `migration_swimmer_map`).
9. **DROP the Phase D transitional family-id OR-arms** (RD-10, the RC-1
   pattern): narrow `swim_results_select_own`, `personal_bests_select_own`
   and `goals_select_own` to `is_my_swimmer()` only; update pgTAP 008's
   family-arm tests to prove the same reads via backfilled guardianships.

Cutover-sequencing constraints (not removals): the D-C1 line above
(attendance data cutover needs C+G+J readers, or accepts those functions
dark during the window); Phase J recompute must be status-aware (07 §2).

---

## Phase D mini-plan WRITTEN + red-teamed — 2026-06-09 (planning only; no code — the scoping tripwire FIRED)

Kevin's tripwire: "if the two apps disagree on the model itself, STOP and
write a mini-plan." They do — on the PR model. `08_PHASE_D_TIMES.md` is the
full plan (three-shapes table, D-D1 function scoping, 00005 spec with the
unit cut + PB key + PR-maintenance trigger, the ownership wall + pgTAP 008
list, swap specs 5a–5e, commit sequence, RD-1..RD-13 red-team register).
Headline findings:
- **RD-1 GHOST TABLES (worst):** the pre-A swapped `goals.ts`/`groupNotes.ts`,
  the Phase B `goals(event_name)` embeds, and parentPortal's detail read all
  query `goals`/`group_notes` — which NO migration creates (verified absent
  on the running local DB). Invisible to jest (mocks) and pgTAP (no tests) —
  guaranteed 404s at first real run. Plan: catch-up DDL + RLS + pgTAP land
  in Phase D (D-D6).
- **PR truth lives in 3 places** (Coach isPR flag w/ client un-PR/promote +
  trigger-recomputed prsByEvent; BSPC separate personal_bests table keyed
  WITHOUT course; canonical both, course NOT NULL) and **nothing writes
  personal_bests today** → one owner proposed: a `maintain_personal_bests()`
  DB trigger, advisory-locked, impossible to bypass (D-D5).
- **Unit divergence:** BSPC live stores real MILLISECONDS (`÷1000`
  formatter), Coach + canonical hundredths → in-place ÷10 cut behind a
  hard in-migration audit abort; schema commit + BSPC app flip are an
  atomic same-session pair (RD-2/RD-3); recommend converting all four
  time_ms tables at once (D-D3).
- **Analytics would count absences as attendance** post-merge (client twin
  of the banked J bug) → D-C5 filter applied to its attendance read (RD-4).

### [DECIDE] Phase D decisions awaiting Kevin (details in 08 §2/§3/§9)
1. **D-D1:** `onTimesWritten` defers whole to J (extends ratified D-C1(b)
   to the third aggregation trigger). **Recommend yes.**
2. **D-D2:** strict ÷10 unit conversion behind the audit abort (no
   rounding path). **Recommend yes.**
3. **D-D3:** unit cut covers ALL FOUR time_ms tables + seed in one
   migration (swim_results, personal_bests, team_records, time_standards),
   vs only D's two. **Recommend all four.**
4. **D-D4:** personal_bests.course backfill = derive from uniquely-matching
   swim_results, else 'SCY' default with per-row report; ambiguity STOPS.
   **Recommend.**
5. **D-D5 (the model decision):** PR maintenance owner = (b) the
   `maintain_personal_bests()` trigger (advisory-locked recompute; covers
   app writes, imports, AND the cutover backfill), vs (a) RPC pair, vs (c)
   client logic. **Recommend (b)**; on ratification it joins canonical the
   way A3 did.
6. **D-D6:** goals + group_notes catch-up DDL (+pgTAP) lands inside Phase
   D, vs its own micro-phase. **Recommend in D.**
7. Bundled FYIs to accept: timeDisplay derived-on-read everywhere;
   date ordering NULLS-LAST + created_at tiebreak (P0-5); created_by
   parent-visibility stays in the accepted P2 bucket; analytics adopts the
   D-C5 absent-exclusion (RD-4).

---

## Phase D decisions RATIFIED — 2026-06-09 (Kevin)

Plan reviewed and approved ("RD-1 alone justified the tripwire"). Verbatim
calls:

- **D-D1: YES** — `onTimesWritten` defers whole to Phase J, extending the
  D-C1(b) precedent.
- **D-D2: YES** — strict ÷10 conversion behind the hard in-migration audit.
  If the audit finds ANY value that would lose precision, it aborts and the
  session STOPS and reports to Kevin — **never override it**.
- **D-D3: ALL FOUR** time_ms tables convert in the same migration
  (swim_results, personal_bests, team_records, time_standards + seed). The
  database never speaks two unit dialects.
- **D-D4: YES** — course backfill derives from a uniquely-matching result,
  else defaults 'SCY' with every defaulted row reported to Kevin; ambiguity
  stops the migration.
- **D-D5: THE DATABASE TRIGGER** — `maintain_personal_bests()`,
  advisory-locked, recompute-from-rows, the single un-bypassable owner of
  PR truth. **Joins canonical** the way the A3 check-in RPC did (canonical
  amendment ratified).
- **D-D6: IN D** — the goals/group_notes catch-up DDL + RLS + pgTAP land
  inside Phase D.
- **FYI bundle: ACCEPTED in full** — timeDisplay derived-on-read;
  NULLS-LAST with created_at tiebreak; created_by stays in the P2 bucket;
  analytics adopts the D-C5 absent-exclusion.

Execution order: 08 §6 exactly, as ratified. The 00005 migration and the
BSPC unit flip land as the atomic pair (no commit may exist where the
database and the app disagree on units — RC-3 spirit). Honor RD-1..RD-13
fixes including analytics D-C5.

---

## Phase D (times / PRs / meet results) CODE-SIDE LANDED — 2026-06-09

Executed per 08 §6 exactly as ratified, same session as the ratifications.
One green commit each; full bar re-run at every step.

- **BSPC `00005_phase_d_times.sql` + pgTAP 008** (`faae3d5`): D-D2/D-D3 unit
  cut on all four time_ms tables behind the hard ÷10 audit DO-block (RD-3) +
  seed flip same commit — **the audit found ZERO offending rows** (live data
  = the 6 team_records seed rows, all clean ms); swim_results gains
  course/splits/meet_name/source/created_by + nullable date (P0-5);
  personal_bests gains course (D-D4 derive-else-SCY backfill — zero rows
  existed, machinery proven but idle) + meet_name + canonical
  UNIQUE(swimmer, event, course) (P1-13); **`maintain_personal_bests()`
  trigger (D-D5)** — advisory-locked per-key recompute, AFTER
  INSERT/DELETE/UPDATE-of-PR-relevant-columns (the flag's own update can't
  re-fire it), SECURITY DEFINER, mirrors PB rows with achieved_at :=
  COALESCE(date, created_at::date) provenance; RD-10 dual-arm widening of
  both select_own policies (family arm now approved-only, closing the live
  pending-parent hole); **D-D6/RD-1 catch-up DDL: `goals` + `group_notes`
  now EXIST**, satisfying the swapped services' SELECT strings exactly
  (columns_are = the contract), goals dual-arm family-readable, group_notes
  strictly staff-only. pgTAP 008 = 32 proofs: shape/unit/key, trigger math
  for real (first-time flag, faster takes flag, slower no-op, delete
  promotes w/ provenance, group-empty deletes PB, course-split, edit
  recompute), the ownership wall (family arm / guardianship arm / pending=0
  / family INSERT throws + UPDATE 0 / staff all / anon nothing ×4 tables),
  goals+group_notes payload round-trips + walls. pgTAP 001's fixtures now
  speak hundredths and stopped hand-writing personal_bests (trigger truth
  collides with hand-written rows — the D-D5 model working); its 4
  assertions unchanged. Proven on BOTH paths: migration-up on the live DB
  and a from-scratch `db reset`.
- **BSPC unit flip 5a** (`aaa7237`, the atomic pair partner, same session):
  types time_ms→time_hundredths ×4 (+ new nullable result columns),
  formatTimeFromMs→formatTimeFromHundredths (÷100) in progress/standards/
  legacy + the pdf copy, fetchSwimmerResults orders date desc NULLS LAST +
  created_at tiebreak (RD-6), transforms guard null dates (undated rows
  sink; recent-PB cutoff falls back to created_at; date renders empty),
  fixtures ÷10 with display strings UNCHANGED (the RD-2 proof). BSPC tsc
  clean.
- **Coach `times.ts`** (`d6cacfb`): subscribeTimes → swim_results w/
  realtime parity; timeDisplay derived on read; addTime → ONE plain INSERT
  (un-PR loop deleted; existingTimes frozen-but-unused); deleteTime → ONE
  plain DELETE (trigger promotes — BUG #5's no-transient-window guarantee
  now lives in the database); tests inverted to payload pins.
- **Coach `analytics.ts`** (`75682ec`): swimmers/swim_results one-shots,
  chronology-of-entry drop semantics preserved; **the attendance read
  carries the D-C5 filter (RD-4)** or absences would count as attendance;
  distinct-date denominator pinned.
- **Coach `meetResultsImport.ts` times-half** (`48ed2e0`): chunked-400
  plain inserts, un-PR loop deleted, `result.prs` recounted from
  post-insert is_personal_best truth (RD-9); meets/{id}/entries sync stays
  Firestore until H; import_jobs stays (the ratified csvImport split).
- **Functions `parentPortal` times payload** (`a7d57ef`): swim_results via
  service role, FROZEN 8-field shape, timeDisplay derived functions-side
  (RD-12), meetDate stays the same calendar string; sanitizer drop-proof
  fixtures. The last Firestore read in that callable is gone.
- **`migration/times/README.md`** (`671cb1b`): run order + THE UNIT RULE
  (RD-5 — Coach values insert verbatim; no ÷10 code may exist outside
  00005); no transform scaffolding needed (no dedup question — repeat swims
  are legitimate; trigger owns PR state during backfill).

**New green bar: BSPC jest 835 (TZ=UTC) + pgTAP 106 · Coach 987 · Functions
119.** Coach jest is net −4 vs the 991 baseline: −11 deleted client-side
PR-math tests (their subject moved into the database; pgTAP 008's trigger
proofs carry that math for real now — RC-7) + 7 new swap/pin tests.

Convergence checklist: item 9 added (the three Phase D family arms).
Welded to later phases, unchanged from 08 §7: onTimesWritten +
prsByEvent/activity recompute → J (D-D1); meets/{id}/entries sync +
import_jobs → H/their phases; TEXT CHECK→enums + created_by semantics →
OD-1; parent-facing views (created_by P2) → parent-views work; RUNNING the
times backfill → cutover staging (HARD STOP rules).
Next per 04: **Phase E**.

---

## Phase E (notes + voice notes) CODE-SIDE LANDED — 2026-06-09

**The scoping tripwire did NOT fire** — first phase to execute straight
through. Why: BSPC has no notes model at all (nothing to disagree with;
canonical IS the Coach model normalized), the search collectionGroup
translates to a SIMPLER flat-table read (swimmer_id is a column — the
parent-path extraction dies), and the one named hazard — the P1-5 two-pass
source pointers — is structured by canonical itself (FKs added at file end
for the same create-order cycle) plus 04's per-step line. All deferrals
extend twice-ratified precedent. Kevin's two phase rules held exactly:
audio FILES stay on Firebase Storage until F (profilePhoto precedent), and
the wall did not widen by one field (notes were staff-only in Firestore;
they are strict staff-only in PG, pgTAP-proven).

- **BSPC `00006_phase_e_notes.sql` + pgTAP 009** (`a46dafd`):
  swimmer_voice_notes first, then swimmer_notes with `source_voice_note_id`
  FK (ON DELETE SET NULL) live NOW and `source_audio_draft_id` as a bare
  UUID until F; one-source CHECK (num_nonnulls ≤ 1); 19-value tag CHECK +
  4-value source CHECK; coach_id RESTRICT (P1-1); STRICT staff-only RLS on
  both tables — no parent arm exists, transitional or otherwise. pgTAP 009
  = 19 proofs: SELECT-contract shapes, the writers' exact payloads, CHECK
  rejections, SET-NULL orphan safety, **parents/guardians/pending/anon all
  read ZERO rows (even their own swimmer's)**, coach-delete RESTRICTed.
- **Coach `notes.ts`** (`fba2ed7`): realtime-parity subscribe w/ coach
  embed; addNote maps the untyped sourceRefId → typed pointer by source
  kind; coachName denorm dropped (derived on read); SwimmerNote.source
  union gains 'voice_inline' (stored data always had it — the type lied).
- **Coach `swimmerVoiceNotes.ts`** (`87bb9bb`): rows → PG (id DB-owned
  unless caller supplies one); upload + AsyncStorage queue UNCHANGED on
  Firebase Storage.
- **Coach `aiDrafts.ts` note-half** (`bff4957`): approve/approveAll post
  canonical notes w/ source_audio_draft_id := draft id; the one-batch
  atomicity splits at the F seam (draft updates commit on Firestore per
  400-chunk, then the chunk's notes in one insert — the accepted
  meetResultsImport trade). Draft reads/mutations stay Firestore until F.
  **BUG #4 media-consent assertions unchanged word-for-word.**
- **Coach `videoDrafts.ts` note-half** (`f0d2bd9`): video_ai notes carry NO
  note-side pointer (posted_note_id is draft-side, lands in F).
- **Coach `search.ts` notes-half** (`f6749ce`): collectionGroup retired;
  frozen fetch-then-filter semantics (most-recent window, then client-side
  content/tags match); searchNotes gains its first 5 tests. Meet/calendar
  searches stay Firestore until H.
- **`migration/notes/README.md`** (`2bc98f5`): the two-pass rule — pass 1
  inserts voice notes + notes (audio pointers NULL + transient map), pass 2
  after F's drafts backfill sets source_audio_draft_id + posted_note_id.

**New green bar: BSPC jest 835 (TZ=UTC) + pgTAP 125 · Coach 998 · Functions
119.** ZERO test deletions this phase (standing norm: deletions only when
subject code is deleted — none was; every re-pointed test kept its subject).
Functions untouched: parentPortal never exposed notes (verified), and the
notes-reading functions defer whole — **Banked for F:** ADD CONSTRAINT
fk_notes_source_audio_draft + the two posted_note_id FKs + backfill pass 2;
aiDrafts/videoDrafts draft-half + audio file storage move. **Banked for
G/J (extends ratified D-C1(b)/D-D1):** dailyDigest(notes) → G whole;
onNotesWritten + notes aggregations → J (the fourth aggregation trigger;
its recompute product retires in J). Cutover-sequencing constraint: the
notes DATA cutover needs E+G+J reader code landed, or accepts
digest/dashboard-aggregations dark during the window (same class as the
attendance D-C1 line).
Next per 04: **Phase F (media)**.

---

## Phase F (media) MINI-PLAN WRITTEN — TRIPWIRE FIRED — 2026-06-09

Kevin set an INVERTED DEFAULT for F (presumed mini-plan territory); the
investigation confirmed it. **`UNIFY/10_PHASE_F_MEDIA.md`** is the mini-plan
+ red-team, ending in [DECIDE] D-F1..D-F6. No Phase F code written.

Why it fired (full register RF-1..RF-14 in 10): the file tier is pinned
NOWHERE — 04's storage guidance is one word, canonical is host-agnostic,
"Supabase Storage" appears in no UNIFY doc — and two hard couplings
surfaced: **post-auth-cutover clients hold no Firebase token, so today's
auth-gated Storage rules cannot authenticate them at all** (RF-4), and
**Vertex AI requires `gs://` URIs for >20MB video analysis** (RF-3), so the
file home and the AI pipeline are coupled. Independently of the file
decision, all four media Cloud Functions are FIRESTORE document triggers
whose subject docs move to PG in F — the trigger mechanism dies and 04
names no replacement (RF-2 → D-F2).

**Cutover-checklist line (RF-4, holds under EVERY D-F1 outcome):** the
Firebase `storage.rules` wall is `isCoach()` = a Firestore `coaches/{uid}`
doc-existence check. At identity cutover those docs stop being maintained
and the wall fails closed; at auth cutover clients cannot pass ANY
auth-gated Firebase rule. Resolved by D-F1(a) (rules retire with the move)
or by a rules rewrite under D-F1(b) — either way this line stays open until
one lands.

Banked-from-E obligations all accounted for in 10 §1f/§5: FK closures +
pass-2 pointers + draft-halves close IN F; practice-plan PDF + import FILES
re-banked to **Phase H** with their data (per-coach-private scope preserved
— RF-6). `onVideoSessionWritten` → J (fifth aggregation trigger, extends
D-C1(b)/D-D1).

---

## Phase F ratifications — 2026-06-09 (Kevin, verbatim calls)

Plan reviewed and approved ("the auth-cutover coupling alone justified the
inverted default").

- **D-F1: SUPABASE STORAGE is the file home.** Post-cutover clients
  authenticate natively; the wall becomes storage.objects RLS with pgTAP
  proofs — one wall, one rule, extended to files literally. The
  resumable-upload rework, the transient Google-storage staging step inside
  the video function, and the cutover file copy (behind the HARD STOP, as
  always) are accepted costs.
- **D-F2: CLIENT-INVOKE + SCHEDULED SWEEPER** replaces the Firestore
  document triggers. No webhook architecture — webhook delivery is
  untestable on our stack, and we don't trust mocks. Every link provable,
  the sweeper catches drops.
- **D-F3: THREE BUCKETS** with today's exact mime/size caps; media
  staff-only matching today's coaches-only set, not one bit wider; profile
  photos via long-lived signed capability URLs, shape-identical to today's
  token URLs — parents keep exactly ONE media affordance. Consent stays at
  create/approve with BUG #4 verbatim; the file layer neither gains nor
  loses consent logic.
- **D-F4: SCOPE** — photos + voice audio move in F as promised by B/E.
  Practice-plan PDFs and import files RE-BANK to H with their data, because
  they are per-coach-private today and a staff wall would widen access.
  **The no-widening doctrine applies within staff too.**
- **D-F5: RATIFIED** — the draft tables gain `reviewed_at` (the
  lossless-home precedent).
- **D-F6: RATIFIED** — the `approve_draft` RPC heals the E seam atomically
  in the database (the A3/D-D5 precedent); `onDraftReviewed` retires as a
  true subject-code deletion, its tests named per the standing norm when
  that lands.

Execution: 10 §3/§5 exactly — the nine green commits. BUG #4 verbatim;
every storage.objects policy pgTAP-proven like table RLS; no file one bit
more accessible after the move; the parent surface keeps exactly one
affordance, proven. No production/live file movement this phase.

---

## Phase F (media) CODE-SIDE LANDED — 2026-06-09

Executed per 10 §3/§5 exactly as ratified, same session as the
ratifications. One green commit each; full bar re-run at every step.

- **BSPC `00007_phase_f_media.sql` + pgTAP 010, 42 proofs** (`a881ff4`):
  six tables (house TEXT CHECK), P1-4 junctions (video `kind`
  tagged|selected — tagged is the consent-bearing set, FK-guaranteed
  stale-id-free), D-F5 `reviewed_at` on both draft tables; **the
  banked-from-E FK closure** (`fk_notes_source_audio_draft` + both
  `posted_note_id` FKs) in the same migration that creates their targets
  (RC-3); **`approve_session_draft()` RPC** (D-F6) — note insert + draft
  review-stamp + back-pointer in ONE transaction, idempotent double-tap,
  staff-gated inside SECURITY DEFINER; **the file tier**: 3 PRIVATE buckets
  with today's exact size/mime caps + storage.objects staff-only policies.
  pgTAP proves: shapes, CHECK domains, the P1-5 cycle closed BOTH
  directions, SET-NULL orphan safety, cascade, **RPC atomicity (a bad-tag
  approve leaves the draft byte-for-byte untouched — the E seam heal
  demonstrated in the database)**, idempotency, **the wall on tables AND
  storage.objects for every parent principal + anon (all ZERO)**, and the
  bucket caps. pgTAP 009 fixture consequence: the audio_ai payload test
  points at a real draft now that the FK exists (assertions unchanged).
- **Coach `audio.ts`** (`2ab855c`): sessions + junction to PG;
  coachName/selectedSwimmerIds derived on read; uploads via the shared
  `mediaUpload` helper (signed upload URL + XHR PUT — the
  uploadBytesResumable onProgress percent contract survives);
  **D-F2 kick lives in the data layer**: updateAudioSession fires the HTTPS
  pipeline on the flip to 'uploaded' (fire-and-forget; sweeper owns
  retries); config in `src/config/functions.ts`, no hardcoded secrets.
- **Coach `video.ts`** (`e2b7326`): same + BOTH junction kinds; BUG #4
  consent assertions at create UNCHANGED; drafts read off the
  subcollection onto video_session_drafts w/ swimmerName via embed.
- **Coach `aiDrafts.ts` draft-half** (`4886bc7`): subscribePendingDrafts'
  Firestore N+1 collapses to ONE joined read (drafts `approved IS NULL` +
  `audio_sessions!inner` status=review); approve/approveAll through the
  atomic RPC; checkAndCompleteSession → PG and becomes THE completion
  owner. **Named test deletions (subject code deleted):** the E-seam
  mechanics pins — "commits the draft-update batch on Firestore; the notes
  go to swimmer_notes (F seam)", "4 drafts — one draft-update batch commit
  + one canonical notes insert", "401 drafts chunk into two commits + two
  note inserts at the 400-item limit". Replacement proofs: pgTAP 010's RPC
  atomicity/idempotency/cycle tests + the per-draft RPC loop pins.
- **Coach `videoDrafts.ts` draft-half** (`35c85cd`): atomic RPC
  (kind=video); BUG #4 verbatim; zero deletions.
- **Coach file-halves** (`a1fc53e`): voice-note uploads → media-audio
  (path layout UNCHANGED, AsyncStorage queue untouched); recorder playback
  derives fresh signed URLs; **profile_photo_url now persists a ~10y
  signed capability URL** — the parents' ONE media affordance,
  shape-identical to the Firebase token URL it replaces (D-F3).
- **Functions** (`b2dd10b`): `processAudioSession`/`processVideoSession`
  (onRequest, shared-secret, 401/400 pinned) wrap idempotent cores gated
  on status='uploaded'; **RF-10 CLOSED** (video swimmer names from
  canonical via the junction); **the ≥20MB Vertex path streams a TRANSIENT
  gs:// staging copy, deleted after analysis** (code-side only);
  extractObservations drafts → ONE canonical insert (firebase-admin gone
  from the module); `sweepStuckSessions` every 5 min with per-session
  error isolation. **Retired with subjects: onAudioUploaded.ts,
  onVideoUploaded.ts, onDraftReviewed.ts. Named test deletions:
  onDraftReviewed.test.ts (5 tests) — completion now owned by
  checkAndCompleteSession (pinned client-side) + the RPC's pgTAP proofs;
  plus the Firestore event-snapshot mechanics pins in the two rewritten
  pipeline suites ("should return early if event data is missing",
  "should skip if status did not change") whose successor is the pinned
  idempotency gate.** onVideoSessionWritten stays exported, subject
  collection now write-dead → **Phase J** (D-C1(b)/D-D1 family, the fifth
  aggregation trigger).
- **`migration/media/README.md`** (`22f3d25`): row→junction→draft order,
  identity/roster map resolution with STOP-on-unresolvable, **pass 2
  pointer closure (banked ③ from E)**, and the path-preserving file-copy
  manifest (audio/**→media-audio incl. voice notes, video/**→media-video,
  profiles/**→profile-photos; practice_plans/** + imports/** RE-BANKED to
  H with their data, per-coach-private scope — D-F4) + the
  profile_photo_url rewrite pass. Runs at cutover staging behind the HARD
  STOP.

**New green bar: BSPC jest 835 (TZ=UTC) + pgTAP 167 · Coach client 1022 ·
Functions 118 · BSPC tsc clean.** Deletions per the standing norm all named
above (3 Coach + 7 Functions); every other test kept its subject.

**Banked/open after F:** notification-routing for media (`ai_drafts_ready`
category) is G's whole; dashboard aggregations incl. onVideoSessionWritten
→ J; statuses/practice_group TEXT→enum at OD-1; **cutover checklist
additions:** set `PROCESS_SHARED_SECRET` (functions env) +
`EXPO_PUBLIC_PROCESS_FUNCTIONS_BASE_URL`/`EXPO_PUBLIC_PROCESS_SHARED_SECRET`
(app env) before the media pipeline goes live; confirm hosted storage tier
covers the 500MB video cap before the file copy; the old Firebase
`storage.rules` retire WITH the file copy (RF-4 closes under D-F1(a)).
**Flagged risks (no trusted mocks):** Vertex calls and the GCS staging
stream remain jest-mocked only — first real exercise happens at staging;
webhook-free design means the only delivery untestable locally is nothing —
the kick + sweeper are both fully unit-tested.
Next per 04: **Phase G (notifications)**.

---

## 2026-06-10 — Phase G scoping tripwire: FIRED → 11_PHASE_G_NOTIFICATIONS.md

Baseline confirmed green at session start (BSPC 835 TZ=UTC + pgTAP 167 ·
Coach 1022 · Functions 118; all repos clean/synced). Full notification
surface read end to end (Coach: notifications.ts, notificationRules.ts,
evaluateNotificationRules, onNotification, manageTopics, dailyDigest, the
shared pure evaluation module; BSPC: push.ts, notifications api,
send-notification + cleanup-tokens Edge Functions, pgTAP 003; canonical 01
delta vs landed 00001).

**Fired because the delivery architecture is mostly unpinned do-nothing
defaults:** evaluator's firing mechanism post-Firestore (D-F2 was ratified
for media, not attendance); coach push transport — today's effective coach
push delivery is ZERO (registerForPushNotifications has no call site;
Expo-format tokens were fed to an FCM sender) and the canonical Deno sender
unconditionally inserts in-app rows (double-notification seam) while having
zero tests; OD-4 (digest enumeration, deferred whole from A) + the digest
pref has no canonical home (notification_preferences lacks it; only writer
is AuthContext, itself cutover-banked); ai_drafts_ready = wire-or-re-bank;
nothing anywhere schedules send-notification/cleanup-tokens (the whole BSPC
notification feature is dormant pending an invoker). **Cross-phase finding
RG-6:** no migration ever added tables to the supabase_realtime publication
— all 12 Coach-subscribed tables from B–F (+2 from G) depend on hosted
config that exists nowhere in code.

11 ends with **[DECIDE] D-G1..D-G6** (invocation, push transport, digest
enumeration+pref, ai_drafts_ready, publication-as-code, pipeline
scheduling), each with a recommendation. No Phase G code written; bar
unchanged.

---

## 2026-06-10 — Phase G ratifications (Kevin, verbatim intent recorded)

- **D-G1 RATIFIED — kick + sweep, the D-F2 pattern extended to attendance.**
  The attendance data layer kicks the evaluator with **row ids only**; the
  server re-derives swimmer/group/marker/practice_date from PG; a five-minute
  sweeper catches missed kicks. **Condition:** the kick must never make an
  attendance write fail or wait — fire-and-forget, internal catch; if the
  evaluator is unavailable, attendance still saves and the sweeper covers it.
- **D-G2 RATIFIED — coach notifications are in-app only for Phase G.** The
  dormant Deno sender is not touched, not scheduled, not extended. **On the
  record: coaches receive zero pushes today and will receive zero after
  Phase G, deliberately — parity with a feature that never functioned is that
  feature's absence.** Push delivery is a named post-cutover product line item.
- **D-G3 RATIFIED — digest enumerates staff by role from canonical tables;
  the preference becomes `notification_preferences.digest_enabled BOOLEAN NOT
  NULL DEFAULT TRUE`.** The edge-case flip is **explicitly ratified**:
  missing-preference formerly meant skip; the canonical default means
  included. Reasoning: signup always wrote default-true, "missing" only
  described accounts that bypassed signup, and we are pre-launch with zero
  real users. The Firestore home (`coaches.notificationPrefs`, AuthContext
  writer) retires at cutover. **Standing rule restated: no digest may carry a
  field its recipient couldn't read directly.**
- **D-G4 RATIFIED — `ai_drafts_ready` re-banked as post-cutover product
  work** (named in the bank below). No producer has ever existed; wiring one
  mid-migration is new behavior, not parity. G lands only the category domain.
- **D-G5 RATIFIED — 00008 adds all fourteen tables to the supabase_realtime
  publication** (the twelve from B–F + G's two), pgTAP proving **exact**
  membership. Codification of hosted behavior, not widening — delivery still
  rides the same RLS walls; the proofs pin the set exactly.
- **D-G6 RATIFIED — no Deno changes, no cron now.** Cutover-runbook line
  (behind the HARD STOP): schedule `send-notification` + `cleanup-tokens`
  (Supabase cron) at cutover staging with an end-to-end drain verification.
  **Required reconciliation mechanism, named now:** rule-engine and digest
  writers NEVER enqueue `notification_jobs` — they own their idempotent
  `in_app_notifications` rows directly, so the sender's unconditional in-app
  insert can never duplicate them while the queue carries only BSPC-side
  announcements. If coach push later rides the jobs queue (the D-G2 product
  line), `notification_jobs` first gains a `skip_in_app BOOLEAN` the sender
  honors. **The drain verification must prove it:** enqueue one ordinary job
  AND one rule-mirroring flagged job; assert exactly one in-app row per
  recipient for each (the writer-owned row, never a sender duplicate).

Execution per 11 §5 begins now; standing norms in force (green at every
commit, RC-3, data layer only, no-widening incl. everything SENT, no Deno
edits, deletion norm, no force-push/rebase/amend).

---

## 2026-06-10 — PHASE G (notifications) LANDED — code-side complete

Executed per 11 §5 under D-G1..D-G6, one green commit at a time (all four
bars green at every commit; RC-3 held; no Deno file touched).

- **BSPC `00008_phase_g_notifications.sql` + pgTAP 011, 42 proofs**
  (`9dcae51`): notification_rules (TEXT-CHECK 6-trigger domain per OD-1,
  coach_id → profiles RESTRICT, updated_at trigger, staff FOR ALL wall);
  in_app_notifications + category (6-value)/data/rule_id/swimmer_id/
  source_eval_date, **[P1-6]** rule FK (SET NULL), **[P2-3]** idempotency
  as the expression-partial UNIQUE (COALESCE sentinels; NULL-rule digest
  rows deliberately unconstrained), **[P1-7]** UPDATE policy recreated with
  explicit WITH CHECK, jobs policy → is_staff() (**verified the SAME
  principal set** — is_staff() IS role IN (coach_admin, super_admin); pure
  refactor, not widening); `digest_enabled BOOLEAN NOT NULL DEFAULT TRUE`
  (D-G3); **`upsert_rule_notification()`** SECURITY DEFINER, service-role
  only — the FOLLOWUP-#2 upsert lives in SQL because **PostgREST cannot
  target an expression index's ON CONFLICT** (the D-F6 class); merge
  semantics match the old set(merge:true) exactly (re-fire = one row,
  refreshed, unread again, re-dated) — pgTAP proves single-row re-fire,
  23505 on raw duplicate, sentinel dedup, staff/anon execute-denied;
  **D-G5 publication**: exactly the 14 subscribed tables added to
  supabase_realtime in a membership-checked DO block, pgTAP pins the set
  EXACTLY (results_eq, collate "C" — pg_publication_tables.tablename is a
  `name`). Walls: rules staff-wide CRUD ✓ / parent zero + 42501 / pending +
  anon zero-tuples; **in_app own-row holds even for staff** (a coach reads
  ONLY their own rows); **[P1-7] proof: reassigning your own notification's
  user_id throws 42501**; mark-own-read lives_ok.
- **Coach `notificationRules.ts`** (`0699221`): CRUD + realtime-parity
  subscribe on notification_rules; coach_id per D-B7; timestamps DB-owned
  (inverted pins); the pure evaluation module untouched (19 tests verbatim);
  criticalOp re-pointed.
- **Coach `notifications.ts`** (`779250a`): list/unread/markRead →
  in_app_notifications with **RLS-as-the-scope** (no client-side user filter
  exists to get wrong — pinned by asserting the ABSENCE of an eq filter);
  register/unregister → push_tokens upsert/delete keyed by auth.uid
  (**D-G2: storage parity only; registration still has no caller — coaches
  get zero pushes, deliberately, on the record**). manageTopics client half
  DELETED. **Named test deletions (subject: FCM topic machinery):**
  "subscribes to group topics + broadcast_all", "continues on individual
  topic failure", "unsubscribes from group topics + broadcast_all" —
  replacements: pgTAP 011 walls + the push_tokens storage pins. AuthContext
  sign-out lost only the dead topics call (its Firestore-guarded cleanup
  block retires whole with the provider at cutover).
- **Functions evaluator rebuild** (`5492035`): `evaluateAttendanceRules`
  HTTPS entry (same x-process-secret gate + env lines as the media
  pipeline) takes **row ids only** — the core re-derives swimmer/group/
  marker/date from PG (id-only trust, the processSession precedent);
  **D-C5 NOT_ABSENT filter on every presence-meaning history read** (pinned);
  limit-then-unique streak window math verbatim; body fallback strings
  verbatim; **RG-7 recipient mapping pinned** (rule owner's auth user ≡
  marked_by, since rules are matched on the marker's profile);
  writes via the RPC. `sweepAttendanceEvaluations` every 5 min over the
  10-min created_at window (attendance has no updated_at; a lost CHECKOUT
  kick outside the window is not re-swept — a checkout changes no rule
  input, noted in 11). **Attendance data-layer kicks** (checkIn /
  batchCheckIn per committed chunk / checkOut) are fire-and-forget per the
  RATIFIED D-G1 condition — a kick can never fail or delay a write (pinned:
  no-kick-on-failed-write; committed-chunk kicks survive batch failures;
  never-rejects pinned in attendancePipeline's own suite per the
  jest+Node24 rule). **Retired with subjects:** evaluateNotificationRules
  (trigger, dark since C), onNotification (FCM sender), manageTopics
  (callable; no functions test file existed). **Named test deletions:**
  onNotification.test.ts (6: "should be defined", "should return early if
  event data is null", "should skip if coach has no FCM tokens", "should
  send push notification to each token", "should clean up invalid tokens",
  "should not clean up tokens on other errors") — transport deleted under
  D-G2; replacements: the writers' in_app pins + pgTAP walls; token
  staleness is BSPC cleanup-tokens' canonical job.
  evaluateNotificationRules.test.ts re-pointed wholesale into
  evaluateAttendanceRules.test.ts — all 5 behavioral subjects kept; the
  Firestore "after"-snapshot guard lives on as the row-gone/no-marker
  no-ops.
- **dailyDigest rewrite** (`ce360e1`): OD-4 RESOLVED — recipients
  enumerated from the staff ROLE SET (role filter pinned, RG-8), gated by
  digest_enabled with the **ratified missing-row-means-included flip**
  (**named deletion:** "should skip coaches without dailyDigest preference"
  — subject was the Firestore prefs map; replaced by the flip pin);
  presence count = distinct swimmers under D-C5 + departed_at IS NULL
  (RC-13 same-meaning); body + pluralization verbatim; ONE batched insert
  of NULL-rule_id rows (RG-11 faithful). **DIGEST DOCTRINE held provably:
  content = counts of staff-readable tables; recipients = staff by
  construction; pgTAP's own-row wall keeps each digest readable only by
  its recipient.**
- **`migration/notifications/README.md`** (`5b405de`): rules → notifications
  → prefs → tokens order; the RG-7 recipient mapping spelled out
  (coachId → profiles.user_id, the AUTH id); domain-CHECK STOPs;
  duplicate-triple REPORT+STOP; absent pref map = no row; fcmTokens
  expected EMPTY (non-empty REPORTED, never auto-copied). Behind the HARD
  STOP.

**New green bar: BSPC jest 835 (TZ=UTC) + pgTAP 209 · Coach client 1034 ·
Functions 125 · BSPC tsc clean.** Deletions per the standing norm all named
above (3 Coach topic tests + 6 Functions onNotification + 1 digest
missing-pref pin = 10); every other test kept its subject.

**Banked/open after G:** `ai_drafts_ready` = **named post-cutover product
line item** (D-G4: category domain landed, no producer — wiring is a
one-line writer + tests when product says go); **coach push delivery** =
named post-cutover product line item (D-G2; the D-G6 runbook line already
names the skip_in_app dedup mechanism it must use if it rides the jobs
queue). **Cutover checklist additions:** schedule send-notification +
cleanup-tokens (Supabase cron) at cutover staging with the end-to-end
drain verification proving no duplicate in-app rows (D-G6, mechanism named
in the ratification entry above); the evaluateAttendanceRules endpoint
rides the SAME `PROCESS_SHARED_SECRET` + `EXPO_PUBLIC_PROCESS_*` env lines
already banked at F (no new secrets). **Flagged (no trusted mocks):** the
client kick's fetch and the functions' supabase-js calls are jest-mocked as
transport (same accepted class as F); everything provable locally IS proven
— the upsert's merge semantics, the walls, the publication set, and the
policy refactor are pgTAP-proven against the real database.

Next per 04: **Phase H (calendar + meets + plans)** — calendar.ts, meets.ts,
meetResultsImport meets-half, practicePlans+workoutLibrary as a pair,
seasonPlanning (data-layer tests FIRST), syncCalendar; plus the re-banked
practice-plan PDF + import FILES from D-F4.

---

## 2026-06-10 — pgTAP count reconciliation (Kevin's ITEM 0)

Drafting typo, not a deletion: the in-session "43" was a miscount in 011's
`plan()` line only (the first run reported "planned 43 ran 40" — wrong plan
number, plus a collation error aborting the publication test; both fixed
before anything was committed). The landed 011 declares `plan(42)` and
contains exactly 42 test calls — re-verified today by direct count
(167 + 42 = the green 209); no pgTAP proof was ever deleted or merged, so
the deletion norm never engaged.

---

## 2026-06-10 — Phase H scoping tripwire: FIRED → 12_PHASE_H_CALENDAR_MEETS_PLANS.md

Baseline confirmed at session start (bar 835+209/1034/125, all three repos
clean/synced). Full Phase H surface read end to end on BOTH apps before any
code: Coach calendar.ts / meets.ts / practicePlans.ts / workoutLibrary.ts /
seasonPlanning.ts / importJobs.ts / search.ts meets+calendar halves /
meetResultsImport meets-half / syncCalendar + icalParser; firestore.rules +
storage.rules verbatim; BSPC features/meets + features/schedule +
calendar-feed Edge Function + live 00001–00008 policies; canonical 01 for
all eight H tables + enums + RLS; every banked item pulled from the bank by
name (12 §1e).

**Fired on five grounds (12 §0):** (1) canonical's staff-wide RLS on
practice_plans + import_jobs contradicts the ratified D-F4 within-staff
no-widening doctrine — live walls are per-coach (+public arm / +admin arm);
(2) canonical calendar_events cannot host syncCalendar's writes (coach_id
NOT NULL FK vs the 'ical_sync' sentinel; no source/ical_uid/raw_rrule/
synced_at columns — and ical_uid is the idempotency key); (3) canonical
grants calendar read to active accounts + family RSVP write where today's
wall is coach-only — ratified law vs the later no-widening doctrine, Kevin
arbitrates; (4) the D-F4 premise is half-imprecise: practice-plan PDFs are
real and per-coach, but import FILES have never existed (no uploader was
ever written; `imports/**` is a rules-only dead path; csvImport's
storagePath is the constant 'manual/pasted-roster.csv'); (5) 04 assigns
import_jobs to no phase while D-F4's "with their data" implies H.

**Scope confirmation (12 §1e, stated plainly):** 04's "calendar + meets +
plans" and the handoff-era "leftover searches + per-coach-private files"
differ in exactly two material places — import_jobs (04: phase-less; plan
proposes H, D-H8) and import files (bank presumed files that don't exist;
plan records absence-as-parity, D-G2 class, D-H2b). Everything else is the
union of both lists. Out of scope by name: BSPC schedule_events + scrape
pipeline (BSPC-native, already canonical), aggregations (J), parent_invites
(I), SETTLED-#5 dead collections, P2-9 recurring expansion.

12 ends with **[DECIDE] D-H1..D-H8 + an FYI bundle** (per-coach canonical
amendment incl. the project's first within-staff pgTAP walls; the file
tier; the calendar sync amendment; RSVP upsert; the calendar parent-arm
widening question — the one genuine coin-flip, recommendation (b)
staff-only-now; rateWorkout parity-deny; live meets policy alignment;
import_jobs into H), each with a recommendation. Notable register entries:
RH-4 (the Firestore lexical "-31" month bound is an invalid PG date
literal), RH-12 (pgTAP 011 pins the publication set EXACTLY — 00009 must
update it 14→22 in the same commit), RH-2 (PG RLS filters where Firestore
rules reject — caller filters stay), RH-7 (cross-coach rating is provably
broken today — rules deny it). **No Phase H code written; bar unchanged
(835 TZ=UTC + 209 / 1034 / 125).** seasonPlanning's 19 tests are pure-helper
only — the 04 tests-FIRST mandate is §5 commit 1.

---

## 2026-06-10 — Phase H PARTIAL ratifications (Kevin, verbatim intent recorded; records-and-readback session, NO H code)

Four of the 12 §7 [DECIDE] blocks are resolved. Each ratification was
checked against its block's question and options as written before
recording — all four match; nothing was force-fit. Still OPEN after this
entry: **D-H2(a)** (the practice-plans bucket design), **D-H3** (calendar
sync amendment), **D-H4** (RSVP upsert), **D-H6** (cross-coach rating
parity-deny), **D-H7** (live meets policy alignment), and the **§4 FYI
bundle** — all read back to Kevin verbatim this session, awaiting his
calls. Pre-approved by Kevin as norm compliance, no further text needed:
the publication 14→22 same-commit growth (RH-12).

- **D-H1 RATIFIED — within-staff walls; canonical is amended to match
  ratified law, not the reverse.** Practice plans are owner-private, with
  the explicit public-share arm preserved exactly as it behaves today —
  other staff read only what a coach has deliberately shared. Import jobs
  are readable by their owner and admins only. D-F4 already decided
  within-staff privacy; the drafted all-staff walls were a drafting error
  against standing law, and the amendment corrects the draft. (Resolves
  D-H1 as option (a): the `is_my_profile()` helper; practice_plans SELECT
  own-or-is_public within staff, writes own-only with no reassign;
  import_jobs SELECT owner-or-super_admin, writes own-only, DELETE
  super_admin; season_plans stays staff-shared — that IS today's wall,
  unchanged by this ratification.)
- **D-H5 RATIFIED — option (b): the coach calendar ships staff-only.** No
  parent calendar screen exists in either app, and granting standing
  access to data with no feature behind it is widening with zero user
  benefit — the no-widening doctrine wins the tiebreak. The parent read
  and RSVP arms are **banked as a named post-cutover product line item,
  contingent on an actual parent calendar feature**, and canonical is
  amended so the deferral is recorded law rather than drift (the
  [SCOPE-DEFERRED] annotation on the calendar_events/rsvps parent
  policies, not a rewrite).
- **D-H2(b) RATIFIED — there will be no imports storage bucket.** No
  import file has ever been uploaded by any code; the storage rule guards
  a path nothing writes. Per the Phase G precedent, parity with a feature
  that never functioned is that feature's absence. **The D-F4 bank entry
  is corrected on the record: the per-coach-private files banked into H
  are the practice-plan PDFs only.** (Scope note, no force-fit: this
  resolves only the (b) half of D-H2 — the (a) half, the practice-plans
  bucket itself with its caps and the is_staff()+owner wall and the named
  one-bit hole-closing, remains OPEN.)
- **D-H8 RATIFIED — import_jobs is pulled into Phase H, and 04 is amended
  to say so.** D-F4's "with their data" implies it, the table's walls are
  amended in this same phase (D-H1), and work assigned to no phase is
  work that gets forgotten.

Paperwork per the A1/A2/A3 precedent: the canonical 01 text edits (D-H1
per-coach walls, D-H5 [SCOPE-DEFERRED] annotation) and the 04 §H line
addition (import_jobs) are hereby ratified; the document text edits land
with the Phase H execution session — 12 + this entry are authoritative
until then. Records-and-readback session only: UNIFY is the sole repo
touched; BSPC and Coach unchanged; bar untouched
(835 TZ=UTC + 209 / 1034 / 125).

---

## 2026-06-10 — Phase H ratifications COMPLETE (D-H2a/D-H3/D-H4/D-H6/D-H7 + FYI 10/11) · the RH-8 gate FIRED → [DECIDE] D-H9 (12 §8) · NO H code

Kevin resolved every remaining 12 §7 block this session, gated on one
check: print RH-8 verbatim and answer whether any principal gains
database-layer read access it lacks today. **The gate returned YES —
widening — so per Kevin's own wiring this is a tripwire: D-H9 is written
in 12 §8, no §5 code executed, and execution now blocks on D-H9 alone.**
Each ratification below was checked against its block as written before
recording; all five match; nothing force-fit.

- **D-H2(a) RATIFIED — the practice-plans file tier lands as drafted.**
  Private `practice-plans` bucket; today's caps mirrored exactly (25MB,
  application/pdf); storage walls `is_staff() AND owner-path-segment`;
  uploads via the F-phase mediaUpload helper; reads via signed URLs; the
  copy-manifest line rewrites the owner segment through the identity map
  at cutover. The single named stricter bit — the RH-14 parent-segment
  hole-closing — is accepted as hole-closing narrowing. **Binding rider
  (Kevin, verbatim substance): the "exactly one named divergence" claim
  is binding — any second behavioral difference between today's storage
  rule and the new wall discovered during execution is a tripwire, not a
  judgment call.**
- **D-H3 RATIFIED — calendar_events hosts the iCal sync.** Columns added:
  `source TEXT`, `ical_uid TEXT UNIQUE`, `raw_rrule TEXT`, `synced_at
  TIMESTAMPTZ`; `coach_id` relaxes NOT NULL → NULLABLE with ON DELETE SET
  NULL. Synced rows carry coach_id NULL with provenance in `source`; the
  foreign key keeps fake owners unrepresentable forever (every non-NULL
  coach_id must still reference a real profiles row — the 'ical_sync'
  string sentinel can never exist). syncCalendar becomes one upsert
  `onConflict('ical_uid')` with clobber semantics preserved; the
  created_at churn heals as a named invisible fix; the sync-table
  alternative is rejected as a join tax for zero wall benefit.
- **D-H4 RATIFIED — RSVP becomes the canonical upsert** on
  UNIQUE(event_id, swimmer_id): one row per swimmer per event, re-RSVPs
  refresh status/parent_name/note + updated_at — the strictly-better
  atomic class. The backfill collapse rule (keep latest updatedAt, REPORT
  every collapse) lands in the manifest only and runs behind the HARD
  STOP at cutover staging.
- **D-H6 RATIFIED — cross-coach rating/tagging stays parity-denied** (the
  feature never functioned; absence is parity). The `rate_workout`
  SECURITY DEFINER RPC is banked as a named post-cutover product line
  item alongside coach push and ai_drafts_ready.
- **D-H7 RATIFIED — live meets policies align inside 00009 itself.**
  `meets_select_all USING (TRUE)` narrows to `is_active_account()` (the
  accepted P1-8 narrowing class, proven: deactivated → 0); the admin
  inline-EXISTS policy refactors to `is_staff()` as a verified same-set
  swap (the G jobs-policy pattern). Policy travels in the same migration
  as the new Coach columns so no intermediate commit exposes the new
  fields to deactivated accounts. (D-H7 stands regardless of D-H9's
  outcome: it narrows the existing BSPC-origin surface; D-H9 decides only
  whether Coach-origin rows join that surface.)
- **FYI bundle — ten of eleven items accepted as named** (month-window
  rewrite RH-4; pdf title := filename RH-16; weeks-key 23505 +
  single-DELETE cascade RH-10; entries display-string/stamp drops; search
  null-mapping; publication 14→22 RH-12, separately pre-approved; ratings
  keys stay coach.uid; created_at-churn heal; tagWorkout trigger bump;
  PDF-exclusion server-side + group filter client-side RH-16). **The
  eleventh — RH-8 merged-meets cross-visibility — was accepted only via
  the STEP 0 gate, and the gate returned WIDENING:** at the cutover
  merge, active (and pending) parent accounts gain SELECT over
  Coach-origin meet rows — and over the Coach-authored fields the
  superset-fill merge writes onto matched rows — all of which sit behind
  `isCoach()` (staff-only) in firestore.rules today; the merged table's
  `is_active_account()` wall (01 L1110) admits principals today's Coach
  wall denies. RH-8's FYI disposition is superseded → **[DECIDE] D-H9
  (12 §8)**: (a) accept the named widening — one parent-readable meets
  table (recommended: the parent meets feature exists and ships in BSPC,
  unlike D-H5's absent calendar UI); (b) visibility-split column; (c)
  staff-only sibling table. meet_entries does not widen under any option
  (canonical keeps entries strictly staff-only, 01 L1112).

Status after this entry: **D-H1–D-H8 all ratified; the sole open item is
D-H9.** §5 executes the moment D-H9 lands (if (b)/(c), commit 2's meets
walls and the §5.11 meets manifest lines re-derive from the chosen option
first). The A1/A2/A3 paperwork rider extends: the 01/04 text edits for
D-H2(a)/D-H3 join the earlier D-H1/D-H5/D-H8 set and land with the
execution session — 12 + NOTES are authoritative until then.
Records-and-gate session only: UNIFY is the sole repo touched; BSPC and
Coach unchanged; bar untouched (835 TZ=UTC + 209 / 1034 / 125); zero
Phase H code.

---

## 2026-06-10 — D-H9 RATIFIED (Kevin, verbatim intent recorded) — the DECIDE queue is EMPTY; Phase H executes

Checked against 12 §8's block as written: matches option (a) exactly,
with three condition riders that strengthen the block without contradicting
it. Nothing force-fit.

**D-H9 RATIFIED — one parent-readable meets table; the widening is
accepted and signed as a NAMED widening, the first on the books.**
Reasoning on the record: the no-widening doctrine stops *accidental*
access expansion; it does not freeze the unified product at the most
restrictive of two legacy apps. The D-H5 test — capability follows
product — passes here because the parent-facing meets feature exists and
ships: BSPC's meets screens render this very table to families today,
and a meet schedule is the same team-wide logistics class as
schedule_events and announcements that pending parents already read by
ratified law. A parent schedule silently omitting coach-entered meets
would show families a false schedule — worse than the widening it avoids.
Sized precisely: parents gain the existence of coach-origin meets and
their logistics fields; meet_entries — children's race data — stays
strictly staff-only and does not widen one bit; the staff direction
widens nothing; the BSPC side only narrows per D-H7.

**Conditions, binding:**
1. **The precedent is narrow** — a named widening requires an existing,
   shipping parent surface and an explicit signature; widenings never
   happen by drift.
2. **pgTAP must pin the exact post-merge principal set per D-H7 AND
   prove that parent and pending principals read zero meet_entries
   rows.** (Lands in 012, §5 commit 2.)
3. **Rejected on the record:** the publish-column option invents a
   product workflow the data-layer freeze forbids and fails the F-lesson
   do-nothing audit in both default directions; the sibling-table option
   forks the one-table model, duplicates physical meets, and re-raises
   this identical question at convergence with live data.

With D-H9 in, **every Phase H decision (D-H1–D-H9 + the full FYI bundle)
is ratified**. The queued 01/04 paperwork lands now, with this execution
session, per the A1/A2/A3 precedent; then 12 §5 executes in order.

---

## 2026-06-10 — Phase H (calendar + meets + plans + import_jobs) CODE-SIDE COMPLETE — landed per 12 §5, eleven green commits

**Bar: BSPC 835 (TZ=UTC, unchanged as predicted) · pgTAP 209 → 274 (+65) ·
Coach 1034 → 1077 (+43) · Functions 125 → 128 (+3). All four bars green at
every commit; never advanced on red. Zero test deletions** — two pin
TRANSFORMS named per the norm, subjects kept with replacements: (1) the two
Firestore client-cascade pins on deleteSeasonPlan merged into the one
canonical single-DELETE pin (RH-10 — the behavior they pinned was replaced
by ratified design); (2) the three stableId/djb2 pins re-pointed to the
ical_uid conflict key (D-H3 — same idempotency-key subjects: determinism,
distinctness, weird-char safety). Test counts only rose.

Paperwork (UNIFY `e71050a`): 01 amended — is_my_profile() helper, D-H1
per-coach walls, D-H3 calendar_events sync columns + nullable coach_id,
D-H5(b) [SCOPE-DEFERRED] annotation, D-H9 named-widening note on the meets
policies; 04 amended — import_jobs into Phase H (D-H8). (01 has no storage
DDL section; D-H2a's bucket lives in 00009 + 12.)

The eleven commits, landed in order:
1. **Coach `6745a39`** — seasonPlanning DATA-LAYER pins FIRST (04 §H
   mandate): all six Firestore data functions pinned before any swap.
2. **BSPC `cc037d9`** — `00009_phase_h_calendar_meets_plans.sql` + pgTAP
   012 (65 proofs) + 011's publication proof 14 → 22 SAME commit (RH-12).
   Eight tables; D-H1 within-staff walls via is_my_profile() — the
   project's FIRST staff-A/staff-B pgTAP proofs (private invisible, public
   template readable-not-writable, no reassign, no spoof; imports
   owner+super_admin, delete admin-only); D-H2a practice-plans bucket
   (25MB/pdf caps mirrored; is_staff() AND owner-segment — RH-14's
   parent-segment hole closed, proven as the ONE named stricter bit);
   D-H3 sync columns + ical_uid UNIQUE + fake-owner-unrepresentable FK
   proof; D-H4 RSVP key; D-H5(b) staff-only calendar walls; D-H7 meets
   policy swap in-migration (deactivated → 0 proven; admin-inline →
   is_staff() same set); D-H9 pins (parent reads coach-origin meets row +
   its logistics fields; parents AND pending read ZERO meet_entries rows);
   RH-10 weeks key + single-DELETE cascade; house triggers; rsvps
   trigger-less (DEFAULT-only updated_at, proven).
3. **Coach `b605bed`** — calendar.ts swap: RH-4 month rewrite (February +
   December pinned), D-H4 upsert onConflict(event_id,swimmer_id),
   denorms derived on read, realtime parity ×2 channels.
4. **Coach `cb7083b`** — meets.ts swap: Coach slice of the D-H9 superset;
   BSPC-origin null tolerance pinned (RH-8); entries hundredths verbatim +
   derived displays (RD-5).
5. **Coach `8313ca1`** — meetResultsImport meets-half: one meet_entries
   UPDATE keyed (meet_id, swimmer_id, event_name); display + stamp drops;
   swallow-and-report verbatim.
6. **Coach `6b5b34c`** — practicePlans + workoutLibrary pair: D-H1 walls
   under the reads (RH-2 filter discipline pinned), RH-16 server-side PDF
   exclusion + title := filename, D-H2a uploads via the F helper +
   fresh signed URLs, D-H6 parity-deny (rateWorkout read-merge-write;
   ratings keys stay coach.uid until cutover), tagWorkout trigger-bump
   named.
7. **Coach `4b0a002`** — seasonPlanning swap UNDER the commit-1 pins;
   RH-10 single delete; id-based week upsert 1:1; no-stamp weeks.
8. **Coach `a6477b2`** — search meets+calendar halves: frozen
   fetch-then-filter; BSPC-origin NULL course/status → '' (frozen result
   shape); the halves' FIRST tests.
9. **Coach `bc7d314`** — importJobs + csvImport/meetResultsImport
   jobs-halves (D-H8): owner+super_admin walls; vestigial storage_path
   constants verbatim (RH-13).
10. **Functions `9c2a247`** — syncCalendar re-point (D-H3): one upsert
    onConflict('ical_uid'); ownerless rows (coach_id NULL +
    source='ical_sync'); clobber semantics preserved; created_at churn
    HEALED (named); env contract unchanged; no Deno changes.
11. **BSPC migration/h/README.md + this log** — manifests only, HARD STOP:
    meets reconcile (name+start_date, ambiguity STOPS, superset-fill,
    D-H9 rows counted by name) → entries (roster map, unresolvable STOPS,
    hundredths verbatim) → calendar (sentinel → NULL+source) → rsvps
    (dup collapse keep-latest + REPORT) → plans (ratings-key +
    templateSourceId remaps; pdf title synthesis) → season plans/weeks
    (practice_plan_ids remap) → import_jobs (coachId → profiles.id).
    File copy: owner-segment rewrite via the identity map + the D-H2a
    one-divergence tripwire restated; `imports/**` verify-empty (non-empty
    → REPORT, never auto-copy). NO backfill ran; NO file was copied.

**Cutover lines banked:** syncCalendar's first PG run post-backfill must
verify zero net new rows (same ical_uid keys); D-H5(b) parent arms ship
only with a parent calendar feature; the D-H9 backfill log counts
coach-origin meets made parent-readable, by decision name.

**Phases A–H code-side COMPLETE. Next per 04: Phase I (parent_invites +
parent-portal cutover), then J (aggregations decommission).** Firestore
reads/writes remaining in the Coach app data layer: NONE in swapped
services; parentInvites.ts is Phase I's subject. Bar at close: 835 TZ=UTC
+ 274 / 1077 / 128, BSPC tsc clean.

---

## 2026-06-10 — Phase H RATIFIED (Kevin, verbatim intent recorded) + one decision + one banked item

Checked against the landed log above as written — every claim matches the
record; nothing force-fit.

**Phase H is ratified complete code-side.** Eleven green commits verified;
all four bars green throughout; final counts BSPC 835 / pgTAP 274 / Coach
1077 / Functions 128; zero test deletions. **The two named test transforms
are ACCEPTED as conforming to the deletion norm:** (1) the cascade-delete
pin merge — subject preserved, behavior replaced by ratified schema
(RH-10); (2) the three doc-id-hashing pins re-pointed to the upsert key —
same subjects: determinism, distinctness, special characters (D-H3).
Verified on the record: **RC-3 held in 00009**; the **publication proof
sits at 22 in the same commit** that grew the set; **D-H2's single named
divergence (RH-14, a narrowing)** verified — no second divergence found in
execution; **D-H9's pins** verified — a parent reads coach-origin meets,
parent and pending principals read zero meet_entries rows, a deactivated
account reads zero meets.

**DECISION (Kevin, in words): the cutover-manifests folder remains
`migration/h/`** as the plan doc named it — this phase's manifests span
meets, files, and imports, so the phase letter is the honest umbrella. No
rename.

**BANKED (paperwork): UNIFY/01 gains a storage appendix** cataloging every
bucket, its limits, and its walls in words — **due no later than the
convergence sweep.** Joins the banked list alongside the existing items
(coach push delivery, `ai_drafts_ready` wiring, `rate_workout` RPC, the
D-H5(b) calendar parent arms, and the convergence-sweep obligations).

---

## 2026-06-10 — Phase I SCOPE (parent invites + identity) — scoping ONLY, no code; mini-plan + red-team + [DECIDE] D-I1–D-I4

Scope-before-code session per Kevin's mandate: no migrations, no service
swaps, no schema changes, no Deno changes; UNIFY paperwork commits only.
Full Phase I surface read end to end on both apps before writing this:
Coach parentInvites.ts + its two test files + the invite-parent screen +
firestore.rules; functions redeemInvite.ts + parentPortal.ts + identity.ts
+ index.ts + both test files (+ the ORIGINAL parentPortal at `b7e0c74` via
git, for the schedule field's provenance); the parent-portal Next.js app
(all five lib files + all three pages); BSPC features/auth + features/admin
+ 00001 (profiles/families/handle_new_user) + 00002 (Phase A identity,
verbatim) + 00003 (family_id NOT NULL drop); canonical 01 parent_invites /
guardianships / profiles DDL + policies; 04's four Phase I mentions; 05 §§
1/2/3/5.6/8 + the recorded OD-1/OD-2/OD-3/OD-6 + NM-1..NM-6 rulings.
**04's "Depends on A+B" is satisfied: A and B are code-side complete.**
Bar untouched this session (835 TZ=UTC + 274 / 1077 / 128); no code repo
modified.

### §1 — Inventory: the Coach-world invite surface (all of it)

**`src/services/parentInvites.ts` — 3 functions, the LAST Firestore
reads/writes in the Coach app data layer:**
- `createParentInvite(swimmerId, swimmerName, coachId, coachName)` —
  `addDoc` to `parent_invites`: `{code, swimmerId, swimmerName, coachId,
  coachName, redeemed: false, expiresAt: client-computed now+7d,
  createdAt: serverTimestamp}`. The code is `secureInviteCode()`
  (crypto-random, format `XXXX-XXXX`, alphabet `A-HJ-NP-Z2-9` — no
  I/O/0/1). **Firestore enforces NO uniqueness on code** (addDoc only).
  swimmerName/coachName are write-time denorms (the house drop-and-derive
  class). coachId arrives verbatim from `useAuth().coach.uid` (D-B7).
- `subscribeInvitesForSwimmer(swimmerId, cb)` — onSnapshot `where
  swimmerId ==`, client-side sort createdAt desc.
- `revokeInvite(inviteId)` — `updateDoc {redeemed: true}` — revoke IS
  "mark redeemed"; redeemedBy/redeemedAt stay absent (a revoked code is
  indistinguishable from a redeemed one except by the missing redeemer).
**Sole UI consumer:** `app/swimmer/invite-parent.tsx` (generate / share /
revoke; active-vs-past split computed client-side from redeemed + expiry;
share text says "Sign up at the BSPC Parent Portal and enter this code").
**Tests:** 7 in `__tests__/parentInvites.test.ts` + 3 in
`test/critical-ops/parentInvites.criticalOp.test.ts` (code shape/alphabet,
no-Math.random, 7-day expiry, payload, swimmerId query, revoke).
**Today's wall (firestore.rules L144):** `parent_invites` read+write
`isCoach()` — staff-shared, NOT per-coach; parents NEVER read the
collection ("parents redeem through Cloud Functions only").
`parents/{uid}`: own-read only, client write `false` (functions only).

**`functions/src/callable/redeemInvite.ts` — fully Firestore (UNMIGRATED;
this phase's core):** auth required → code sanity (≥8-char string) →
normalize `toUpperCase().trim()` → query `parent_invites` where code ==
AND redeemed == false, limit 1 → `not-found` ("Invalid or already redeemed
invite code") → expiry check vs now → `failed-precondition` ("This invite
code has expired") → read `parents/{uid}`: exists? already-linked →
`already-exists` ("This swimmer is already linked to your account"), else
arrayUnion(swimmerId); not exists? **CREATE the parent doc** `{uid, email
(from token, `|| ''`), displayName: email.split('@')[0], linkedSwimmerIds:
[swimmerId]}` → mark invite `{redeemed: true, redeemedBy: uid,
redeemedAt}` → return `{success, swimmerId, swimmerName}` (swimmerName
from the invite's denorm). 10 jest tests pin all of the above. **Note the
read-then-write claim:** redeemed-check and redeemed-set are two steps —
no atomic claim (Firestore-era race tolerated).

**Already migrated (NOT this phase's work, verified):**
`callable/parentPortal.ts` reads canonical swimmers (B) +
swimmer_coach_profile/goals (B) + swim_results (D) + attendance with the
D-C4 collapse (C); identity via `identity.ts resolveParentIdentity` (A) —
profiles by user_id, guardianships by guardian_profile_id, **no
account_status filter**, unknown caller → empty-profile fallback
(`displayName 'Parent', linkedSwimmerIds []`). `schedule: []` in the
swimmer payload is **pre-existing** (verified in the original at
`b7e0c74`, line 217) — the portal has NEVER returned schedule data.

**Parent-portal (Next.js):** session is Firebase email/password
(`lib/firebase.ts` + `lib/auth.ts` signIn/signUp/signOut — cutover-banked,
per the Phase A Option (b) ratification); `lib/profile.ts` getParentProfile
already reads profiles+guardianships (goes live at cutover; returns null
for unknown); `lib/parentPortal.ts` wraps the three callables including
`redeemParentInvite(code)`; the redeem UI is an invite-code input on
`dashboard/page.tsx` (≥8 chars → callable → reload). **The portal touches
NO Firestore collection directly** — 04's terrain line "Directly touches
only `posts`" is STALE (no `posts` usage exists anywhere in
parent-portal/src; correction on the record, the D-H2b accuracy class).
Code-side, the portal needs ZERO changes in Phase I: the callable
contract is frozen.

### §2 — Inventory: how a parent account comes into existence in BSPC

BSPC has **no invite surface at all** (the only "invite" hits in the repo
are meet names). Its locked product decision (BSPC CLAUDE.md, "Family
Onboarding — CHANGED from V1"): **"Open signup + admin approval (replaces
claim code system)"** — claim codes were deliberately REMOVED from BSPC's
design. The lifecycle today:
1. `features/auth/api.ts signUp` → `supabase.auth.signUp` with
   `options.data.full_name`;
2. `00001 handle_new_user()` trigger → profiles row `{role: 'family',
   account_status: 'pending', full_name: metadata || 'New User'}`;
3. pending = limited access (announcements/schedule via the
   is_active_account-class policies; nothing swimmer-specific);
4. `features/admin/api.ts approveFamily({profileId, familyName,
   swimmerData[]})` — INSERT families row → UPDATE profiles
   `{account_status: 'approved', family_id}` → **INSERT swimmers rows
   created from admin-typed data, linked by `swimmers.family_id`** (the
   OD-1 transitional model — NOT guardianships);
5. full access via the family_id RLS path. (`deactivateAccount` sets
   'deactivated'; `enforce_profile_self_update` P0-1 guard means only
   staff change account_status/family_id, only super_admin changes role —
   service-role exempt.)

**Phase A already covers:** guardianships table + select_own/staff_write
policies, all seven SECURITY DEFINER helpers (`is_my_swimmer` =
approved-guardian-only by design), the P0-1 guard, coach_groups — all
live in 00002 verbatim-from-canonical; 00003 dropped `swimmers.family_id
NOT NULL` ("a NULL family_id never matches the family RLS subquery").
**The live BSPC DB has NO parent_invites table** (no migration creates
it) and **no redeem RPC** — both are Phase I's to add. The
`migration_identity_map` scaffolding + identity backfill mapping tests
exist from A; OD-6 settled credentials as fresh-provision (no hash
import).

### §3 — What the law currently says Phase I contains (exact quotes)

- 04 phase table: "| **I** | **parent_invites + parent-portal cutover** |
  redeemInvite creates guardianships; portal callable now reads migrated
  A/B(+C/D). Parent-facing cutover. |"
- 04 per-step: "**I — parent_invites + portal.** Client: parentInvites.ts.
  Functions: `redeemInvite` (guardianship creation), `parentPortal` (now
  reads migrated data). Depends on A+B. Guardrails: functions suite +
  parent-portal build."
- 04 collection map: "| parent_invites | parentInvites.ts | redeemed by a
  function |"; function map: "| callable/redeemInvite | parent_invites,
  parents (W) — **creates the parent↔swimmer link (D-A)** |"
- 01 L216-217 (comment over the DDL): "parent_invites — [D-A] redemption
  creates a guardianship (link redeemer<->swimmer) via a SECURITY DEFINER
  RPC. coach_id authorship -> RESTRICT [P1-1]; redeemer -> SET NULL." The
  table: `code TEXT NOT NULL UNIQUE`, `swimmer_id` CASCADE, `coach_id`
  NOT NULL RESTRICT, `redeemed BOOLEAN NOT NULL DEFAULT FALSE`,
  `redeemed_by` SET NULL, `redeemed_at`, `expires_at TIMESTAMPTZ NOT
  NULL`, `created_at` — **no swimmerName/coachName denorms** (derive on
  read), + `idx_parent_invites_code/swimmer`.
- 01 L1102: "CREATE POLICY parent_invites_staff ON parent_invites FOR ALL
  TO authenticated USING (is_staff()) WITH CHECK (is_staff());"
- 01 L1090-1091 (guardianships): "writes are staff-only (or via the
  SECURITY DEFINER invite-redemption RPC). No family self-insert."
- **01 contains NO redeem-RPC DDL.** 05 §5.6 assigns it: "(design, lands
  code in I) redeemInvite SECURITY DEFINER redeem RPC. Specify and
  unit-test the RPC that, on valid invite, creates a `guardianships` row
  (never a client-side insert — D-A)." The RPC's CONTRACT is therefore
  materially unpinned → D-I2.
- Standing rulings that bind here: **OD-3** "new accounts require
  approval (BSPC's gated provisioning wins; no auto-approve)"; **OD-2**
  "redeemInvite stays Phase I with A→I run back-to-back (revisit at I)" —
  revisited in §6 below; **NM-5** auto-admin-on-first-login removed (at
  cutover); **D-A** family users never self-insert guardianships.

### §4 — Code-side-now vs cutover-time (the HARD STOP map)

**Code-side, this phase's commits (§5):** BSPC migration 00010
(parent_invites + redeem RPC) + pgTAP 013 + the 011 publication pin;
Coach parentInvites.ts swap + tests; functions redeemInvite internals →
the RPC behind the frozen callable contract + tests; (per D-I3) the
identity-gate approved-filter; migration/i manifests; paperwork.

**Cutover-time, NAMED and PARKED behind the HARD STOP — none of this is
planned into this phase's commits:**
- **The production auth provider** (Firebase → Supabase) for the Coach
  app (AuthContext swap, Option (b), already banked) and the
  parent-portal session (`lib/auth.ts` signIn/signUp/signOut +
  `lib/firebase.ts`) — live credential paths, untouchable now.
- **Account-creation flow coupling**: `handle_new_user()` stays exactly
  as-is; nothing in Phase I touches signup, password, or provisioning.
  OD-6 fresh-credential provisioning runs at cutover only.
- **The portal's post-cutover data path**: once sessions are Supabase,
  `httpsCallable` arrives with no Firebase auth — the portal must either
  re-point loads to direct RLS reads (profile.ts is the first such read,
  already staged) or retire in favor of the BSPC app. That is the
  "parent-facing cutover" of 04's Phase I row: a RUNTIME event, designed
  in the cutover mini-plan 05 §6 already mandates, not a Phase I commit.
- **NM-5 removal** (AuthContext auto-admin, still at AuthContext.tsx:62
  today) — dies with the provider swap, ratified.
- **OD-1 convergence** (approveFamily/fetchFamilySwimmers/RLS off
  family_id onto guardianships, then DROP family_id) — banked for the
  convergence sweep (D-I4 confirms timing).
- **All backfill RUNS** (parent_invites rows, guardianships from
  linkedSwimmerIds — the latter already scaffolded in A's identity
  manifest; Phase I adds the invites manifest only).

### §5 — Mini-plan: the green commits (each lands all four bars green)

1. **BSPC `00010_phase_i_parent_invites.sql` + pgTAP
   `013-parent-invites-walls.test.sql` + 011's publication pin 22 → 23 in
   the SAME commit (RH-12 class).** The table verbatim-from-canonical
   (code UNIQUE; swimmer CASCADE; coach RESTRICT; redeemer SET NULL; both
   indexes; RLS `parent_invites_staff` = today's isCoach() wall, the
   verified same-set swap class) + the `redeem_parent_invite` RPC per
   D-I2 + GRANT EXECUTE to authenticated + publication ADD. Proofs:
   columns_are; FK probes (RESTRICT blocks deleting an invite-authoring
   coach, SET NULL on redeemer, CASCADE on swimmer); code-collision
   23505; per-principal walls (family/pending/deactivated/anon read ZERO
   invites and 42501 on writes; staff full CRUD; staff-B reads staff-A's
   invites — staff-SHARED is today's parity, no D-F4 narrowing exists to
   preserve); **family self-insert into guardianships still 42501 WITH
   the RPC present (D-A)**; RPC happy path creates EXACTLY one
   guardianship + flags the invite (redeemed/redeemed_by/redeemed_at);
   re-redeem fails atomically; expired fails; unknown code fails;
   already-linked fails clean (UNIQUE intact); **account_status untouched
   by redemption (the OD-3 pin)**; case-insensitive code entry; pending
   redeemer: link lands, `is_my_swimmer` still false until approval (the
   OD-3 composition proof).
2. **Coach `parentInvites.ts` swap + tests.** House idiom: Row interface
   + SELECT with `swimmer:swimmers(first_name,last_name)` +
   `coach:profiles(full_name)` embeds (denorms derived on read);
   `createParentInvite` SIGNATURE FROZEN — swimmerName/coachName params
   become dead (kept for compat, never written; D-B7: coachId verbatim);
   insert().select('id'); code still client-generated `secureInviteCode()`
   (UNIQUE constraint now backstops collisions — surfaced via the
   screen's existing catch); expiresAt client-computed now+7d verbatim
   (parity); `subscribeInvitesForSwimmer` = eq swimmer_id + order
   created_at desc + filtered channel (stable key); `revokeInvite` = one
   UPDATE `{redeemed: true}` verbatim. Both test files re-pointed, all
   ten subjects preserved; counts rise.
3. **Functions `redeemInvite.ts` internals → the RPC, contract FROZEN.**
   Resolve caller → profile id (the identity.ts lookup), call
   `redeem_parent_invite`, map RPC errors onto the EXACT HttpsError codes
   + message strings pinned today (`not-found` / `failed-precondition` /
   `already-exists` / unauthenticated / invalid-argument), return
   `{success, swimmerId, swimmerName}` with swimmerName derived (join,
   not denorm). The parent-doc CREATE arm retires — account creation is
   `handle_new_user()`'s job since A (named, §6.1). All 10 test subjects
   preserved + new pins (RPC args, error map, status-untouched). The
   parent-portal needs NO change (frozen callable); its build is the
   guardrail if anything shared moves.
4. **(lands only if D-I3 = option (a)) identity-gate approved-filter.**
   `resolveParentIdentity` + portal `profile.ts` add the
   `account_status = 'approved'` filter with tests — the service-role
   gate then says exactly what the RLS wall says (one wall, one rule)
   before any parent ever uses either at runtime.
5. **`BSPC/ACTIVE/migration/i/README.md` (HARD-STOP header, manifest
   only) + NOTES landed log; push; report.** Invite rows: code verbatim;
   swimmerId via the roster map (unresolvable STOPS); coachId via the
   identity map (a missing author REPORTS AND STOPS — RESTRICT forbids
   orphans); redeemed/redeemedBy/redeemedAt/expiresAt/createdAt verbatim
   (redeemed_by via identity map, unmapped → REPORT, land NULL);
   pre-launch expectation: zero-to-test-only docs. Cross-reference (not
   duplicate) A's identity manifest for linkedSwimmerIds→guardianships.
   Cutover lines: the §6.1 provisioning probe; the portal data-path
   mini-plan pointer; OD-1 convergence ordering (backfill guardianships →
   switch reads/RLS → drop family_id).

Expected deltas: BSPC jest unchanged; pgTAP +25-to-35; Coach +small;
Functions +small — exact old → new per bar reported at execution.

### §6 — Red-team

**6.1 The F lesson — every do-nothing default, audited for auth-cutover
coupling (this is the phase that lesson was made for):**
- `identity.ts` unknown-caller → **empty profile, no error.** Pre-cutover
  runtime: every Firebase uid misses `profiles.user_id` → EVERY portal
  caller resolves to zero swimmers, silently. Post-cutover: a
  provisioning miss looks IDENTICAL to a parent with no links. The
  default is parity (the old `parents/{uid}` fallback) and stays — but
  the cutover runbook gains a NAMED probe: after provisioning, every
  Firestore parents-doc uid must resolve a NON-empty profile via the
  map; zero-resolves = STOP. The mask is removed by verification, not by
  code (data-layer freeze).
- Portal `profile.ts` unknown → null; dashboard renders email fallback —
  same class, same probe covers it.
- `parentPortal` `schedule: []` — pre-existing (original verified);
  absence is parity; stays empty until a portal schedule FEATURE ships
  (D-H5(b)'s calendar arms are the eventual source; banked there).
- `redeemInvite`'s `email || ''` + `displayName = email.split('@')[0]`
  (NM-4's dirty-data source) — RETIRES with the create-arm in §5.3. New
  accounts get real names from signup metadata via handle_new_user.
- AuthContext auto-admin (NM-5) — named; dies at cutover per ratified
  law; NOT a Phase I commit.
- UI guards (invite screen's `!coach` return; dashboard's <8-char gate) —
  benign, unchanged.
**6.2 No-widening, applied to every invite/identity policy:**
- parent_invites staff wall = today's isCoach() set (same-set swap, the
  G/H verified class). Parents/pending/deactivated/anon: zero rows today
  (rules deny), zero rows after (is_staff()) — pinned in 013.
- guardianships policies: UNCHANGED from A. The RPC adds a write PATH,
  not a policy — and 013 proves family self-insert still fails WITH the
  RPC installed. No principal gains read access anywhere. **No D-I block
  proposes a widening, so none cites the D-H9 precedent; if execution
  uncovers one, it arrives as a [DECIDE] naming its shipping surface,
  per D-H9's narrow-precedent condition.**
- Publication 22→23 is transport, not access (RLS walls realtime rows
  identically — the G-era finding); pin updates in the same commit.
**6.3 Absence is parity:** BSPC gets NO invite UI (it never had one — and
its design REMOVED claim codes deliberately); the portal gets no invite
LIST (parents have never read invites); revoked-vs-redeemed stays
indistinguishable (today's exact semantics); no expiry sweeper exists
today → none is built (expired codes simply fail redemption, verbatim).
**6.4 Capability follows product:** the invite feature exists and SHIPS
in both directions (Coach invite-parent screen; portal redeem input) —
migrating it grants no new capability to anyone. The redeem RPC is the
D-A-ratified mechanism for an existing product flow, not a new surface.
**6.5 OD-2 revisited (as the A-era ruling requires):** the A↔I
split-brain window (new redemptions writing Firestore linkedSwimmerIds
while reads come from guardianships) existed only under STAGED per-phase
cutovers. The project converged on one coordinated cutover with
code-first everywhere: redeemInvite is already the RPC version before any
runtime flip, and pre-launch there are zero live redemptions. **The
window is structurally gone; option (a) confirmed costless; no dual-write
bridge.** (If a staged parent-facing cutover is ever chosen instead, this
re-opens — flagged for the cutover mini-plan.)
**6.6 The wall the inventory caught (→ D-I3):** the portal callable
authorizes on guardianship EXISTENCE (service-role, no status check);
BSPC RLS authorizes on guardianship + `account_status = 'approved'`
(is_my_swimmer, by Phase A design). Post-merge, a pending-but-linked
parent reads a child's data through the portal door while the database
wall denies the same read — two rules on one wall. Today's portal
behavior is honest Coach-world parity (NM-3: no status concept existed),
so this is a RECONCILIATION decision, not a bug fix: D-I3.
**6.7 Tripwire check — do the two apps disagree about what an invite
IS?** They disagree about the ONBOARDING MODEL an invite lives in, and
per the mandate that disagreement is presented as the FIRST decision
(D-I1) rather than guessed around. Concretely: Coach-world = coach issues
a per-swimmer code against the existing roster; redemption AUTO-CREATES
the parent account (no approval concept) and self-links it. BSPC-world =
open signup + admin approval; the ADMIN creates the swimmers and the link
at approval time; claim codes deliberately removed. Canonical already
holds both write doors (staff writes + the SECURITY DEFINER RPC) and
OD-3 already settled that approval governs ACCOUNTS — what no law yet
states is how the two LINK doors compose in the unified product. That is
D-I1; D-I2/3/4 are conditional on it.

### §7 — [DECIDE] queue (verbatim blocks; nothing compressed)

**[DECIDE] D-I1 — What is an invite in the unified product? (the
model-reconciliation tripwire, decided FIRST)**
The two apps hold incompatible onboarding stories. Coach app: an invite
is a coach-issued, 7-day, per-swimmer code; redeeming it creates the
parent's account record on the spot and links it to the swimmer — the
invite IS the authorization, no approval step exists. BSPC app: there are
no codes (the design explicitly REPLACED its old claim-code system);
parents self-signup, wait pending with team-wide-only access, and an
ADMIN both approves the account and creates/links the swimmers. Canonical
already reconciles the DATA layer (both doors write `guardianships`;
parent_invites exists; D-A forbids family self-insert; OD-3 says approval
governs new accounts — no auto-approve). The unresolved PRODUCT question:
do both LINK-creation doors ship in the unified product, and how do
redemption and approval compose?
- **(a) — RECOMMENDED — both doors ship; redemption = staff-authorized
  LINK creation; approval = ACCOUNT activation; they compose.** A parent
  may exist via open signup (pending) and redeem a coach's code: the
  guardianship lands immediately (the coach's code IS staff
  authorization for the LINK), but swimmer-specific access stays dark
  until an admin approves the ACCOUNT (OD-3 honored; `is_my_swimmer`
  already enforces exactly this). The admin door (approveFamily)
  continues unchanged on its transitional family_id path until the OD-1
  convergence. Nothing widens; both apps' shipping flows keep working;
  the Coach-world auto-provisioning arm retires (its job moved to
  handle_new_user at A).
- **(b) Invites retire; admin-linking becomes the only door.** Honors
  BSPC's "replaces claim code system" doctrine team-wide, but deletes a
  SHIPPING Coach feature (screen + service + callable + portal input) —
  that is product removal, not parity, and it leaves parent_invites in
  canonical as dead law.
- **(c) Invites become the only door; admin approval auto-follows
  redemption.** The Coach model wins; redemption flips account_status →
  approved. This AMENDS ratified OD-3 ("no auto-approve") and is an
  access-granting default — it fails the F-lesson audit in the dangerous
  direction (a leaked/guessed code would mint an approved account with a
  child link, no human in the loop).
If (b) or (c), D-I2–D-I4 and §5 re-derive first.

**[DECIDE] D-I2 — The `redeem_parent_invite` RPC contract (the law 01
never wrote).** D-A pins THAT redemption creates a guardianship via a
SECURITY DEFINER RPC; no document pins HOW. Proposed contract, every
clause a pgTAP pin:
- **Name/args/grant:** `redeem_parent_invite(p_code TEXT,
  p_redeemer_profile_id UUID DEFAULT NULL)`; SECURITY DEFINER, search_path
  public; GRANT EXECUTE to authenticated (+ service_role implicitly).
- **Caller derivation (the spoof-proof clause):** redeemer :=
  `auth_profile_id()` when `auth.uid()` IS NOT NULL (end-user calls — the
  param is IGNORED; a family user can never redeem AS someone else);
  else the explicit param (service-role calls from the frozen callable —
  the enforce_profile_self_update exemption precedent). NULL both ways →
  error.
- **Atomic claim (strictly-better class, the D-H4 precedent):** `UPDATE
  parent_invites SET redeemed = true, redeemed_by = v_redeemer,
  redeemed_at = now() WHERE code = upper(trim(p_code)) AND redeemed =
  false AND expires_at > now() RETURNING ...` — one statement claims the
  code; the Firestore-era read-then-write race is unrepresentable.
  Distinct error signals preserved for the callable's frozen message map:
  unknown-or-redeemed vs expired vs already-linked.
- **Link creation:** INSERT guardianships (guardian_profile_id :=
  redeemer, swimmer_id from the claimed invite; relationship NULL,
  is_primary false — linkedSwimmerIds parity). UNIQUE collision → the
  invite is NOT consumed (already-linked errors BEFORE the claim, or the
  claim rolls back — same transaction).
- **OD-3 clause:** the RPC NEVER touches profiles.account_status (or any
  profiles column). Pinned by proof.
- **Return:** swimmer_id + the swimmer's name (derived via join — the
  callable's frozen `{success, swimmerId, swimmerName}` needs it).
Alternative (b): no defaulted param — two RPCs (user-facing zero-arg +
an internal service one). More objects, same walls; recommend (a).

**[DECIDE] D-I3 — One wall, one rule for the portal identity gate
(§6.6).** The portal callable (service-role) grants swimmer reads on
guardianship existence; the database wall (`is_my_swimmer`) requires the
guardian be APPROVED. Post-merge those disagree for pending-but-linked
parents.
- **(a) — RECOMMENDED — align the gate to the wall, now, in Phase I:**
  `resolveParentIdentity` (and portal `profile.ts`) filter to
  `account_status = 'approved'`. This is a NARROWING (the P1-8/D-H7
  accepted class), it lands before any parent ever hits either path at
  runtime (pre-launch; pre-cutover the resolver returns empty anyway),
  and it makes the service-role door and the RLS wall state one rule. A
  pending parent sees the same team-wide-only world through every door.
- **(b) Leave the gate as-is; bank a cutover line.** Defers the
  reconciliation to the riskiest moment (cutover) and leaves a standing
  two-rules wall in code — the exact drift class this project exists to
  prevent. Only argument for (b): zero code in A-migrated files this
  phase; weak against a one-line filter + tests.

**[DECIDE] D-I4 — OD-1 convergence timing vs Phase I.** Redemption
writes guardianships; BSPC's approveFamily + reads still run on
family_id (transitional). Until the banked convergence sweep, an
RPC-created link is visible to the portal but INVISIBLE to the BSPC app.
- **(a) — RECOMMENDED — convergence stays banked (its own named sweep,
  per the standing FOLLOWUP);** Phase I lands invites guardianship-only
  (the canonical primitive), the manifest restates the cutover ordering
  (backfill guardianships → switch BSPC reads/RLS → drop family_id), and
  pre-launch the visibility gap has zero users standing in it. Phase I
  stays small and single-subject.
- **(b) Pull the convergence INTO Phase I** (rewrite approveFamily +
  fetchFamilySwimmers + family RLS + their pgTAP onto guardianships now).
  Real work, real risk, in the parent app's tested core — and it belongs
  to the convergence sweep that already owns family_id's death. Only if
  Kevin wants the two-tables window closed before any cutover staging.

**FYI bundle (named, no decision needed unless objected):** (1)
publication 22→23 with the 011 pin in the same commit — the
pre-approved RH-12 class; (2) swimmerName/coachName denorms drop,
derived via embeds (the house drop-and-derive class; params stay for
frozen signatures); (3) invite codes stay client-generated
`secureInviteCode()` verbatim — canonical's UNIQUE adds a collision
backstop Firestore never had (strictly-better, named); (4) expiresAt
stays client-computed now+7d verbatim (business datum, not a
bookkeeping stamp); (5) revoke stays `redeemed := true` with no
redeemer (today's exact semantics, indistinguishability preserved); (6)
relationship/is_primary land NULL/false on RPC links (linkedSwimmerIds
parity); (7) the 04 terrain "portal touches `posts`" line corrected as
stale (§1); (8) the redeemInvite create-arm retirement (§5.3/§6.1 —
handle_new_user owns account creation since A).

**Execution blocks on D-I1–D-I4. No Phase I implementation this
session; bar untouched (835 TZ=UTC + 274 / 1077 / 128); UNIFY is the
sole repo touched.**

---

## 2026-06-10 — Phase I ratifications COMPLETE (D-I1–D-I4 + FYI bundle; Kevin, verbatim intent recorded) — execution unblocked

Each ratification was checked against its §7 block as written before
recording: all four match (D-I1 = option (a) plus a precisification rider
that DEFINES the block's "stays dark" clause rather than altering it;
D-I2 = option (a) as drafted; D-I3 = option (a) plus a load-bearing
rider; D-I4 = option (a)). Nothing force-fit; no mismatches found.

- **D-I1 RATIFIED — both doors ship and compose.** Redemption is
  staff-authorized LINK creation; approval is ACCOUNT activation. The
  coach invite feature continues; OD-3 stands untouched; the Coach-world
  auto-provisioning arm retires in favor of handle_new_user per Phase A.
  **Precisification on the record:** "dark until approval" means ZERO
  rows from every swimmer-keyed table, proven in pgTAP; it is explicitly
  acknowledged and accepted that a pending redeemer reads their own
  guardianships row (six fields, opaque swimmer UUID) under ratified
  Phase A law, and learns the swimmer's name once in the frozen callable
  response (contract parity). **Kevin explicitly DECLINES a D-I5
  amendment to `guardianships_select_own`** — the row is new state
  created by the redeemer's own action under already-ratified law; no
  widening signature is required; future narrowing remains available and
  unbanked.
- **D-I2 RATIFIED as written** — the single `redeem_parent_invite` RPC
  with the defaulted-param contract: spoof-proof caller derivation
  (end-user param IGNORED; service-role explicit param per the
  established exemption precedent), one-statement atomic claim,
  already-linked never consumes the code, distinct error signals for the
  frozen message map, redemption never touches profiles.account_status
  (pinned), return includes swimmer_id and the joined swimmer name.
- **D-I3 RATIFIED — align the gate to the wall NOW:**
  resolveParentIdentity and portal profile.ts filter to
  `account_status = 'approved'`, with tests. **Recorded as LOAD-BEARING
  for D-I1's composition:** without it the service-role door contradicts
  the RLS wall for pending-but-linked parents. Accepted narrowing class
  (P1-8/D-H7).
- **D-I4 RATIFIED — the OD-1 family_id convergence stays banked** for
  its own named sweep; Phase I lands invites guardianship-only; the
  manifest restates the cutover ordering (backfill guardianships →
  switch BSPC reads/RLS → drop family_id).
- **FYI bundle: all eight items accepted as named.** The §6.1 cutover
  verification probe is accepted as BANKED, carried by reference in
  commit 5's cutover lines.

§5 executes now, commit 4 INCLUDED per D-I3(a); all standing norms in
force: four bars green at every commit, never advance on red; one green
commit per logical change; data layer only (business logic, UI, and the
callable's external contract frozen); RC-3 — commit 1 carries the table,
the RPC, the walls, pgTAP 013, and the 011 publication pin 22→23
together; ZERO test deletions pre-declared; the tripwire stays armed
mid-execution; no backfill runs, no file copies — commit 5's manifest is
instructions-only behind its HARD-STOP header.

---

## 2026-06-10 — Phase I (parent_invites + identity gate) CODE-SIDE COMPLETE — landed per §5, five green commits

**Bar: BSPC 835 (TZ=UTC, unchanged as predicted) + tsc clean · pgTAP
274 → 316 (+42 — ABOVE the predicted +25-to-35 band: more proofs than
promised, none fewer) · Coach 1077 → 1081 (+4) · Functions 128 → 133
(+5). All four bars green at every commit; never advanced on red. ZERO
test deletions** — two subjects RE-POINTED with the mechanism they pin
(named per the H precedent, counts only rose): the redeemInvite
create-new-parent and arrayUnion subjects now pin the same first-time /
second-swimmer redemptions through the RPC path, with an explicit
`from('parents')`-never-called assertion (the parents collection left
the function entirely).

The five commits, landed in order (plus the ratification paperwork
UNIFY `c791466`):
1. **BSPC `23fb17e`** — `00010_phase_i_parent_invites.sql` + pgTAP
   `013` (42 proofs) + 011's publication pin 22 → 23 SAME commit
   (RH-12/RC-3). Table verbatim-from-canonical (code UNIQUE, coach
   RESTRICT, redeemer SET NULL, swimmer CASCADE, both indexes); staff
   wall = today's isCoach() set; `redeem_parent_invite()` per D-I2 with
   the grant hygiene the spoof-proof clause requires (EXECUTE revoked
   from PUBLIC/anon — anon also has auth.uid() NULL and could otherwise
   reach the param path; granted to authenticated + service_role;
   anon → 42501 proven). New pin classes, by name: **the OD-3
   COMPOSITION proof** (a pending redeemer's link lands; is_my_swimmer
   stays FALSE; the swimmer row reads ZERO rows; account_status
   untouched by redemption), **the D-A SIDE-DOOR proof** (family
   self-insert into guardianships still 42501 WITH the RPC installed),
   **the ATOMIC RE-REDEEM proof** (the one-statement claim consumes the
   code; a second redemption gets the same signal as an unknown code),
   the SPOOF-PROOF pair (end-user param ignored; link lands on the
   caller), the SERVICE-ROLE param path, already-linked-never-consumes,
   expired-vs-unknown distinct signals, case-insensitive entry, and the
   D-I1 precisification pin (the pending redeemer READS their own link
   row — the count probe runs AS that principal under
   guardianships_select_own, accepted state on the record).
2. **Coach `5421dfd`** — parentInvites.ts swap (the LAST Firestore
   reads/writes in the Coach data layer are gone): house idiom, frozen
   signature with the two name params dead (denorms derive via embeds),
   client code-gen + UNIQUE collision surfaced, client 7-day expiry
   verbatim, filtered channel on swimmer_id, single-UPDATE revoke
   (`redeemed := true`, no redeemer). Both test files re-pointed —
   services 7 → 10, critical-ops 5 → 5 (subjects verbatim; fixture
   contract untouched).
3. **Coach `fed26e3`** — redeemInvite callable internals → ONE
   `supabase.rpc('redeem_parent_invite')` call behind the FROZEN
   contract: same arg validation, same HttpsError codes + message
   strings (INV01 → not-found "Invalid or already redeemed invite
   code"; INV02 → failed-precondition "This invite code has expired";
   INV03 → already-exists "This swimmer is already linked to your
   account"), same return shape (swimmerName derived via join). **The
   create-arm retirement, named with its §6.1 reference:** account
   creation has been handle_new_user()'s job since Phase A; the NM-4
   dirty-data source (`email.split('@')[0]`) retires with it, and a
   caller with NO profiles row now fails LOUDLY (failed-precondition
   "No parent profile for this account" — the F-lesson direction: a
   provisioning miss never masquerades as a bad code; the §6.1 probe
   verifies the same thing fleet-wide at cutover). Tests 10 → 13.
4. **Coach `dd81a97`** — the D-I3 gate: resolveParentIdentity + portal
   profile.ts filter the LINK derivation to `account_status =
   'approved'`. Placement precisified on the record: the filter sits on
   the guardianship DERIVATION (the is_my_swimmer mirror) — the profile
   identity row still resolves (profiles_select_own parity), so a
   pending parent keeps their name/email and gets ZERO swimmers: one
   wall, one rule in BOTH directions (the gate is neither looser nor
   stricter than the wall). parent-portal typecheck clean (the 04
   guardrail). Mid-execution red, fixed before landing: the gate broke
   two portal-auth fixtures that predate account_status — fixtures
   updated + a D-I3 pending pin added in test/parentPortal-auth.test.ts
   (it lives under Coach test/ because jest ignores parent-portal/
   paths) and two D-I3 pins added in parentPortal.test.ts
   (pending dashboard = profile + zero swimmers; pending-but-linked
   detail = permission-denied).
5. **BSPC migration/i/README.md + this log.** Manifest only, HARD STOP:
   code/timestamps/redeemed verbatim; swimmerId via the roster map
   (unresolvable STOPS); coachId via the identity map (missing author
   STOPS — RESTRICT forbids orphans); redeemed_by via the identity map
   (unmapped → REPORT, land NULL); duplicate source codes REPORT AND
   STOP; the linkedSwimmerIds→guardianships work stays in A's identity
   manifest (cross-referenced, with an agreement audit line); cutover
   lines = the §6.1 probe (banked by reference), the portal data-path
   mini-plan pointer, the D-I4/OD-1 convergence ordering. NO backfill
   ran; NO file copied; NO Deno touched.

**Mid-execution flags (tripwire armed, none fired):** (1) pgTAP 013's
first run aborted on a nested data-modifying CTE — rewritten to the
house top-level-WITH-inside-results_eq idiom before anything landed;
(2) the drafted plan(43) counted the link-creation proof and the
precisification pin separately, but one test proves both (the count
probe runs AS the pending principal) — plan corrected to 42, no subject
dropped; (3) the pgTAP delta (+42) exceeds the §5 prediction (+25-35)
in the MORE-proofs direction.

**Cutover lines banked:** the §6.1 provisioning probe (every Firestore
parents-doc uid must resolve a NON-empty profile; zero-resolve = STOP);
the portal post-cutover data path is designed in the 05 §6 auth-cutover
mini-plan; the OD-1 convergence ordering restated (backfill
guardianships → switch BSPC reads/RLS → drop family_id); post-backfill
invite/guardianship agreement audit.

**Phases A–I code-side COMPLETE. Firestore reads/writes remaining in
the Coach app data layer: NONE** — parentInvites.ts was the last; what
remains on Firebase in the clients is the auth/session layer
(AuthContext + the portal's session provider, both cutover-banked by
ratified Option (b)) and Firebase Storage file serving until the
cutover copy. **Next per 04: Phase J (aggregations decommission — do
NOT migrate; recompute in PG; retire/re-point rebuildAggregations +
dashboardAggregations + onNotesWritten/onVideoSessionWritten readers).**
Bar at close: 835 TZ=UTC + 316 / 1081 / 133, BSPC tsc clean, portal
tsc clean.

---

## 2026-06-10 — Phase I RATIFIED complete code-side (Kevin, in words) + two post-hoc ratifications

Each item was checked against the landed log (previous entry) before
recording; no mismatches, nothing force-fit.

1. **Kevin ratifies Phase I COMPLETE code-side.** Five green commits
   verified (BSPC `23fb17e`; Coach `5421dfd`, `fed26e3`, `dd81a97`;
   BSPC `064aa3f` + UNIFY `68ecfe3` paperwork); final bars BSPC 835 /
   pgTAP 316 / Coach 1081 / Functions 133; RC-3 held in 00010 (table +
   RPC + walls + pgTAP 013 + publication pin 22→23 landed together, no
   exposed intermediate); publication proven at EXACTLY 23; ZERO test
   deletions, with the two named re-points accepted (the redeemInvite
   first-time and second-swimmer subjects preserved through the RPC
   path, plus the NEW never-touches-`parents` assertion); the pgTAP
   overshoot (+42 against the predicted +25-to-35 band) ACCEPTED as a
   more-proofs deviation, honestly flagged at landing.
2. **POST-HOC RATIFICATION — the anon EXECUTE revoke on
   `redeem_parent_invite` is accepted as conforming to D-I2's intent.**
   Postgres grants EXECUTE to PUBLIC by default, which contradicted the
   ratified grant list (authenticated + service_role); the revoke is a
   NARROWING to the ratified surface, proven with its own test
   (anon → 42501 in 013). Recorded as a named instance of the F-lesson
   class: a platform default that silently widens beyond ratified
   intent gets corrected in the same commit and proven, never left
   implicit. (Check note: the landed log derived the same revoke from
   the spoof-proof clause — anon also carries auth.uid() NULL and could
   otherwise reach the param path — the identical finding from the
   other direction; no mismatch.) The one-time grant audit that
   GENERALIZES this instance is commissioned in the Phase J scope
   (next entry).
3. **POST-HOC RATIFICATION — account-less callers failing LOUDLY is
   accepted as the ratified create-arm retirement landing correctly.**
   The failed-precondition signal rides the frozen HttpsError
   vocabulary (the CODE already exists in the frozen map — expired uses
   it; the MESSAGE "No parent profile for this account" is new only
   because the PATH is new: the legacy create-arm silently absorbed
   account-less callers, and that arm is what retired). Account
   creation remains handle_new_user()'s job per Phase A; the banked
   §6.1 provisioning probe verifies the same invariant fleet-wide at
   cutover.

Phase I is closed end-to-end: scoped, ratified, landed, ratified
complete. Next per 04: Phase J (aggregations decommission) — scoping
follows.

---

## 2026-06-10 — PHASE J SCOPE (aggregations decommission) — SCOPE BEFORE CODE; **TRIPWIRE FIRED — D-J1 is presented FIRST**

Scoping only. No migrations, no swaps, no schema changes, no trigger
code. This entry is the inventory (§1), the banked-trigger map with
per-trigger parity verdicts (§2), the exact 01/04 law (§3), the
one-time grant audit (§4), the numbered mini-plan (§5), the red-team
(§6), and the decision queue (§7). Execution blocks on D-J ratification.

**THE TRIPWIRE, up front:** while inventorying the aggregation READERS,
the scope sweep found that the Coach app's **UI layer (routed screens,
hooks, components) still holds ~43 live Firestore call sites in 19
files**, spanning domains whose services swapped in B/C/D/E/F/H/I —
including WRITES to write-dead collections — plus one live, routed
feature (`coach_chat`) that SETTLED #5 recorded as "dead/unimplemented."
Every phase inventory (04's per-phase "Client:" lists and every landed
log) was SERVICE-layer scoped; none of these files appears anywhere in
NOTES before this entry. The terrain disagrees with the docs, so per
the standing rule this is the first decision: **D-J1**. Two
corrections-of-record ride with it (§7 D-J1, FYI-4/FYI-5) — recorded
here, never edited in place.

### §1 Inventory — the two aggregation cloud functions + every consumer

**1a. `scheduled/rebuildAggregations` (functions/src/scheduled/rebuildAggregations.ts)**
- Trigger condition: `onSchedule('every day 04:00')` — no timeZone set
  (platform default; FYI-6). **THE ONLY PART OF THE MACHINERY THAT
  STILL FIRES.**
- Behavior: enumerates the roster from CANONICAL PG
  (`swimmers.is_active = true` — re-pointed in Phase B, NOTES:334),
  then per swimmer awaits `recomputeAttendanceAggregation(id)`,
  `recomputeSwimmerPRs(id)`, `recomputeNotesAggregation(id)` in chunks
  of 400, then the two dashboard recomputes once. All five recompute
  internals READ FIRESTORE collections that have been write-dead since
  C/D/E/F — so it rewrites stale-by-construction values daily.
- Writes: every doc listed in 1c, via the recomputes.
- Tests: `rebuildAggregations.test.ts` — 1 test (dispatch wiring:
  "recomputes dashboard docs once after per-swimmer rebuilds").

**1b. `triggers/dashboardAggregations` (functions/src/triggers/dashboardAggregations.ts)**
- NOT a deployed trigger — a recompute MODULE (04:61 calls it a
  trigger; the terrain nuance is named here, not force-fit). Its two
  exports are invoked by the four Firestore triggers (§2) and by 1a.
- `recomputeDashboardAttendanceAggregation()`: reads Firestore
  `attendance` where `practiceDate >= today−84d`, counts rows per
  practiceDate → writes `aggregations/dashboard_attendance`
  `{ countsByDate: Record<dateString, n>, updatedAt }` (merge:true).
- `recomputeDashboardActivityAggregation()`: reads four sources with
  per-source limits — attendance ordered createdAt desc LIMIT 8,
  collectionGroup notes LIMIT 5, collectionGroup times LIMIT 5,
  video_sessions where status=='review' LIMIT 5 (double-filtered
  defensively client-side) — maps each to
  `{ id: 'att-|note-|time-|video-'+docId, type:
  attendance|note|time|pr|video, text, coach, timestamp }` with text
  templates: "X checked in", `truncateNote` (60 chars + ellipsis),
  "EVENT COURSE: TIME — NEW PR!" (type 'pr' iff `isPR`), "VIDEO READY:
  N swimmer(s) analyzed" (count = taggedSwimmerIds.length), coach
  fallback 'Coach' / meet fallback 'Manual entry'; sorts desc by
  timestamp, slices 15 → writes `aggregations/dashboard_activity`
  `{ items, updatedAt }` (merge:true). Text strings embed denormalized
  swimmerName/coachName from the source docs.
- Tests: `dashboardAggregations.test.ts` — 2 tests (84-day exclusion;
  text formatting + review-only + sorting + top-15 truncation).

**1c. Write targets (Firestore `aggregations` collection) — every computed field**
- `aggregations/attendance_{swimmerId}` (from
  `recomputeAttendanceAggregation` in onAttendanceWritten.ts):
  `totalPractices`, `last30Days`, `last90Days`, `attendancePercent30`
  (= round(last30/22·100)), `attendancePercent90` (= round(last90/64
  ·100)) — **denominators HARDCODED** ("Approximate: 5 practices/week →
  ~22 per 30 days, ~64 per 90 days"), `lastPracticeDate` (max
  practiceDate string), `updatedAt`. Counts EVERY attendance row —
  written pre-merge when a Coach row meant "attended."
- `aggregations/swimmer_{swimmerId}` — ONE doc, TWO writers merging:
  `recomputeSwimmerPRs` (onTimesWritten.ts) writes `prsByEvent:
  { "<event>_<course>": { time (min wins), timeDisplay, date
  (meetDate ?? createdAt) } }` + `updatedAt`;
  `recomputeNotesAggregation` (onNotesWritten.ts) merges `noteCount`,
  `lastNoteDate` (max createdAt; field omitted when no notes) +
  `updatedAt`.
- `aggregations/dashboard_attendance`, `aggregations/dashboard_activity`
  — per 1b.

**1d. Every consumer of the computed values — both apps + portal**
- **Coach `app/(tabs)/roster.tsx`** — INLINE Firestore `onSnapshot` per
  active swimmer on BOTH per-swimmer docs (lines 73/89 — it bypasses
  the service and builds 2×N subscriptions with ignore-errors
  handlers). Renders exactly TWO fields: `attendancePercent30`
  (line 223, double-rounded — FYI-7) and the PR badge
  `getPRCount(swimmerAggs[id])` = `Object.keys(prsByEvent).length`
  (lines 226–229, the one service import it uses).
- **Coach `src/hooks/useDashboardData.ts`** → dashboard screen: via
  `services/aggregations.ts` subscribes `dashboard_attendance`
  (→ `weekAttendance` + `sparkData`; doc holds 84 days, UI renders
  SPARK_DAY_COUNT=30 — FYI-8) and `dashboard_activity`
  (→ `recentActivity`). The same hook also queries Firestore
  `audio_sessions`/`video_sessions` (status=='review') directly for
  `pendingDrafts` — an F-domain residual read (D-J1).
- **`src/services/aggregations.ts`** — the 04:54 reader service. Its
  two DASHBOARD subscriptions are consumed (above); its two PER-SWIMMER
  subscriptions (`subscribeAttendanceAggregation`,
  `subscribeSwimmerAggregation`) are DEAD EXPORTS — no importer
  anywhere except tests (roster inlines its own).
- **`src/utils/demoReadiness.ts`** — pure builders typed against the
  aggregation shapes (`buildRosterDemoFacts` consumes
  attendancePercent30 + prsByEvent count). NO app importer — test-only
  dead code (D-J6).
- **Consumed-fields summary:** of everything in 1c, the app renders
  ONLY `attendancePercent30`, `prsByEvent` (key count), `countsByDate`,
  and `items`. `totalPractices`/`last30Days`/`last90Days`/
  `lastPracticeDate`/`noteCount`/`lastNoteDate` are write-only (the
  profile screen's note count is `notes.length` from a live read, not
  the aggregate). Absence-is-parity applies (D-J3).
- **BSPC app: ZERO aggregation consumers** (verified by repo-wide
  search — only docs/manifest mentions). **Parent portal: ZERO** (the
  callable reads raw tables, 04:72). `dailyDigest` (G, PG) reads raw
  tables, not aggregations.
- **Current test coverage riding the machinery:** Functions 18
  (rebuild 1 + dashboard 2 + onAttendance 4 + onTimes 4 + onNotes 4 +
  onVideoSession 3 — per-subject list captured for the §5 deletion
  plan; all but the 2 dashboard value pins are dispatch-wiring pins).
  Coach 29 (services/aggregations 18, useDashboardData 8, demoReadiness
  3). BSPC 0. pgTAP 0 (no aggregations object exists in any migration —
  verified: `CREATE TABLE aggregations` appears in NO migration file).

### §2 The five banked aggregation triggers — each named, mapped, with its parity question ANSWERED

The banked list reconciles with the terrain EXACTLY — five banked
items, of which four are literal `onDocumentWritten` triggers and one
(dashboardAggregations) is the recompute module they share (named
nuance, §1b). The scheduled rebuild (1a) rides with it as the second of
"the two aggregation CFs" (04:106). No disagreement between bank and
terrain on the LIST itself; the tripwire (D-J1) is about the READER
side, not the trigger side.

The standing parity frame for ALL five: **none of the four Firestore
triggers has fired since its source collection went write-dead**
(attendance→C, times→D, notes→E, video_sessions→F). Today's production
semantics are "frozen snapshots, rewritten daily at 4 AM from dead
collections." The parity bar is therefore the frozen SHAPE and the
contractual semantics, not today's (broken) freshness — and the named
deltas below are corrections in already-ratified directions, never
silent.

1. **`onAttendanceWritten`** — banked Phase C, D-C1(b) (NOTES:398–403;
   07 §2:51: "defer whole to J — its product (aggregations) is retired
   in J; re-pointing it in C builds PG plumbing J deletes (RC-8)").
   Fires on `attendance/{recordId}`; recomputes the per-swimmer
   attendance doc + BOTH dashboard docs.
   **Replacement:** PG recompute over `attendance` (architecture per
   D-J2). **Values verdict: NOT identical — by ratified design.** The
   banked law (07 §2:69–71, verbatim): "J's recompute MUST be
   status-aware (`status IS NULL OR status NOT IN
   ('absent','excused','sick','injured')` — same set as the parent
   view) or attendance percentages inflate." Today's CF counts every
   row; on merged data it would count BSPC absences as attendance.
   The PG values are the corrected ones; the divergence class is named
   and was banked in C (RC-4c). Percent denominators stay hardcoded
   22/64 unless D-J4 says otherwise. **Timing verdict: NOT identical —
   strictly fresher.** Today: async trigger (dead) + 24h rebuild floor.
   Replacement: read-time-fresh (D-J2a) or same-transaction (D-J2b).
2. **`dashboardAggregations`** — banked Phase C, D-C1(b) (NOTES:400;
   07 §2:52: "defer whole to J (same reason; it spans 4 phases'
   collections)"). The shared recompute module (§1b).
   **Replacement:** the two dashboard computations in PG (D-J2 + D-J3
   shape). **Values verdict: identical EXCEPT four named items:**
   (i) the attendance arm adopts the status-aware set above;
   (ii) `type:'pr'` cannot come from an `isPR` column — canonical has
   NONE (verified: no `is_pr` in any migration; D-D5 made
   `personal_bests` the single owner of PR truth) — it derives via a
   personal_bests match, proven in pgTAP; (iii) name strings derive via
   joins, not stored denorms (D-B7 law) — text templates carry verbatim
   (FYI-9); (iv) `updatedAt` becomes DB-owned/read-time. **Timing: as
   #1.**
3. **`onTimesWritten`** — banked Phase D, D-D1 (NOTES:600–601: "defers
   whole to Phase J, extending the D-C1(b) precedent" — "the third
   aggregation trigger"). Fires on `swimmers/{sid}/times/{tid}`;
   recomputes `prsByEvent` + dashboard activity.
   **Replacement: ALREADY EXISTS.** `maintain_personal_bests()` (D-D5,
   landed in Phase D) is the un-bypassable PG owner of PR truth; J only
   re-points the reader (PR badge = count of personal_bests rows per
   swimmer). **Values verdict: identical count by construction** (both
   = distinct event+course bests) **EXCEPT two named items:** the
   doc's `timeDisplay` is derived-on-read post-D (ratified FYI), and
   the doc's `date: meetDate ?? createdAt` fallback maps to
   personal_bests' date semantics — exact column mapping named at
   execution, never assumed. **Timing verdict: BETTER than today's
   contract** — the PG trigger recomputes in the writing transaction;
   no async window at all.
4. **`onNotesWritten`** — banked Phase E (NOTES:758: "onNotesWritten +
   notes aggregations → J (the fourth aggregation trigger"). Fires on
   `swimmers/{sid}/notes/{nid}`; recomputes `noteCount`/`lastNoteDate`
   + dashboard activity.
   **Replacement:** count(*)/max(created_at) over `swimmer_notes`.
   **Values verdict: identical** (same count, same max) — with the
   absence-is-parity note that NOTHING renders these two fields today
   (§1d; D-J3 decides whether the shape carries them). The feed arm:
   note items derive from swimmer_notes (the CF's collectionGroup
   read never included group_notes — parity = swimmer_notes only,
   named). **Timing: as #1.**
5. **`onVideoSessionWritten`** — banked Phase F (NOTES:902–904:
   "subject collection now write-dead → Phase J (D-C1(b)/D-D1 family,
   the fifth aggregation trigger)"). Fires on
   `video_sessions/{sessionId}`; dashboard activity only.
   **Replacement:** the feed's video arm reads PG `video_sessions`
   where status='review'; the swimmer count comes from the
   `video_session_swimmers` junction (F landed it) instead of
   `taggedSwimmerIds[].length`. **Values verdict: identical** given
   junction-parity (F's backfill law owns that). **Timing: as #1.**

### §3 What 01 and 04 say Phase J contains — exact quotes

- 04:54 (collection table): "| aggregations | aggregations.ts
  (read-only) | **DO NOT migrate — recompute in PG** |"
- 04:106 (phase table): "| **J** | **aggregations decommission** | Do
  NOT migrate; recompute via PG triggers/jobs; retire/re-point
  rebuildAggregations + dashboardAggregations. |"
- 04:156–158 (per-step): "**J — aggregations.** No data migration.
  Recompute via PG (unbuilt triggers/jobs); point `aggregations.ts`
  reads at PG-computed views; retire the two aggregation CFs."
- 04:172 (backfill table): "| Aggregations: recompute in PG (NOT
  migrated) | **J** |"
- 01:722–730: "-- AGGREGATIONS — [SCOPE] read-model store; staff read;
  writes by service role/ triggers only. [P2-5] DO NOT migrate rows;
  recompute post-migration. CREATE TABLE aggregations ( key TEXT
  PRIMARY KEY, kind TEXT NOT NULL, payload JSONB NOT NULL, updated_at
  TIMESTAMPTZ NOT NULL DEFAULT NOW() );" — plus 01:1066 RLS-enable and
  01:1182 `aggregations_select_staff` (staff SELECT; "writes: service
  role only").
- **The docs DISAGREE on the architecture:** 01 pins a materialized
  JSONB doc-store TABLE; 04 §156 says "point reads at **PG-computed
  views**." Both are ratified text. Whichever way D-J2 goes, the loser
  is amended by name (the A3/D-D5 canonical-amendment precedent). No
  migration ever created the 01 table, so there is no schema to roll
  back either way.
- Standing banked constraints that bind J: the D-C1(b) cutover
  checklist line (NOTES:401–403: attendance data cutover requires
  C+G+J reader code landed); "Phase J recompute must be status-aware
  (07 §2)" (NOTES:539); rebuild's roster enumeration already canonical
  (NOTES:334).

### §4 ONE-TIME GRANT AUDIT (read-only; the D-I2 anon-revoke, generalized)

Method: live query of the running local DB (migrations 00001–00010
applied) over `pg_proc` — every SECURITY DEFINER function in `public`,
its full ACL (NULL ACL = Postgres default = PUBLIC EXECUTE), plus
explicit `has_function_privilege` checks for anon/authenticated.
17 functions. `=X/postgres` in an ACL is the PUBLIC grant.

**Already narrowed (conform — the ratified pattern):**
`redeem_parent_invite` (anon=false; the Phase I revoke),
`approve_session_draft` (anon=false; authenticated+service_role),
`swim_results_recompute_pb` (service_role ONLY),
`upsert_rule_notification` (service_role ONLY).

**FINDING GA-1 — `attendance_check_in(p_swimmer_ids uuid[], …)`:
anon=true via a surviving PUBLIC default.** ACL =
`=X/postgres ; postgres ; authenticated ; service_role` — the explicit
grants were added but Postgres's default PUBLIC EXECUTE was never
revoked, so **anon can EXECUTE a SECURITY DEFINER WRITE RPC**. This
contradicts canonical intent exactly the way D-I2's default did (D-C2
ratified an authenticated client RPC; nothing ratified anon
reachability). Whether its internal guards would stop an anon caller is
NOT relied on — the ratified posture is grant-level denial. **Proposed
closure (FYI class, mechanically safe):** `REVOKE EXECUTE … FROM
PUBLIC, anon;` + a pgTAP anon→42501 proof, landing inside J's
migration commit. Mechanically safe because every known caller is
authenticated (both apps) or service_role; the F-lesson class instance
is named, matching the Phase I post-hoc precedent.

**FINDING GA-2 (inert, hygiene):** the four SECURITY DEFINER
trigger-functions (`attendance_derive_practice_date`,
`enforce_profile_self_update`, `handle_new_user`,
`maintain_personal_bests`) all carry PUBLIC/anon EXECUTE. Inert by
construction — Postgres refuses direct invocation of
trigger-returning functions, and trigger firing does not consult the
caller's EXECUTE — but the uniform house rule ("no PUBLIC EXECUTE on
any SECURITY DEFINER object") argues for revoking in the same hygiene
statement. Proposed as part of GA-1's closure block; zero behavior
change.

**CONFORMING (no action, rationale named):** the helper predicates
(`auth_profile_id`, `is_active_account`, `is_my_profile`,
`is_my_swimmer`, `is_staff`, `is_super_admin`, `my_family_ids`,
`my_swimmer_groups`) are broadly granted INCLUDING explicit anon — and
that IS canonical intent: they are RLS-policy plumbing that any
policy-evaluating role must be able to execute, and under an anon
context they yield NULL/false/empty (no information, no capability
beyond what RLS already grants). Revoking could break policy
evaluation; explicitly NOT proposed.

Nothing in the audit is ambiguous enough to need a [DECIDE]; GA-1/GA-2
ride as FYI items (§7) per the "mechanically safe narrowings" rule.

### §5 The numbered mini-plan (BLOCKS on §7; baseline bar 835 TZ=UTC + 316 / 1081 / 133)

Drafted against the recommended options (D-J2(a) views, D-J3(a) full
shape, D-J1(a) J/K split); commits renumber mechanically if Kevin picks
otherwise. All standing norms apply: four bars green at every commit,
never advance on red; one green commit per logical change; data layer
only; RC-3; the tripwire stays armed mid-execution.

1. **BSPC `00011_phase_j_aggregations.sql` + pgTAP `014` (one commit,
   RC-3).** Four staff-gated views (each carries an explicit
   `is_staff()` arm — the no-widening wall, §6.3): per-swimmer
   attendance aggregate (status-aware filter VERBATIM from 07 §2;
   22/64 denominators verbatim per D-J4), per-swimmer PR/notes
   aggregate (personal_bests + swimmer_notes), dashboard attendance
   (84-day counts by practice_date), dashboard activity (4-arm UNION
   with per-arm limits 8/5/5/5, joined name strings, truncateNote-60
   semantics, personal_bests-derived 'pr' type, review-only video arm
   + junction count, ORDER BY timestamp DESC LIMIT 15). PLUS the GA-1
   + GA-2 grant closure block. pgTAP 014 proves: per-view staff values
   on fixtures (the recompute-truth successors to the retired CF value
   pins), per-view family/pending/anon ZERO rows, the status-aware
   proof (absent/excused/sick/injured rows do not count), the
   'pr'-derivation proof, attendance_check_in anon→42501 (GA-1), and
   publication membership UNTOUCHED at EXACTLY 23 (views join no
   publication; if a needed source table proves absent from the
   publication at execution, the addition is an RH-12 same-commit
   23→24 pin — named contingency, not expected). **Expected: pgTAP
   +14-to-22; other bars unchanged.**
2. **Coach `aggregations.ts` swap + the aggregation readers re-point
   (one commit).** Service keeps its FROZEN exported signatures/types;
   house idiom (channel on source tables + full re-fetch — the
   importJobs pattern; views can't join publications). roster.tsx's
   2×N inline Firestore subscriptions collapse INTO the service's
   per-swimmer subscriptions (the dead exports come back to life as
   the only path — 04:54's "aggregations.ts (read-only)" finally true).
   useDashboardData re-points its two dashboard subscriptions (already
   via the service) and its `pendingDrafts` queries onto the EXISTING
   PG audio.ts/video.ts services (the F-domain catch-up rider, D-J1 —
   same query shape, no new capability). Test transforms: services 18
   → house supabase mock (subjects preserved), hook 8 re-pointed,
   roster tests follow the screen. **Expected: Coach 1081 → 1081±6;
   others unchanged.**
3. **Functions retirement (one commit).** Delete the four trigger
   modules + `scheduled/rebuildAggregations.ts` +
   `triggers/dashboardAggregations.ts`; index.ts drops the five
   exports (its Phase F comment block updates — the machinery it
   pointed at Phase J is now gone). **NAMED TEST DELETIONS,
   pre-declared per the deletion norm (the Functions bar goes NET
   NEGATIVE for the first time — flagged here, honestly):** all 18
   tests in the six files named in §1 retire WITH their subjects; 16
   are dispatch-wiring pins whose mechanism (CF dispatch) ceases to
   exist — successor: the pgTAP 014 value proofs own recompute truth;
   the 2 dashboard value pins re-point BY NAME to pgTAP 014's 84-day
   window proof and activity-formatting/top-15 proof + the commit-2
   service mapping tests. **Expected: Functions 133 → ~115; others
   unchanged.**
4. **Dead-code sweep (one commit, membership per D-J6):** delete
   `useSwimmer.ts`, `useMeetDetails.ts`, `demoReadiness.ts` (+ their
   test files — named deletions: 8 + ~5 + 3 subjects whose features
   were never mounted; no successors exist or are needed for code with
   zero importers), the stores' type-only `firebase/firestore`
   `Unsubscribe` imports → local type. **Expected: Coach net negative
   by the named amounts.**
5. **`migration/j/README.md` + NOTES landed log (one commit).**
   Manifest is INSTRUCTIONS-ONLY behind the standing HARD-STOP header
   and is mostly a null-manifest: aggregations rows DO NOT MIGRATE
   (04:172, 01 P2-5 — ratified twice); no rows copied, no backfill
   exists; first PG read is correct by construction. Cutover lines:
   the D-C1(b) checklist line ("attendance data cutover requires
   C+G+J reader code landed") is SATISFIED as of commit 2 — recorded;
   the stale Firestore `aggregations` docs (and every write-dead
   collection) die with the Firebase project per the 06 runbook
   decommission step — deletion is runbook territory, NOTHING here
   runs; coach_chat's disposition line per D-J7.

Zero test deletions is NOT the posture this phase — the deletion norm's
named-deletion-with-successors arm is, with every file and count
pre-declared above. Any deletion NOT named here is a flagged deviation.

### §6 Red-team

- **6.1 Absence-is-parity.** (i) The entire machinery is FROZEN today —
  the four triggers haven't fired since C/D/E/F; the 4 AM rebuild
  rewrites yesterday's stale values from dead collections. Nothing
  Kevin's users have ever relied on breaks; the parity bar is shape +
  contract, and freshness only improves. (ii) Six of the computed
  fields are write-only (§1d) — D-J3 decides whether shape parity
  carries them; nothing renders them either way. (iii) The dead
  exports, dead hooks (`useSwimmer`, `useMeetDetails` — zero importers)
  and test-only `demoReadiness` are absence-is-parity deletions
  (D-J6). (iv) The aggregation that "never actually worked" in the
  audit sense: dashboard freshness post-C was already 24h-stale by
  design; no probe asserts freshness, so none is owed.
- **6.2 The F lesson — every default and do-nothing path, audited.**
  The triggers' silent `if (!swimmerId) return` and the rebuild's
  silent daily stale overwrite both LOOK like success while doing
  nothing real — the retirement (not re-pointing) of all five is the
  F-lesson answer: no do-nothing path survives to mask a recompute
  miss. roster.tsx's ignore-errors snapshot handlers silently render
  empty badges on permission failure — the commit-2 re-point inherits
  the house idiom's surfaced errors instead. merge:true partial-field
  writes disappear with the docs (a view cannot half-exist). The
  jest-mock blindness class (RC-7) is what hid the whole D-J1 terrain:
  screens mocked Firestore, services mocked PG, and the green bar
  never crossed the boundary — pgTAP 014 + the swapped service mocks
  are the structural answer, and D-J1's inventory is the residue made
  loud. GA-1 is the F-lesson at the grant layer (a platform default
  silently wider than ratified intent).
- **6.3 No-widening (D-H9 cited as the precedent gate).** Today's
  Firestore rule: `aggregations` read=isCoach, write=false (rules:111–
  114). The PG surface preserves it exactly: every J view carries an
  explicit `is_staff()` arm, family/pending/anon proven to ZERO rows in
  pgTAP 014 — security_invoker alone would have WIDENED (a parent
  computing partial aggregates over their own visible rows is a NEW
  capability nothing ratified; declined by construction). Parents/
  portal gain nothing (the portal has never read aggregations and still
  won't). No new fields; the only widening-shaped idea on the table
  (real schedule-derived denominators, D-J4(b)) is presented to be
  DECLINED per the no-widening doctrine unless Kevin rules otherwise —
  no D-H9-class precedent citation supports it, so per the standing
  rule it cannot ship this phase. The pendingDrafts rider re-points an
  EXISTING read through EXISTING services — query shape identical, no
  capability change.
- **6.4 Ordering/atomicity vs today's eventual consistency — stated
  honestly.** TODAY (contractual): async trigger fan-out; two
  concurrent writes race their full recomputes last-write-wins per
  doc; the 4 AM rebuild can interleave with triggers; merge:true
  interleaves per-field; readers can see values from BEFORE their own
  write (eventual). TODAY (actual): permanently stale, refreshed daily.
  D-J2(a) VIEWS: no materialization → no write ordering AT ALL to get
  wrong; every read is one consistent MVCC snapshot; semantics move
  from eventually-consistent-or-frozen to read-time-fresh. NAMED
  consequence: a dashboard read mid-bulk-import now sees the half-
  loaded live state rather than yesterday's snapshot — accepted
  pre-launch, recorded. D-J2(b) TABLE+TRIGGERS: same-transaction
  recompute is STRONGER ordering than today, but reintroduces
  concurrent-recompute racing that needs the D-D5 advisory-lock
  discipline, plus a staleness class whenever a trigger path is
  missed — the exact bug family J exists to retire. This asymmetry is
  why §5 drafts against (a).
- **6.5 Stale aggregated values sitting in Firestore at cutover —
  manifest territory, parked.** The `aggregations` docs hold the
  frozen pre-C/D/E/F numbers forever; they DO NOT MIGRATE (ratified
  04:172 + 01 P2-5), nothing reads them after commit 2, and they die
  with the Firebase project at the 06-runbook decommission step. The
  same fate covers every write-dead collection AND whatever sits in
  `coach_chat` (D-J7's data-loss line is named there). NOTHING in
  Phase J copies, deletes, or runs against either store — **behind
  the HARD STOP, always.**
- **6.6 COPPA/PII.** Activity-feed text embeds minors' names; the
  surface stays staff-only (6.3) and the PG derivation removes stored
  denorm copies. Fixtures stay synthetic (house law). No real data was
  read for this scope; coach_chat contents were not opened.
- **6.7 RC-8 echo.** J builds nothing a later phase deletes: the
  views/grants are end-state; Phase K (if D-J1(a)) deletes only UI
  residue, never J's work.

### §7 [DECIDE] — Phase J decision queue (awaiting Kevin; compress nothing)

**D-J1 — THE TRIPWIRE (decide first): the UI layer still has a foot in
Firestore, and the docs say otherwise.** The classified inventory
(file:line = live Firestore call sites; NONE of these files appears in
any phase inventory or landed log before this entry):
- **(i) Aggregation readers — J-proper either way:**
  services/aggregations.ts (4 subs); roster.tsx:73,89 (inline 2×N) +
  :223,:226–229 (rendered fields); useDashboardData.ts:62,95 (via
  service) and :74,:81 (pendingDrafts on audio_sessions/
  video_sessions — F-domain data inside the J-target hook).
- **(ii) Write-dead-domain readers/WRITERS missed by the service-
  scoped sweeps (split-brain live TODAY, hidden by mocks — concrete
  examples):** app/swimmer/new.tsx:76 **addDoc(swimmers)** — creating
  a swimmer writes a FIRESTORE doc no PG reader will ever see;
  app/swimmer/[id].tsx:970 addDoc(times) + :116,:134 deleteDoc(notes/
  times) while the SAME screen's add-note path writes PG via
  services/notes.addNote — a coach adds a note (PG write) and the
  screen's list (Firestore read via useSwimmerData) never shows it;
  app/swimmer/edit.tsx:69,117 getDoc/updateDoc(swimmers);
  app/swimmer/standards.tsx:52,59 (swimmers doc + times);
  app/swimmer/invite-parent.tsx:39 (swimmers doc — one day after
  Phase I swapped the invites service, the screen's header still
  subscribes Firestore); app/meet/[id].tsx:38 + useMeetDetails.ts:36
  (meets — H); app/calendar/event/[id].tsx:35 (calendar_events — H);
  app/video/[id].tsx:57, SwimmerVideoClips.tsx:33,
  VideoComparison.tsx:45,61,70 (video_sessions + drafts subcollections
  — F); SwimmerTimeline.tsx:66,74 (notes + times subcollections — D/E;
  mounted by the profile screen); useSwimmerData.ts:49,61,77 (swimmers
  + notes + times); useSwimmer.ts:23 (dead hook).
- **(iii) `coaches`-collection surfaces — the auth/session family:**
  AuthContext.tsx:48,74,120 (ALREADY cutover-banked by ratified Option
  (b)); app/admin.tsx:39,59,73 (approval queue reads/WRITES coaches);
  app/(tabs)/settings.tsx:46 (updateDoc coaches). admin/settings were
  never explicitly banked — they ride the same Firebase-auth account
  store AuthContext owns, so the COHERENT reading is they belong to
  the same bank; D-J1 makes that explicit instead of implicit.
- **(iv) `coach_chat`** — D-J7, its own block.
- **Corrections of record (ride with whatever option is picked):** the
  Phase I landed-log line "Firestore reads/writes remaining in the
  Coach app data layer: NONE — parentInvites.ts was the last" was an
  OVERCLAIM — true for src/services EXCEPT aggregations.ts (which 04
  banks to J in the same breath), and false for the app at large (this
  inventory). The session memory file carries the same overclaim and
  is corrected alongside. Append-only correction; nothing edited in
  place.
  **Options:**
  (a) **[RECOMMEND]** Phase J keeps its 04 charter PLUS the aggregation-
  adjacent readers in (i) (roster + dashboard surfaces whole, including
  the pendingDrafts rider — they ARE the aggregation consumers); the
  rest of (ii) becomes **PHASE K — UI residual sweep**, a NEW NAMED
  phase with its own scope-before-code round, starting from this
  file:line list (re-point screens/hooks/components onto the EXISTING
  swapped services — no new services, no new capability, the
  no-widening doctrine governing); (iii) is recorded as explicitly
  banked-with-auth; one-service-at-a-time stays intact.
  (b) Widen J to swallow all 19 files now (one phase, but it spans
  seven domains and dwarfs the aggregation work — violates the
  one-service-at-a-time norm that has held since A).
  (c) Leave (ii) until cutover and rely on the manifest (NAMED RISK,
  not recommended: the split-brain writes above are live bugs TODAY —
  pre-launch and test-data-only, which is why this is survivable, but
  every day they stand is a day a colleague's manual test writes data
  into a store that dies at cutover).

**D-J2 — the recompute architecture (01 and 04 disagree; the loser is
amended by name).**
  (a) **[RECOMMEND] PG-computed VIEWS, staff-gated, compute-on-read**
  — 04 §156's own words; the analytics.ts precedent (it already
  computes attendance percentages from PG with the D-C5 filter);
  no staleness class, no ordering machinery, no publication change;
  canonical amendment: 01's unbuilt `aggregations` JSONB table +
  `aggregations_select_staff` policy are RETIRED from canonical (a
  narrowing — the table was never created by any migration).
  (b) Build 01's `aggregations` table (key/kind/payload JSONB) +
  PG triggers/jobs maintaining it — preserves the materialized
  read-model and enables realtime-on-the-table, at the cost of trigger
  machinery + advisory-lock discipline (D-D5 class), a reintroduced
  staleness/missed-path class, publication 23→24 (RH-12 pin), and a
  JSONB payload no pgTAP column-proof can pin as tightly; canonical
  amendment: 04 §156's "views" wording updates.

**D-J3 — view/result shape.**
  (a) **[RECOMMEND] Full legacy doc shape** — every §1c field computed
  (including the six write-only ones; each is one cheap aggregate
  expression), service exported types FROZEN, zero type ripple.
  (b) Consumed-fields-only (attendancePercent30, PR count, countsByDate,
  items) — smaller SQL, but the service types narrow and
  absence-is-parity is being used to change a frozen interface, which
  the freeze norm exists to prevent.

**D-J4 — the attendance-percent denominators.**
  (a) **[RECOMMEND] Hardcoded 22/64 VERBATIM** in the view, comment
  carried ("Approximate: 5 practices/week") — parity; the honest fake
  stays an honest fake.
  (b) Derive real denominators from the calendar/schedule — WIDENING
  (new semantics nothing ratified; no D-H9-class citation exists);
  presented only to be declined and BANKED as a named post-cutover
  product item.

**D-J5 — the retirement + named-deletion plan.** Ratify §5 commit 3 as
written: all five CF modules + the scheduled rebuild retire in one
commit; the 18 named Functions tests delete WITH their subjects under
the deletion norm (successors named per file in §5/§1); the Functions
bar going net-negative (133 → ~115) is accepted as the honest count.
The alternative — keeping any CF alive against PG — re-creates the
RC-8 plumbing-J-deletes problem in J itself and is not offered.

**D-J6 — dead-code sweep membership (each item strikeable):**
useSwimmer.ts + its test file; useMeetDetails.ts + its test file;
demoReadiness.ts + its 3 tests; the stores' type-only Unsubscribe
imports. (a) **[RECOMMEND]** all four items land as §5 commit 4 (J is
already holding the aggregation-reader scalpel; these are its dead
siblings, all zero-importer-verified). (b) Park them to Phase K's
list.

**D-J7 — `coach_chat` / app/messages.tsx (SETTLED #5's premise was
wrong; its intent needs an explicit call).** The record: SETTLED #5
(NOTES:96–98) dropped coach_chat as "dead/unimplemented… Kevin
confirmed no near-term plan for messaging"; the H manifest repeats
"nothing reads them" (migration/h/README:82–83). The terrain:
app/messages.tsx is a FULL live CRUD screen on `coach_chat` (read/
send/edit/delete, coach-only rules), routed from the dashboard
(app/(tabs)/index.tsx:163), and it has existed since 2026-04-02 —
the premise was wrong WHEN SETTLED, not drifted-wrong since. The
product INTENT (no messaging investment) was still Kevin's ratified
call. Options:
  (a) **[RECOMMEND] Honor SETTLED #5's intent, now with true facts:**
  the messages screen + its dashboard entry point RETIRE (a Phase K
  deletion, since it is UI-residue work, not aggregations); coach_chat
  gets no PG home; whatever test chatter sits in the collection dies
  with Firestore at cutover (named data loss, pre-launch, zero minors'
  data expected in a coach-to-coach channel — contents not read this
  scope). Correction-of-record lands in the K landed log + the 06
  runbook line.
  (b) Keep the feature: coach_chat needs a canonical table + RLS + a
  service + a swap mini-round — this UN-DOES a settled decision and
  needs its own scope round; nothing about it is Phase J.
  (c) Leave it live-on-Firestore until cutover and decide in the 05/06
  auth-cutover planning (it would be the LAST live Firestore write
  surface standing after K — named).

**FYI bundle (accept-as-named unless struck):**
1. **GA-1** — attendance_check_in `REVOKE … FROM PUBLIC, anon` +
   pgTAP anon→42501 proof, inside J commit 1 (the D-I2/F-lesson class,
   mechanically safe, callers verified authenticated/service-role).
2. **GA-2** — the four inert PUBLIC grants on SECURITY DEFINER
   trigger-functions revoke in the same hygiene block (zero behavior
   change; uniform rule).
3. **GA-3** — helper-predicate broad grants CONFORM (policy plumbing;
   anon context yields nothing); no action, rationale recorded in §4.
4. The Phase I landed-log "NONE" overclaim and 5. the session-memory
   echo of it: corrected by D-J1's inventory, append-only (no
   edit-in-place).
6. rebuild's `every day 04:00` has no timeZone (platform default) —
   moot at retirement, named for completeness.
7. roster double-rounds attendancePercent30 (CF rounds, UI rounds) —
   harmless, carries as-is.
8. dashboard_attendance holds 84 days, the UI renders 30
   (SPARK_DAY_COUNT) — the view keeps 84 (shape parity, D-J3(a)).
9. Activity item id prefixes (`att-`/`note-`/`time-`/`video-`) and the
   text templates (truncateNote-60, 'Manual entry', 'VIDEO READY: N
   swimmer(s) analyzed', '— NEW PR!') carry VERBATIM into the PG
   mapping.
10. `type:'pr'` derives via personal_bests (no is_pr column exists in
    canonical — D-D5 owns PR truth); proven in pgTAP 014.
11. Publication stays EXACTLY 23 (views join no publication); any
    source-table addition discovered at execution is an RH-12
    same-commit pin (named contingency, not expected — attendance,
    swim_results, swimmer_notes, video_sessions, audio_sessions all
    verified present in 011's membership list).
12. The D-C1(b) cutover checklist line is SATISFIED at J commit 2;
    the manifest records it.

**Execution blocks on D-J1–D-J7. No Phase J implementation this
session; bar untouched (835 TZ=UTC + 316 / 1081 / 133); UNIFY is the
sole repo touched (ratification entry + this scope).**

---

## 2026-06-10 — PHASE J RATIFICATION (Kevin, in words) — D-J1/2/3/4/6/7 RATIFIED; D-J5 HELD OPEN ON EVIDENCE (the 18-row successor table, below); FYI 1–12 accepted; the 01 amendment APPLIED

Docs-only round: this entry plus the ratified 01 amendment are the
only changes anywhere; no application code, no migrations, no test
changes; bars untouched by construction (835 TZ=UTC + 316 / 1081 /
133). Each ruling was checked against its [DECIDE] block before
recording — no ruling mismatches its block. Two precision items
surfaced and are NAMED in place rather than force-fit: the D-J1 rider
arithmetic is decomposed (the "19" needs one qualifier), and §5's
"~5" useMeetDetails estimate was WRONG (actual: 7) — flagged inside
the D-J6 record.

**D-J1 RATIFIED — option (a), the J/K split.** Phase J keeps its 04
charter PLUS the aggregation-adjacent readers in (i): the roster and
dashboard surfaces whole, including the pendingDrafts re-point onto
the EXISTING PG audio.ts/video.ts services (the F-domain catch-up
rider — same query shape, no new capability). Everything else in the
write-dead-domain inventory becomes **PHASE K — UI RESIDUAL SWEEP**,
a new named phase with its own scope-before-code round, re-pointing
screens/hooks/components onto the EXISTING swapped services only —
no new services, no new capability, the no-widening doctrine
governing. The coaches-collection surfaces (AuthContext.tsx,
app/admin.tsx, app/(tabs)/settings.tsx) are recorded as EXPLICITLY
banked with the auth cutover (the ratified Option (b) bank) —
implicit no longer. The D-J1 file:line inventory (previous entry,
§7 D-J1) is DESIGNATED the named NOTES artifact Phase K scopes from.
The corrections of record (the Phase I landed-log "NONE" overclaim
and its session-memory echo) are ACCEPTED as append-only corrections.
  **RIDER — the arithmetic, pinned.** Kevin's ruling, verbatim: "the
  entry enumerates 21 files; the actionable Phase K count is 19
  because useSwimmer.ts and useMeetDetails.ts are zero-importer dead
  hooks deleted in J commit 4 under D-J6." Recorded — with the
  decomposition stated explicitly so the 19 is never conflated with
  Phase K's own work list: 21 enumerated = 3 J-proper
  aggregation-reader files in (i) + 14 write-dead-domain files in
  (ii) + 3 auth-banked files in (iii) + 1 coach_chat file in (iv).
  The tripwire headline's "19" = 21 minus the two dead hooks (which
  J deletes, not K). Phase K's own work list as ratified = the 12
  remaining (ii) files to re-point + the messages.tsx retirement per
  D-J7 = 13 files; K's scope round starts from the full 21-file
  artifact regardless, so nothing rides on the label.

**D-J2 RATIFIED — option (a): Postgres-computed VIEWS, staff-gated,
compute-on-read.** The canonical amendment is RATIFIED AND APPLIED
this round: 01's unbuilt `aggregations` JSONB table (was 01:725–730),
its RLS-enable line (was 01:1066), and `aggregations_select_staff`
(was 01:1182) are RETIRED from canonical — a narrowing; no migration
ever created any of them (§1d's check: `CREATE TABLE aggregations`
appears in no migration file). The [P2-5] law (DO NOT migrate rows;
recompute post-migration) SURVIVES verbatim in the banner — it is
the law the views implement. 04 §156's "PG-computed views" is now
the single architecture on the books; the §3 docs-disagreement is
resolved by name. Amendment mechanics: the e71050a in-repo precedent
followed exactly — in-place edits with dated [D-J2, ratified
2026-06-10] bracket annotations at each retired site, landing in the
SAME commit as this ratification entry (01 has no amendments
appendix and none was needed).

**D-J3 RATIFIED — option (a): full legacy doc shape.** Every §1c
field is computed, including the six write-only ones
(totalPractices, last30Days, last90Days, lastPracticeDate, noteCount,
lastNoteDate); service exported types stay FROZEN; zero type ripple.
Absence-is-parity is not a license to narrow a frozen interface.

**D-J4 RATIFIED — option (a): the denominators stay the honest
fake.** 22 and 64 hardcoded VERBATIM in the view, the "Approximate:
5 practices/week" comment carried. Option (b) (schedule-derived real
denominators) is DECLINED as a widening with no D-H9-class citation
— and BANKED: **real attendance denominators (schedule-derived)**
joins the named post-cutover product line items (alongside push
delivery, ai_drafts_ready, and the parent-calendar/RSVP arms).

**D-J5 NOT RATIFIED THIS ROUND — held open deliberately; no mismatch
with the block.** This would be the FIRST test-count drop in project
history, and ratification happens only off a literal per-deletion
successor table. The §5 commit-3 plan is otherwise UNOBJECTED.
Recorded PENDING-ON-EVIDENCE; the evidence follows immediately
below, read from the six test files this round. With the counts now
pinned, commit 3's expectation de-tildes: Functions 133 − 18 = 115
EXACTLY.

### D-J5 EVIDENCE — the literal successor table (18 rows, one per test; it(...) titles transcribed exactly from the files; nothing paraphrased)

All six files live in BSPC-Coach-App `functions/src/__tests__/`.
Successor key — names bind execution: **P-ATT / P-PRNOTES /
P-DASHATT / P-DASHACT** = pgTAP 014's four per-view staff-value
proofs pre-declared in §5 commit 1 (P-ATT carries the status-aware
negative proof + the verbatim 22/64 denominators; P-PRNOTES =
personal_bests + swimmer_notes aggregate values; P-DASHATT = the
84-day window proof; P-DASHACT = the activity formatting proof —
text templates verbatim per FYI-9, 'pr' derivation per FYI-10,
per-arm limits 8/5/5/5, review-only video arm + junction count,
ORDER BY timestamp DESC LIMIT 15). **SVC-MAP** = J commit 2's
aggregations.ts mapping tests (subjects preserved through the swap).
Ordering law (RC-8 echo): the successors land in commits 1–2; the
deletions land in commit 3 — successor-before-deletion holds by
commit order.

Row format: file / exact it(...) title / class / named successor.

1. rebuildAggregations.test.ts / 'recomputes dashboard docs once
   after per-swimmer rebuilds' / dispatch-wiring pin (scheduler
   fan-out) / retires with the scheduler; recompute truth → P-ATT +
   P-PRNOTES + P-DASHATT + P-DASHACT (views compute at read time —
   no dispatch left to prove).
2. dashboardAggregations.test.ts / 'recomputes dashboard attendance
   history and excludes records older than 84 days' / VALUE pin /
   P-DASHATT + SVC-MAP (countsByDate shape).
3. dashboardAggregations.test.ts / 'recomputes dashboard activity
   with preserved text formatting, review-only videos, sorting, and
   top-15 truncation' / VALUE pin / P-DASHACT + SVC-MAP (items
   shape).
4. onAttendanceWritten.test.ts / 'dispatches per-swimmer and
   dashboard recomputes when attendance is created' /
   dispatch-wiring pin, carries a value fragment (totalPractices,
   merge:true) / P-ATT (totalPractices computed in the full shape
   per D-J3(a)); the dispatch mechanism ceases to exist.
5. onAttendanceWritten.test.ts / 'dispatches using the after swimmer
   id when attendance is updated' / dispatch-wiring pin (event
   routing) / P-ATT — the view keys rows by swimmer_id from the
   table itself; there is no event payload to route.
6. onAttendanceWritten.test.ts / 'dispatches using the before
   swimmer id when attendance is deleted' / dispatch-wiring pin
   (event routing) / P-ATT — a delete is an absent row at read time.
7. onAttendanceWritten.test.ts / 'does not dispatch when no swimmer
   id is present' / dispatch-wiring pin (the silent do-nothing guard
   — the §6.2 F-lesson path) / the guarded path RETIRES with the
   mechanism; a view has no do-nothing analogue (it computes from
   rows); recompute truth → P-ATT. Named as the deletion of an
   F-lesson liability, not a lost proof.
8. onTimesWritten.test.ts / 'dispatches swimmer PR and activity
   recomputes when a PR time is created' / dispatch-wiring pin,
   carries a value fragment (prsByEvent '50 Free_SCY' min-time +
   timeDisplay) / P-PRNOTES + the STANDING pgTAP 008
   maintain_personal_bests proofs (D-D5), which have owned min-time
   truth since Phase D.
9. onTimesWritten.test.ts / 'dispatches swimmer PR and activity
   recomputes for a non-PR time as well' / dispatch-wiring pin /
   P-PRNOTES + P-DASHACT ('pr'-vs-'time' typing derives via
   personal_bests; no isPR column exists — FYI-10).
10. onTimesWritten.test.ts / 'dispatches swimmer PR and activity
    recomputes when a row is updated' / dispatch-wiring pin /
    P-PRNOTES; write-path recompute owned same-transaction by
    maintain_personal_bests (D-D5, pgTAP 008).
11. onTimesWritten.test.ts / 'dispatches swimmer PR and activity
    recomputes when a row is deleted' / dispatch-wiring pin /
    P-PRNOTES; as row 10.
12. onNotesWritten.test.ts / 'dispatches note and dashboard activity
    recomputes when a note is created' / dispatch-wiring pin,
    carries a value fragment (noteCount, lastNoteDate) / P-PRNOTES
    (noteCount = count(*), lastNoteDate = max(created_at) over
    swimmer_notes — full shape per D-J3(a)).
13. onNotesWritten.test.ts / 'dispatches recomputes when a note is
    updated' / dispatch-wiring pin / P-PRNOTES (compute-on-read; no
    dispatch).
14. onNotesWritten.test.ts / 'dispatches recomputes when a note is
    deleted' / dispatch-wiring pin / P-PRNOTES (an absent row at
    read time).
15. onNotesWritten.test.ts / 'does not gate dashboard activity on
    unchanged note fields' / dispatch-wiring pin (no-change-gating
    semantics) / retires STRUCTURALLY: a view recomputes on every
    read, so no change-gate exists to get wrong (D-J2(a)); recompute
    truth → P-PRNOTES + P-DASHACT.
16. onVideoSessionWritten.test.ts / 'dispatches dashboard activity
    recompute when a video session is created' / dispatch-wiring pin
    / P-DASHACT video arm (review-only filter +
    video_session_swimmers junction count).
17. onVideoSessionWritten.test.ts / 'dispatches dashboard activity
    recompute when a video session is updated' / dispatch-wiring pin
    / P-DASHACT video arm.
18. onVideoSessionWritten.test.ts / 'dispatches dashboard activity
    recompute when a video session is deleted' / dispatch-wiring pin
    / P-DASHACT (a deleted/non-review row contributes nothing at
    read time).

Tally: 18 rows = 1 + 2 + 4 + 4 + 4 + 3 — matches §1d EXACTLY. Class
split: 2 VALUE pins (rows 2–3) + 16 dispatch-wiring pins — §1d's
headline HOLDS, with one refinement named: rows 4, 8, and 12 are
dispatch pins that ALSO carry a small value fragment
(totalPractices; a prsByEvent entry; noteCount/lastNoteDate); each
fragment's successor is named on its row. Functions bar at commit 3:
133 − 18 = **115 exactly** (§5's "~115" de-tilded). D-J5 ratification
now waits only on Kevin reading this table.

**D-J6 RATIFIED — all four items land as J commit 4 — and the rider
is satisfied with exact counts (files read this round; no tildes):**
- src/hooks/__tests__/useSwimmer.test.ts — **8 tests** (§5 said 8 —
  confirmed).
- src/hooks/__tests__/useMeetDetails.test.ts — **7 tests** — **FLAG,
  LOUD: §5 pre-declared "~5"; the file holds 7.** The tilde estimate
  was wrong by two; pinned from the file, not silently reconciled.
  (§1d is not contradicted — its Coach-29 figure counted only the
  aggregation-riding suites and never claimed these hooks.)
- src/utils/__tests__/demoReadiness.test.ts — **3 tests** (§1d/§5
  said 3 — confirmed).
- The stores' type-only imports: exactly two sites —
  swimmersStore.ts:5 and attendanceStore.ts:4, each `import type
  { Unsubscribe } from 'firebase/firestore'` typing an
  `_unsubscribe` field → replaced with a local
  `type Unsubscribe = () => void`.
Commit-4 deletion pre-declaration, exact: **18 Coach tests (8 + 7 +
3) delete with their three zero-importer subjects** — expected Coach
bar after commit 4 = (the commit-2 landing count) − 18; with commit
2 landing inside its 1081±6 band, commit 4 lands at 1063±6.
**Zero-importer evidence, one line per module (grep-verified this
round, each module's own test file excluded):** useSwimmer — no
`hooks/useSwimmer` import anywhere in app/ or src/; useMeetDetails —
no reference anywhere in app/ or src/ outside the module itself;
demoReadiness — no reference anywhere in app/ or src/ outside the
module itself. All three: sole consumers are their test files;
deleting module + test together orphans nothing.

**D-J7 RATIFIED — option (a): SETTLED #5's intent honored on true
facts.** The messages screen (app/messages.tsx) and its dashboard
entry point (app/(tabs)/index.tsx:163) RETIRE in Phase K; coach_chat
gets NO canonical table; the Firestore contents die at the
06-runbook decommission step as NAMED pre-launch data loss (a
coach-to-coach channel; zero minors' data expected; **contents never
read this scope — recorded**). The correction-of-record lands in the
K landed log and the 06 runbook line, per the block.

**FYI BUNDLE 1–12 ACCEPTED AS NAMED — none struck.** GA-1's closure
(`REVOKE EXECUTE ... FROM PUBLIC, anon` on attendance_check_in + the
pgTAP anon→42501 proof) lands inside J commit 1; GA-2's four inert
trigger-function PUBLIC grants revoke in the same hygiene block;
GA-3's helper predicates conform ON PURPOSE (rationale stands in §4;
no action). Items 4–12 accepted as written — including the
publication pinned at EXACTLY 23 with the RH-12 same-commit
contingency named, the D-C1(b) checklist line recorded SATISFIED at
commit 2, and the id-prefix + text-template verbatim carries.

**§2 PARITY RECORD ACCEPTED.** Every value delta is a named
correction in an already-ratified direction (status-aware attendance
per the banked C law, 07 §2; 'pr' derived via personal_bests per
D-D5; names via joins per D-B7; timeDisplay derived-on-read;
updatedAt DB-owned); timing is strictly fresher. **The
onTimesWritten date-column mapping (`meetDate ?? createdAt` onto
personal_bests' date semantics) carries as a NAMED-AT-EXECUTION
OBLIGATION: the exact column mapping appears in the execution
report, never assumed.**

**TOLERANCE BANDS ACCEPTED as pre-declarations:** pgTAP +14-to-22
(commit 1) and Coach 1081±6 (commit 2). Landing OUTSIDE a declared
band is a flagged deviation — stop and explain before proceeding.
(Commit 3 = 115 and commit 4 = −18 are now EXACT pins per the
evidence above, not bands.)

**Standing after this entry:** D-J1, D-J2 (amendment applied), D-J3,
D-J4, D-J6, D-J7 ratified; FYI 1–12, the §2 parity record, and the
bands accepted; PHASE K named and chartered (scope-before-code, from
the D-J1 artifact). D-J5 PENDING-ON-EVIDENCE with the evidence now
on the record — J commits 1, 2, 4 are cleared; commit 3 BLOCKS on
D-J5; commit 5 closes whatever lands. No implementation began this
round; the only repo touched is UNIFY (this entry + the 01
amendment).

---

## 2026-06-10 — D-J5 RATIFIED (Kevin, in words) + the precisification confirmed + residual rulings — PHASE J EXECUTION OPENS

1. **D-J5 RATIFIED.** The five CF modules + the scheduled rebuild
   retire in commit 3; the 18 named tests delete WITH their subjects;
   **the evidence table at `1ce60a1` BINDS row-by-row as the
   successor mapping**; successors precede deletions by commit order
   (commits 1–2 land the successors, commit 3 the deletions);
   **Functions lands at EXACTLY 115**; the drop is deliberate — the
   FIRST test-count drop in project history — and the landed log must
   cite it; **any deletion outside the 18 rows is a flagged
   deviation.**
2. **The director confirms the D-J1 rider's recorded decomposition as
   a PRECISIFICATION (D-I1 class): it defines, does not alter; no
   correction required.** The 21 = 3 + 14 + 3 + 1 decomposition, the
   headline 19, and the Phase K work-list 13 stand as recorded.
3. **Residual rulings:** (i) 04:106 and 04:156 receive ONE-LINE dated
   [D-J2] annotations in commit 5 — annotate, never rewrite; the
   original words stay visible. (ii) **02_SCHEMA_REDTEAM.md stays
   UNTOUCHED, by ruling** (a point-in-time register); commit 5's
   landed log carries the line that 02:122/162 are
   moot-by-retirement.

All seven D-J decisions are now ratified. Execution of the §5 plan
opens under the standing norms: four bars green at every landed
commit, never advance on red, one green commit per logical change,
RC-3, tripwire armed mid-execution, no force-push/rebase/amend, HARD
STOPS unchanged. Pre-declared expectations bind: pgTAP +14-to-22
(commit 1), Coach 1081±6 (commit 2), Functions 115 EXACT (commit 3),
Coach −18 EXACT from the post-commit-2 count (commit 4). Bars
untouched by this entry (docs only): 835 TZ=UTC + 316 / 1081 / 133.

---

## 2026-06-10 — PHASE J LANDED (code-side COMPLETE): six green commits; the FIRST net-negative bars, deliberate, bound, and hit to the digit

Baseline re-verified before any code (835 TZ=UTC + 316 / 1081 / 133;
colima + supabase healthy). Every pre-declared expectation landed
exactly or inside its declared band; zero deletions outside the two
named sets; the tripwire never fired. Per commit:

1. **UNIFY `eac93cc` (commit 0, paperwork)** — D-J5 ratification +
   precisification confirmation + residual rulings recorded
   (previous entry).
2. **BSPC `c073e29` (commit 1)** — `00011_phase_j_aggregations.sql`
   + pgTAP `014-aggregation-views` (19 proofs). Four staff-gated
   compute-on-read views, each with an explicit is_staff() arm:
   agg_swimmer_attendance (status-aware VERBATIM per 07 §2 — applied
   to the WHOLE per-swimmer row set including last_practice_date,
   the coherent reading of the law, named; strict legacy 30/90
   timestamp-cutoff semantics carried — practice_date > today−N;
   22/64 denominators + the "Approximate: 5 practices/week" comment
   verbatim per D-J4(a)); agg_swimmer_prs_notes (full D-J3(a) shape;
   prsByEvent from personal_bests, "<event>_<course>" keys verbatim);
   agg_dashboard_attendance (the CF's INCLUSIVE 84-day date-string
   window carried — both legacy inclusivity asymmetries preserved,
   annotated in the migration); agg_dashboard_activity (4-arm UNION
   8/5/5/5, every FYI-9 template verbatim — truncateNote-60+'...',
   '— NEW PR!', 'Manual entry', 'VIDEO READY: N swimmer(s) analyzed'
   with the junction-counted plural, joined names per D-B7, FYI-10
   'pr' via the personal_bests match, review-only video arm, ORDER BY
   ts DESC LIMIT 15). PLUS the GA-1 closure (attendance_check_in
   REVOKE FROM PUBLIC, anon — 00004 had revoked only anon's direct
   grant; PUBLIC inheritance was the GA-1 hole — anon→42501 proven)
   and GA-2 (four inert trigger-fn defaults revoked, zero behavior
   change). pgTAP 014 = P-ATT, the status-aware negative, P-PRNOTES
   ×2, P-DASHATT, P-DASHACT ×3 + the FYI-10 derivation proof, 3
   family/pending/anon zero-rows walls, GA-1, GA-2, publication
   EXACTLY 23 (re-proven; the RH-12 contingency did NOT fire — all
   five source tables were already members). **pgTAP 316 → 335 (+19,
   inside the declared +14-to-22 band).**
3. **Coach `6183004` (commit 2)** — aggregations.ts swap behind
   FROZEN signatures (channel-on-source-tables + full re-fetch — the
   importJobs idiom; the swim_results channel covers personal_bests,
   whose trigger runs in the same transaction; activity fetch carries
   an explicit ORDER BY ts DESC — view-internal order is not a
   PostgREST guarantee). **The §2 NAMED-AT-EXECUTION obligation,
   executed: prsByEvent's date column is `personal_bests.achieved_at`,
   whose canonical rule COALESCE(date, created_at::date) IS the
   legacy `meetDate ?? createdAt` fallback — same semantics, one
   column, stated.** timeDisplay derived on read via the existing
   formatTimeDisplay (the SQL formatter in the activity texts matches
   it branch-for-branch). roster.tsx's inline 2×N Firestore doc subs
   collapsed INTO the service (04:54's "aggregations.ts (read-only)"
   finally literally true); useDashboardData's pendingDrafts
   re-pointed onto two new count subscriptions in the EXISTING
   audio.ts/video.ts services (the ratified D-J1 rider — same
   status='review' team-wide count, staff wall, no new capability);
   the hook holds ZERO direct Firestore. Tests: services 18 → house
   supabase mock with subjects preserved (the doc-missing arms became
   the view's no-row/zero-row arms — named transform); hook 8
   re-pointed; roster 2 follow the screen; +4 rider pins (2 per media
   service). **Coach 1081 → 1085 (+4, inside the declared ±6 band).**
4. **Coach `13967d8` (commit 3)** — the retirement. Deleted the four
   dark Firestore triggers + dashboardAggregations (the shared
   recompute module) + scheduled/rebuildAggregations (the 4 AM stale
   rewriter — the only machinery that still fired); index.ts dropped
   the five exports and its Phase F comment block now hands the
   family to this record. Test deletions = EXACTLY the 18 rows of
   the evidence table bound at `1ce60a1` — no more, no fewer;
   successors landed AHEAD by commit order (commits 1–2). functions
   tsc clean. **Functions 133 → 115 EXACTLY — the FIRST test-count
   drop in project history, pre-declared, ratified, and cited here.**
5. **Coach `fce4d62` (commit 4)** — the D-J6 sweep: useSwimmer.ts +
   8 tests, useMeetDetails.ts + 7 tests (the corrected count — §5's
   "~5" was wrong, flagged at ratification), demoReadiness.ts + 3
   tests; zero-importer evidence re-verified at deletion time. The
   stores' type-only firebase Unsubscribe imports → local type.
   **Coach 1085 → 1067 (−18 EXACTLY, the pre-declared pin).**
6. **BSPC `migration/j/README.md` + this landed log (commit 5)** —
   the null-manifest behind the standing HARD-STOP header: NOTHING
   migrates (P2-5/04:172, ratified twice), no rows copied, no
   backfill exists, first PG read correct by construction. Cutover
   lines recorded there: **the D-C1(b) checklist line is SATISFIED
   as of commit 2** (C+G+J reader code all landed); the stale
   aggregations docs + every write-dead collection die at the
   06-runbook decommission step (nothing here runs); the D-J7
   coach_chat disposition line (Phase K retirement; named pre-launch
   data loss; contents never read). Ruled paperwork applied: 04:106
   and 04:156 carry one-line dated [D-J2] annotations (original
   words visible — annotate-never-rewrite); **02_SCHEMA_REDTEAM.md
   stays untouched by ruling, and this log carries the line: 02:122
   and 02:162 are MOOT-BY-RETIREMENT** (they describe the drafted
   shape of a table D-J2 retired; their don't-migrate/recompute law
   halves remain true).

Named execution details (none rose to tripwire; all in ratified
directions): (i) the activity time arm renders canonical NULL-course
rows (BSPC-origin; the legacy feed never saw any) without the course
token — template-preserving for every row the legacy feed could have
produced, never the string 'undefined'; (ii) the status-aware set
governs the whole per-swimmer aggregate row set (not just the
percentages) and both dashboard attendance arms — the 07 §2 law read
coherently; (iii) commits 2–4 passed through the house lint-staged
pre-commit pass (eslint --fix + prettier); suites were re-verified
green against the committed trees; (iv) BSPC app code was untouched
(migrations + pgTAP only), so BSPC tsc is clean by construction;
Coach tsc keeps its pre-existing errors (jest-only bar, standing).

**Bar at close: BSPC 835 (TZ=UTC) + pgTAP 335 / Coach 1067 /
Functions 115.** Deletion norm: the two named sets (18 Functions
rows bound at `1ce60a1`; 18 Coach tests = 8+7+3 pinned at
ratification) — nothing else. Phases A–J code-side COMPLETE.
**Next: PHASE K — UI residual sweep (named at D-J1), scope-before-
code, from the D-J1 file:line artifact; then the 05/06 cutover
planning.**

---

## 2026-06-10 — PHASE K SCOPE (UI residual sweep) — scope before code: commit-5 verification + execution-round acceptances; the fresh terrain sweep; per-file scope for all 12 re-points + messages; D-K decision queue + numbered mini-plan

Read-only on code; UNIFY append-only. Heads at scope: UNIFY `b6330bb`,
BSPC `9e68c17`, Coach `fce4d62` — all clean, matching the standing
record. Baseline for every pre-declaration below: **BSPC 835 (TZ=UTC)
+ pgTAP 335 / Coach 1067 / Functions 115.**

### PART 0a — commit-5 verification: all five artifacts PRESENT, quoted verbatim

1. **The HARD-STOP header atop `migration/j/README.md`** (lines 1–5):

   > # Phase J — aggregations (NULL-MANIFEST)
   >
   > **Nothing in this directory runs against any database.** **Every row
   > backfill stays behind the HARD STOP, always** — and this phase owns
   > NONE: there is nothing to copy.

2. **The D-C1(b) checklist line recorded SATISFIED** (README lines 23–27):

   > - **The D-C1(b) checklist line is SATISFIED** as of Phase J commit 2:
   >   attendance data cutover required C+G+J reader code landed — all
   >   three now exist (C: `attendance_parent_view` + attendance.ts;
   >   G: the evaluator + digest; J: the aggregation views + the
   >   re-pointed roster/dashboard readers).

3. **The coach_chat disposition line** (README lines 32–39):

   > - **coach_chat disposition (D-J7, ratified):** the messages screen
   >   (`app/messages.tsx`) and its dashboard entry point retire in
   >   **PHASE K**; `coach_chat` gets no canonical table; whatever test
   >   chatter sits in the collection dies with Firestore at the
   >   decommission step — **NAMED pre-launch data loss** (a coach-to-coach
   >   channel; zero minors' data expected; contents never read during
   >   scoping or execution). The 06 runbook decommission step carries
   >   this line.

4. **The landed-log line naming 02:122/162 moot-by-retirement** (this
   file, lines 3167–3173):

   > Ruled paperwork applied: 04:106
   > and 04:156 carry one-line dated [D-J2] annotations (original
   > words visible — annotate-never-rewrite); **02_SCHEMA_REDTEAM.md
   > stays untouched by ruling, and this log carries the line: 02:122
   > and 02:162 are MOOT-BY-RETIREMENT** (they describe the drafted
   > shape of a table D-J2 retired; their don't-migrate/recompute law
   > halves remain true).

5. **The landed log's final-bars statement** (this file, lines 3188–3191):

   > **Bar at close: BSPC 835 (TZ=UTC) + pgTAP 335 / Coach 1067 /
   > Functions 115.** Deletion norm: the two named sets (18 Functions
   > rows bound at `1ce60a1`; 18 Coach tests = 8+7+3 pinned at
   > ratification) — nothing else. Phases A–J code-side COMPLETE.

No artifact missing; nothing to flag.

### PART 0b — the director's PHASE J EXECUTION-ROUND ACCEPTANCES (recorded)

1. **The cross-repo two-half commit 5 is ruled CONFORMING** — the
   "one green commit per logical change" norm met by a mechanically
   forced split (the null-manifest lives in BSPC, the landed log in
   UNIFY; one logical change, two repos), named at execution
   (BSPC `9e68c17` + UNIFY `b6330bb`).
2. **The two legacy date-window quirks are ACCEPTED carried verbatim**
   (parity doctrine): per-swimmer 30/90 windows STRICT
   (`practice_date > CURRENT_DATE − N`), dashboard 84-day window
   INCLUSIVE (`>= CURRENT_DATE − 84`) — both asymmetries preserved
   and annotated in 00011, by ruling.
3. **The no-course rendering is ACCEPTED as a NAMED CORRECTION** of a
   stringified-undefined artifact: canonical NULL-course swim_results
   rows render the activity time text without the course token —
   template-preserving for every row the legacy feed could have
   produced; never the string 'undefined'.
4. **The whole-calculation status-aware reading is BLESSED as a
   PRECISIFICATION of the banked law** (coherent-reading class, D-I1
   family): the 07 §2 status filter governs the WHOLE per-swimmer
   aggregate row set (including last_practice_date) and both
   dashboard attendance arms — defines, not alters.

### PART 1 — FRESH TERRAIN SWEEP (trust nothing, re-derived at Coach `fce4d62`)

Method: precise live-usage grep — `from 'firebase…'` /
`require('firebase…')` / dynamic `import('firebase…')` across `app/`
+ `src/` (tests separated), cross-checked against every importer of
`src/config/firebase` (the handle module). The two lists reconcile
one-to-one; comment-only and type-name-only mentions (e.g.
`firestore.types.ts` legacy-shape interfaces) carry no live firebase
import and are excluded as usage.

**App-side LIVE firebase: exactly 19 files.**

- **The 12 predicted re-point targets — ALL CONFIRMED live, exactly
  where the D-J1 inventory pinned them** (minor line drift only,
  named in PART 2): app/swimmer/new.tsx, app/swimmer/[id].tsx,
  app/swimmer/edit.tsx, app/swimmer/standards.tsx,
  app/swimmer/invite-parent.tsx, app/meet/[id].tsx,
  app/calendar/event/[id].tsx, app/video/[id].tsx,
  src/components/SwimmerVideoClips.tsx,
  src/components/VideoComparison.tsx,
  src/components/SwimmerTimeline.tsx, src/hooks/useSwimmerData.ts.
- **app/messages.tsx** — confirmed live full-CRUD on coach_chat
  (import block :14–24; D-J7 retirement, PART 3).
- **The 3 predicted auth-banked files** — confirmed:
  src/contexts/AuthContext.tsx:8–10 (firebase/auth + firestore),
  app/admin.tsx:12–13, app/(tabs)/settings.tsx:5–6.
- **The Phase J (i) trio holds ZERO live firebase** — confirmed:
  services/aggregations.ts, app/(tabs)/roster.tsx,
  src/hooks/useDashboardData.ts are clean at HEAD (the J commit-2
  claim re-proven by sweep).

**⚠️ TWO LIVE FILES THE EXPECTATION DID NOT PREDICT** (both outside
the D-J1 inventory's scan radius — that inventory enumerated
FIRESTORE call sites; these are firebase-AUTH and firebase-STORAGE):

1. **app/forgot-password.tsx:13–14** — `sendPasswordResetEmail` from
   `firebase/auth` + the `auth` handle. Pure auth-layer surface (a
   password reset against the Firebase-auth account store). Not a
   Firestore call site, so D-J1 never listed it; not in the named
   3-file auth bank either. → D-K1.
2. **src/components/practice-pdf-uploader.tsx:5–6, :139** —
   `getDownloadURL(ref(storage, todayPlan.storagePath))` from
   `firebase/storage`. **A LIVE SPLIT-BRAIN BUG TODAY**: since Phase H
   the upload arm writes SUPABASE storage
   (practicePlans.uploadDashboardPracticePlanPdf → practice-plans
   bucket, D-H2a) and `subscribeTodayPracticePlan` reads PG rows whose
   `storagePath` is a Supabase path — but the view-PDF arm asks
   FIREBASE storage for that same path. Every PDF uploaded post-H has
   a dead VIEW button. The successor ALREADY EXISTS
   (mediaUpload.getSignedFileUrl — the same helper the upload arm uses
   for its immediate downloadUrl). → D-K2.

Also named for completeness (no live firestore/auth/storage calls or
already-classified):
- **src/config/firebase.ts** — the shared handle module
  (initializeApp + getFirestore/getAuth/getStorage/getFunctions).
  Rides the auth bank; dies whole at cutover. Its `fns`
  (getFunctions) handle has ZERO app-side consumers at HEAD (the F
  pipeline went HTTPS; I went PG) — named, untouched.
- **Test-side**: 6 suites mock firebase for LIVE subjects
  (AuthContext, useSwimmerData, SwimmerTimeline, SwimmerVideoClips,
  VideoComparison ×2 suites) — they transform with their subjects;
  **4 suites carry DEAD firebase mocks** whose subjects are already
  PG (useTimes, useGoals, useSwimmerAttendance, sdifImport tests) —
  hygiene sweep, K6, verify-at-deletion per file (a dead
  `jest.mock('../../config/firebase')` is only dead if the subject's
  import graph no longer reaches the module).
- **Satellites** (not Coach-app runtime; classified, no K work):
  `scripts/` (5 dev seed/create tools on firebase + firebase-admin —
  STALE-BY-MIGRATION: anything they seed is invisible to PG readers;
  named to the 06-runbook decommission family), `functions/`
  workspace (Firebase by nature; its remaining members are live
  plumbing — parentPortal, redeemInvite, digest, evaluator, AI
  pipeline, syncCalendar, sweeps — dies at decommission per 06),
  `parent-portal/` workspace (Firebase auth + callables — the Phase A
  Option (b) banked identity surface; 05/06 territory), root infra
  (firebase.json, .firebaserc, firestore.rules, firestore.indexes.json,
  storage.rules — decommission artifacts; the firestore.rules
  coach_chat block dies there too).

**Sweep verdict on the record:** the D-J1 inventory is CONFIRMED
complete WITHIN ITS RADIUS (live Firestore call sites) — every (ii)
file live exactly as pinned, the (i) trio clean, (iii)+(iv) as
recorded. The residual-set sentence is CORRECTED: the true app-side
residual is **12 re-points + messages.tsx + an auth bank of FOUR
files plus the config module (AuthContext, admin, settings,
forgot-password, config/firebase.ts) + ONE live storage read
(practice-pdf-uploader.tsx:139, a split-brain bug, not a banked
surface)**. Storage otherwise: zero live firebase-storage code
remains (uploads/reads went Supabase in F/H); what stays banked to
cutover is the historical-object FILE COPY (06 runbook), not code.

### PART 2 — PER-FILE SCOPE: the 12 re-point targets

Format per file: live call sites (verified at HEAD) → owning EXISTING
service → re-point shape → test surface. "GAP" = data no existing
export exposes → D-K4.

1. **app/swimmer/new.tsx** — :76 `addDoc(collection(db,'swimmers'))`
   (+ :71–72 serverTimestamp). → swimmers.addSwimmer (Phase B; maps
   every written field; the screen's `goals: []` is a no-op — the
   service derives goals on read and never writes the denormalized
   field). Re-point: one call swap; addSwimmer returns the new id for
   `router.replace`. Tests: none exist for the screen; service
   already pinned. NO gap.
2. **app/swimmer/edit.tsx** — :69 `getDoc(doc(db,'swimmers',id))`
   prefill; :117 `updateDoc` full form write. → swimmers.updateSwimmer
   maps EVERYTHING the form writes (incl. mediaConsent → 5 columns;
   strengths/techniqueFocusAreas/parentContacts →
   swimmer_coach_profile upsert) EXCEPT the **goals textarea**:
   canonical derives `goals` from the goals table on read and NEVER
   writes the legacy denormalized field (ratified Phase B design) —
   the textarea's write path is gone BY DESIGN → **D-K3**. Prefill
   read is a single-swimmer read → **D-K4**. Tests: none for the
   screen.
3. **app/swimmer/standards.tsx** — :52 swimmer doc sub (→ D-K4);
   :59–60 times sub `orderBy('createdAt','desc')` with **NO limit**
   → times.subscribeTimes(id, cb, max) is the successor (same order:
   `created_at desc`), but it is max-bounded (default 50) — the
   legacy read is unbounded. NAMED PARITY DELTA: the re-point passes
   an explicit high max (1000), named here, never silent (the screen
   computes best-time-per-event; truncation could change a computed
   best; pre-launch data sits far below the bound either way). Goals
   arm already on subscribeGoals ✓. Tests: none for the screen.
4. **app/swimmer/invite-parent.tsx** — :39 swimmer doc sub, used ONLY
   to derive the header name when the `name` route param is absent
   (→ D-K4; one-shot semantics). Invites arm already on
   parentInvites.subscribeInvitesForSwimmer ✓ (Phase I). Tests: none
   for the screen.
5. **app/swimmer/[id].tsx** — :116 `deleteDoc(notes/{noteId})` →
   notes.deleteNote ✓; :134 `deleteDoc(times/{timeId})` →
   times.deleteTime ✓ (the D-D5 trigger re-promotes next-fastest in
   the same transaction — the legacy batch's no-transient-window
   guarantee, already pinned); :970 `addDoc(times)` →
   times.addTime ✓ (frozen signature; PR math trigger-owned); the
   **:965–:999 client-side isPR computation + demotion sweep
   (getDocs + dynamic `import('firebase/firestore')` updateDoc at
   :992–:995) RETIRES WITH THE RE-POINT** — its successor is the
   D-D5 maintain_personal_bests trigger, landed Phase D, proven in
   pgTAP 008. timeDisplay/isPR render fields come from the service's
   read mapping. Reads come via useSwimmerData (row 12). Tests: none
   for the screen (the hook's suite is the surface).
6. **app/meet/[id].tsx** — :38 single-meet doc sub (→ D-K4; meets.ts
   exports list subs only: subscribeMeets(max=50)/
   subscribeUpcomingMeets). Entries arm already on subscribeEntries
   ✓; delete on deleteMeet ✓. Tests: none for the screen.
7. **app/calendar/event/[id].tsx** — :35 single-event doc sub
   (→ D-K4; calendar.ts exports month/range/date list subs only).
   RSVPs arm already on subscribeRSVPs ✓; delete on deleteEvent ✓.
   Tests: none for the screen.
8. **app/video/[id].tsx** — :57 single-session doc sub (→ D-K4;
   video.subscribeVideoSessions is coach_id-scoped + max 20 — wrong
   axis for an arbitrary session by id, and the AI pipeline flips
   this row's status live, so a real subscription is required).
   Drafts arm already on subscribeVideoDrafts ✓; approve/reject on
   videoDrafts service ✓; roster context via swimmersStore ✓.
   Tests: none for the screen.
9. **src/components/SwimmerVideoClips.tsx** — :32–41 query
   `video_sessions where taggedSwimmerIds array-contains swimmerId,
   createdAt desc, limit 10` (inventory said :33 — drift of the
   import block only). **GAP: no existing export reads sessions by
   tagged-swimmer axis** (canonical models tags as the
   video_session_swimmers junction, kind='tagged', P1-4) → D-K4.
   Tests: 4 (transform with the component).
10. **src/components/VideoComparison.tsx** — :44–50 same
    tagged-swimmer query PLUS `where status=='posted'` (inventory
    :45 ✓); :60–66 + :67–74 left/right drafts subs →
    subscribeVideoDrafts ✓ (two instances, existing export). The
    sessions arm → D-K4 (posted-only variant). Tests: 3 + 1
    (VideoCompareScreen.test.tsx also exercises this component —
    its firebase mocks are LIVE for this subject; both suites
    transform together).
11. **src/components/SwimmerTimeline.tsx** — :64–71 notes sub
    (createdAt desc, limit 100) → notes.subscribeNotes(id, cb, 100)
    ✓ EXACT (same order, same bound); :72–81 times sub (same shape)
    → times.subscribeTimes(id, cb, 100) ✓ EXACT. NO gap — the only
    target fully covered by existing exports with zero deltas.
    Tests: 4 (transform).
12. **src/hooks/useSwimmerData.ts** — :50 swimmer doc sub (→ D-K4);
    :61–66 notes sub limit 50 → subscribeNotes(id, cb, 50) ✓ EXACT;
    :77–82 times sub limit 50 → subscribeTimes(id, cb, 50) ✓ EXACT;
    attendance arm already on subscribeSwimmerAttendance ✓; goals
    arm already on subscribeGoals ✓; prCount derives from the
    mapped times' isPR (service read field) ✓. Tests: 8 (transform —
    the house supabase-mock conversion, J commit-2 class).

**The single-record fact that drives D-K4:** swimmersStore subscribes
ACTIVE swimmers only (`subscribeSwimmers(true, …)`, app-wide at
_layout) — and INACTIVE swimmers are REACHABLE: roster.tsx:95–98 has
a showInactive arm (`subscribeSwimmers(false, …)`) whose rows open
the same profile/edit/standards screens. The store selector is
therefore NOT a complete successor for any single-swimmer read.

### PART 3 — MESSAGES RETIREMENT SCOPE (D-J7 execution shape)

The exact deletion set (files, routes, tests — successors or
retire-with-subject per row):

| # | Deletion | Kind | Successor / rationale |
|---|----------|------|----------------------|
| 1 | `app/messages.tsx` (304 lines; full coach_chat CRUD — collection/query/orderBy/onSnapshot/addDoc/updateDoc/deleteDoc/serverTimestamp/limit, import block :14–24) | file = the expo-router route itself | RETIRE-WITH-SUBJECT — D-J7(a) ratified: the feature retires whole; no PG home; contents never read |
| 2 | `app/(tabs)/index.tsx:161–166` — the CHAT TouchableOpacity block (`router.push('/messages')` at :163) | UI block edit | retire-with-subject (the dashboard entry point named in D-J7) |
| 3 | `app/_layout.tsx:208–217` — the `<Stack.Screen name="messages" …/>` registration ("COACH CHAT" header) | UI block edit | retire-with-subject (route registration dies with the route) |
| 4 | `src/types/firestore.types.ts:297` — `export interface Message` | type | SOLE importer is app/messages.tsx (verified at HEAD) — zero-importer at deletion, D-J6 evidence class; re-verify at deletion time |

**Test deletions: EXACTLY ZERO — pre-declared.** No test file exists
for app/messages.tsx; the only app-route suites at HEAD are
app/(tabs)/__tests__/roster.test.tsx and
app/practice/__tests__/browse.test.tsx, and no suite pins the CHAT
button or the route registration. Coach bar UNCHANGED by this commit
(exact pin). `coach_chat` contents remain UNREAD (confirmed this
round: scope derived from code shape only). The correction-of-record
(SETTLED #5's "dead/unimplemented" premise was wrong-when-settled;
the intent stands, the facts now true) lands in K's landed log, and
the 06-runbook decommission step carries the coach_chat
named-data-loss line (already written into migration/j/README.md —
quoted in PART 0a).

### PART 4 — THE D-K DECISION QUEUE

**D-K1 — the auth bank has a fourth file and a config module; record
the membership explicitly.** The sweep found app/forgot-password.tsx
(firebase/auth sendPasswordResetEmail — :13–14) live outside both the
D-J1 inventory (Firestore-only radius) and the named 3-file bank.
src/config/firebase.ts is the bank's shared handle module (its
getFunctions handle is consumer-less at HEAD — named, untouched).
  (a) **[RECOMMEND]** Record both as EXPLICIT auth-bank members (the
  D-J1 (iii) coherent-reading precedent: surfaces that operate on the
  Firebase-auth account store belong to the bank; a password reset IS
  the account store). The bank is then FIVE artifacts by name:
  AuthContext.tsx, app/admin.tsx, app/(tabs)/settings.tsx,
  app/forgot-password.tsx, src/config/firebase.ts — all die together
  at the 05 auth cutover. K touches none of them; the K work list is
  unchanged by this ruling.
  (b) Pull forgot-password.tsx into K and build a Supabase-auth reset
  now — premature: auth is banked whole to the 05 cutover by ratified
  Option (b); a mid-migration mixed-auth surface is the exact class
  the bank exists to prevent.

**D-K2 — practice-pdf-uploader.tsx:139 joins the K work list (a
live split-brain read of already-migrated data).** Upload arm:
Supabase (practicePlans → practice-plans bucket, D-H2a). Row source:
PG practice_plans. View arm: FIREBASE `getDownloadURL(ref(storage,
storagePath))` on a Supabase path — dead button for every post-H
upload; same live-bug class as the D-J1 (ii) split-brain writes.
  (a) **[RECOMMEND]** Add the file to the K work list (work list
  becomes 13 re-points + messages). Re-point: replace the
  getDownloadURL call with mediaUpload.getSignedFileUrl(
  PRACTICE_PLANS_BUCKET, storagePath, 3600) — the EXISTING export the
  upload arm already uses — and drop the firebase/storage import.
  PRACTICE_PLANS_BUCKET is currently a practicePlans-local const: the
  narrowest conforming shape is exporting that one const (a named
  one-line contract ADDITION, no behavior), or equivalently passing
  through a practicePlans wrapper — the const export is recommended.
  NAMED CAVEAT (not a blocker): any pre-H PG row carrying a legacy
  Firebase path would 404 against a signed Supabase URL until the 06
  file-copy step — pre-launch test data; the dashboard reads TODAY's
  plan only; the 06 runbook owns object existence either way. Tests:
  the component has NO suite at HEAD; the service addition (if the
  const export counts) is type-only — zero test-count change,
  pre-declared.
  (b) Bank it to cutover as "file storage" — REJECT-RECOMMENDED: it
  is not a banked legacy surface, it is a broken read of MIGRATED
  data; every day it stands is a coach-visible dead button.

**D-K3 — the edit screen's goals textarea has no write path BY
RATIFIED DESIGN; the control's disposition needs a call.**
app/swimmer/edit.tsx:117 writes `goals: toArray(goals)` to the legacy
denormalized field. Canonical (Phase B, standing): `goals` is DERIVED
on read from the goals table (`goals(event_name)`) and NEVER written
— updateSwimmer carries an explicit comment to that effect. The
first-class goals feature (subscribeGoals/useGoals/GoalCard, B-era)
owns goal lifecycle. Even TODAY the screen is split-brain: it
prefills from the Firestore doc's free-text lines while every PG
reader derives event names from the goals table.
  (a) **[RECOMMEND]** RETIRE the textarea (and its prefill) from the
  edit form — a NAMED UI change, parity-CORRECTING (the legacy write
  lands in a field no PG reader will ever surface: dead-end data, the
  D-J1 (ii) split-brain class; the goals feature is the ratified
  owner). The screen's remaining form fields all map onto
  updateSwimmer verbatim. No test pins the textarea (the screen has
  no suite).
  (b) Diff-map textarea lines onto goals-table rows — WIDENING: new
  semantics (free text ≠ structured per-event goals), a write shape
  nothing ratified, fragile line-diffing. Presented to be declined.
  (c) Render the derived goals read-only in the form — keeps a dead
  control on screen; declined-recommended.

**D-K4 — the single-record read shape: five narrow service ADDITIONS
(the J-rider class) vs composition from list reads.** The gap, from
PART 2: four single-record subscriptions (swimmers ×4 call sites;
meets ×1; calendar_events ×1; video_sessions ×1) and one
tagged-swimmer sessions query (×2 call sites, one posted-only) have
NO existing export. The store covers only active swimmers (PART 2
closing fact); subscribeVideoSessions is coach-scoped; nothing reads
the tag axis.
  (a) **[RECOMMEND]** FIVE named additions to EXISTING services —
  additions, not changes; every frozen export stays byte-frozen; each
  is a narrower projection of rows the same role already reads via
  existing list subs (RLS-identical, zero new capability — the
  ratified D-J1-rider precedent: audio/video count subscriptions):
    1. swimmers.subscribeSwimmer(id, cb) — single row, active or
       inactive; house channel idiom (swimmers table, id-filtered).
    2. meets.subscribeMeet(id, cb) — single row.
    3. calendar.subscribeEvent(id, cb) — single row.
    4. video.subscribeVideoSession(id, cb) — single row (status
       flips live during AI processing).
    5. video.subscribeSwimmerVideoSessions(swimmerId, cb, opts?:
       {postedOnly?: boolean; max?: number /* default 10 */}) —
       sessions whose video_session_swimmers junction holds
       (swimmer_id, kind='tagged'), created_at desc (PostgREST
       inner-join filter); channel on video_sessions +
       video_session_swimmers with re-fetch (the J idiom — junction
       writes land in the same transaction as session writes via the
       F service paths).
    Each addition lands WITH its own house-mock pins (≥2 per export,
    exact counts pre-declared at execution) in ONE commit (K1),
    BEFORE any consumer re-points — successors-precede-consumers, the
    J commit-order discipline.
  (b) Compose from existing exports only — FAILS the terrain:
  swimmers would need both-arms subscription gymnastics
  (active+inactive) per screen; meets/events would over-fetch lists
  to find one row (subscribeMeets caps at 50; the range subs need the
  event's date BEFORE reading it); video/[id] composed from the
  coach-scoped list REGRESSES (a session opened from another coach's
  clip list sits outside the subscription's axis); and NOTHING
  composes the tag-axis query — (b) is partially IMPOSSIBLE, named to
  show why (a) is the honest floor.
  (c) Hybrid (store selectors where active-only suffices + additions
  elsewhere) — two patterns for one problem class, more moving parts,
  the inactive-reachability hole stays live on three screens.

**FYI bundle (accept-as-named unless struck):**
1. The 4 dead-mock suites (useTimes/useGoals/useSwimmerAttendance/
   sdifImport tests) get their dead `jest.mock('firebase/…')` /
   `jest.mock('../../config/firebase')` blocks removed in K6 with
   per-file verify-at-deletion (graph must no longer reach
   config/firebase); ZERO test-count change, pre-declared.
2. `scripts/` seed/create tooling is STALE-BY-MIGRATION (writes
   Firestore nobody reads); named to the decommission family; K
   deletes nothing there (no-widening).
3. config/firebase.ts's getFunctions handle is consumer-less at HEAD;
   named; untouched (the module is bank property, D-K1).
4. firestore.rules' coach_chat block dies with the Firebase project
   (06 runbook); K touches no rules file.
5. Inventory line drift observed and absorbed: SwimmerVideoClips
   :33→:32–41, VideoComparison :45,61,70→:44–50,:60–66,:67–74,
   SwimmerTimeline :66,74→:64–71,:72–81, useSwimmerData
   :49,61,77→:50,:61–66,:77–82 — same files, same shapes, no
   substantive drift.
6. The standards.tsx unbounded→max(1000) times read is the ONLY
   parity delta in the 12 re-points (PART 2 #3); every other mapping
   is exact (order, bound, fields).
7. VideoCompareScreen.test.tsx's subject is VideoComparison (the
   compare SCREEN lives in app/ untested) — its 1 test transforms
   with VideoComparison's 3.

### PART 4b — THE NUMBERED MINI-PLAN (pre-declared bars from 835+335 / 1067 / 115)

Standing for every commit: four bars green before landing; never
advance on red; one green commit per logical change; tripwire armed —
anything material unpinned at execution = STOP + report; no
force-push/rebase/amend; HARD STOPS unchanged (manifests
instructions-only; nothing runs against any database). RC-3: N/A this
phase — no schema work, no migrations; BSPC repo UNTOUCHED end to
end. **BSPC 835 (TZ=UTC) + pgTAP 335 and Functions 115 are EXACT
UNCHANGED pins for EVERY commit below.**

- **K0 (UNIFY only)** — ratification recording for D-K1..D-K4 + FYI
  acceptances, this entry's rulings quoted back. Bars untouched.
- **K1 (Coach)** — the five D-K4(a) service additions + their
  house-mock pins, no consumer changes. **Coach 1067 → +10-to-+15
  (declared band: ≥2 pins per addition; cite the exact landed
  count).** Functions/BSPC pins exact-unchanged.
- **K2 (Coach)** — swimmer-family re-points: new.tsx, edit.tsx
  (incl. D-K3 ruling), standards.tsx (named max=1000 delta),
  invite-parent.tsx, swimmer/[id].tsx writes (PR sweep retires to
  D-D5), useSwimmerData.ts, SwimmerTimeline.tsx. Test surface:
  useSwimmerData 8 + SwimmerTimeline 4 TRANSFORM in place (house
  supabase mock, subjects preserved); screens have no suites.
  **Coach count UNCHANGED from post-K1 — EXACT pin (transform-only
  commit).**
- **K3 (Coach)** — video-family re-points: video/[id].tsx,
  SwimmerVideoClips.tsx, VideoComparison.tsx. Transforms:
  SwimmerVideoClips 4 + VideoComparison 3 + VideoCompareScreen 1.
  **Coach count UNCHANGED — EXACT pin.**
- **K4 (Coach)** — meet/[id].tsx + calendar/event/[id].tsx re-points
  + the D-K2 pdf-uploader re-point (+ the one-line
  PRACTICE_PLANS_BUCKET export if (a)). No test surface exists for
  any of the three. **Coach count UNCHANGED — EXACT pin.**
- **K5 (Coach)** — D-J7 messages retirement: the PART 3 table rows
  1–4, nothing else. **Test deletions ZERO; Coach count UNCHANGED —
  EXACT pin.** Any deletion beyond the four named rows = flagged
  deviation, STOP.
- **K6 (Coach + UNIFY)** — dead-mock hygiene (FYI-1, 4 named files,
  verify-at-deletion) + K landed log in NOTES (carrying the D-J7
  correction-of-record line + the residual-set sentence as corrected
  by PART 1) + memory update. **Coach count UNCHANGED — EXACT pin.**
  If the mechanically-forced cross-repo split recurs (log in UNIFY),
  it lands under the PART 0b #1 precedent, named.

**End-of-phase expectation: BSPC 835 (TZ=UTC) + pgTAP 335 / Coach
1067 + Δ(K1) / Functions 115, where Δ(K1) ∈ [+10, +15] cited exact.**
After K: the Coach app's live firebase surface is EXACTLY the D-K1
auth bank (five named artifacts) — the precondition line for the
05/06 cutover planning.

**Execution blocks on D-K1–D-K4. No Phase K implementation this
round; bars untouched (835 TZ=UTC + 335 / 1067 / 115); UNIFY is the
sole repo touched (this entry).**

---

## 2026-06-10 — PHASE K RATIFICATION (Kevin, in words) — D-K1/D-K2/D-K3/D-K4 ALL RATIFIED; FYI 1–7 accepted unstruck; execution unblocked

Each ruling below was checked against its [DECIDE] block in the PHASE
K SCOPE entry at `60abc91` before recording. **All four rulings and
all seven FYIs match their blocks exactly — no mismatches, nothing
recorded half-open.**

**D-K1 RATIFIED — option (a).** The auth bank is FIVE named
artifacts: src/contexts/AuthContext.tsx, app/admin.tsx,
app/(tabs)/settings.tsx, app/forgot-password.tsx,
src/config/firebase.ts. A password-reset screen IS the Firebase-auth
account store (coherent-reading class, per the D-J1 (iii) precedent).
All five die together at the 05 auth cutover; Phase K touches NONE of
them. The consumer-less getFunctions handle is named and untouched
(bank property). Building a Supabase reset now is DECLINED as a
mixed-auth surface mid-migration.

**D-K2 RATIFIED — option (a).** practice-pdf-uploader.tsx joins the
Phase K work list (13 re-points + messages). Its view arm re-points
onto the EXISTING mediaUpload.getSignedFileUrl(PRACTICE_PLANS_BUCKET,
storagePath, 3600); the firebase/storage import drops. The contract
shape is exporting the existing PRACTICE_PLANS_BUCKET const — a named
one-line ADDITION, no behavior change. The pre-H legacy-path 404
caveat is ACCEPTED AS NAMED: pre-launch test data; the 06 runbook
owns object existence at file copy. Zero test-count change
pre-declared (the component has no suite; the const export is
type-only).

**D-K3 RATIFIED — option (a).** The goals textarea AND its prefill
RETIRE from app/swimmer/edit.tsx: a NAMED UI change,
parity-CORRECTING. The legacy write lands in a field no PG reader
will ever surface (dead-end data, split-brain class); the B-era goals
feature is the ratified owner of goal lifecycle.
Free-text-to-structured diff-mapping is DECLINED as a widening; a
read-only dead control is DECLINED. No test pins the textarea.

**D-K4 RATIFIED — option (a).** Five named ADDITIONS to existing
services, signatures AS WRITTEN in the block binding:
swimmers.subscribeSwimmer(id, cb); meets.subscribeMeet(id, cb);
calendar.subscribeEvent(id, cb); video.subscribeVideoSession(id, cb);
video.subscribeSwimmerVideoSessions(swimmerId, cb, opts
{postedOnly?, max? default 10}) via the video_session_swimmers
junction (kind='tagged', created_at desc, channel on both tables with
re-fetch — the J idiom). Additions, not changes; every frozen export
stays byte-frozen. Each is a narrower projection of rows the same
role already reads — RLS-identical, zero new capability (the ratified
J-rider precedent). Composition was shown partially impossible (no
tag-axis composition; a coach-scoped list regresses cross-coach
opens; the store covers active swimmers only while inactive are
reachable), so the additions are the honest floor. Each lands in K1
with ≥2 house-mock pins per export, exact counts cited at landing,
BEFORE any consumer re-points (successors-precede-consumers, the J
commit-order law).

**FYI-1 THROUGH FYI-7 ALL ACCEPTED AS NAMED, none struck:** (1) dead
jest.mock firebase blocks removed in K6 with per-file
verify-at-deletion — the module graph must no longer reach
src/config/firebase — zero count change; (2) scripts/ seed tooling is
stale-by-migration, named to the decommission family; K deletes
nothing (no-widening); (3) the getFunctions handle is named and
untouched; (4) firestore.rules untouched — dies with the Firebase
project per 06; (5) inventory line drift absorbed, no substantive
drift; (6) standards.tsx unbounded → max(1000) is the phase's SINGLE
named parity delta, conservative direction, carried in the landed
log; (7) VideoCompareScreen.test transforms with VideoComparison's 3.

**Standing after this entry:** execution unblocked on the K1–K6
mini-plan as written at `60abc91`; only K1 moves the Coach bar
(declared band 1067 → +10-to-+15, cite exact); BSPC 835 (TZ=UTC) +
pgTAP 335 and Functions 115 are EXACT-unchanged pins for every
commit; the BSPC repo is untouched end to end.

---

## 2026-06-10 — PHASE K LANDED (code-side COMPLETE): seven green commits; every pin hit exactly; the Coach app's live firebase surface is now EXACTLY the five-artifact auth bank

Baseline re-verified before any code (835 TZ=UTC + 335 / 1067 / 115;
colima + supabase healthy; heads 60abc91 / 9e68c17 / fce4d62 clean).
Every pre-declared expectation landed exactly or inside its declared
band; zero deletions outside the named set; the tripwire never fired.
The BSPC repo was UNTOUCHED end to end (no schema work — RC-3 n/a);
BSPC 835 (TZ=UTC) + pgTAP 335 and Functions 115 held EXACT at every
commit. Per commit:

1. **UNIFY `181c08f` (K0, paperwork)** — D-K1/D-K2/D-K3/D-K4 ratified
   option (a), FYI 1–7 accepted unstruck; every ruling checked
   against its block at `60abc91` — no mismatches, nothing half-open
   (previous entry).
2. **Coach `da19046` (K1)** — the five D-K4 service ADDITIONS, frozen
   exports byte-frozen, no consumer changes: swimmers.subscribeSwimmer
   (id-filtered two-table channel — swimmers + swimmer_coach_profile,
   the list sub's watch-set narrowed); meets.subscribeMeet;
   calendar.subscribeEvent (a single row IS a stable row key — the
   channel filters by id); video.subscribeVideoSession (watches both
   projection sources: the session row + its swimmer junction,
   session_id-filtered); video.subscribeSwimmerVideoSessions
   (postedOnly?/max?=10 — the tag axis via a SECOND `tag_filter`
   embed of video_session_swimmers used as the PostgREST !inner
   filter while the UNFILTERED `swimmers` embed keeps the mapper's
   tagged/selected arrays intact, a named execution detail; channel
   on video_sessions table-wide + the junction swimmer-filtered).
   Missing single rows emit null (≙ snap.exists() === false, the
   house listener-error parity). 13 house-mock pins (3 swimmers /
   2 meets / 2 calendar / 6 video). **Coach 1067 → 1080 (+13, inside
   the declared +10-to-+15 band).**
3. **Coach `b742937` (K2)** — swimmer-family re-points: new.tsx →
   addSwimmer (data layer owns timestamps/created_by; goals:[] a
   no-op by design); edit.tsx → subscribeSwimmer one-shot prefill
   (first-emission fill — a remote change never clobbers an
   in-progress edit) + updateSwimmer, **with the D-K3 ruling
   EXECUTED: the goals textarea AND its prefill retired — the
   phase's only UI change, parity-correcting**; standards.tsx →
   subscribeSwimmer + subscribeTimes(id, cb, **1000**) — **FYI-6
   carried: the phase's SINGLE named parity delta (legacy unbounded
   → max-bounded, conservative)**; invite-parent.tsx →
   subscribeSwimmer name fallback (+ the dead Firestore-Timestamp
   instanceof branches left with the import — the service emits real
   Dates since Phase I); swimmer/[id].tsx writes → deleteNote /
   deleteTime / addTime — **the client-side isPR computation +
   demotion sweep (the dynamic-import updateDoc block) RETIRED to
   the D-D5 maintain_personal_bests trigger**, its standing
   successor; useSwimmerData.ts + SwimmerTimeline.tsx onto
   subscribeSwimmer/subscribeNotes/subscribeTimes (same order, same
   bounds 50/100 — exact mappings). Tests: useSwimmerData 8 +
   SwimmerTimeline 4 TRANSFORMED in place. **Coach 1080
   EXACT-unchanged.**
4. **Coach `d7f9106` (K3)** — video-family re-points: video/[id].tsx
   → subscribeVideoSession (the AI pipeline's live status flips
   carry through); SwimmerVideoClips.tsx → subscribeSwimmerVideoSessions
   (all statuses); VideoComparison.tsx → subscribeSwimmerVideoSessions
   ({postedOnly: true}) + the left/right drafts arms onto the
   EXISTING subscribeVideoDrafts. Tests: 4 + 3 + 1 transformed
   (VideoCompareScreen.test's subject is VideoComparison — FYI-7).
   **Coach 1080 EXACT-unchanged.**
5. **Coach `1df983a` (K4)** — meet/[id].tsx → subscribeMeet;
   calendar/event/[id].tsx → subscribeEvent; **the D-K2 split-brain
   read CLOSED**: practice-pdf-uploader.tsx's view arm →
   mediaUpload.getSignedFileUrl(PRACTICE_PLANS_BUCKET, storagePath,
   3600) — the same store the upload arm writes — with the named
   one-line PRACTICE_PLANS_BUCKET export added to practicePlans.ts;
   the firebase/storage import dropped. **The D-K2 pre-H 404 caveat
   stands as ACCEPTED: any pre-H row carrying a legacy Firebase path
   404s against a signed Supabase URL until the 06-runbook file-copy
   step, which owns object existence — pre-launch test data; the
   dashboard reads today's plan only.** No test surface. **Coach
   1080 EXACT-unchanged.**
6. **Coach `19f66ea` (K5, D-J7 executed)** — messages retirement,
   EXACTLY the four named PART 3 rows: app/messages.tsx deleted (the
   expo-router route itself, 304→329 lines at deletion incl. the
   import block); the index.tsx CHAT block; the _layout.tsx
   "COACH CHAT" Stack.Screen registration; the Message interface
   (sole importer re-verified at deletion — zero importers).
   **Test deletions: ZERO, as pre-declared** (no suite ever covered
   the screen). coach_chat contents were never read.
   **CORRECTION-OF-RECORD (D-J7): SETTLED #5's "coach_chat
   dead/unimplemented" premise was wrong WHEN SETTLED — the screen
   was full live CRUD routed from the dashboard. The ratified
   no-messaging INTENT is now executed with true facts: the feature
   is retired, coach_chat gets no canonical home, and whatever test
   chatter sits in the collection dies with Firestore at the
   06-runbook decommission step (named pre-launch data loss).**
   **Coach 1080 EXACT-unchanged.**
7. **Coach `707439c` + this landed log (K6, cross-repo two-half —
   the PART 0b #1 CONFORMING precedent, mechanically forced,
   named)** — FYI-1 hygiene: the dead firebase mock blocks removed
   from useTimes/useGoals/useSwimmerAttendance/sdifImport tests with
   per-file verify-at-deletion evidence (useTimes→services/times,
   useGoals→services/goals, useSwimmerAttendance→services/attendance,
   sdifImport→utils+meetResultsImport — every graph PG/parser-only;
   none reaches src/config/firebase). **Coach 1080 EXACT-unchanged.**

Named execution details (none rose to tripwire): (i) commits 1–6
passed through the house lint-staged pre-commit pass; suites were
re-verified green against the committed trees (J precedent);
(ii) the K1 tag-axis read uses the dual-embed shape (filter embed +
unfiltered mapper embed) so the frozen VideoSessionWithId mapping
never truncates — pinned in the K1 tests; (iii) BSPC tsc clean by
construction (repo untouched); Coach tsc keeps its pre-existing
errors (jest-only bar, standing).

**THE RESIDUAL-SET SENTENCE, CORRECTED ON THE RECORD (supersedes the
Phase I "NONE" overclaim and the Phase J landed log's framing): after
Phase K, the Coach app's ENTIRE live firebase surface is EXACTLY the
five-artifact auth bank — src/contexts/AuthContext.tsx, app/admin.tsx,
app/(tabs)/settings.tsx, app/forgot-password.tsx,
src/config/firebase.ts — re-proven by a fresh import grep on the
final tree (five files, nothing else; test-side, only the shared
manual mock and the AuthContext suite still reference firebase, both
bank shadows).** All five die together at the 05 auth cutover.
Satellites unchanged and classified (functions/ workspace live
plumbing until decommission; parent-portal/ the Phase A banked
identity surface; scripts/ stale-by-migration; root rules/config
files die with the project per 06).

**Bar at close: BSPC 835 (TZ=UTC) + pgTAP 335 / Coach 1080 /
Functions 115.** Deletion norm: the four named K5 rows + the four
named FYI-1 mock blocks — nothing else. Phases A–K code-side
COMPLETE. **Next: the 05/06 cutover planning (auth cutover, file
copy, backfills behind the HARD STOP, decommission).**

---

## 2026-06-11 — CUTOVER STAGING SCOPE (05/06) — docs-only round: fresh death-inventory + landing-zone derivation; 05 auth-cutover and 06 decommission plan OUTLINES; D-CUT1–D-CUT9 decision queue + FYI A–G; numbered round plan

**PART 0 — gate + doctrine.** Heads at start: UNIFY `e8fb7f7`, BSPC
`9e68c17`, Coach `707439c`, all trees clean, all synced. Four bars
re-verified on these exact trees before this entry: **BSPC 835 (TZ=UTC)
+ pgTAP 335 (Files=14, Result: PASS) / Coach 1080 / Functions 115.**
HARD-STOP doctrine, restated and absolute for this entire stage: the
production auth cutover, and the RUNNING of any backfill or file
migration, execute only in a future round with Kevin's explicit
approval. This round and the doc rounds that follow are documentation
ONLY; every operational sequence written into 05/06 sits under an
explicit HARD-STOP header as instructions-only. Nothing in this round
ran against any database except the local test stack for the bars.

### PART 1a — UNIFY doc census (what exists, what is stub, what 05/06 must become)

- **00_TERRAIN.md** (371 ln) — final reconciliation map; §0 census (23
  Coach Firestore collection paths) is the death-list source used in
  PART 3. No changes owed.
- **01_CANONICAL_SCHEMA.sql** (64.7 KB) — law. OWES the banked storage
  appendix ("cataloging every bucket, its limits, and its walls in
  words — due no later than the convergence sweep"). Slotted by D-CUT9.
- **02_SCHEMA_REDTEAM.md** — historical record; no changes owed.
- **03_MIGRATION_PLAYBOOK.md** — the service-swap playbook; cutover
  rounds add nothing to it (its job ended with Phase K).
- **04_CROSS_TIER_SEQUENCING.md** — the backbone; gains pointer
  annotations to the landed 05 §6 / 06 PART B when those land
  (in-place, the e71050a/D-J2 annotation precedent). Nothing binding.
- **05_PHASE_A_IDENTITY.md** — the Phase A plan. Its §6 ("SINGLE
  riskiest sub-step — the auth-credential / account cutover") is a
  PLACEHOLDER that prescribes its own successor: "treat the auth
  cutover as its own mini-plan with its own red-team pass." That
  mini-plan was never written; every later phase banked cutover lines
  pointing at "05 §6." All §8 open decisions are since ratified (OD-1
  transitional; OD-2 redeemInvite in I; OD-3 gated provisioning wins;
  OD-4 digest deferred whole to G; NM-1/NM-5 rulings; OD-6 SETTLED
  2026-06-09: NO password-hash import). **05 must become:** §6 expanded
  in place into the full auth-cutover mini-plan (PART 2 outline).
- **06_FIREBASE_RUNBOOK.md** (169 ln) — currently a beginner GO-LIVE
  guide (create the Firebase project, enable services, deploy rules +
  functions, seed). §7 sketches only the post-cutover env additions and
  carries the load-bearing banked sentence: "the **Cloud Functions stay
  hosted on Firebase** (they just read Postgres). Re-homing them off
  Firebase is a separate, optional, post-Phase-J decision." It is now
  post-Phase-J: that decision is D-CUT5. **06 must become:** the
  DECOMMISSION RUNBOOK (PART 3 outline) — file copy, backfill manifests
  behind HARD-STOP, cron, env, ordered project death, named losses.
- **07/08/10/11/12** — landed phase mini-plans; historical; no changes.
- **NOTES.md** — carries the CONSOLIDATED CONVERGENCE / CUTOVER REMOVAL
  CHECKLIST (9 items, 2026-06-09) and the banked cutover lines. 06
  RESTATES what it executes; the checklist remains authoritative for
  the convergence sweep.

### PART 1b — the Firebase death inventory (fresh, trust-nothing)

**(i) Coach app live bank — re-proven this round, exactly five files**
(fresh import grep on app/ + src/, tests excluded): AuthContext.tsx ·
app/admin.tsx · app/(tabs)/settings.tsx · app/forgot-password.tsx ·
src/config/firebase.ts. Per-file surface, re-read in full this round:
- `src/contexts/AuthContext.tsx` — firebase/auth session
  (onAuthStateChanged, signInWithEmailAndPassword, signOut) +
  `coaches/{uid}` getDoc/setDoc. Carries the ratified-dead NM-5
  auto-admin-on-first-login branch (:57–:85) — DELETED at the swap, not
  ported. signOut (:117–:139) reads the coaches doc's `fcmTokens` to
  decide push cleanup — successor reads push_tokens via the existing
  notifications service (the suite's one pinned assertion, cleanup-
  before-signout, is preserved).
- `app/admin.tsx` — onSnapshot on the WHOLE `coaches` collection (:39);
  role toggle admin↔coach (:59) and groups toggle (:73) via updateDoc.
  Successor surface does not exist yet → D-CUT8.
- `app/(tabs)/settings.tsx` — notificationPrefs toggles updateDoc the
  coaches doc (:46). **Named split-brain inside the bank:** since Phase
  G the functions read `notification_preferences` (PG); this write has
  had NO reader — a dead-end write that was accepted as part of the
  coherent-reading bank and closes at the swap → D-CUT7.
- `app/forgot-password.tsx` — sendPasswordResetEmail (:31) →
  supabase.auth.resetPasswordForEmail (redirect/template are cloud
  console staging lines in 06).
- `src/config/firebase.ts` — initializeApp + db/auth/storage/functions
  exports. Post-K the `storage` and `functions` exports have ZERO live
  importers (FYI-G); the whole file dies with the bank.

**(ii) Parent-portal residue — OUTSIDE the app-side bank claim (the K
sentence stands as scoped to app/ + src/), four files, named now:**
- `parent-portal/src/lib/firebase.ts` — full client ("Same Firebase
  project as the coach app"), NEXT_PUBLIC_FIREBASE_* env.
- `parent-portal/src/lib/auth.ts` — HYBRID by Phase A design: profile
  READ is Supabase since A; the session half (sign-in/out via
  firebase/auth, :7–:11, :28) is still Firebase. Swaps at 05 with the
  bank (same supabase.auth idiom as the portal already uses for reads).
- `parent-portal/src/app/dashboard/page.tsx` — firebase/auth `User`
  type import (:14); dies with the auth.ts swap.
- `parent-portal/src/lib/parentPortal.ts` — httpsCallable transport to
  the two portal callables. Post-cutover the caller is a SUPABASE
  session; the Firebase callable sees no request.auth → the portal data
  path MUST change (this is exactly the banked "the portal post-cutover
  data path is designed in the 05 §6 auth-cutover mini-plan") → D-CUT6.

**(iii) functions/ workspace — live plumbing until decommission.** 19
src files; 10 deployed exports (processAudioSession, processVideoSession,
sweepStuckSessions, evaluateAttendanceRules, sweepAttendanceEvaluations,
dailyDigest, redeemInvite, getParentPortalDashboard,
getParentSwimmerPortalData, syncCalendar); deps firebase-admin +
firebase-functions + supabase-js + vertexai; manual mock
`functions/src/__mocks__/firebaseAdmin.ts`. **The Functions jest bar
(12 suites / 115 tests) DIES WITH THE WORKSPACE — pre-declared NOW as a
deliberate future test-count event** (per-step declines as functions
retire under D-CUT5; the bar fully RETIRES at workspace death; the 06
doc must carry this pre-declaration verbatim).

**(iv) Root config artifacts** (die at the 06 config step):
firebase.json · .firebaserc (project `bspc-coach`; storage target
`bspc-coach.firebasestorage.app`) · firestore.rules (190 ln) ·
storage.rules (50 ln; paths /audio/**, /video/**, /profiles/**,
/imports/**, /practice_plans/{coachId}/**) · firestore.indexes.json
(315 ln). The F bank already pins: "the old Firebase `storage.rules`
retire WITH the file copy (RF-4 closes under D-F1(a))."

**(v) scripts/** — firebase-admin seed tooling: create-coach.ts,
seed-demo-data.ts, seed-calendar.ts, seed-meets.ts, seed-roster.ts
(stale-by-migration, K classification stands). **LOUD finding:**
`scripts/__tests__/seed-demo-data.test.ts` (4 tests) is INSIDE the
Coach 1080 (root jest testMatch covers scripts/__tests__; verified via
--listTests) → **the scripts deletion is a pre-declared Coach −4
event** at the 06 scripts step. check-*.sh/.mjs +
sync-functions-shared.js are repo tooling, NOT firebase — they survive.

**(vi) The live-project side** (Firebase Auth user store, Firestore
collections, Storage objects): the repo CANNOT prove a live project
exists or holds data — env files are unreadable by standing security
rule, 06 §§1–3 is a create-from-scratch guide, and OD-6 recorded "Both
apps are pre-launch with **zero real users**." Resolved by probe, not
assumption → D-CUT3. Collection-by-collection dispositions in PART 3.

**(vii) BSPC repo** — fresh grep: the string "firebase" appears ONLY in
the two migration mapping test files (identity-mapping,
roster-reconciliation), which are successor machinery (they test the
firebase_uid→profiles mapping), not residue; they retire WITH the map
tables at convergence checklist item 8. Zero firebase imports anywhere.

### PART 1c — the Supabase landing zone

- **Auth:** the BSPC Supabase project (local mirror project_id
  `bspc-swim-app`); email/password is the native provider (BSPC parents
  already use it; local config.toml is db-only/minimal — no repo-side
  auth config owed). Coach app ALREADY holds the env-driven supabase
  client (`src/config/supabase.ts`) — the swap adds no new client.
  **Design pin for the 05 doc:** supabase-js session persistence in RN
  (AsyncStorage storage adapter + autoRefreshToken) must be configured
  at the swap — today's client is data-only; cold-start session restore
  is exactly the 05 §6.4 named risk. **Identity pin (derived, not open):
  post-swap `Coach.uid` := `auth.users.id`** — forced by the D-C7
  transitional `attendance.marked_by → auth.users` FK; legacy Firebase
  uids embedded in rows remap at convergence (checklist item 5) via
  migration_identity_map.
- **Storage:** four canonical buckets live since F/H: media-audio
  (100MB, audio/*) · media-video (500MB, video/*) · profile-photos
  (5MB, image/*) · practice-plans (25MB, application/pdf). Walls:
  staff-only on media-*, signed-URL capability for parents
  (profile_photo_url), owner-folder on practice-plans
  (foldername[1] = auth.uid). This derivation IS the storage-appendix
  material (D-CUT9).
- **Backfill-receiving tables:** per-collection map in PART 3; the
  staged scaffolding lives in `BSPC/ACTIVE/migration/` — TEN dirs:
  identity, roster, attendance, times, notes, media, notifications, h,
  i, j(null) — plus `__tests__/migration/` mapping tests. The identity
  README's staged run order (steps 1–8, OD-6-settled, runner for step 3
  "not yet written") is the provisioning manifest 06 incorporates.

### PART 1d — Coach test-side bank shadows (exact, fresh)

- **Live shadow:** `src/contexts/__tests__/AuthContext.test.tsx` —
  exactly **1 test** ("cleans up push subscriptions before sign out")
  behind 3 firebase-targeting jest.mock blocks (config/firebase,
  firebase/auth, firebase/firestore). At 05 it TRANSFORMS in place
  (assertion preserved; mocks re-pointed to the supabase idiom) + new
  pins per §6.4 — never deleted.
- **The shared manual mock** `src/__mocks__/firebase.ts` — retires WITH
  the bank, but only after the next item is swept:
- **LOUD fresh-sweep finding (the expectation did not predict this):
  TWELVE more test files carry DEAD `jest.mock('../../config/firebase',
  …)` lines** — 8 routing through the shared mock (GoalCard, docExport,
  attendanceStore, calendarStore, meetStore, practiceStore,
  swimmersStore, videoStore) + 4 with inline factories (csvImport,
  docxExport, export, hy3Import). Same class as the four FYI-1 removals
  K6 executed: their subjects' module graphs no longer reach
  config/firebase (the five-file live grep proves it), so the mocks are
  no-ops. They sweep at the 05 code round with per-file
  verify-at-deletion evidence, ZERO test-count impact (K6 precedent:
  1080 exact) — FYI-A. Eight other files (seasonStore, search,
  meetResultsImport, VideoCompareScreen, useTimes, useGoals,
  useSwimmerAttendance, sdifImport) mention firebase in COMMENTS only —
  no action.
- **Functions-side:** `functions/src/__mocks__/firebaseAdmin.ts` + all
  12 suites die with the workspace (the (iii) pre-declaration).
- **scripts-side:** seed-demo-data.test.ts = the −4 event ((v) above).

### PART 2 — 05 AUTH CUTOVER mini-plan (outline; the doc lands post-ratification)

Lands as the in-place expansion of 05 §6 (D-CUT1). Sections:

- **§6.0 Precondition line (opens the doc, quoted from the K landed
  log at e8fb7f7):** "after Phase K, the Coach app's ENTIRE live
  firebase surface is EXACTLY the five-artifact auth bank — …— re-proven
  by a fresh import grep on the final tree." Plus the portal residue
  inventory (PART 1b(ii)) as the second, portal-half precondition.
- **§6.1 Provisioning (the BINDING GATE, banked text quoted):** OD-6
  settled ("accounts are provisioned with fresh Supabase credentials…
  never touches password material"); the identity README staged order
  1–8; **THE PROBE, verbatim from the bank: "after provisioning, every
  Firestore parents-doc uid must resolve a NON-empty profile via the
  map; zero-resolves = STOP. The mask is removed by verification, not
  by code (data-layer freeze)."** Plus the banked post-backfill
  invite/guardianship agreement audit, and the NM-1 step: "the live
  list must be pulled from the `coaches` collection at backfill time
  for Kevin to confirm; not derivable from code" (Kevin = super_admin;
  remaining Coach "admins" → coach_admin).
- **§6.2 The swap design (all five die together; one logical change per
  commit):** AuthContext → supabase.auth (onAuthStateChange +
  getSession; RN persistence pin; signInWithPassword behind the frozen
  error-message map; coach resolution = profiles(user_id) +
  coach_groups [+ notification_preferences per D-CUT7] mapped into the
  frozen `Coach` type, super_admin→'admin' / coach_admin→'coach', uid
  := auth.users.id; NM-5 branch deleted; push cleanup via push_tokens).
  forgot-password → resetPasswordForEmail. settings → useAuth coach +
  D-CUT7 prefs surface. admin → D-CUT8 staff surface. config/firebase.ts
  + src/__mocks__/firebase.ts deleted (after FYI-A sweep). Portal half:
  lib/auth.ts session → supabase.auth; dashboard User type → supabase
  Session/User; lib/firebase.ts dies UNLESS D-CUT6 keeps the callable
  transport temporarily (then it survives functions-scoped until the
  D-CUT5 step that retires the callables).
- **§6.3 What cutover MUST NOT change (D-I1 interplay, quoted):**
  redemption stays staff-authorized LINK creation; approval stays
  ACCOUNT activation; **"'dark until approval' means ZERO rows from
  every swimmer-keyed table, proven in pgTAP"** — unchanged, including
  the explicitly-accepted pending-redeemer guardianships-row read; OD-3
  gated provisioning governs all new accounts (no auto-approve
  anywhere; NM-5's removal composes); parent_invites + the redeem RPC
  are already PG (Phase I) — the cutover changes WHO the caller is
  (native supabase uid), and nothing else about invites.
- **§6.4 Swap test plan (pre-declared):** Coach 1080 → **+10 to +18,
  ZERO deletions** (provisional band, K-precedent — fixed per-export in
  the 05 doc): AuthContext suite transforms 1→1 + new mapping/role/
  session pins; D-CUT8 staff surface ≥2 pins per export; D-CUT7 prefs
  surface ≥2 pins per export; portal-auth additions land in root
  `test/` (the Phase A +5 precedent — parent-portal/ itself is outside
  the bar). FYI-A dead-mock sweep + shared-mock deletion = ZERO count
  change with per-file verify-at-deletion evidence. BSPC 835 + pgTAP
  335 + Functions 115 EXACT-unchanged through every 05 commit.
- **§6.5 Rollback + smoke:** pre-launch rollback = env flip back +
  revert commit; smoke checklist (coach login, role render, admin list,
  prefs toggle persists to PG, reset email round-trip, portal login).

### PART 3 — 06 DECOMMISSION RUNBOOK (outline; PART B of 06 per D-CUT2)

Every operational sequence below sits under its own HARD-STOP header in
the doc; nothing runs in any docs round.

- **§B0 Live-project inventory probe (D-CUT3, FIRST):** per-collection
  doc counts + storage prefix counts + auth user count from the
  console/CLI; output feeds the D-CUT4 keep/drop sheet. EMPTY project →
  every data manifest is a named no-op (the probe output is the record).
- **§B1 FILE COPY — owns object existence; closes the D-K2 caveat
  (quoted: "any pre-H row carrying a legacy Firebase path 404s against
  a signed Supabase URL until the 06-runbook file-copy step, which owns
  object existence").** Map: /audio/** → media-audio · /video/** →
  media-video · /profiles/** → profile-photos ·
  /practice_plans/{firebaseUid}/** → practice-plans/{auth.users.id}/
  (folder remap via migration_identity_map) **+ rewrite the
  practice-plan rows' storagePath values to the new keys** (without the
  rewrite, getSignedFileUrl still 404s — the caveat closes only when
  both halves land) · /imports/** → NO destination (D-H2b: no import
  file was ever uploaded; absence is parity — named no-op).
  Verification: per-bucket object counts + a spot signed-URL resolve;
  the dashboard todayPlan render is the named acceptance check. F-bank
  lines carried: confirm hosted storage tier covers the 500MB cap
  BEFORE the copy; storage.rules retire WITH the copy.
- **§B2 BACKFILL MANIFESTS (one per collection → table, each with its
  verification query, quoted from its migration/ README):** coaches →
  profiles + coach_groups (identity) · parents → profiles +
  guardianships (identity) · swimmers → swimmers (roster,
  migration_swimmer_map) · attendance → attendance (three-bucket dedup)
  · times → swim_results (personal_bests via the D-D5 trigger, never
  hand-written) · notes → swimmer_notes · voice_notes rows →
  swimmer_voice_notes (files ride §B1) · audio/video sessions + drafts
  → their F tables (media) · notification_rules → notification_rules ·
  notifications (CF-write) → per the notifications README disposition,
  quoted verbatim in the doc · meets/calendar_events+rsvps/
  practice_plans/season_plans+weeks/import_jobs → their H tables (h) ·
  parent_invites → parent_invites (i) · aggregations → NULL-MANIFEST
  (j; nothing to copy, ratified twice). **LOUD gap, named: `goals` and
  `group_notes` have NO migration/ scaffolding dir** (they migrated
  pre-UNIFY-discipline, 2026-05-31) — the 06 doc round WRITES those two
  manifests fresh. Never-implemented paths (medical, meets/relays,
  live_events, splits, workout_library) = named no-ops. **Named
  pre-launch data losses, coach_chat FIRST (D-J7 as corrected, quoted:
  "whatever test chatter sits in the collection dies with Firestore at
  the 06-runbook decommission step (named pre-launch data loss)");**
  then any keep/drop-sheet drops Kevin signs under D-CUT4.
- **§B3 CRON (D-G6, quoted verbatim in the doc):** "schedule
  `send-notification` + `cleanup-tokens` (Supabase cron) at cutover
  staging with an end-to-end drain verification… enqueue one ordinary
  job AND one rule-mirroring flagged job; assert exactly one in-app row
  per recipient for each (the writer-owned row, never a sender
  duplicate)" — with the skip_in_app mechanism sentence carried.
- **§B4 ENV (F/G banks, quoted):** set `PROCESS_SHARED_SECRET`
  (functions env) + `EXPO_PUBLIC_PROCESS_FUNCTIONS_BASE_URL` /
  `EXPO_PUBLIC_PROCESS_SHARED_SECRET` (app env) before the media
  pipeline goes live; "the evaluateAttendanceRules endpoint rides the
  SAME `PROCESS_SHARED_SECRET` + `EXPO_PUBLIC_PROCESS_*` env lines
  already banked at F (no new secrets)"; SUPABASE_URL +
  SUPABASE_SERVICE_ROLE_KEY via functions:secrets:set; portal
  NEXT_PUBLIC_SUPABASE_* (06 §7 existing lines, carried into PART B).
- **§B5 OD-1 CONVERGENCE ORDERING — restated VERBATIM in the manifests,
  executes at the convergence sweep, NOT in 06:** "backfill
  guardianships → switch BSPC reads/RLS → drop family_id" — the
  consolidated 9-item checklist incorporated by reference with items
  1/2/6 quoted in full; map-table drop (item 8) sequenced AFTER the
  convergence sweep (the maps are the remap inputs: cutover →
  convergence sweep → drop maps).
- **§B6 FIREBASE PROJECT DEATH, ordered:** (1) Email/Password sign-in
  disabled only after 05 is verified live (the existing §7 HARD-STOP
  sentence); (2) Firestore rules → deny-all; data per the keep/drop
  sheet; (3) **functions/ workspace retirement per D-CUT5 — LAST
  compute standing; carries the pre-declared Functions-bar event (115 →
  per-step declines → bar RETIRES; firebaseAdmin mock + 12 suites with
  it)**; (4) repo config deletions (firestore.rules, storage.rules,
  firestore.indexes.json, firebase.json, .firebaserc) — one named
  commit; (5) scripts/ firebase seeds deletion WITH
  scripts/__tests__/seed-demo-data.test.ts → **Coach −4, pre-declared**;
  (6) portal lib/firebase.ts + parentPortal.ts transport per
  D-CUT6/D-CUT5 timing; (7) the Firebase project deleted in the console
  + Blaze billing closed.
- **§B7 Named pre-launch data losses, consolidated** (coach_chat first;
  then the keep/drop-sheet outcomes; each loss named, none silent).

### PART 4 — the banked UNIFY/01 storage appendix

Bank text: "UNIFY/01 gains a storage appendix cataloging every bucket,
its limits, and its walls in words — due no later than the convergence
sweep." The material is fully derived in PART 1c. Slot decided by
D-CUT9 below (recommendation: rider commit in the 06 doc round).

### PART 5 — numbered round plan (post-ratification) + the decision queue

Round plan (one green commit per logical change; all four bars EXACT at
every commit except the pre-declared events; tripwire stays armed):

1. **CUT-0 (UNIFY, paperwork):** ratification recording for
   D-CUT1–D-CUT9 + FYI A–G, checked against these blocks verbatim.
2. **CUT-1 (UNIFY, docs):** 05 §6 in-place expansion lands (PART 2
   outline → full mini-plan with its own red-team section, per 05's own
   prescription). Bars untouched.
3. **CUT-2 (UNIFY, docs):** 06 PART B decommission runbook lands (PART
   3 outline → full manifests incl. the two fresh goals/group_notes
   manifests, every sequence behind HARD-STOP). Bars untouched.
4. **CUT-3 (UNIFY, docs, rider):** the 01 storage appendix (if D-CUT9 =
   (a)). Bars untouched.
5. **CUT-4+ (code, Coach + portal-half):** the 05 swap executes under
   its own pre-declared band (+10..+18, zero deletions) — separate
   round(s), only after the 05 doc is ratified. BSPC/pgTAP/Functions
   EXACT-unchanged throughout.
6. **STAGING/CUTOVER rounds (ALL behind HARD-STOP, Kevin live):**
   dry-run rehearsal against a throwaway project (the 05 §6 standing
   recommendation; the provisioning-runner skeleton for identity README
   step 3 lands here as scaffolding, unit-tested pure parts only); §B0
   probe + keep/drop sheet; provisioning + the §6.1 probe gate; §B1
   file copy; §B3 cron + §B4 env; verification. Then the OD-1
   convergence sweep as its own session (§B5); then §B6 project death
   with the Functions phase per D-CUT5.

**[DECIDE] D-CUT1 — where the 05 auth-cutover mini-plan lands.**
(a) In-place expansion of 05 §6 (every banked pointer says "05 §6";
in-place keeps every pointer true — the e71050a/D-J2 in-place
precedent). (b) New standalone doc (13_CUTOVER_AUTH.md) with a pointer
from 05 §6. **Recommendation: (a).**

**[DECIDE] D-CUT2 — where the decommission runbook lands.** (a) Extend
06 in place: existing go-live content becomes PART A (kept, marked
historical/optional — it documents the project being killed), new PART
B = DECOMMISSION RUNBOOK (the K landed log, D-K2 caveat, and D-J7
correction all name "the 06-runbook … step"; extending 06 keeps those
pointers true). (b) New standalone doc. **Recommendation: (a).**

**[DECIDE] D-CUT3 — the live-Firebase-project reality gate.** The repo
cannot prove whether a live project exists or holds data (env unreadable
by standing security rule; 06 §1 is a create-from-scratch guide; OD-6
recorded zero real users). (a) Condition-first manifests: §B0 inventory
probe is STEP 0 of the runbook; every data manifest branches on its
probe count, EMPTY → named no-op; the probe output becomes the cutover
record. (b) Kevin states the reality now and the manifests are written
to that one world. **Recommendation: (a) — the docs stay true in every
world and the probe doubles as the D-J7 "whatever test chatter" record.**

**[DECIDE] D-CUT4 — which backfills RUN at cutover (pre-launch, zero
real users).** (a) Identity ALWAYS runs (coach accounts must exist; the
§6.1 probe demands non-empty resolution for every parents doc that
exists); every DATA manifest runs only per a keep/drop sheet Kevin
signs at execution with the §B0 counts in front of him — drops become
§B7 named losses. (b) Run everything (full-rehearsal value, even for
test data). (c) Clean-slate: provision staff fresh, skip all data
manifests, name every collection a loss. **Recommendation: (a) — the
machinery is still rehearsed by the mandatory dry-run either way.**

**[DECIDE] D-CUT5 — the functions/ workspace fate (the banked
"separate, optional, post-Phase-J decision", now due).** Full project
death requires the 10 deployed functions to stop being Firebase-hosted.
(a) COLLAPSE-FIRST, then re-home the irreducible rest: portal callables
retire when D-CUT6(a) lands (direct reads); redeemInvite is already a
thin shell over the PG RPC — its caller can invoke the RPC directly;
syncCalendar + the sweepers + dailyDigest move to Supabase cron (the
D-G6 line already moves two jobs); the irreducible server piece is the
AI pipeline (processSession + Vertex + GCS staging) + evaluateAttendance
endpoint — re-homed in a dedicated phase (host choice = its own future
[DECIDE] at that phase; Supabase Edge Functions is the default
candidate). Functions bar declines per named retirement, RETIRES at
workspace death; the Firebase project survives functions-only until the
final re-home. (b) Port the whole workspace in one dedicated phase
first, then decommission. (c) Keep the functions Firebase-hosted
indefinitely (the project never fully dies — conflicts with §B6 step 7).
**Recommendation: (a) — maximum deletion before any porting, and every
step is a named, bar-tracked event.**

**[DECIDE] D-CUT6 — the portal's post-cutover data path** (the banked
05 §6 design item). After 05, the portal session is Supabase; the
Firebase callable sees no request.auth, so the current transport is
dead the moment auth cuts over. (a) Direct Supabase reads under the
parent RLS walls (the canonical end-state; attendance_parent_view +
the family-arm views exist; gap inventory owed: the banked D-H5(b)
calendar parent arms + any portal-payload field with no parent-readable
source — the 05 doc round produces this inventory; small gap → build at
the swap rounds, large gap → re-banked with a due phase, on the
record). (b) Keep the callables, re-fronted as Supabase-JWT-verified
HTTPS endpoints on the functions (delays D-CUT5 collapse; new verify
surface). (c) Portal re-banked dark to a later product round (it is
pre-launch; the coach app is the live product). **Recommendation: (a)
as the designed end-state in 05 §6, with the gap inventory deciding
WHEN it builds; (b) explicitly disrecommended (new auth surface on a
component slated for collapse).**

**[DECIDE] D-CUT7 — the settings notification-prefs successor.** No
client surface for `notification_preferences` exists (fresh export
greps of notifications.ts + notificationRules.ts). (a) The existing
notifications service gains get/upsert preferences exports (the D-K4
addition class: named signatures, ≥2 house-mock pins each, landing
BEFORE the consumer re-point; settings' dead-end doc write dies with
the bank). (b) Settings prefs go read-only/hidden until a product
round. **Recommendation: (a) — it is the same narrow-successor shape
every phase has used; (b) silently drops a shipped affordance.**

**[DECIDE] D-CUT8 — the admin.tsx successor + isAdmin semantics.**
Surface: (a) a NEW small `staff.ts` service (subscribeStaffProfiles +
setStaffRole + setStaffGroups; profiles+coach_groups; the K-era
"no new services" pin was a Phase K pin, not a standing law) or (b)
additions to an existing service (none owns profiles administration —
forced fit). Semantics: post-swap `isAdmin` = role==='admin' maps to
super_admin ONLY (NM-1: Kevin sole super_admin) — admin screen AND the
settings import buttons become Kevin-only; role changes are
DB-enforced super_admin-only regardless (enforce_profile_self_update).
(a-strict) Accept: UI parity with NM-1's deliberate-assignment intent;
any widening (e.g. imports open to all staff, which the is_staff() DB
walls would permit) is a future PRODUCT decision, never a migration
side-effect. (b-split) Introduce an isStaff gate now so coach_admins
keep the import screens. **Recommendation: surface (a) + semantics
(a-strict), with (b-split) named as the future product option.**

**[DECIDE] D-CUT9 — the 01 storage-appendix landing slot (PART 4).**
(a) Rider commit in the 06 doc round (CUT-3): the material is fully
derived (PART 1c); one paperwork commit closes a bank early. (b)
Re-bank to the convergence sweep with the due date restated on the
record. **Recommendation: (a).**

**FYI bundle (accept or strike, none blocks ratification):**
- **FYI-A** — the 12 dead jest.mock('../../config/firebase') lines
  (PART 1d list) sweep at the 05 code round with per-file
  verify-at-deletion evidence; the shared mock deletes after; zero
  count impact (K6 precedent).
- **FYI-B** — the portal 4-file firebase residue is OUTSIDE the
  app-side bank claim; the K residual-set sentence stands as scoped
  (app/ + src/); this entry is the portal residue's naming of record.
- **FYI-C** — settings' notificationPrefs doc write has been a dead-end
  since Phase G (functions read PG); named split-brain inside the
  accepted bank; closes via D-CUT7.
- **FYI-D** — legacy /imports/** storage path has no canonical bucket
  (D-H2b absence-is-parity); the file copy names it a no-op.
- **FYI-E** — scripts/__tests__/seed-demo-data.test.ts (4 tests) sits
  inside the Coach 1080; the −4 event rides the 06 scripts step,
  pre-declared (PART 1b(v)).
- **FYI-F** — BSPC-side "firebase" mentions = the two mapping-test
  successors only; they retire with the map tables (checklist item 8).
- **FYI-G** — config/firebase.ts `storage` + `functions` exports have
  zero live importers post-K; verified again at deletion.

**Execution blocks on D-CUT1–D-CUT9. No 05/06 document content lands
this round; no code changes anywhere; the four bars stand exact at
835 (TZ=UTC) + 335 / 1080 / 115 on heads e8fb7f7 / 9e68c17 / 707439c.**

---

## 2026-06-11 — CUTOVER RATIFICATION (CUT-0) — D-CUT1–D-CUT9 ALL RATIFIED (Kevin, in words, checked against the blocks at cdfc8d6); FYI A–G accepted unstruck; PWD-PROOF adopted as standing process; doc rounds CUT-1–CUT-3 unblocked

**Gate:** heads at the start of the doc rounds: UNIFY `cdfc8d6`, BSPC
`9e68c17`, Coach `707439c`, all trees clean, all synced. Bars pinned
EXACT at every commit of this round: BSPC 835 (TZ=UTC) + pgTAP 335 /
Coach 1080 / Functions 115; all commits UNIFY-only, BSPC and Coach
untouched. HARD-STOP doctrine in force for the whole round:
documentation only; no command in any manifest executes; nothing runs
against any database (local test stack for the bars excepted); every
operational sequence sits under an explicit HARD-STOP header,
instructions-only.

**Standing process line, adopted this round forward — PWD-PROOF**
(named after the scope round's catch, where a backgrounded Coach jest
launched without an explicit cd executed in the WRONG workspace and
reproduced the BSPC output byte-for-byte): every backgrounded or
parallel bar run carries an explicit `cd` + `pwd` proof in its output;
cited numbers come only from proven runs.

**Ratification-check method:** each ruling below was checked
word-against-block against the [DECIDE] payloads as committed at
`cdfc8d6`. A ruling MATCHes when it selects an option its block
offered and any added rationale is consistent with the block; anything
else would be FLAGGED and recorded half-open, never force-fit.
**Result: nine MATCHes, zero mismatches, nothing half-open.** Two
rulings add precedent citations beyond their blocks; both resolve in
the record and are noted in place.

**D-CUT1 RATIFIED** — The 05 auth-cutover mini-plan expands 05 §6 IN
PLACE. Every banked pointer in the record reads "05 §6"; in-place
amendment keeps every pointer true, per the e71050a/D-J2 in-place
precedent. A standalone doc is declined as pointer-orphaning.
*Check: MATCH — option (a) as recommended.*

**D-CUT2 RATIFIED** — The decommission runbook lands by extending 06
IN PLACE: existing go-live content kept as PART A, marked
historical/optional; new PART B is the DECOMMISSION RUNBOOK. The K
landed log, the D-K2 caveat, and the D-J7 correction all name "the
06-runbook step"; extending 06 keeps all three landed pointers true.
A standalone doc is declined.
*Check: MATCH — option (a) as recommended.*

**D-CUT3 RATIFIED** — Manifests are written CONDITION-FIRST: the §B0
inventory probe is STEP 0 of the runbook; every data manifest branches
on its own probe count, EMPTY resolving to a named no-op; the probe
output is preserved as the cutover record and doubles as the D-J7
"whatever test chatter" record. Writing to one asserted world is
declined — counted facts at execution time outrank anyone's
recollection of the project's state, the D-J7 lesson applied
prospectively. Kevin may volunteer what he knows; nothing in the docs
depends on it.
*Check: MATCH — option (a) as recommended; the added
counted-facts-outrank-recollection line applies the D-J7 lesson
prospectively, consistent with the block's own "doubles as the D-J7
record" clause.*

**D-CUT4 RATIFIED** — Identity ALWAYS runs: coach accounts must exist,
and the §6.1 probe demands non-empty resolution for every parents doc
that exists. Every DATA manifest runs only per a keep/drop sheet Kevin
signs at execution with the §B0 counts in front of him; every drop
becomes a §B7 named loss. Run-everything is declined (rehearsal
without consent pollutes the canonical store with test chatter);
clean-slate is declined (pre-decides without counts). The machinery is
rehearsed regardless by the mandatory dry-run.
*Check: MATCH — option (a) as recommended.*

**D-CUT5 RATIFIED** — COLLAPSE-FIRST, then re-home the irreducible
rest. The portal callables retire when D-CUT6's direct reads land;
redeemInvite's caller invokes the PG RPC directly and the shell
retires; syncCalendar, the sweepers, and dailyDigest move to Supabase
cron, the banked D-G6 line already carrying two of those jobs; the
irreducible server piece — the AI pipeline (processSession + Vertex +
GCS staging) plus the evaluateAttendance endpoint — re-homes in a
dedicated future phase whose host choice is its own future [DECIDE],
Supabase Edge Functions the default candidate. The Functions bar
declines ONLY by named, pre-declared retirements and retires entirely
at workspace death. The Firebase project survives functions-only until
the re-home completes; §B6 project deletion is the FINAL act, after
it. Whole-workspace porting is declined (ports code slated for
deletion); indefinite Firebase hosting is declined (conflicts with the
ratified project-death endpoint).
*Check: MATCH — option (a) as recommended; "project deletion is the
FINAL act, after the re-home" makes explicit what the block's
"survives functions-only until the final re-home" already ordered.*

**D-CUT6 RATIFIED** — The portal's canonical post-cutover data path is
DIRECT SUPABASE READS under the parent RLS walls, designed as the
end-state in 05 §6. The 05 doc round produces the gap inventory in
full: the banked D-H5(b) calendar parent arms plus every
portal-payload field with no parent-readable source. A small gap
builds at the swap rounds; a large gap re-banks with a named due phase
on the record — the inventory decides WHEN, the end-state is settled
NOW. Re-fronting the callables with Supabase-JWT verification is
declined as a new verification surface on a component slated for
collapse; re-banking the portal dark is declined as dominated by the
inventory-gated path.
*Check: MATCH — option (a) as recommended, (b) declined exactly as
the block disrecommended.*

**D-CUT7 RATIFIED** — The notifications service gains get-preferences
and upsert-preferences exports in the D-K4 addition class: named
signatures bound in the 05 doc, at least two house-mock pins each,
landing BEFORE the settings consumer re-point
(successors-precede-consumers). This closes the FYI-C split-brain —
the dead-end Firestore prefs write dies with the bank — and restores a
shipped toggle surface silently ineffective since Phase G.
Read-only/hidden-until-product-round is declined as silently dropping
a shipped affordance.
*Check: MATCH — option (a) as recommended.*

**D-CUT8 RATIFIED** — Surface: a NEW small staff.ts service owning
profiles administration — subscribeStaffProfiles, setStaffRole,
setStaffGroups over profiles + coach_groups — in the D-K4 addition
discipline (signatures bound in the 05 doc, ≥2 house-mock pins each,
landing before the admin.tsx re-point). The Phase-K "no new services"
pin bound Phase K only and is not standing law; forced-fit additions
to a service that does not own profiles administration are declined.
Semantics: A-STRICT — post-swap isAdmin maps to super_admin ONLY, UI
parity with NM-1's deliberate-assignment intent; the admin screen and
the settings import buttons become Kevin-only at the swap; role
changes remain DB-enforced super_admin-only regardless
(enforce_profile_self_update). Any future opening of the import
screens to staff — which the is_staff() walls would permit — is a
NAMED PRODUCT decision in the D-H9 class on a shipping surface, never
a migration side-effect; (b-split) is recorded as that future option.
*Check: MATCH — surface (a) + semantics (a-strict) as recommended;
the added "D-H9 class" citation resolves in the record (D-H9,
2026-06-10: the ratified named-widening product decision on the meets
table — exactly the class of deliberate, named widening the ruling
invokes for any future import-screen opening).*

**D-CUT9 RATIFIED** — The 01 storage appendix lands as the CUT-3 rider
commit in the 06 doc round, consuming the PART 1c derivation (the four
buckets with limits and walls), amended into 01 in place with a dated
annotation per the e71050a precedent. Re-banking to the convergence
sweep is declined: the material is fully derived, and carrying
finished work as debt serves nothing.
*Check: MATCH — option (a) as recommended.*

**FYI A–G: ALL ACCEPTED AS NAMED, none struck** — (A) the 12 dead
jest.mock lines sweep at the 05 code round with per-file
verify-at-deletion evidence, the shared mock deleting after, zero
count impact, K6 precedent; (B) the portal four-file residue is
outside the app-side bank claim, the K residual-set sentence stands as
scoped, and the scope entry is the residue's naming of record; (C) the
settings prefs doc write is a named split-brain inside the accepted
bank since Phase G, closing via D-CUT7; (D) the legacy /imports/**
path has no canonical bucket per D-H2b absence-is-parity, and the file
copy names it a no-op; (E) the 4 seed-script tests inside the Coach
1080 are a pre-declared −4 event riding the 06 scripts step — **Coach
1080 → 1076 at that named future commit, exact**; (F) the BSPC-side
firebase mentions are the two mapping-test successors only, retiring
with the map tables; (G) config/firebase.ts's storage and functions
exports have zero live importers post-K, verified again at deletion.
*Check: consistent with the bundle as committed; FYI-E's added
arithmetic (1080 → 1076) restates the −4 event exactly.*

**Effect: the cutover DECIDE queue is EMPTY.** CUT-1 (05 §6 in-place
expansion), CUT-2 (06 PART A/PART B decommission runbook), and CUT-3
(the 01 storage-appendix rider) execute in this round — one UNIFY
commit each, bars exact at each. **The swap CODE rounds (CUT-4+) do
NOT start this round:** they are authorized only after the director
reviews the bound successor signatures, the pre-declared test events,
and the gap-inventory verdict in this round's report.

---

## 2026-06-11 — CUT-4-OPEN — SWAP UNLOCKED: CALL-1..CALL-4 RECORDED (Kevin, in words, checked against the bindings at 6038377) + THE SWAP-ROUND PRE-DECLARATION TABLE (exact, fixed before any code commit lands)

**Gate:** heads at the start of the swap round: UNIFY `eb0a54c`, BSPC
`9e68c17`, Coach `707439c`, all trees clean, all synced. Baseline bars
proven fresh at those heads (STEP 0, every run with explicit `cd` +
`pwd` proof): BSPC 835 (TZ=UTC) + pgTAP 335 (Files=14) / Coach 1080 /
Functions 115. **PWD-PROOF's second live catch, named:** the STEP-0
Coach jest call was issued without its own explicit `cd` and its pwd
line proved it executed in BSPC/ACTIVE (it reproduced the BSPC 835);
the run was re-issued correctly and the cited 1080 comes from the
proven re-run. HARD-STOP restated for the round: this is a CODE
round — nothing runs against any live store; no §B0 probe, no
provisioning, no backfill, no file copy, no live-auth action of any
kind. The §6.1 provisioning probe stays a binding gate at PROVISIONING
(a future HARD-STOP-zone operation with Kevin present), not work for
today. Local test stack only.

**Check method (CUT-0 precedent):** each call below was checked
word-against-binding against 05 §6.2a / §6.2b / §6.4 / §6.6 as landed
at `6038377`. A call MATCHes when it accepts what its binding bound
and any added rationale is consistent with the binding; anything else
would be FLAGGED and the round STOPPED, never force-fit. **Result:
four MATCHes, zero mismatches. The swap is unlocked.**

**CALL-1 — SUCCESSOR SIGNATURES: RATIFIED.** Both successor signature
sets are APPROVED AS BOUND at 6038377. D-CUT7 pair:
getNotificationPreferences() → {pushEnabled, digestEnabled};
upsertNotificationPreferences(Partial) → void; own-row RLS
(notification_prefs_own); ON CONFLICT (user_id); a missing row reads
both-true (schema defaults + dailyDigest missing-row-means-included);
4 bound pins minimum. D-CUT8 — staff.ts as a NEW service: StaffProfile
shape as bound; subscribeStaffProfiles(cb) → unsubscribe;
setStaffRole(profileId, 'super_admin'|'coach_admin');
setStaffGroups(profileId, Group[]) via delete+insert reconciliation;
transport = postgres_changes on profiles + coach_groups; NO
client-side authority pre-check — enforce_profile_self_update is the
wall (A-STRICT semantics; the screen is Kevin-only via isAdmin); 6
bound pins minimum. Signatures land AS WRITTEN; frozen exports stay
byte-frozen; successors precede consumers.
*Check: MATCH — restates §6.2a and §6.2b exactly as bound; the
successors-precede-consumers ordering law matches the §6.2
one-logical-change-per-commit design.*

**CALL-2 — SETTINGS TOGGLES: RATIFIED.** The three reader-less
settings toggles (newNotes, attendanceAlerts, aiDraftsReady) RETIRE at
the swap as a NAMED UI change in the D-K3 class. The Daily Digest
toggle is restored end-to-end onto digest_enabled — the D-CUT7
"restores a shipped surface" intent lands exactly there. The read-only
Push OS-status row stays read-only (a pushEnabled toggle is a future
product decision — no-widening). The frozen Coach.notificationPrefs
type keeps all four keys with type-compat true defaults so no consumer
changes shape. Persisting reader-less keys to new PG columns is
DECLINED as the FYI-C dead-end class reborn — a toggle that lies.
Named paths back: aiDraftsReady returns WITH the banked D-G4 producer;
attendanceAlerts is superseded by the real notification_rules surface;
newNotes returns only if a product round revives its producer. KEVIN
LEVER: if Kevin says keep the toggles, this call re-opens BEFORE the
settings re-point lands; otherwise it stands.
*Check: MATCH — ratifies the §6.2a RECOMMENDED disposition in its own
words; the KEVIN LEVER is an addition consistent with the binding's
"returns to the director" framing and is honored by sequencing (the
settings re-point lands late in the Coach sequence, after the
successor surfaces and the auth core).*

**CALL-3 — TEST-EVENT TABLE: RATIFIED.** The 05 §6.4 table is ACCEPTED
AS BOUND. Coach 1080 → declared band +10..+18 with ZERO deletions (the
AuthContext suite TRANSFORMS 1→1 preserving the push-cleanup
assertion; D-CUT7 +4 min; D-CUT8 +6 min; new AuthContext pins +3..+5 —
role map super_admin→admin / coach_admin→coach / non-staff→null,
cold-start session restore, signOut push_tokens cleanup; settings +
forgot-password +1..+2; portal session pins +0..+1 landing in root
test/, Phase A precedent; FYI-A 12-file dead-mock sweep +
src/__mocks__/firebase.ts deletion at count 0 with per-file
verify-at-deletion, K6 precedent). BSPC 835 and Functions 115 EXACT
through every 05 commit. pgTAP 335 EXACT through every 05 commit
EXCEPT the §6.6 gap-build commit, which ADDS pins in a +4..+8 band
fixed by its own pre-declaration. The realtime-publication migration
(exactly 23 → exactly 25: + profiles, + coach_groups) updates pgTAP
011's exact-membership VALUES in the SAME commit as a CONTENT-ONLY
change — pgTAP stays 335 there, pre-declared; event delivery rides
existing walls (profiles_select_admin, coach_groups_staff). Exact
per-commit counts fix in this round's pre-declarations, which the
execution report MUST OPEN WITH.
*Check: MATCH — the §6.4 table and its band sentences accepted
verbatim; the fix-per-commit requirement is discharged by the
PRE-DECLARATION TABLE below, committed in this entry BEFORE any code
commit lands.*

**CALL-4 — GAP VERDICT: RATIFIED.** The §6.6 SMALL verdict is ACCEPTED
and the reserved fork resolves to BUILD AT THE SWAP ROUNDS. GAP-1
closes by adding the is_my_swimmer() OR-arm to swimmers_select_own
(the standing transitional two-arm shape, RC-1/RD-10; narrows to
guardianships-only at convergence with checklist items 3/9). GAP-2
closes with the narrow swimmer_strengths_parent_view(swimmer_id,
strengths) WHERE is_my_swimmer(swimmer_id) (D-C4 one-wall-one-rule;
the staff table stays staff-only). BOTH land in ONE BSPC migration
carrying the §6.4 +4..+8 pgTAP band. The portal's parentPortal.ts
re-points from httpsCallable to direct reads with the DTO interfaces
FROZEN. Capability-preserving: the callable already served these same
parents this same data via its sanitized service-role slice — a
transport re-homing, not a widening. This unblocks decline-schedule
step C1 on schedule. Re-banking declined. (On record: schedule[] has
been served EMPTY since Phase H — parity-is-empty; the D-H5(b) bank
stands.)
*Check: MATCH — accepts the §6.6 verdict and recommendation exactly;
the added capability-preserving line is TRUE against the callable as
re-read fresh this round (functions/src/callable/parentPortal.ts
serves sanitized swimmers/strengths/goals/times/attendance slices via
service-role to exactly the linkedSwimmerIds parents — the same
parents, the same fields); the C1-unblock line matches 06 §B6's "gated
on D-CUT6 direct reads live (05 §6.6)".*

**Four derivation facts pre-stated for the record (fresh reads this
round, so the landed log carries no surprises):**
1. **The signOut re-point adds NO service export.** AuthContext reads
   its own active `push_tokens` rows with the supabase client (own-row
   RLS, `push_tokens_own`) and unregisters EACH via the EXISTING
   `unregisterPushToken` export. The D-K4 addition freeze holds: the
   only service additions this round are the two ratified surfaces.
2. **The portal redeem re-point is the RPC's designed second path.**
   `redeem_parent_invite` already GRANTs EXECUTE to authenticated
   (00010:131) and derives the redeemer from auth.uid() — the D-I2
   spoof-proof clause IGNORES the profile param for end users. The
   portal calls the RPC directly with the SAME frozen INV01/INV02/
   INV03 → message-string map the Phase-I shell carries; the shell
   itself retires later at 06 §B6 step C2, unchanged this round.
3. **GAP-1's family arm narrows to the 00005 idiom as it widens.** The
   new two-arm swimmers_select_own carries the SAME family arm shape
   attendance/times/goals already have (family_id NOT NULL + approved
   account) — the 00004/00005 hole-closing precedent applies to the
   pending-parent read, pinned in the new pgTAP file.
4. **Non-staff means role 'family'.** user_role is
   ('family','coach_admin','super_admin') — the §6.2 "non-staff"
   resolution (coach = null) keys on role ∉ {super_admin, coach_admin}
   OR account_status ≠ 'approved'.

### THE PRE-DECLARATION TABLE (exact; fixed NOW, before any code commit; landing outside any line = STOP)

| # | Commit | Repo | One-line scope | BSPC jest | pgTAP | Coach jest | Functions |
|---|---|---|---|---|---|---|---|
| 0 | CUT-4-OPEN | UNIFY | this entry: CALL-1..4 + this table | 835 (E) | 335 (E) | 1080 (E) | 115 (E) |
| 1 | SWAP-1 | BSPC | 00012: publication 23 → 25 (+profiles, +coach_groups) + 011 VALUES same-commit (content-only) | 835 | 335 | 1080 (E) | 115 (E) |
| 2 | SWAP-2 | BSPC | 00013: GAP-1 two-arm swimmers_select_own + GAP-2 swimmer_strengths_parent_view + NEW pgTAP 015 (+8: four GAP-1 pins, four GAP-2 pins) | 835 | **343** | 1080 (E) | 115 (E) |
| 3 | SWAP-3 | Coach | D-CUT7 pair lands in notifications.ts, signatures AS WRITTEN, +4 pins in notifications.test.ts | 835 (E) | 343 (E) | **1084** | 115 |
| 4 | SWAP-4 | Coach | staff.ts NEW service, signatures AS WRITTEN, +6 pins in NEW staff.test.ts | 835 (E) | 343 (E) | **1090** | 115 |
| 5 | SWAP-5 | Coach | config/supabase.ts persistence pin + AuthContext core swap (suite TRANSFORMS 1→1, +4 new pins) + forgot-password successor (+1, new screen test) | 835 (E) | 343 (E) | **1095** | 115 |
| 6 | SWAP-6 | Coach | settings re-point onto the D-CUT7 pair + the NAMED CALL-2 three-toggle retirement (+1, new screen test) | 835 (E) | 343 (E) | **1096** | 115 |
| 7 | SWAP-7 | Coach | admin.tsx re-points onto staff.ts (screen renders its own labels from PG roles; +0) | 835 (E) | 343 (E) | 1096 | 115 |
| 8 | SWAP-8 | Coach | firebase death: FYI-A 12-file dead-mock sweep + src/__mocks__/firebase.ts + src/config/firebase.ts + firebase dep removal; closing grep (+0) | 835 (E) | 343 (E) | 1096 | 115 |
| 9 | SWAP-9 | Coach (parent-portal/ + root test/) | portal session → supabase.auth; parentPortal.ts httpsCallable → direct reads + redeem RPC, DTOs BYTE-FROZEN; lib/firebase.ts + portal firebase dep die; +1 root-test session pin | 835 (E) | 343 (E) | **1097** | 115 |
| 10 | LANDED LOG | UNIFY | the round's landed-log entry | 835 (E) | 343 (E) | 1097 (E) | 115 (E) |

**(E) = untouched-repo endpoint run**, legal only when that repo's
head is byte-identical to the head of its nearest proven run, named as
such in the scoreboard. The Functions bar re-runs FRESH at every Coach
commit (rows 3–9) — its workspace sits inside the Coach repo, so the
repo head moves even though functions/ is untouched. BSPC re-runs
fresh at rows 1–2; pgTAP re-runs fresh at rows 1–2 (migration up +
full suite).

**Band conformance, checked at declaration:** Coach ends 1097 = 1080
+17, inside [+10..+18], ZERO test deletions (the AuthContext suite
transforms 1→1; every other touched suite only grows). pgTAP ends 343
= 335 +8, inside the gap-build [+4..+8] band, 335 exact at the
content-only publication commit. BSPC 835 exact at every row.
Functions 115 exact at every row (decline schedule C1..C6 rides future
06 rounds, none of it executes here).

**Deletions pre-declared (the complete list; everything else only
transforms or grows):** ZERO test deletions. Count-0 deletion events,
each with per-file verify-at-deletion evidence at landing: the 12
FYI-A dead jest.mock('../../config/firebase') blocks (GoalCard,
docExport, attendanceStore, calendarStore, meetStore, practiceStore,
swimmersStore, videoStore via the shared mock; csvImport, docxExport,
export, hy3Import inline) — mock lines only, their tests untouched;
src/__mocks__/firebase.ts; src/config/firebase.ts (FYI-G re-verified
at deletion); the Coach `firebase` package dependency (+ the stale
package.json keyword); parent-portal/src/lib/firebase.ts + the portal
`firebase` dependency (outside the bar). Named code deletions inside
transforms: the NM-5 auto-admin branch (AuthContext.tsx:57–85) dies
unported; settings' dead Firestore prefs write (:46) and admin's
onSnapshot/updateDoc trio (:39/:59/:73) die with their re-points.

**Effect: SWAP-1..SWAP-9 execute in this round under the table above.
Any landing outside its declared line = STOP and explain before
proceeding. The cutover OPERATION (provisioning, probe, go-live,
Firebase sign-in disable) stays HARD-STOP future work per 05 §6.1/§6.5
and 06 PART B.**

---

## 2026-06-11 — CUT-4+ SWAP EXECUTION LANDED LOG — the 05 §6.2 swap code is COMPLETE; every commit landed EXACTLY on its pre-declared line

**The eleven commits (every bar proven with cd + pwd at landing;
(E) = endpoint cite, head byte-identical to the nearest proven run):**

| Commit | Repo | What | BSPC | pgTAP | Coach | Functions | vs declaration |
|---|---|---|---|---|---|---|---|
| `f9e23a9` CUT-4-OPEN | UNIFY | CALL-1..4 + the pre-declaration table | 835 (E) | 335 (E) | 1080 (E) | 115 (E) | exact ✓ |
| `d5c4c0d` SWAP-1 | BSPC | 00012 publication 23→25 + BOTH membership proofs (011 + 014:19) | 835 | 335 | 1080 (E) | 115 (E) | exact ✓ |
| `58e7cff` SWAP-2 | BSPC | 00013 GAP-1 two-arm + GAP-2 view + NEW pgTAP 015 (+8) | 835 | **343** | 1080 (E) | 115 (E) | exact ✓ |
| `3c18f76` SWAP-3 | Coach | D-CUT7 pair AS WRITTEN, +4 pins | 835 (E) | 343 (E) | **1084** | 115 | exact ✓ |
| `ecfc26c` SWAP-4 | Coach | staff.ts AS WRITTEN, +6 pins | 835 (E) | 343 (E) | **1090** | 115 | exact ✓ |
| `9670768` SWAP-5 | Coach | persistence pin + AuthContext swap (1→1 + 4 pins) + forgot-password (+1) | 835 (E) | 343 (E) | **1095** | 115 | exact ✓ |
| `000f722` SWAP-6 | Coach | settings → D-CUT7 pair + the NAMED CALL-2 retirement (+1) | 835 (E) | 343 (E) | **1096** | 115 | exact ✓ |
| `35f3663` SWAP-7 | Coach | admin.tsx → staff.ts (+0) | 835 (E) | 343 (E) | 1096 | 115 | exact ✓ |
| `090b27a` SWAP-8 | Coach | firebase death: FYI-A 12 + shared mock + config + dep; closing grep (+0) | 835 (E) | 343 (E) | 1096 | 115 | exact ✓ |
| `c2b0339` SWAP-9 | Coach (portal + root test/) | portal session + direct reads + redeem RPC; lib/firebase.ts + dep die (+1) | 835 (E) | 343 (E) | **1097** | 115 | exact ✓ |
| (this commit) | UNIFY | this landed log | 835 (E) | 343 (E) | 1097 (E) | 115 (E) | exact ✓ |

**Endpoint: BSPC 835 (TZ=UTC) + pgTAP 343 (Files=15) / Coach 1097 /
Functions 115. Coach 1080 → 1097 = +17 inside the ratified [+10..+18],
ZERO test deletions (the AuthContext suite transformed 1→1 with the
push-cleanup assertion preserved; every other touched suite only
grew). pgTAP 335 → 343 = +8 at the gap-build commit only, top of the
ratified [+4..+8]. BSPC jest and Functions EXACT at every commit.**

**The named CALL-2 UI change, landed at `000f722` (quoted):** "THE
ROUND'S ONE NAMED UI CHANGE (CALL-2, D-K3 class): the three
reader-less toggles RETIRE — newNotes (producer retired pre-G, no
server reader), attendanceAlerts (superseded by the per-coach
notification_rules surface, real since G), aiDraftsReady (returns WITH
the banked D-G4 producer) — named in-file with their paths back; the
read-only Push OS-status row stays; the dead Firestore prefs write
(:46) and the NotifPref type (:13) die with the bank." Daily Digest is
restored end-to-end onto digest_enabled. The Kevin lever stood unused.

**The closing grep (SWAP-8/SWAP-9, shown in-session):** Coach app-wide
live firebase imports = ZERO (the only matcher left before deletion
was src/config/firebase.ts itself); the K-era five-artifact list reads
0/0/0/0 mentions with config/firebase.ts and src/__mocks__/firebase.ts
GONE; parent-portal/src + portal package.json = zero firebase
mentions, lib/firebase.ts gone, both client firebase deps uninstalled.
**Named carve-out:** `firebase-admin` stays in the Coach root
package.json — it is the scripts/ seed-tool dependency whose
retirement rides the 06 scripts step (the FYI-E pre-declared −4).

**Named corrections (none silent, none landed red):**
1. **The 05 §6.2b "ONE results_eq" aside was WRONG** — the publication
   exact-membership proof exists in TWO places: pgTAP 011 AND pgTAP
   014 test 19 (Phase J's "publication untouched" pin carried a full
   second copy of the 23-list). Caught LIVE by the first SWAP-1 pgTAP
   run (014:19 failed 23-vs-25); both VALUES lists updated in the same
   commit; the operative pre-declaration (CONTENT-ONLY, pgTAP 335)
   held exactly. The 05 aside is corrected by this entry — the
   membership proof is TWO results_eq tests, and BOTH update with any
   future publication change.
2. **The first AsyncStorage jest wiring was wrong** (SWAP-5): the
   stale v2 deep path ('/jest/async-storage-mock') broke 5 suites RED
   in the working tree; fixed to the package's v3 './jest' export
   before anything landed — no red commit exists.
3. **PWD-PROOF live catches this round: three.** The STEP-0 Coach
   baseline run (no explicit cd → executed in BSPC/ACTIVE, printed the
   BSPC 835 — re-issued); two mid-round compound commands whose
   git/grep halves ran in functions/ after a `cd functions` earlier in
   the same chain (both caught by their pwd lines before any damage;
   re-issued from the root). The standing line keeps earning its keep.

**Machine note (J precedent):** the Coach pre-commit formatter
restyled at several landings; the suite was re-run against each
committed tree and the landed numbers above are from those re-runs.

**Effect: the 05 §6.2 SWAP CODE IS COMPLETE — both apps and the portal
ride supabase.auth + direct canonical reads end to end; the
five-artifact bank is dead; the D-CUT6 direct reads are LIVE in code,
so 06 §B6 steps C1 (portal callables) and C2 (redeemInvite shell) are
now condition-met and UNBLOCKED for a future 06 execution round.
NOTHING ran against any live store this round (local test stack only).
What remains before the apps point at a real project is OPERATION, all
HARD-STOP: 05 §6.1 provisioning + THE PROBE + NM-1 confirm + agreement
audit (throwaway dry-run first), the §6.5 go-live + named smoke
checklist, Firebase Email/Password sign-in disabled only after smoke
passes, then 06 PART B per the keep/drop sheet — every step with Kevin
live.**

---

## 2026-06-11 — STAGING-PREP OPEN — CUT-4+ acceptance recorded + the 05 §6.2b correction annotated + THE ROUND PRE-DECLARATION (code-side only; every live op stays HARD-STOP)

**Gate:** UNIFY `848010d` / BSPC `58e7cff` / Coach `c2b0339` — all clean,
all level with origin (pwd-proven). Baseline bars re-proven FRESH, each
run carrying its own cd + pwd line: BSPC jest **835** (TZ=UTC, 117
suites) + pgTAP **343** PASS (Files=15 — the publication pinned at
exactly 25 in BOTH membership tests, 011 + 014:19) / Coach jest **1097**
(107 suites) / Functions **115** (12 suites). HARD-STOP restated for the
whole round: this is a CODE round — the §B0 probe script LANDS but NEVER
RUNS; nothing executes against any store (not Firestore, not Storage,
not any Supabase project, not even read-only); no provisioning, no
backfill, no file copy, no throwaway-project creation; local test stack
only for the bars. Standing constraints: ZERO test deletions; the
swap-era BSPC migrations are DONE — any BSPC schema or migration change
this round = STOP.

### The director's acceptance + rulings (recorded in words)

1. **CUT-4+ ACCEPTED** — eleven commits, every bar exactly on its
   pre-declared line, audit passed on all ten checklist items.
2. **Named correction 1 RATIFIED (D-J7 class):** the publication
   exact-membership proof is TWO `results_eq` tests — pgTAP 011 AND
   pgTAP 014 test 19 — and BOTH update together with any future
   publication change. SWAP-1 stands as landed.
3. The AsyncStorage v3 wiring fix and the three PWD-PROOF catches are
   **acknowledged as norms held**; no red commit exists.
4. **The firebase-admin carve-out is ACCEPTED AS NAMED
   (scripts-class);** FYI-E's pre-declared Coach −4 RE-BASES to
   1097 → 1093 at the named future 06 scripts step — **the delta is the
   binding fact.** (See the lifecycle line under the pre-declaration
   below: this round's probe pins bank onto the SAME named step.)
5. **The Kevin lever on CALL-2 EXPIRED UNUSED at `000f722`;** toggle
   returns are product-round items via their named banked paths.
6. **D-K1's decline EXPIRED as designed at SWAP-5** — forgot-password's
   successor is the Supabase reset.
7. **NEW GREEN BASELINE:** UNIFY `848010d`, BSPC `58e7cff`, Coach
   `c2b0339`; bars 835 / 343 (Files=15) / 1097 / 115.
8. **06 §B6 C1 and C2 are recorded condition-met and UNBLOCKED;** they
   execute only at a future 06 round — Functions stays 115 until each
   pre-declared decline.

### The 05 §6.2b annotation (lands in THIS commit, same repo)

The wrong aside at 05 §6.2b ("that proof is ONE `results_eq` test") is
amended IN PLACE with a dated annotation — the e71050a amend-in-place
idiom extended to the cutover plan, named as such. Checked
word-against-binding vs the landed log's named correction 1 (NOTES
:4796): the annotation states the proof is TWO `results_eq` tests
(pgTAP 011 + 014 test 19), both updating together with any future
publication change, caught live at SWAP-1, content-only held.
*Check: MATCH — no force-fit.*

### THE ROUND PRE-DECLARATION TABLE (fixed BEFORE any landing; the report opens with this)

| # | Commit | Repo | One-line scope | BSPC jest | pgTAP | Coach jest | Functions |
|---|---|---|---|---|---|---|---|
| 0 | STAGE-0 | UNIFY | this entry: acceptance record + this table + the 05 §6.2b dated annotation | 835 (E) | 343 (E) | 1097 (E) | 115 (E) |
| 1 | STAGE-1 | Coach | §B0 probe scaffolding LANDS, never runs: `scripts/probe-firebase-inventory.ts` (thin I/O shell, HARD-STOP header, read-only by construction, explicitly UNTESTED) + `scripts/probe-firebase-inventory-report.ts` (pure: census table + row status + storage aggregation + report shaping) + **+14 pure-part pins** in `scripts/__tests__/probe-firebase-inventory-report.test.ts` (suites 107 → 108) | 835 (E) | 343 (E) | **1111** | 115 |
| 2 | STAGE-2 | UNIFY | runbook readiness sweep verdict: READY or the numbered gap list | 835 (E) | 343 (E) | 1111 (E) | 115 (E) |

(E) = untouched-repo endpoint cite, legal only while that repo's head is
byte-identical to its nearest proven run, named in the scoreboard.
Functions re-runs FRESH at the Coach commit (its workspace sits inside
the Coach repo). **The only bar that moves this round is Coach jest,
+14 at STAGE-1, ZERO deletions anywhere; BSPC and pgTAP do not move
(the swap-era BSPC migrations are DONE).**

**The +14, fixed:** census-table pins ×4 (all 32 enumerated paths, no
duplicates; the exact seven ⚠ expected-EMPTY set; the two `/drafts`
subcollections counted PER-PARENT so audio and video drafts never merge
under one collectionGroup; the five storage prefixes exact) +
`resolveRowStatus` pins ×4 (the four count×expectation cells, incl. the
⚠-non-empty REPORT flag) + storage-aggregation pins ×2 (count+bytes
sum; an empty prefix = a zero row, a counted fact) + report-shaping
pins ×4 (a row for every census path + the storage table + the auth
line; the preserve-verbatim-in-NOTES header + the named-no-op footer;
an UNEXPECTED-NON-EMPTY ⚠ row surfaces rendered; zero auth users
renders as the counted fact 0).

**Lifecycle, banked + named (pre-declared BEFORE the pins land):** the
probe pair + its 14 pins are decommission tooling — they retire at
**06 §B6 step 5 (the scripts/ deletion step), the SAME named step as
FYI-E.** That step's Coach delta re-bases **−4 → −18** (FYI-E's seeds
−4 + the probe scaffolding's −14): **1111 → 1093 — the director's
ruling-4 endpoint (1093) is preserved; the step's delta is the binding
fact.**

**Derivation facts (named; zero new decisions taken):**
1. **The census is built on the ENUMERATED list, and the "23" is
   FLAGGED:** 00_TERRAIN §0's header says "23 collection paths" and 06
   §B0 echoes "ALL 23 census paths" — but the census block ENUMERATES
   **32** paths (25 ★ + 7 ⚠), corroborated by the §B2 manifest table,
   which covers the same 32 paths in exactly **23 ROWS** (parent+child
   collections share rows; the five never-implemented ⚠ paths share one
   row — the likely origin of the number). Membership is pinned by name
   twice; only the cardinal is wrong somewhere. The probe covers the
   enumerated 32 — a superset can never under-count — and the numeric
   discrepancy goes to the STAGE-2 gap list as a doc-class decision,
   NOT silently fixed.
2. **Home/invocation/auth ride the standing scripts-class idiom §B0
   itself points at:** home = `scripts/` (the named scripts-class
   carve-out — the only place firebase-admin is legal); invocation =
   `npx tsx scripts/<tool>.ts` (the seed tools' Usage idiom); auth =
   service-account JSON per PART A §6, resolved exactly as
   `seed-demo-data.ts:386` does (`FIREBASE_ADMIN_KEY_PATH` else
   `GOOGLE_APPLICATION_CREDENTIALS`; a real secret — never read,
   printed, or committed; `.gitignore` lines 18/20 already cover it);
   shell guard = `require.main === module` (the seed shells' guard).
   Tests live in `scripts/__tests__/` and ride the Coach bar (the
   FYI-E precedent file sits there today).
3. **Storage bytes ride along, named:** §B0 demands per-prefix object
   COUNTS; the report adds a bytes column because the §B1 pre-step
   (F bank, quoted: "confirm hosted storage tier covers the 500MB video
   cap before the file copy") needs source sizes and the probe is the
   only read of the source. Additive, read-only, named here and
   in-file.
4. **The default-bucket name is a probe-time counted fact:** Firebase
   default buckets are `<project>.appspot.com` (older projects) or
   `<project>.firebasestorage.app` (newer); the shell resolves by
   read-only `exists()` against the two known shapes (env override
   `BSPC_FIREBASE_STORAGE_BUCKET` wins) and the report NAMES which
   bucket it probed. No decision needed before run time.

**Tripwire check (the four material-unpinned candidates):** home
directory — pinned by the scripts-class carve-out; output format —
pinned by §B0 ("the probe output table is preserved verbatim in
UNIFY/NOTES.md", per-path counts + the named-no-op resolution
sentence); auth mode — pinned by §B0's own cite ("the admin SDK with
the service-account key (PART A §6 handling rules apply)"); invocation
shape — pinned by the standing seed-tool Usage idiom. **No tripwire:
nothing material required a new decision.** The one genuine doc
discrepancy (the "23") is flagged above and lands in the STAGE-2 gap
list as a decision for the director.

**Effect:** the acceptance is on the record, the 05 plan no longer
carries the wrong aside, and the swap rounds' pre-declaration
discipline now governs this round's three landings.

---

## 2026-06-11 — STAGING-PREP STAGE-2 — RUNBOOK READINESS SWEEP (fresh-eyes re-read of 06 PART B + 05 §6.1/§6.5 against the landed code; the verdict + the numbered gap list)

**Method:** fresh re-read, re-derived (inventories go stale): 06 PART B
§B0–§B7 whole; 05 §6.0/§6.1/§6.2b/§6.4/§6.5; the identity README (40
lines) + the roster README (36 lines) end-to-end; the landed probe pair
+ pins at `c399516`; the re-run closing greps.

**Verified READY (four items):**
1. **§B0 spec vs the script AS LANDED: MATCH.** Census membership = the
   enumerated TERRAIN §0 list (32 paths; the 7 ⚠ exactly §B0's
   parenthetical); the five storage prefixes exact; the auth count;
   PART A §6 key handling (`FIREBASE_ADMIN_KEY_PATH` else
   `GOOGLE_APPLICATION_CREDENTIALS`); unit-tested pure parts only (+14;
   the I/O shell named UNTESTED, no trusted mocks); the output opens
   with the preserve-verbatim-in-NOTES rule and carries the
   named-no-op + REPORT-never-auto-copy rules of record; every §B2 row
   that cites "(§B0 count)" can be filled from the per-path table
   (parent+child rows get both paths' counts).
2. **05 §6.1's gate logic is executable as written ONCE GAP-C closes:**
   probe input source = Firestore `parents` docs ×
   `migration_identity_map` (both artifacts exist; `auditIdentityMap` /
   `auditGuardianships` are Phase-A unit-tested pures); zero-resolves =
   STOP is unambiguous; NM-1 names its source (the live `coaches` list,
   Kevin confirms before any role writes); the agreement audit is
   banked and named.
3. **Stop conditions: PASS.** The PART B governing HARD STOP covers
   every section; per-step explicit stops verified: identity step 7
   stop-on-audit-failure; roster step 3 STOP-on-ambiguous + step 6
   stop-on-failure; §B2.1/§B2.2 CHECK-domain STOPs (course / standard /
   tag / group / unmapped-coach); §B1 imports non-empty → REPORT, never
   auto-copy; §B6.1 sign-in disable gated on §6.5 smoke; §6.5 steps
   each gated on the one before, rollback named. (Note, not a gap:
   §B1's verification-failure consequence rides the governing HARD STOP
   rather than a section-local STOP sentence.)
4. **D-I1 + the frozen surfaces: untouched by this round** (zero
   behavior changes; the only code that landed is the never-run probe
   pair + its pins).

**VERDICT: GAP LIST — five numbered gaps. Every one ends as a decision
for the director; NONE is fixed silently (no pre-ratified cover exists
this round, so all five wait).**

1. **GAP-A — the census cardinal "23" is wrong in two bound places.**
   00_TERRAIN §0's header says "23 collection paths" and 06 §B0 echoes
   "ALL 23 census paths"; the census block ENUMERATES **32** (25 ★ +
   7 ⚠), corroborated by §B2's manifest table — the same 32 paths in
   exactly **23 ROWS** (parent+child collections share rows; the five
   never-implemented ⚠ paths share one row — the likely origin of the
   number). The probe is built on the enumerated 32 (superset-safe).
   **Decision: ratify a D-J7-class dated correction of both numbers to
   "32 paths (25 ★ + 7 ⚠)" (the e71050a idiom), or rule that the
   header means §B2's 23 manifest rows and annotate it as such.**
2. **GAP-B — the mandatory throwaway-Supabase dry-run is bound
   everywhere and specified nowhere.** The identity README (:39), the
   roster README (:36), 06 §B2, and 05 §6.5 step 1 all REQUIRE it; none
   specifies project setup (which migrations, applied how), input data,
   success criteria, or teardown. **And the input-data question
   collides with a standing security rule:** PART A's standing rules
   say "Never put real swimmer/family data in a demo project" — a
   dry-run fed by the REAL Firestore export would put real minors' data
   in a throwaway project. **Decision: ratify a dry-run spec.
   Recommended shape: throwaway project + the full migration chain
   (00001..00013) + a SYNTHETIC fixture export (the seed-demo shapes);
   success = identity/roster audits green + the §6.1 probe non-empty on
   the fixture + both smoke logins; teardown = project deletion,
   confirmed; real-export rehearsal explicitly OUT (the security rule
   wins).**
3. **GAP-C — the §6.1 step-3 provisioning runner is still "not yet
   written."** The identity README says so (:21); 05 §6.1 expects it to
   land "as scaffolding in the staging round"; THIS staging round's
   bound scope was the §B0 probe only. **Decision: scope the runner's
   own scaffolding commit (pure parts + pins pre-declared, lifecycle
   banked) into the next round, or re-date 05 §6.1's expectation to
   that round.**
4. **GAP-D — the §6.5 smoke checklist does not name the portal redeem
   path or the portal direct-read surfaces.** Named today: "portal
   parent login + dashboard render" only. Post-SWAP-9, dashboard render
   exercises ONE direct read; the D-I2 redeem RPC path and the
   swimmer-detail direct reads (swimmers row + strengths view +
   goals/results/attendance under the 00013 walls) go un-smoked.
   **Decision: ratify two named additions to §6.5 step 3 — "portal
   invite-code redeem round-trips (code → guardianship → swimmer
   appears)" and "portal swimmer detail renders the direct-read
   surfaces (strengths + results + attendance under the 00013
   walls)".**
5. **GAP-E — one STALE pre-cutover comment in landed portal code.**
   `parent-portal/src/lib/profile.ts:12` still reads "the session
   provider in auth.ts stays on Firebase until the coordinated
   identity-cluster cutover, so this read goes live at that cutover" —
   false since SWAP-9 (auth.ts rides supabase.auth; the read is live).
   Surfaced by this round's STRICTER case-insensitive sweep; the
   as-landed lowercase grep stays CLEAN, and the only other capital-F
   mention (`parentPortal.ts:73`) is accurate history needing nothing.
   **Decision: ratify the one-line comment correction (comment-only,
   zero behavior) for the next round that touches the Coach repo.**

**Effect:** the §B0 probe is real, tested where it can honestly be
tested, and waiting for Kevin; the runbook is executable on its spine
(stops everywhere; the §B0 → keep/drop sheet → manifests wiring
verified) and NOT READY only at the five named seams above — every seam
is a decision, none is code this round was allowed to write.

---

## 2026-06-11 — GAP-CLOSURE + RUNNER ROUND, GC-0: STAGING-PREP accepted; the six gap rulings recorded; doc closures executed (the last build round before the Kevin-live session)

**Heads gate at round open:** UNIFY `30dcb19` / BSPC `58e7cff` / Coach
`c399516`, all clean, all level with origin. Fresh baseline bars, each run
carrying its own cd + pwd (PWD-PROOF): BSPC jest **835** (TZ=UTC, 117
suites) at `/Users/kevin/bspc-unify/BSPC/ACTIVE`; pgTAP **343 PASS**
(Files=15; "Local database is up to date") same pwd; Coach jest **1111**
(108 suites) at `/Users/kevin/bspc-unify/BSPC-Coach-App`; Functions **115**
(12 suites) at `/Users/kevin/bspc-unify/BSPC-Coach-App/functions`.
**HARD-STOP standing for the whole round:** the runner LANDS but NEVER
RUNS; the §B0 probe stays un-run; nothing executes against any store — no
Firestore, no Storage, no Supabase project of any kind, no throwaway
creation; local test stack only. ZERO test deletions. **BSPC is FROZEN —
no schema, no migrations, no commits; any BSPC change = STOP.**

### The director's acceptance, in words

**STAGING-PREP is ACCEPTED:** three landings (`fb83588` / `c399516` /
`30dcb19`), every bar exactly on its pre-declared line, zero deletions,
both closing greps clean. **The four derivation facts are RATIFIED:** the
probe is built on the ENUMERATED 32-path census (the "23" flagged, now
ruled below); the scripts-class home/invocation/auth idiom; the storage
bytes column riding along for the §B1 F-bank pre-step; the
default-bucket name as a probe-time counted fact.

### The six rulings, in words

1. **GAP-A — RULED: corrected to 32.** Both bound sites — the 00_TERRAIN
   §0 header and 06 §B0's "ALL 23" — take a D-J7-class dated correction
   to **"32 paths (25 ★ + 7 ⚠)"**, each annotation naming §B2's
   23-manifest-ROW organization as the old number's origin and the landed
   probe's enumerated-32 build as the operative reading.
2. **GAP-B — RULED: the dry-run spec is RATIFIED, synthetic-data-only,
   the security rule WINS.** The spec lands in 05 under §6.5 step 1 as
   its own block: fresh throwaway project; migrations 00001..00013 via
   standard tooling; SYNTHETIC fixture data ONLY from the seed-demo
   shapes; PART A's never-real-swimmer/family-data rule RESTATED inside
   the spec; success = identity + roster audits green + the §6.1 probe
   non-empty on the fixture + one coach smoke login + one parent portal
   smoke login; teardown = throwaway project deletion, confirmed and
   recorded; **real-export rehearsal EXPLICITLY OUT**; the dry-run
   executes at the Kevin-live session, FIRST item. 06 §B2 gets a one-line
   pointer to the spec. **README pointers:** the pre-declared conditional
   covered only the case where the identity/roster READMEs live in the
   Coach repo — they live in the FROZEN BSPC repo
   (`BSPC/ACTIVE/migration/{identity,roster}/README.md`), so NO pointer
   line lands there this round; named for the re-verdict.
3. **GAP-C — RULED: the §6.1 step-3 provisioning runner is scoped to
   THIS round**, under binding construction rules (HARD-STOP header;
   Kevin-live only; NO default target, NO embedded project ref, NO
   credentials in the repo; plan-only by default with a NAMED no-op line;
   the §6.1 gate IN the runner — zero-resolves = HARD ABORT before any
   write path is reachable; pure half pinned, I/O shell untested with no
   trusted mocks; lifecycle banked at 06 §B6.5; the firebase-admin
   carve-out grows by exactly the runner shell; tripwire on anything
   material unpinned) **plus the named 05 §6.1 re-date annotation** (the
   runner lands this round per this ruling, not the staging round).
4. **GAP-D — RULED: the two smoke additions are RATIFIED AS WRITTEN**
   and land in 05 §6.5 step 3: "portal invite-code redeem round-trips
   (code → guardianship → swimmer appears)" and "portal swimmer detail
   renders the direct-read surfaces (strengths + results + attendance
   under the 00013 walls)".
5. **GAP-E — RULED: the one-line comment fix is RATIFIED** at
   `parent-portal/src/lib/profile.ts:12` — comment-only, zero behavior,
   zero test delta, its own pre-declared Coach commit.
6. **The two broken-dormant client-SDK scripts** (`scripts/create-coach.ts`
   + `scripts/seed-calendar.ts`, importing the firebase CLIENT SDK that
   SWAP-8 uninstalled) **are LEFT TO DIE at 06 §B6.5** — named here as
   ruled — **and the GAP-C runner is the ONLY legitimate provisioning
   tool** (no resurrection of create-coach, ever).

### ROUND PRE-DECLARATION (fixed BEFORE any landing)

| # | Commit | Repo | One-line scope | BSPC jest | pgTAP | Coach jest | Functions |
|---|---|---|---|---|---|---|---|
| 0 | GC-0 | UNIFY | this entry: acceptance + the six rulings + the GAP-A/B/C/D doc closures (TERRAIN §0 + 06 §B0 corrections; 05 §6.5 step-1 dry-run spec + 06 §B2 pointer; 05 §6.1 re-date; 05 §6.5 step-3 two smoke additions) | 835 (E) | 343 (E) | 1111 (E) | 115 (E) |
| 1 | GC-1 | Coach | the §6.1 step-3 provisioning runner LANDS, never runs: `scripts/provision-identities.ts` (thin I/O shell, HARD-STOP header, no default target, plan-only by default, the §6.1 gate, explicitly UNTESTED) + `scripts/provision-identities-plan.ts` (pure: plan derivation + gate + render) + **+17 pure-part pins** in `scripts/__tests__/provision-identities-plan.test.ts` (suites 108 → 109) | 835 (E) | 343 (E) | **1128** | 115 |
| 2 | GC-2 | Coach | GAP-E: the one-line comment correction at `parent-portal/src/lib/profile.ts:12` (comment-only, zero behavior, zero test delta) | 835 (E) | 343 (E) | 1128 | 115 |
| 3 | GC-3 | UNIFY | the re-verdict: the five seams re-run against the landed state — READY or numbered residual decisions | 835 (E) | 343 (E) | 1128 (E) | 115 (E) |

(E) = untouched-repo endpoint cite, legal only while that repo's head is
byte-identical to its nearest proven run, named in the scoreboard.
Functions re-runs FRESH at every Coach commit (its workspace sits inside
the Coach repo); Coach runs FRESH at both Coach commits. **The only bar
that moves this round is Coach jest, +17 at GC-1, ZERO deletions
anywhere; BSPC and pgTAP do not move (BSPC is FROZEN).**

**The +17, broken down (pre-declared):** `deriveProvisioningPlan` ×6
(fresh-map all-create; empty-map-read all-create; partial-map skip set;
user_id-NULL re-plans as create; duplicate-uid reporting; unmatched-map-row
reporting), `runZeroResolvesGate` ×3 (zero parents docs → abort; zero
identities → abort; non-zero → pass with resolve count),
`renderProvisioningPlan` ×6 (HARD-STOP + header + per-source counts; NM-1
coach-roster block + confirm-before-roles + sole-super_admin; OD-6 block —
no password material, no emails dispatched, both credential paths named;
the §6.1 probe line + plan-only NAMED no-op tail; gate-abort banner;
duplicate/unmatched WARNING lines), `renderExecutionSummary` ×2
(created/skipped + map-recording + step-4/step-7 pointers; failures →
named STOP).

**Lifecycle, banked + named (pre-declared BEFORE the pins land):** the
runner pair + its 17 pins are decommission tooling — they retire at
**06 §B6 step 5 (the scripts/ deletion step), the SAME named step as
FYI-E and the probe pair.** That step's Coach delta re-bases **−18 →
−35** (seeds −4 + probe −14 + runner −17): **1128 → 1093 — the
director's ruling-4 endpoint (1093) is preserved; the step's delta is
the binding fact.**

### Named construction facts for GC-1 (derivations the director can object to)

1. **Names** (the bound text names no filename): `scripts/
   provision-identities.ts` + `scripts/provision-identities-plan.ts` +
   `scripts/__tests__/provision-identities-plan.test.ts` — the
   scripts-class idiom (probe precedent).
2. **Target env, operator-supplied, NO defaults:**
   `BSPC_MIGRATION_SUPABASE_URL` + `BSPC_MIGRATION_SUPABASE_SERVICE_ROLE_KEY`
   — deliberately DISTINCT from the app's `EXPO_PUBLIC_SUPABASE_*` pair,
   which carries embedded fallback placeholders (`src/config/supabase.ts:7-8`)
   — exactly what the runner must not inherit. A PARTIAL pair is a named
   error, not a silent fallback. Firestore side: `FIREBASE_ADMIN_KEY_PATH`
   else `GOOGLE_APPLICATION_CREDENTIALS` (the seed/probe idiom, PART A §6
   handling rules).
3. **Scope = identity README step 3 EXACTLY:** one Supabase auth user per
   Firestore `coaches`/`parents` doc; record `(firebase_uid, user_id,
   source)` in `migration_identity_map`; `profile_id` stays NULL (step 4's
   business). **Roles are NOT written by this runner** — NM-1 gates step 4;
   the plan PRINTS the live coach roster for Kevin's confirm. `'bspc'`-source
   map rows are step-6 business, not this runner's.
4. **OD-6 construction, choice-preserving:** `createUser({ email,
   email_confirm: true })` — ZERO password material, ZERO emails dispatched
   by the tool. Both ratified credential paths stay open to Kevin at
   cutover: the landed forgot-password flow (SWAP-5) and operator-sent
   dashboard invites. Auto-sending invites would be an unbound
   outward-facing side effect — the no-email construction is the null
   action, named so the director can re-rule.
5. **The cross-repo contract is the DDL, not an import:** the Phase-A
   pures (`auditIdentityMap`/`auditGuardianships`, `mapping.ts`) live in
   the FROZEN BSPC repo; a cross-repo import would be fragile and is not
   attempted. The runner's pure half re-states the map-row type from
   `migration_identity_map.sql` (provenance-commented) and carries
   plan-layer audit-class checks (duplicate uids, unmatched map rows)
   CONSISTENT with the step-7 audits, which remain the BSPC pures,
   untouched and not duplicated. Idempotency: map rows with `user_id`
   non-null SKIP; `user_id`-NULL rows re-plan as create; the execute path
   upserts only `(firebase_uid, user_id, source)` on `firebase_uid` —
   `profile_id` is never written by step 3. Supabase writes ride
   `@supabase/supabase-js` (already a Coach dependency — the TARGET
   stack, not a carve-out).

**Tripwire check (mission: home directory, output format, auth mode,
invocation shape + anything material):** runner home/name → the
scripts-class idiom, named (1); target supply → mission-pinned
(operator env/flags only, no defaults), names derived + named (2); auth
modes → Firestore side PART-A-§6-pinned, Supabase side the service-role
key named (2); credential mechanism → OD-6 pins the fresh-credentials
class, the no-email construction named (4); gate semantics →
mission-pinned (zero-resolves = HARD ABORT before any write path) with
the §6.1 probe arithmetic (parents docs × map) as the resolve
definition, construction named in the pin list; map write shape →
DDL-pinned (5); invocation → `npx tsx` scripts-class Usage, plan + execute
forms in the header. **NO TRIPWIRE — five named derivations stand above
for objection.**

### Doc closures executed in this commit (each checked against the ruling words — all MATCH, none force-fit)

- **GAP-A:** 00_TERRAIN §0 header `~~23~~ → 32 paths (25 ★ + 7 ⚠)` +
  dated annotation; 06 §B0 `ALL ~~23~~ → ALL 32` + dated annotation —
  both name the §B2 23-row origin and the enumerated-32 operative
  reading (the e71050a amend-in-place idiom).
- **GAP-B:** the ratified dry-run spec lands as its own block under 05
  §6.5 step 1, every ruled element present (checked word-against-ruling
  above); 06 §B2 gets the one-line pointer.
- **GAP-C:** 05 §6.1's "lands as scaffolding in the staging round" takes
  the dated re-date annotation (this round, per the ruling).
- **GAP-D:** the two ruled smoke items land in 05 §6.5 step 3, worded
  exactly as ruled, with the dated marker.

**Effect:** the rulings are on the books; the documents now say what the
director ruled; the only code this round may write is the GC-1 runner +
pins and the GC-2 comment line, both pre-declared above.

---

## 2026-06-11 — GAP-CLOSURE + RUNNER ROUND, GC-3: THE RE-VERDICT (the five seams re-run against the landed state)

**Method.** Fresh re-run of the STAGE-2 sweep's five seams against the
trees as committed this round (UNIFY `2355f2e`, Coach `1767355` +
`39e6585`; BSPC FROZEN at `58e7cff`, untouched as bound). Quote-checks
read the LANDED text, not intentions; the closing proofs P1–P7 were run
against the committed trees and are reproduced in the round readback.

**The five seams:**

1. **GAP-A — CLOSED.** Both corrections landed in `2355f2e` and read as
   ruled: the TERRAIN §0 header now says **"~~23~~ 32 collection paths
   (25 ★ + 7 ⚠)"** with the dated annotation naming §B2's 23-manifest-ROW
   organization as the old number's origin; 06 §B0 now says **"ALL ~~23~~
   32 census paths"** with the matching annotation. Both name the landed
   probe's enumerated-32 build as the operative reading; the probe itself
   needed no change (it was built on the enumerated list).
2. **GAP-B — CLOSED in its ruled homes; ONE residual, numbered below.**
   The dry-run spec block sits under 05 §6.5 step 1 with every ruled
   element verified present (fresh throwaway; 00001..00013 via standard
   tooling; SYNTHETIC fixtures only with PART A's rule RESTATED inside;
   the five-part success bar; teardown deletion confirmed + recorded;
   real-export rehearsal EXPLICITLY OUT; Kevin-live FIRST item). 06 §B2
   carries the one-line pointer. **R-1:** the identity/roster READMEs'
   own dry-run lines (BSPC repo, FROZEN this round; the pre-declared
   pointer conditional covered only the Coach-repo case) still lack a
   pointer to the spec — their requirement lines are not WRONG, just
   unlinked.
3. **GAP-C — CLOSED; ONE fresh-eyes residual, numbered below.** The
   runner landed at `1767355` and was verified against every binding
   construction rule on the COMMITTED tree: HARD-STOP header present;
   step-3 scope exactly (no roles, profile_id never written, 'bspc' rows
   out of scope); NO default target (the operator env pair, partial =
   named error; zero embedded refs/credentials — the service-role key
   never appears anywhere); plan-only by default with the NAMED no-op
   line; the §6.1 gate at main():198 sits physically ABOVE the plan-only
   return (:204) and the single write call site (:210), and all write
   verbs live inside executeProvisioning (:146-186) — proofs P1–P3;
   the +17 pins green (suite 17/17; Coach 1128 EXACT, twice, second run
   against the committed tree); lifecycle re-based −18 → −35 with the
   1093 endpoint preserved; the carve-out grew by exactly the runner
   shell (proof P6: five named files). 05 §6.1 carries the dated
   re-date annotation. **R-2 (fresh sweep, new):** identity README
   steps 4–6 (profiles via coachToProfile/parentToProfile; coach_groups;
   guardianships with the COPPA dangling-link repair) have ratified,
   unit-tested PURES but NO named executor — the README marked only
   step 3 "not yet written," and the GAP-B dry-run runs "identity README
   steps 1–8," so something must drive 4–6 at the dry-run. This was
   invisible to STAGE-2 (its §6.1 item verified the GATE, and the
   README's own text flagged only step 3); the fresh sweep surfaces it.
4. **GAP-D — CLOSED.** Both ruled items verified verbatim in 05 §6.5
   step 3 with the dated marker: the invite-code redeem round-trip and
   the swimmer-detail direct-read render (strengths + results +
   attendance under the 00013 walls).
5. **GAP-E — CLOSED.** The comment at parent-portal/src/lib/profile.ts
   now reads "auth.ts has ridden Supabase sessions since the CUT-4+ swap
   (SWAP-9), so this read is LIVE" — no firebase mention in ANY case.
   The faithful SWAP-9 lowercase grep stays EMPTY (proof P5); the
   STRICTER case-insensitive sweep now shows exactly ONE hit in the
   whole portal: parentPortal.ts:73, accurate history, needing nothing.

**Ruling 6 standing:** the two broken-dormant client-SDK scripts are
named in the GC-0 record and die at §B6.5; the GC-1 runner is the ONLY
legitimate provisioning tool.

**VERDICT: READY on all five ruled seams — every gap the director ruled
is CLOSED as ruled. TWO residuals, each a decision for the director,
neither fixed silently:**

- **R-1 — README pointers (doc-only, two lines, BSPC repo).** Decision:
  schedule a doc-only BSPC commit for the two pointer lines at the next
  round BSPC unfreezes, or rule the 05 §6.5 + 06 §B2 homes sufficient
  (the READMEs already bind the dry-run; only the cross-reference is
  missing).
- **R-2 — the steps-4–6 executor.** The dry-run (and the live identity
  backfill) needs a driver for README steps 4–6; the pures exist and are
  tested, the executor does not. Decision: scope ONE more pre-declared
  build round (the same construction rules as the GC-1 runner: plan-only
  default, HARD-STOP header, no default target, pure half + pins,
  lifecycle banked at §B6.5), or rule steps 4–6 Kevin-live-manual at the
  dry-run (NOT recommended: Kevin is a beginner, and a manual path
  rehearses nothing the live run would reuse).

**Recommendation, plainly:** rule R-2 into one more small build round;
treat R-1 as bundle-able into any future BSPC-unfrozen commit. With R-2
landed, the next step is SCHEDULING THE KEVIN-LIVE SESSION per the
runbook — the dry-run (05 §6.5 step 1, synthetic fixtures, throwaway
project, teardown recorded) is its first item, and every remaining step
is Kevin-live by standing rule.

**Effect:** the five ruled seams are closed on the books and in the
code; the runbook's spine now has its gate-bearing tool; the only
daylight between here and a schedulable Kevin-live session is the R-2
ruling.
