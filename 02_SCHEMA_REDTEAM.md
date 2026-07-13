# 02 — SCHEMA RED-TEAM

Adversarial review of `UNIFY/01_CANONICAL_SCHEMA.sql`. **No schema changed** — findings only, for your review before any fix.

**Method:** 5 parallel red-team agents, one per attack angle (RLS/privacy, constraint traps, migration landmines, parent-app regression, referential integrity), each reading the schema in full + angle-specific sources (Coach App services, BSPC parent-app queries, the original BSPC migration). I then verified their claims, deduped, and re-rated severity. Where my rating differs from an agent's, I say so.

**Severity:** P0 = breaks core flow / privacy breach / data loss if shipped · P1 = serious but scoped or has a workaround · P2 = hardening.
**Fix lives in (classification):** `SCHEMA` = edit the .sql · `BACKFILL` = the data-migration script · `APP` = parent/coach app code (the planned data-layer swap).

---

## Verdict

**The schema is not yet safe to ratify as "law."** Six P0 schema defects, a parent-app P0 regression bundle (expected, but needs a mitigation decision), and two items that need a **design decision from you** (the family/guardianship model and the two-a-day uniqueness mechanism). The good news: most P0s are small, surgical edits. Nothing invalidates the overall "BSPC extended" shape.

| Severity | Count | Of which need a schema edit |
|---|---|---|
| **P0** | 6 schema + 1 parent-app bundle + 2 migration-process | 6 |
| **P1** | 12 | 8 |
| **P2** | 11 | 6 |

**Two decisions only you can make** (flagged 🟥 below): the **family vs guardianship** model (D-A) and the **two-a-day uniqueness mechanism** (D-B).

---

## P0 — must fix before "law"

### P0-1 · Privilege escalation: `profiles` UPDATE has no `WITH CHECK` 🔴 [RLS]
**Where:** `profiles_update_own` (~:980) and `profiles_update_staff` (~:981). **Fix in: SCHEMA.**
A `family` user can run:
```sql
UPDATE profiles SET role='super_admin', account_status='approved', family_id='<victim-family>'
WHERE user_id = auth.uid();
```
An `UPDATE` policy with no `WITH CHECK` falls back to the `USING` expression (`user_id = auth.uid()`), which the attacker preserves — nothing pins `role`/`account_status`/`family_id`. Two breaches in one: (a) self-escalate to `super_admin` → `is_staff()`/`is_super_admin()` unlock **every** coach-only table (medical, notes, video, etc.); (b) rewrite own `family_id` to a victim family → `is_my_swimmer()` returns true for their kids → read another family's `swim_results`, `goals`, `attendance`. *(Inherited from the original BSPC schema, which had the same "limited fields via app logic" comment — RLS never enforced it.)*
**Fix:** Forbid self-mutation of `role`/`account_status`/`family_id`. RLS `WITH CHECK` can't see the OLD row, so use a `BEFORE UPDATE` trigger that rejects changes to those columns unless `is_super_admin()`; keep a `WITH CHECK (user_id = auth.uid())` on the policy. The correct pattern already exists in this file: `push_tokens_own`/`notif_prefs_own` have both `USING` + `WITH CHECK`.

### P0-2 · Cross-family minor PII leak: `calendar_event_rsvps` is world-readable 🔴 [RLS]
**Where:** `rsvps_select_all ... USING (TRUE)` (~:1012). **Fix in: SCHEMA.**
```sql
SELECT swimmer_id, parent_name, status, note FROM calendar_event_rsvps;
```
Any authenticated user — including a brand-new `pending` signup — reads **every** family's RSVPs: which minor is attending which event, parent name, free-text note. Direct COPPA/SafeSport exposure of minors' whereabouts across families. Compounding bug: families have **no** insert/update policy (only `rsvps_staff_all` writes), so parents can't even RSVP.
**Fix:** `USING (is_my_swimmer(swimmer_id) OR is_staff())` for SELECT; add a family write policy `WITH CHECK (is_my_swimmer(swimmer_id))`.

### P0-3 · `attendance.status NOT NULL` rejects the normal check-in 🔴 [Constraints, Migration]
**Where:** `attendance.status attendance_status NOT NULL` (~:642). **Fix in: SCHEMA (+ BACKFILL).**
The Coach App writes `status: null` at check-in (`attendance.ts:62,105`) and sets it only at checkout — and checkout without a status leaves it null (`00_TERRAIN.md:95` "null until checkout"). So the single most common attendance write, and the bulk of historical rows, **violate NOT NULL**. Separately, `'normal'` (the Coach App's "present" value) is **not** in the canonical enum, so a raw migrate also fails the cast.
**Fix:** Make `status` **NULLABLE** (a check-in row with null status = "present, not yet checked out"). Backfill maps `'normal' → 'present'`. Then fix P0-4.

### P0-4 · `attendance_parent_view` shows present swimmers as ABSENT 🔴 [Constraints]
**Where:** view CASE (~:664): `CASE WHEN status IN ('present','left_early') THEN 'present' ELSE 'absent' END`. **Fix in: SCHEMA.**
A checked-in swimmer with `status = NULL` (the common case, see P0-3) falls to `ELSE 'absent'` — parents see their present child as absent. The mapping is also semantically loose for the widened statuses.
**Fix (deliberate mapping):** present/left_early/**NULL** → `present`; absent/excused/sick/injured → `absent`:
```sql
CASE WHEN status IN ('absent','excused','sick','injured') THEN 'absent' ELSE 'present' END
```

### P0-5 · `swim_results.date NOT NULL` rejects dateless Coach App times 🔴 [Constraints, Migration]
**Where:** `swim_results.date DATE NOT NULL` (~:417). **Fix in: SCHEMA (+ BACKFILL).**
A Coach App manual time (`times.ts:56-67`) writes **no date** — only `createdAt`; `meetDate` is null. Imports (`meetResultsImport.ts:138`) also allow null `meetDate`. A large share of `swimmers/{id}/times` has no value to map to `date`.
**Fix:** Make `date` NULLABLE, with backfill `date := COALESCE(meet_date, created_at::date)`.

### P0-6 · `attendance` SET NULL × `NULLS NOT DISTINCT` deadlocks schedule deletes & two-a-days 🔴 [Referential, Constraints]
**Where:** `attendance.schedule_event_id ... ON DELETE SET NULL` (~:639) + `UNIQUE NULLS NOT DISTINCT (swimmer_id, practice_date, schedule_event_id)` (~:650). **Fix in: SCHEMA.** 🟥 **see decision D-B.**
The very feature we just added self-conflicts. Swimmer S has two-a-day rows `(S, date, E1)` and `(S, date, E2)`. Delete/replace those schedule events (which the **scrape pipeline does routinely**) → `ON DELETE SET NULL` converges both rows to `(S, date, NULL)` → under `NULLS NOT DISTINCT` the two NULLs collide → unique violation → **the entire delete is rolled back.** Even a single event delete collides if a Coach-App NULL-event row already exists for that swimmer/date.
**Fix (D-B):** Replace `NULLS NOT DISTINCT` (also drops the PG15-only dependency, P2-7) with two **partial unique indexes**, and change the FK action:
```sql
-- one NULL-event ("day-keyed", Coach App) row per swimmer/day:
CREATE UNIQUE INDEX attendance_day_key ON attendance (swimmer_id, practice_date)
  WHERE schedule_event_id IS NULL;
-- and distinct event-linked rows for two-a-days:
CREATE UNIQUE INDEX attendance_event_key ON attendance (swimmer_id, practice_date, schedule_event_id)
  WHERE schedule_event_id IS NOT NULL;
```
plus `ON DELETE RESTRICT` (or a trigger that detaches/merges) so deleting an event can't converge two rows onto the single NULL slot. This also works on Postgres <15.

### P0-7 (bundle) · Parent app is broken against this schema 🔴 [Parent-app] — **Fix in: APP (planned), with optional SCHEMA mitigations**
The canonical schema changes three things the live BSPC parent app depends on. These are *expected* consequences of the migration (the app's data layer gets swapped one service at a time), but they're P0-severity breakages, so they must be tracked and possibly cushioned:
- **Attendance returns zero rows.** `features/attendance/api.ts:28` reads `.from('attendance')` directly; base table is now staff-only → family screen shows "no data". **Fix:** repoint to `attendance_parent_view`. *Schema mitigation option:* add a family-scoped SELECT policy on `attendance` instead of forcing the view (you chose the view; flagging the alternative).
- **All times render `NaN`.** `time_ms` → `time_hundredths` rename breaks `features/{progress,standards,legacy}` + `lib/pdf/...` which read `.time_ms`. **Fix:** rename in `types/database.ts` + call sites. *Schema mitigation option:* keep a read-compat column `time_ms INTEGER GENERATED ALWAYS AS (time_hundredths*10) STORED` during the transition.
- **Times are 10× wrong even after rename.** Formatters do `ms/1000`; values are now hundredths. **Fix:** `formatTimeFromHundredths` (`/100`).
- **(P1) Admin attendance upsert errors:** `onConflict: "swimmer_id,schedule_event_id"` (`attendance/api.ts:76,122`) no longer matches the unique key and omits now-NOT-NULL `practice_date` → PG 42P10. **Fix:** update onConflict + include `practice_date`.

### P0-8 (migration) · Identity remap + `handle_new_user` trigger fights the backfill 🔴 [Migration] — **Fix in: BACKFILL**
`profiles.user_id` is a Supabase UUID; the Coach App uses **Firebase string UIDs** and Firestore auto-ids everywhere (coach_id, marked_by, swimmer ids, ids inside JSONB/arrays). Creating `auth.users` during backfill **fires `on_auth_user_created`** (~:862), which inserts a `family/pending` profile — then the backfill's own profile INSERT hits `user_id UNIQUE` and **fails**, and coaches land mis-roled. **Fix:** disable the trigger during backfill (or convert backfill to UPDATE the trigger-made rows); build an id-remap table holding **both** `auth_user_id` and `profile_id` per Firebase UID (needed because `attendance.marked_by`→auth.users but `swimmer_notes.coach_id`→profiles — see P1 mixed-FK). Full remap inventory is in the migration-agent appendix below.

### P0-9 (migration) · Family synthesis can't model shared custody 🔴 [Migration] — 🟥 **see decision D-A**
`swimmers.family_id` is a **single** FK, but Coach App parents hold `linkedSwimmerIds[]` (N:M). "One family per invite" (schema comment ~:128) silently breaks for divorced/two-account households: if Parent A and Parent B both link swimmer X, the second link overwrites X's `family_id` and **the other parent loses all RLS access to their own child** (`is_my_swimmer` matches one family only). Also: Coach swimmers that are the *same real child* as an existing BSPC swimmer (match on `usa_swimming_id`/name+DOB) must reuse the existing family, not synthesize a duplicate.
**Fix (D-A):** either (a) **swimmer-clustered union-find** synthesis (any parents sharing ≥1 swimmer collapse to one family) + a roster-reconciliation pass before synthesis — keeps the singular FK but can over-merge; or (b) replace singular `family_id` with a **`guardianships(profile_id, swimmer_id)` join table** and rewrite `is_my_swimmer()` — correct multi-guardian model, but a schema change. This is the biggest open design question in the migration.

---

## P1 — serious

| ID | Finding | Where | Fix in | Note |
|---|---|---|---|---|
| **P1-1** | **Coach profile undeletable**: ~11 `coach_id NOT NULL REFERENCES profiles(id)` with no `ON DELETE` (RESTRICT). Can't hard-delete a departed coach who authored anything; `profiles.user_id ON DELETE CASCADE` (~:145) means a Supabase "delete user" also wedges. | all `coach_id` FKs; `:145` | SCHEMA | *Downgraded from agent P0:* `account_status='deactivated'` is the intended offboarding, so hard-delete being blocked is partly by-design. Still: decide a policy (soft-delete only, documented) and the auth-cascade interaction. |
| **P1-2** | **`families` delete CASCADEs swimmers** (`swimmers.family_id ... ON DELETE CASCADE`, ~:174) but only SET NULLs parent profiles — deleting a family annihilates each swimmer + their entire results/attendance/notes/medical history. Contradicts decision #4 (roster pre-exists family). | `:174` vs `:150` | SCHEMA | Change `swimmers.family_id` to `ON DELETE SET NULL`. |
| **P1-3** | **Nullable `*_by` FKs missing `ON DELETE SET NULL`** (`created_by`, `reviewed_by`, `media_consent_granted_by`, `updated_by`, `redeemed_by`) → block profile deletion despite being nullable (clearly intended to null out). | `:189,191,222,235,420,525,559` | SCHEMA | Add `ON DELETE SET NULL` to each. |
| **P1-4** | **`tagged_swimmer_ids UUID[]` consent integrity**: media-consent gate is a denormalized array with no FK — a deleted/withdrawn swimmer's id lingers; consent can't be verified relationally. COPPA-relevant. | `:539-540,509` | SCHEMA | Normalize the consent-bearing set into `video_session_swimmers(session_id, swimmer_id)` with CASCADE FKs; keep arrays only for non-gating selects. |
| **P1-5** | **`swimmer_notes.source_ref_id`**: polymorphic pointer (→ audio_session_drafts *or* swimmer_voice_notes) with **no FK** → guaranteed orphans + accidental cross-table id collision. | `:466` | SCHEMA | Split into two typed nullable FKs (`ON DELETE SET NULL`) + CHECK at most one set, keyed off `source`. |
| **P1-6** | **`in_app_notifications.rule_id` no FK** to `notification_rules`; orphans on rule delete; weakens the idempotency key's meaning. | `:728` | SCHEMA | `REFERENCES notification_rules(id) ON DELETE SET NULL`. |
| **P1-7** | **`in_app_update_own` missing `WITH CHECK`** → a user can rewrite their own notification `title`/`body`/`deep_link` (phishing) or attempt row reassignment. Intent was "toggle is_read." | `:1066` | SCHEMA | `WITH CHECK (user_id = auth.uid())`; ideally restrict to `is_read` via trigger/column grant. |
| **P1-8** | **`USING (TRUE)` reads available to `pending`/`deactivated` accounts** — schedule, calendar, meets, change_log are readable by any auto-created `pending` signup. BSPC's `account_status` gate is bypassed. | `:1002,1007,1010,1028` | SCHEMA | Add `is_approved()` helper; `USING (is_approved() OR is_staff())` on the family-facing reads. |
| **P1-9** | **`schedule_change_log` world-readable** (`USING (TRUE)`) exposes raw `previous_data`/`new_data` JSONB (cancellation reasons, internal notes) to all. | `:1007` | SCHEMA | Restrict SELECT to `is_staff()` (parents read effective `schedule_events`, not the audit log). |
| **P1-10** | **RLS recursion seam + perf:** `families_select_own` (~:983) and `announcements_select_approved` (~:1016) regress to inline `EXISTS`/`IN` subqueries on RLS-enabled tables — the exact pattern the SECURITY DEFINER helpers were added to avoid. No loop today, but it's where one appears under future policy edits, and it's per-row. | `:983,1016` | SCHEMA | Add `my_family_ids()` / `my_practice_groups()` SECURITY DEFINER helpers; use them in these policies. |
| **P1-11** | **`attendance_parent_view` execution context is implicit.** A plain `CREATE VIEW` runs as its owner; whether it bypasses `attendance` RLS depends on unstated ownership. If owned by a non-privileged role → parents get **zero rows**; the COPPA wall shouldn't rest on an undeclared default. | `:658` | SCHEMA | Make explicit: document/assert a privileged owner, or add a family SELECT policy on `attendance` + `security_invoker=true`. (`auth.uid()` inside `is_my_swimmer` does resolve to the caller — that part is fine.) |
| **P1-12** | **time ÷10 lossiness unproven.** No CHECK that BSPC `time_ms % 10 = 0`; if any value isn't a multiple of 10, ÷10 silently changes a recorded PR/record. No rounding rule specified. | `swim_results/personal_bests/team_records/time_standards` | BACKFILL | Pre-audit `WHERE time_ms % 10 <> 0`; decide round vs reject; convert **per-source before** the merge (never ÷10 the Coach App rows, which are already hundredths). |
| **P1-13** | **`personal_bests` dedup loss.** UNIQUE moved to `(swimmer, event, course)` but `course` is nullable; legacy BSPC PBs have NULL course → default NULL-distinct means two NULL-course PBs for one event no longer collide. | `:434` | SCHEMA or BACKFILL | Backfill a non-null course (e.g. `'SCY'`) for legacy PBs, **or** make this index `NULLS NOT DISTINCT`/partial. |

---

## P2 — hardening

| ID | Finding | Where | Fix in |
|---|---|---|---|
| P2-1 | `swimmers_select_own` exposes `media_consent_*`, `created_by` (coach uid), `usa_swimming_id` to the owning parent (own child — acceptable, but `created_by` is staff-internal). | `:989` | SCHEMA (view projection) |
| P2-2 | `meets`/`calendar_events` `USING(TRUE)` leak `coach_id` (staff profile id) to all parents; RLS can't hide columns. | `:1010,1028` | SCHEMA (parent view omitting coach_id) |
| P2-3 | `in_app_notifications` idempotency gap: a rule firing with NULL `swimmer_id`/`source_eval_date` (team-wide rules) won't dedup (NULLs distinct). | `:733` | SCHEMA (partial unique index `WHERE rule_id IS NOT NULL` with COALESCE) |
| P2-4 | `personal_bests` loses meet provenance on meet delete (no `meet_name` fallback, unlike `swim_results`). | `:433` | SCHEMA |
| P2-5 | `aggregations` rows stale on swimmer delete (TEXT key embeds id, no FK); no write policy (service-role only). **Don't migrate aggregations — recompute.** | `:771` | BACKFILL + SCHEMA(doc) |
| P2-6 | `first_name`/`last_name NOT NULL` reject mononym/incomplete roster docs; `meets.location`/`start_date NOT NULL` reject skeletal draft meets. | `:175-176,357,361` | BACKFILL (or relax) |
| P2-7 | `NULLS NOT DISTINCT` is **PG15+ only**, no version guard — `CREATE TABLE` is a syntax error on older Postgres. (Resolved if P0-6 adopts partial indexes.) | `:650` | SCHEMA |
| P2-8 | Enum cast hygiene: stray/mis-cased/legacy group values (`'varsity'`,`'jv'` seen in fixtures, `'bronze'` casing), `note_tag` exact spelling (`'race strategy'`, `'IM'`), `meets.events[].gender = 'Mixed'` not in `gender` enum. | enums | BACKFILL |
| P2-9 | `calendar_events.recurring` JSONB is never expanded into occurrences; parents reading a team calendar won't see recurring instances. | `:317` | APP/BACKFILL |
| P2-10 | `practice_plans.ratings` JSONB keyed by **Firebase coachId**; keys must be rewritten to `profiles.id` or per-coach lookups silently miss. (Not yet in NOTES FOLLOWUP.) | `:586` | BACKFILL |
| P2-11 | `template_source_id` self-FK + note↔draft cross-pointers permit reference cycles / state drift (no deadlock; inserts fine via nullable). | `:582,466,527` | SCHEMA (trigger) / low priority |

**Closed (not findings):** `meet_entries` staff-only is *intentional* (NOTES #3-adjacent) and the parent app doesn't query it — not a regression. Dropped `announcements_select_pending` is *redundant* — `announcements_select_approved` already returns `target_group IS NULL` rows to pending users, so behavior is preserved (confirmed by the parent-app agent). RLS-helper per-row cost is acceptable given the app always pre-filters by `swimmer_id`/`family_id`.

---

## Two decisions only you can make

**🟥 D-A — Family vs guardianship model (P0-9).** Singular `swimmers.family_id` can't represent a swimmer with two independent guardians (shared custody, two accounts). Pick:
- **(a) Keep singular FK** + swimmer-clustered union-find synthesis + roster reconciliation. Simplest; risks over-merging unrelated families and still can't model true co-guardianship.
- **(b) `guardianships(profile_id, swimmer_id)` join table** + rewrite `is_my_swimmer()`. Correct N:M model; a real schema change touching RLS.
*My lean: (b)* — youth swim teams have shared-custody households routinely, and silent access loss for a parent to their own child is the worst failure mode.

**🟥 D-B — Two-a-day uniqueness mechanism (P0-6).** Keep `NULLS NOT DISTINCT` (PG15-only, deadlocks on schedule deletes) or switch to **two partial unique indexes + `ON DELETE RESTRICT`**?
*My lean: partial indexes* — fixes the SET-NULL deadlock, drops the PG15 dependency (P2-7), and the same pattern cleanly fixes P1-13 and P2-3.

---

## Recommended fix batches (when you're ready — still no edits made)

1. **Privacy P0s (smallest, highest urgency):** P0-1 (profiles WITH CHECK/trigger), P0-2 (rsvps RLS). Pure RLS edits.
2. **Attendance correctness:** P0-3 (nullable status), P0-4 (view CASE), P0-6/D-B (partial indexes + RESTRICT). One coherent attendance pass.
3. **Insert-blockers:** P0-5 (nullable date), P2-6 (nullable name/location or backfill).
4. **Referential pass:** P1-1..P1-6 (ON DELETE strategy, typed FKs, consent junction table).
5. **RLS hardening:** P1-7..P1-11 (WITH CHECK, is_approved(), change_log, helper refactor, view ownership).
6. **Design decisions:** D-A (family model) → may reshape `swimmers`/`profiles`/`is_my_swimmer`.
7. **BACKFILL spec** (separate doc): id-remap, ÷10 audit, enum hygiene, attendance dedup, family synthesis, recompute aggregations, two-pass cross-pointers, handle_new_user disable.
8. **APP migration** (planned, per-service): time field+unit, attendance→view, onConflict key, `Masters` label.

Tell me which batches to apply (and your D-A / D-B calls) and I'll make the edits to `01_CANONICAL_SCHEMA.sql` + update NOTES.md. Still schema-only until you say otherwise.

---

### Appendix — full id-remap inventory (from the migration agent)
Columns holding a Firebase/Firestore id that the backfill must remap to a Supabase UUID: `profiles.user_id`; coach refs `swimmers.created_by/media_consent_granted_by`, `swimmer_medical.updated_by`, `parent_invites.coach_id/redeemed_by`, `calendar_events.coach_id`, `meets.coach_id`, `swimmer_notes.coach_id`, `group_notes.coach_id`, `swimmer_voice_notes.coach_id`, `audio_sessions.coach_id`, `video_sessions.coach_id`, `practice_plans.coach_id`, `season_plans.coach_id`, `notification_rules.coach_id`, `import_jobs.coach_id`, `audio_session_drafts.reviewed_by`, `video_session_drafts.reviewed_by`, `attendance.marked_by` (→ auth.users, **not** profiles — mixed target); id-bearing **arrays** `audio/video_sessions.{selected,tagged}_swimmer_ids`, `season_plan_weeks.practice_plan_ids`; **JSONB** `practice_plans.ratings` (keys), `swimmer_coach_profile.parent_contacts`, `meets.events`; **polymorphic** `swimmer_notes.source_ref_id`; **text-key** `aggregations.key` + payload. Migration order: drafts/voice_notes → notes (for `source_ref_id`), with a two-pass UPDATE for note↔draft back-pointers.
> ⚠️ HISTORICAL — superseded by the fresh-launch model in Director Rulings 56/57; retain as schema review evidence, not executable migration instructions.
