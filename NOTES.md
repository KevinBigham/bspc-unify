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
