# 07 — Phase C Mini-Plan: ATTENDANCE (+ red-team)

**PLANNING DOC ONLY.** No app code, no schema changes ship with this file.
04 flagged attendance as the single riskiest step and prescribed its own
mini-plan + red-team pass; this is that document. Canonical
(`01_CANONICAL_SCHEMA.sql`) stays law; §9 lists the canonical amendments this
plan asks Kevin to ratify. Every red-team finding (§8, RC-1…RC-14) is folded
into the sections it attacks.

Why riskiest (04's five compounding risks, all confirmed by code reading):
most function fan-in of any collection; the inherited parent-app reads;
two-a-day uniqueness; historical dedup; cross-tier blast radius. To which
this plan adds a sixth, found while reading: **attendance is the one
collection where the two apps' live schemas and the Coach app disagree on
the MODEL itself** (event-keyed marking vs date-keyed check-in), not just on
column names.

---

## 1. Current reality — three shapes, one table to merge them

| | Coach App (Firestore) | BSPC live (00001) | Canonical (01) |
|---|---|---|---|
| Key | `practiceDate` string, NO event | `schedule_event_id NOT NULL`, NO date | date + optional event |
| Uniqueness | none — blind `addDoc` (double-tap = dup) | `UNIQUE(swimmer_id, schedule_event_id)` | 2 partial unique indexes [D-B] |
| status | `'normal'\|'excused'\|'sick'\|'injured'\|'left_early'` or null; **no 'absent'** (record = attended) | `'present'\|'absent'` NOT NULL; **absence is a row** | 6-value enum, NULLABLE (NULL = checked-in) |
| Extra fields | arrivedAt/departedAt/note + denorm names | — | arrived/departed/note/practice_group |
| marked_by | Firebase uid string | `auth.users` FK NOT NULL | `profiles` FK nullable |
| Parent access | via `parentPortal` callable (sanitized) | **direct table SELECT (`select("*")`) under a family RLS policy** | **table staff-only; parents read `attendance_parent_view`** (present/absent collapse) |
| pgTAP coverage | n/a | **ZERO today** — the most COPPA-sensitive table has no RLS proofs | — |

Audience split in the BSPC app (verified in code):
- **Parent-facing:** `app/attendance.tsx` → `SwimmerAttendanceCard` →
  `useSwimmerAttendance` → `fetchSwimmerAttendance` (`select("*")` on the
  table). This is the read that must move to the parent view.
- **Admin-facing:** `app/admin/attendance.tsx` → `AttendanceMarkerScreen` →
  `useEventAttendance` + `useMarkAttendance`/`useBatchMarkAttendance`
  (event-keyed `upsert(onConflict: 'swimmer_id,schedule_event_id')`). These
  stay on the table (staff RLS) and **depend on the UNIQUE constraint
  existing as a real constraint** (RC-2b).

## 2. Scope decision D-C1 — which of the "5 functions" move in C

04's per-step C lists 5 functions "all move with the client." Reading the
code, 4 of the 5 exist to maintain things that LATER phases deliberately
retire or re-home, and OD-4 has since ratified defer-whole as safe handling:

| Function | What it does with attendance | This plan |
|---|---|---|
| `parentPortal` | reads 30 recent rows per linked swimmer (parent-facing) | **moves in C** (the precedent-pattern payload migration) |
| `onAttendanceWritten` | Firestore TRIGGER → recomputes `aggregations/*` | **defer whole to J** — its product (aggregations) is retired in J; re-pointing it in C builds PG plumbing J deletes (RC-8) |
| `dashboardAggregations` | reads attendance(+notes/times/video) → aggregations | **defer whole to J** (same reason; it spans 4 phases' collections) |
| `evaluateNotificationRules` | attendance trigger → writes notifications | **defer whole to G** (it is a notifications feature; 04 already marks its attendance read "hard dep on C" — lands on PG as part of G, after C) |
| `dailyDigest` | reads today's attendance | already **deferred whole to G** (OD-4, ratified) |

**Recorded cutover constraint:** the attendance DATA cutover requires C+G+J
reader code landed (or accepts digest/notification-rules/dashboard
aggregations dark during the window). Pre-launch with one coordinated
cutover, this costs nothing — it just becomes a checklist line.

This also dissolves the worst trap in Phase C: Firestore `onDocumentWritten`
triggers can never fire from Postgres writes, so SOME re-homing design
(webhooks, RPC side-effects, schedules) was unavoidable for the trigger pair
— deferring them whole moves that design into J, where PG-native recompute
(triggers/scheduled jobs per 04-J) replaces the mechanism anyway.

**J note banked now (RC-4c):** `recomputeAttendanceAggregation` counts EVERY
row as attended (Coach model). The merged table contains BSPC `'absent'`
rows; J's recompute MUST be status-aware (`status IS NULL OR status NOT IN
('absent','excused','sick','injured')` — same set as the parent view) or
attendance percentages inflate.

## 3. Schema migration `00004_phase_c_attendance.sql` (next session, with pgTAP 007)

Additive/widening except where canonical explicitly supersedes (each ⚠ is a
deliberate live-behavior change, called out):

1. **Enum:** `ALTER TYPE attendance_status ADD VALUE` × 4 ('excused',
   'sick', 'injured', 'left_early'). PG12+ allows ADD VALUE in a
   transaction so long as the same migration doesn't USE the value — 00004
   won't (RC-7 lists this as a pgTAP-only provable).
2. **Columns:** ADD `practice_date DATE`, `practice_group TEXT CHECK`
   (ratified 8), `arrived_at TIMESTAMPTZ`, `departed_at TIMESTAMPTZ`,
   `note TEXT`. Then backfill `practice_date` for any existing event-keyed
   rows from `schedule_events.start_time AT TIME ZONE 'America/Chicago'`
   (RC-5: explicit zone, never server-local), then `SET NOT NULL` on
   practice_date (works whether the table is empty or seeded).
3. ⚠ `status` DROP NOT NULL (canonical [P0-3]: NULL = checked-in/present).
4. ⚠ `schedule_event_id` DROP NOT NULL; FK `ON DELETE CASCADE → RESTRICT`
   (canonical [D-B/P0-6]). Behavior change: deleting a schedule event that
   has attendance now errors instead of silently destroying minors' presence
   records (RC-10) — the BSPC admin screen surfaces its normal error state;
   graceful UX is a post-migration nicety.
5. **Keys (D-C3):** KEEP the live `UNIQUE(swimmer_id, schedule_event_id)`
   constraint (NULLs distinct ⇒ it doesn't constrain Coach's NULL-event
   rows, and the BSPC app's existing `upsert(onConflict:…)` inference keeps
   working — RC-2b). ADD `attendance_day_key UNIQUE INDEX (swimmer_id,
   practice_date) WHERE schedule_event_id IS NULL` for Coach check-ins.
   Canonical amendment A2 (§9) aligns 01 to this shape.
6. **RPC (D-C2):** `attendance_check_in(p_swimmer_ids uuid[], p_practice_date
   date, p_practice_group text, p_arrived_at timestamptz)` — SECURITY
   DEFINER, staff-gated via `is_staff()` guard inside, does
   `INSERT … ON CONFLICT (swimmer_id, practice_date) WHERE
   schedule_event_id IS NULL DO NOTHING` (the partial-index ON CONFLICT
   PostgREST cannot express — RC-2a), `marked_by := auth.uid()`, returns
   per-swimmer `(swimmer_id, attendance_id, created boolean)`. One call
   serves both `checkIn` (array of 1) and `batchCheckIn` (chunked arrays).
   Double-tap and concurrent duplicate check-ins resolve atomically at the
   index (RC-12 — an IMPROVEMENT over Firestore, where a double tap created
   two docs).
7. **Parent view:** `attendance_parent_view` with the canonical CASE
   (`absent/excused/sick/injured → 'absent'`, else — incl. NULL and
   left_early — `'present'`), exposing ONLY `id, swimmer_id, practice_date,
   schedule_event_id, status, created_at` — no note, no marked_by, no
   arrival/departure times. **Transitional predicate (RC-1):**
   `WHERE is_my_swimmer(a.swimmer_id) OR <live family_id subquery>` — the
   OD-1 world hasn't backfilled guardianships yet, so a view gated only on
   `is_my_swimmer()` would show live BSPC families NOTHING. The family_id
   arm is dropped at the OD-1 convergence step. (pgTAP proves both arms.)
8. ⚠ **RLS:** DROP `attendance_select_own` (the family direct-table read) in
   the SAME migration that adds the note/arrival columns — there must be no
   commit at which `select("*")` hands a parent another child's coach note
   or any new column (RC-3). The table becomes staff-write/staff-read +
   view-for-parents, exactly canonical. `attendance_manage_admin` stays
   as-is (recursion-safe since 00002's profiles fix; helper conversion is
   convergence-sweep work).

## 4. The COPPA wall, spelled out (who can touch a child's presence records)

| Principal | attendance TABLE | attendance_parent_view | RPC |
|---|---|---|---|
| coach_admin / super_admin (approved) | read+write ALL rows | (n/a — they read the table) | ✓ check-in |
| Approved guardian OF the swimmer | **nothing** (post-00004) | own swimmers' rows, present/absent ONLY | ✗ (`is_staff()` guard) |
| PENDING guardian (even if linked) | nothing | **nothing** (`is_my_swimmer()` requires approved; family_id arm requires an approved profile link — fixture-proven) | ✗ |
| Other families / other guardians | nothing | nothing (predicate scopes to own) | ✗ |
| Cloud Functions (service role) | bypasses RLS — authorization is the guardianship check inside the callable (Phase A pattern), and the sanitizer strips to id/practiceDate/status | — | — |
| anon | nothing (no policies, no grants) | no grant | ✗ |

**pgTAP 007 proof list (~16 tests, the bar rises again):** column/enum/key
shape (3); staff insert + read-all (2); family direct-table SELECT returns 0
rows even for OWN swimmer (1 — the new wall); view shows own swimmer via
family_id arm AND via guardianship arm (2 — RC-1 both transitional arms);
view collapse cases sick→absent + left_early→present + NULL→present (1);
view column shape excludes note/marked_by (1); pending guardian sees 0 in
view (1); cross-family sees 0 (1); family INSERT/UPDATE on table throws (1);
day-key double-insert throws / RPC double-call yields 1 row + created=false
(2); event-key upsert still dedupes (1); RESTRICT blocks event delete with
attendance (1). **These are the proofs jest mocks can never give (RC-7).**

## 5. Code swaps (frozen interfaces; one commit each)

**5a. BSPC app — parent read → view.** `fetchSwimmerAttendance` re-points
`from("attendance")` → `from("attendance_parent_view")` ordered by
`practice_date` (and stops returning `marked_by`, which the parent card
doesn't render — transforms verified to use status/dates only; if next
session's read of `transforms.ts` finds otherwise: STOP, report).
`fetchEventAttendance` + both mark/upsert mutations are admin-facing and
stay on the table, unchanged. Jest: existing attendance tests re-pointed;
count never drops.

**5b. Coach App — `attendance.ts` data layer.**
- Reads: `subscribeTodayAttendance(date)` → `eq('practice_date', date)`;
  `subscribeSwimmerAttendance` → `eq('swimmer_id', …)` ordered desc,
  limited. Realtime parity per playbook (immediate fire, full re-emit,
  sync teardown, post-teardown guard) on the one `attendance` table.
  **D-C5:** reads filter out absent-like rows
  (`status IS NULL OR status NOT IN ('absent','excused','sick','injured')`
  — wait, no: Coach reads exclude ONLY `'absent'`; sick/left_early rows are
  Coach-authored check-ins that its UI legitimately shows). Precisely:
  exclude `status = 'absent'` (the one value Coach never writes and whose
  rows mean "was not there" under the merged model — RC-4b).
- Denormalized names (RC-5 of playbook §"derive on read"): `swimmerName`
  via the `swimmer:swimmers(first_name,last_name)` embed (FK exists);
  `coachName` has NO FK path (marked_by → auth.users, not profiles), so the
  emit composes a second query — `profiles.in('user_id', markedByIds)` — and
  maps `full_name`; write params stay in the signatures, not persisted.
- Writes: `checkIn`/`batchCheckIn` → the `attendance_check_in` RPC (chunks
  of 400 preserved; `BatchPartialFailureError` semantics preserved
  per-chunk). `checkOut` → `update({departed_at, status: mapped, note})`.
- **Status map (D-C6), the only consistent one:** write `'normal'→'present'`,
  others pass through (Coach never writes 'absent'); read `'present'→
  'normal'`, `NULL→undefined`, others pass through. `practice_date` stays a
  calendar STRING end-to-end — never `new Date()`'d (RC-5; the meets-flake
  lesson).

**5c. Functions — `parentPortal` attendance payload.** `from('attendance')
.select('id, practice_date, status').eq('swimmer_id', …).order(…desc)
.limit(30)` via service role. **D-C4:** the sanitizer adopts the SAME
present/absent collapse as the parent view (one wall, one rule) — the
portal's current raw passthrough (`'normal'`, and post-merge `'sick'`)
disappears; fixtures change `'normal'`→`'present'`. All other COPPA
assertions verbatim. times stays Firestore (Phase D).

**5d. Backfill scaffolding `BSPC/ACTIVE/migration/attendance/`** (pure fns +
tests, the A/B pattern; nothing runs against a DB):
- `coachAttendanceToRow`: practiceDate string passthrough; status
  null/'normal'→`'present'` (the NOTES-ratified rule); arrived/departed/note
  passthrough (note lands behind the staff wall ✓); `marked_by` via
  `migration_identity_map`; swimmer id via `migration_swimmer_map` (Phase B
  resolver); names/group denorms dropped/mapped.
- **Three-bucket same-day dedup (RC-6):** exact duplicates (same status +
  same times) → collapse keeping earliest; **time-disjoint same-day rows →
  `needsEventAssignment` bucket** (they are probably REAL two-a-days that
  Firestore couldn't key — a human assigns `schedule_event_id`s at cutover
  rather than the script destroying real history); conflicting rows
  (same/overlapping times, different status) → `conflicts` bucket for human
  review. The runner STOPS while either review bucket is non-empty.
- Audits: ≤1 NULL-event row per (swimmer, day); status domain; dangling
  swimmer ids dropped + reported (NM-6 style).

## 6. Commit sequence (next session), rollback, stop points

1. BSPC `00004` + pgTAP `007` (+ RPC) — pgTAP 45→~61, all 7 files green.
2. BSPC app parent read → view (jest stays green, count up).
3. Coach `attendance.ts` swap + tests (client 983→~990+).
4. Functions `parentPortal` attendance payload + tests (114→~117).
5. BSPC `migration/attendance/` scaffolding + tests (jest 811→~826+).
6. UNIFY NOTES log + green-bar update.

Every commit is a frozen-interface data-layer change, independently
revertible with `git revert` (no force-push/rebase/amend, per standing
rules). **STOP-and-ask triggers:** any pgTAP 001–006 regression; any change
that would weaken an existing COPPA assertion; `transforms.ts`/marker-screen
audience surprises (5a); the enum ALTER misbehaving on the local stack;
seeded local data blocking the practice_date NOT NULL step; anything that
makes the family-arm view predicate insufficient.

## 7. Deliberately welded to later phases (NOT Phase C work)

- `evaluateNotificationRules` + `dailyDigest` → **G** (their attendance
  reads land on PG then; idempotency upsert per decision #2 unaffected —
  RC-11).
- `onAttendanceWritten` + `dashboardAggregations` + trigger re-homing +
  status-aware recompute → **J** (RC-8, RC-4c).
- Guardianship backfill + dropping the view's family_id arm + marked_by
  auth.users→profiles remap (RC-9/D-C7) + inline-EXISTS policy cleanup →
  **OD-1 convergence**.
- Coach UI passing `schedule_event_id` (true AM/PM two-a-day logging) →
  post-migration feature work (the schema is ready; the UI freeze holds).
- Running the actual backfill / cutover → cutover staging (HARD STOP rules).

## 8. RED-TEAM — findings register (all folded in above)

| # | Attack | Disposition |
|---|---|---|
| RC-1 | **Partial-migration trap:** parent view gated on `is_my_swimmer()` alone shows live family_id-world parents NOTHING (guardianships not backfilled until cutover) | View carries a transitional family_id OR-arm; both arms pgTAP-proven; arm dropped at convergence (§3.7) |
| RC-2 | **PostgREST cannot upsert against a partial unique index** (a) Coach day-key check-in; (b) replacing the live UNIQUE with canonical's partial event index silently breaks the BSPC app's existing `onConflict` upsert — jest mocks would NEVER see it | (a) SECURITY DEFINER RPC does the ON CONFLICT in SQL (§3.6, D-C2); (b) keep the real constraint, add only the day partial (§3.5, D-C3 + amendment A2) |
| RC-3 | **COPPA exposure:** parents `select("*")` the table today; adding note/arrived/departed before fixing RLS hands parents coach notes; portal could leak via shape drift | Columns + policy-drop land in ONE migration; view excludes sensitive columns (pgTAP column-shape proof); portal sanitizer shape frozen + collapse (D-C4) |
| RC-4 | **Status-model collision:** Coach has no 'absent' (row=attended), BSPC's absence IS a row → (a) value mapping, (b) Coach roster would show absent kids as present, (c) J aggregation counts absences as attendance | (a) D-C6 bidirectional map; (b) D-C5 Coach reads exclude `'absent'`; (c) J note banked (§2) |
| RC-5 | **TZ races:** deriving practice_date from timestamps or `new Date()`-ing date strings shifts records across midnight (the known meets flake class) | practice_date is a calendar STRING end-to-end in the adapter; 00004's one derivation uses explicit `America/Chicago`; backfill passthrough |
| RC-6 | **Backfill data destruction:** "dedup same-day rows" could collapse REAL two-a-days (Coach data has no event ids) | Three-bucket dedup: exact-dup collapse / time-disjoint → human event assignment / conflicts → human review; runner stops on non-empty buckets (§5d) |
| RC-7 | **Jest-mock blindness:** ON CONFLICT, view shape, RESTRICT, enum domain, RLS walls, RPC atomicity are all invisible to mocks | Each is a named pgTAP 007 test (§4); pgTAP is half the green bar by rule |
| RC-8 | Firestore attendance triggers can never fire from PG writes; naive C "migration" of them ships dead code paths | Trigger pair deferred whole to J where the mechanism is replaced, not ported (D-C1) |
| RC-9 | marked_by FK: canonical wants profiles, live is auth.users NOT NULL; swapping now breaks the BSPC app's writes invisibly (mocks) | Keep auth.users live (transitional); coachName derived via second query; remap at convergence (D-C7) |
| RC-10 | CASCADE→RESTRICT turns a working admin delete into an error | Canonical-ratified [P0-6] (protecting minors' records beats delete convenience); error surfaces in existing UI error state; noted as behavior change |
| RC-11 | Notification dedup key (rule,swimmer,date) could double-fire during the split window | Evaluator G-deferred whole; no C window exists; UNIQUE upsert lands with G (decision #2) |
| RC-12 | Double-tap check-in race: two concurrent inserts | Resolved atomically by the day key + RPC ON CONFLICT — strictly better than today's Firestore dup; documented as an intended improvement, not a regression |
| RC-13 | dailyDigest "still at practice" logic reads `departedAt == null` | G note: PG NULL `departed_at` keeps the same meaning; no C action |
| RC-14 | Unlinked/NULL-family swimmers' attendance visible to wrong parents? | `is_my_swimmer()` false and family-arm unmatched → invisible in view; staff sees all; pgTAP-proven (§4) |

## 9. Canonical amendments for ratification (presented, NOT implemented)

- **A1 — `swimmers.media_consent_granted_by_name TEXT`** (carried from Phase
  B). The Coach App records WHO consented as a free-text guardian name;
  canonical only has a `profiles` FK, which cannot hold a name before (or
  after) guardians become profiles — a parent who signs a paper form may
  never be an app user at all. Live already carries both columns (00003).
  Options: (i) add the name column to canonical 01 — recommended; (ii)
  decline and stuff the name into `media_consent_notes` — lossy, conflates
  two fields; (iii) decline and force consent to reference a profile —
  loses recorded consent for non-user guardians. **Recommend (i).**
- **A2 — replace canonical's partial `attendance_event_key` index with the
  plain `UNIQUE(swimmer_id, schedule_event_id)` constraint** (live's shape).
  Identical coverage (NULLs distinct), but a real constraint is
  ON-CONFLICT-inferable, which the BSPC app's existing upserts require
  (RC-2b). The day-side partial index stays. **Recommend ratify.**
- **A3 — add the `attendance_check_in` SECURITY DEFINER RPC to canonical**
  (§3.6). Canonical already embraces SECURITY DEFINER functions (RLS
  helpers; redeemInvite planned for I); this is the same pattern for the
  one write PostgREST cannot express safely. **Recommend ratify.**
