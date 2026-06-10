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
