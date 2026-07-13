# 08 — Phase D Mini-Plan: TIMES / PRs / MEET RESULTS (+ red-team)

**PLANNING DOC ONLY.** No app code, no schema changes ship with this file.
Kevin's Phase D scoping tripwire fired: the two apps disagree on the PR
MODEL itself (where personal-best truth lives and who maintains it), the
live tables store a different TIME UNIT than both the Coach App and
canonical law, and the end-to-end read surfaced a latent cross-phase gap
(§8 RD-1) that jest can never see. Same drill as 07: plan, red-team, fold
findings in, end with decisions for Kevin. Canonical
(`01_CANONICAL_SCHEMA.sql`) stays law; §9 lists what needs ratification.

Why this fired the tripwire (vs. proceeding straight under 04's one-liner):

1. **PR truth lives in three places today.** Coach: an `isPR` flag ON time
   rows, maintained by THREE client writers (addTime un-PRs the old row;
   deleteTime promotes the next-fastest in a batch; meetResultsImport
   un-PRs inside its import batches) **plus** a `prsByEvent` aggregation
   recomputed by the `onTimesWritten` Firestore trigger. BSPC: a separate
   `personal_bests` TABLE (one row per swimmer+event — **no course in the
   key, no course column at all**) plus an `is_personal_best` flag on
   `swim_results`. Canonical: BOTH (flag + PB table) with
   `UNIQUE(swimmer_id, event_name, course)` and course NOT NULL [P1-13].
   **Nothing in either app writes `personal_bests` today** — without a
   designed owner it goes stale the first time a Coach time lands.
2. **Unit divergence on live tables.** Coach `time` = HUNDREDTHS
   (6523 = "1:05.23", `formatTimeDisplay`). BSPC `time_ms` = REAL
   MILLISECONDS (`formatTimeFromMs` divides by 1000). Canonical [#1] =
   hundredths everywhere, with 04's ratified "÷10 audit per source
   (`time_ms % 10`)". Converting a live column in place couples the schema
   commit to the BSPC app's reads — and jest, fully mocked, would stay
   green through a wrong-unit regression (RC-7 class).
3. **The import spans phases.** `meetResultsImport` writes times (D) AND
   `meets/{id}/entries` finalTime sync (meets = H) AND `import_jobs`
   bookkeeping (unmigrated). Needs the csvImport-style split, stated.
4. **RD-1 (found while reading):** the pre-A swapped services reference
   tables NO migration creates. Verified against the running local DB:
   `goals` and `group_notes` do not exist, yet `goals.ts`/`groupNotes.ts`
   (swapped pre-A), the Phase B `goals(event_name)` embeds in Coach
   `swimmers.ts`, AND `parentPortal`'s detail read all query them. Invisible
   to jest (mocks) and to pgTAP (no tests touch them) — a guaranteed
   runtime 404 at cutover. Phase D is the natural place to close it.

---

## 1. Current reality — three shapes

| | Coach App (Firestore) | BSPC live (00001) | Canonical (01) |
|---|---|---|---|
| Container | `swimmers/{id}/times` subcollection | `swim_results` + `personal_bests` tables | same two tables, merged columns |
| Unit | `time` INTEGER **hundredths** | `time_ms` INTEGER **milliseconds** | `time_hundredths` [#1] |
| Course | `course` on every row ('SCY'/'SCM'/'LCM') | **absent** on both tables | `course` enum; nullable on results, **NOT NULL on PBs** [P1-13] |
| PR model | `isPR` flag on rows; client un-PR/promote; trigger recomputes `prsByEvent` aggregation | `is_personal_best` flag + separate `personal_bests` (UNIQUE swimmer+event) | flag + `personal_bests` (UNIQUE swimmer+event+**course**) |
| Date | `meetDate` nullable timestamp | `date` DATE **NOT NULL** | `date` DATE **nullable** [P0-5] |
| Meet link | `meetName` string (+ optional Firestore `meets/{id}/entries` sync) | `meet_id` FK (SET NULL), no name | `meet_id` FK + `meet_name` text [P2-4] |
| Extras | `splits[]` hundredths, `timeDisplay` denorm, `source`, `createdBy` | — | `splits INTEGER[]`, **no timeDisplay (derived)**, `source` enum, `created_by` [P1-3] |
| Writers | addTime / deleteTime / meetResultsImport (all client) | **none** (read-only app; seed data only) | — |
| pgTAP coverage | n/a | **ZERO today** on both tables | — |

Audience split (verified in code):
- **BSPC (parents, read-only):** `features/progress/api.ts` —
  `fetchSwimmerResults` (`select("*")` on swim_results, ordered `date`
  desc) and `fetchSwimmerPBs` (personal_bests). Family-arm `select_own`
  policies wall them to own swimmers. Sports-performance data is
  parent-visible BY DESIGN (unlike attendance there is no staff-only
  detail on these tables — coach notes live elsewhere). No BSPC writer.
- **Coach (staff):** `times.ts` (subscribe/add/delete), `analytics.ts`
  (time drops, attendance correlation, group reports — one-shot reads
  across swimmers+times+ATTENDANCE), `meetResultsImport.ts` (SDIF/HY3),
  `export.ts` CSV (reads `timeDisplay`/`createdAt`), PRCelebration (isPR).
- **parentPortal:** times payload via `sanitizeTime` — frozen shape
  `{id, event, course, time, timeDisplay, isPR, meetName, meetDate}`.

## 2. Scope — functions and cross-collection reads (D-D1)

| Function / surface | What it does | This plan |
|---|---|---|
| `parentPortal` (times) | reads 50 recent times per linked swimmer | **moves in D** (the precedent payload migration; sanitizer derives `timeDisplay`) |
| `onTimesWritten` | Firestore trigger → recomputes `prsByEvent` + dashboard activity **aggregations** | **defer whole to J** — extends the ratified D-C1(b) precedent to the third aggregation trigger: its product is retired in J, and a Firestore trigger can never fire from PG writes (RC-8) |
| `dashboardAggregations` (times reads) | aggregations | already **J whole** (D-C1(b), ratified) |
| `analytics.ts` (client) | cross-collection one-shot reads: swimmers + times + **attendance** | **moves in D** per 04 — with the D-C5 rule applied to its attendance read (§5c; RD-4) |
| `meetResultsImport.ts` | times writes + meet-entry sync + import_jobs | times-write half moves in D; `meets/{id}/entries` sync stays Firestore until H; `import_jobs` stays until its phase (the ratified csvImport split pattern) |

**In-app PR consumers needing no change:** PRCelebration & screens read
`isPR` off emitted records — the adapter keeps emitting it (§5b).

## 3. Schema migration `00005_phase_d_times.sql` (with pgTAP 008)

Each ⚠ is a deliberate live-behavior change, called out. RC-3 discipline:
every step that changes what a `select("*")` returns lands in the SAME
migration as the policies/columns it implies; the BSPC app's unit flip
lands in the immediately following commit, same session, never pushed
half-done (RD-2).

1. **[D-D3] THE UNIT CUT — all four `time_ms` tables at once, or none.**
   `swim_results`, `personal_bests`, `team_records`, `time_standards` all
   store `time_ms`; canonical names all four `time_hundredths`. Converting
   only D's two tables leaves the database speaking two unit dialects and
   the BSPC app needing both formatters indefinitely. Plan: ONE migration
   converts all four —
   `ALTER TABLE … RENAME COLUMN time_ms TO time_hundredths;` then
   `UPDATE … SET time_hundredths = time_hundredths / 10;` — preceded by
   the ratified audit as a hard gate (RD-3): a DO block raises (aborting
   the whole migration) if ANY row has `time_ms % 10 <> 0`, so a
   sub-hundredth value can never be silently truncated. `supabase/seed.sql`
   values flip in the same commit (team_records seed ÷10).
2. **swim_results additive columns:** `course TEXT CHECK ('SCY','SCM','LCM')`
   (house style: TEXT CHECK now, enum at convergence), `splits INTEGER[]`,
   `meet_name TEXT`, `source TEXT CHECK ('manual','sdif_import','hy3_import')
   NOT NULL DEFAULT 'manual'`, `created_by UUID REFERENCES profiles(id)
   ON DELETE SET NULL` (the exact 00003 pattern; carries the Coach uid
   value-semantics note, D-B7 below).
3. ⚠ **`swim_results.date` DROP NOT NULL** [P0-5] — Coach manual times
   carry no date. BSPC's history read orders `date desc` → the swap adds
   an explicit NULLS-LAST + `created_at` tiebreak so undated manual times
   sink instead of floating (§5a; RD-6).
4. **personal_bests → canonical key:** ADD `course TEXT CHECK` (nullable),
   ADD `meet_name TEXT`; **[D-D4] backfill course** := the course of the
   matching `swim_results` row (same swimmer+event+time) where exactly one
   match exists, else `'SCY'` (short-course-yards default — club reality;
   rows are pre-launch seed data) with every defaulted row REPORTED in the
   migration output (RAISE NOTICE); then `SET NOT NULL`; then ⚠ swap
   `UNIQUE(swimmer_id, event_name)` → `UNIQUE(swimmer_id, event_name,
   course)` [P1-13].
5. **[D-D5] PR MAINTENANCE — the model decision.** One owner for both the
   `is_personal_best` flag and the `personal_bests` table:
   **(b) a database trigger on `swim_results` (RECOMMENDED):**
   `maintain_personal_bests()` AFTER INSERT OR UPDATE OR DELETE, per
   affected (swimmer, event, course): takes
   `pg_advisory_xact_lock(hashtext(swimmer||event||course))` (serializes
   concurrent writers — two simultaneous addTimes converge instead of
   double-flagging), recomputes the min row from scratch (idempotent, not
   incremental), sets `is_personal_best` true on it / false on the rest,
   and upserts/deletes the `personal_bests` row (carrying meet_name/date →
   achieved_at provenance). Why a trigger and not client logic or an RPC:
   it is impossible to bypass — Coach addTime/deleteTime, the SDIF/HY3
   import, the CUTOVER BACKFILL inserts, and any future BSPC admin entry
   all get identical PR math for free, and deleteTime's promote-on-delete
   happens atomically with the delete (no transient "no PR" window — the
   exact guarantee the Firestore code hand-builds with batches). pgTAP
   proves the math directly (insert faster → flag flips + PB updates;
   insert slower → nothing; delete the PR → next-fastest promoted, PB
   row follows; last row deleted → PB row deleted).
   Alternatives: (a) a SECURITY DEFINER RPC pair
   (`swim_results_record_time` / `swim_results_delete_time`) — same
   atomicity, but every writer must remember to use it (the backfill and
   future writers can silently bypass); (c) keep client-side multi-write
   logic — racey, unprovable, three copies. **Recommend (b).**
6. **RLS + pgTAP 008 (both tables currently have ZERO proofs):** keep the
   live family-arm `select_own` + admin policies, but ⚠ WIDEN both
   `select_own` policies to `family-arm OR is_my_swimmer(swimmer_id)` —
   the same transitional dual-arm pattern as the attendance view (RC-1):
   guardianship-linked parents (they exist as soon as invites/redemption
   land) would otherwise see NOTHING until convergence. Approved-account
   requirement on the family arm matches 00004's hole-closing precedent.
   pgTAP 008 (~20 tests): shape/unit/key (columns_are ×2, UNIQUE incl.
   course, audit spot-check vs seed), trigger PR math (4–5), family
   parent sees own swimmer's results+PBs / not others' (4), pending
   parent 0 (1), guardianship-arm read (1), family INSERT/UPDATE throws
   (2), staff all (1), anon nothing (1).
7. **[D-D6] goals + group_notes CATCH-UP DDL (RD-1).** Land canonical
   `goals` and `group_notes` (+ note_tag domain as TEXT CHECK or array
   CHECK per house style, RLS: staff-only per canonical [SCOPE], goals
   family-readable-own per canonical) in Phase D — as `00005`'s final
   section or a sibling `00006` in the same session — with pgTAP shape +
   wall tests (~6). Rationale: the code shipped phases ago; only the DDL
   is missing; goals carries `target_time_hundredths`/`current_time_hundredths`
   so it belongs with the unit cut. The swapped services' column usage
   (`GOAL_SELECT`, `GROUP_NOTE_SELECT`) is the compatibility contract —
   the catch-up DDL must satisfy those selects exactly.

## 4. Who sees a child's times (the wall, spelled out)

Times are parent-visible sports data — the wall here is OWNERSHIP, not
staff-only secrecy:

| Principal | swim_results | personal_bests | goals (catch-up) | group_notes (catch-up) |
|---|---|---|---|---|
| Staff (approved) | read+write all | read+write all (via trigger) | read+write all | read+write all |
| Approved guardian/family parent OF swimmer | read own swimmers' rows | read own | read own (canonical [SCOPE]) | **nothing** (staff-only) |
| Pending parent | nothing | nothing | nothing | nothing |
| Other families | nothing | nothing | nothing | nothing |
| Cloud Functions (service role) | bypasses RLS — linked-swimmer gate + sanitizer (Phase A pattern) | — | (portal goals strings already live) | — |
| anon | nothing | nothing | nothing | nothing |

`created_by` on swim_results is parent-visible via `select("*")` — same
accepted P2-1/P2-2 class as swimmers.created_by (Phase B FYI); resolved by
the parent-facing-views work, not Phase D.

## 5. Code swaps (frozen interfaces; one commit each)

**5a. BSPC progress + legacy + standards — THE UNIT FLIP (lands immediately
after 00005, same session, RD-2).** Types: `time_ms` → `time_hundredths`
on SwimResult/PersonalBest/TeamRecord/TimeStandard (+ new nullable result
columns for honesty). Transforms: `formatTimeFromMs(ms)` →
`formatTimeFromHundredths(h)` (÷100 not ÷1000) and
`formatTimeImprovement` likewise; fixtures' values ÷10 with displays
UNCHANGED (the proof the flip is right: `65230ms → "1:05.23"` becomes
`6523 → "1:05.23"`). `fetchSwimmerResults` gains
`.order("date", { ascending: false, nullsFirst: false })` +
`.order("created_at", { ascending: false })` tiebreak (P0-5). No screen
logic changes.

**5b. Coach `times.ts` → supabase.**
- `subscribeTimes(swimmerId, cb, max=50)` → `from('swim_results')`
  `.select(TIME_SELECT).eq('swimmer_id', …).order('created_at', desc)`
  `.limit(max)`; realtime parity per playbook (immediate fire, full
  re-emit, sync teardown, post-teardown guard) on `swim_results` changes.
  Emit maps rows → SwimTime: `time` := time_hundredths (SAME number the
  app already holds — no UI change), `timeDisplay` DERIVED on read via the
  existing `formatTimeDisplay(time)` (canonical has no denorm column),
  `isPR` := is_personal_best, `meetDate` := date, `splits` passthrough,
  `createdBy` := created_by.
- `addTime` → single plain INSERT (event, course, time_hundredths,
  meet_name, date := null, source 'manual', created_by coach.uid); the
  D-D5 trigger does ALL PR math — the un-PR loop and the `existingTimes`
  param's PR role disappear (param stays in the frozen signature,
  documented as unused-for-PR).
- `deleteTime` → single DELETE by id; the trigger promotes/cleans up. The
  read-then-batch dance disappears.
- Tests: the un-PR/promote assertions become "writes exactly one
  insert/delete and trusts the DB" payload pins + the pgTAP 008 trigger
  proofs carry the actual math (where it's provable for real — RC-7).
**5c. Coach `analytics.ts` → supabase one-shots.** Swimmer enumeration via
`swimmers` select; per-swimmer times via `swim_results` ordered
`created_at` asc (chronology-of-entry semantics preserved); **the
attendance read applies D-C5** — `or('status.is.null,status.neq.absent')`
— or BSPC-marked absences COUNT AS ATTENDANCE and inflate
`attendancePercent` (RD-4, the client-side twin of the banked J note);
distinct-date denominator preserved. Formatting helpers unchanged (already
hundredths).
**5d. Coach `meetResultsImport.ts` (times half).** Matched results →
chunked `swim_results` INSERTs (400s, per-swimmer error capture semantics
preserved); the per-batch un-PR logic DELETED (trigger owns it); `isPR`
in the ImportResult counted from `created`/post-insert reads — simplest:
re-select `is_personal_best` for the inserted ids per swimmer (one query)
to keep the `result.prs` count honest. `meets/{id}/entries` sync +
`import_jobs` calls stay Firestore (split per §2). `matchSwimmersToRoster`
pure logic untouched.
**5e. Functions `parentPortal` times payload.** `from('swim_results')
.select('id, event_name, course, time_hundredths, is_personal_best,
meet_name, date').eq('swimmer_id', …).order('created_at', desc).limit(50)`
via service role; sanitizer keeps the FROZEN output shape — `event` :=
event_name, `time` := time_hundredths, `timeDisplay` := derived
`formatTimeDisplay` (functions-side copy of the formatter — small, pure),
`isPR` := is_personal_best, `meetName`/`meetDate` := meet_name/date.
Fixture rows gain a staff-ish extra column to keep proving the sanitizer
drops unknowns. attendance payload precedent applies verbatim.

**No backfill scaffolding dir for D:** the Coach times export → insert
rows mapping is a straight per-doc transform (swimmer map + identity map +
÷nothing — Coach is already hundredths) with NO dedup question (Firestore
times have no uniqueness rule to merge; duplicates are legitimate repeat
swims). It rides in `migration/roster/`-style runner work at cutover; the
D-D5 trigger maintains flags/PBs during insert automatically. The plan
adds only a tiny `migration/times/README.md` stating run order + the
unit rule (Coach `time` inserts UNCHANGED; never ÷10 twice — RD-5).

## 6. Commit sequence, rollback, stop points

1. UNIFY: NOTES ratifications (this plan's decisions).
2. BSPC `00005` (+ goals/group_notes catch-up §3.7) + pgTAP `008` —
   74→~100, all files green; `supabase migration up --local` before pgTAP.
3. BSPC app unit flip (5a) — jest 831→up; **2 and 3 are an atomic pair:
   never end the session between them** (RD-2).
4. Coach `times.ts` (5b) + tests.
5. Coach `analytics.ts` (5c) + tests.
6. Coach `meetResultsImport.ts` (5d) + tests.
7. Functions `parentPortal` times payload (5e) + tests.
8. `migration/times/README.md` + UNIFY NOTES landed log + green bar.

Every commit `git revert`-able; no force-push/rebase/amend. **STOP
triggers:** the ÷10 audit DO-block fires (data not clean ms→hundredths);
any pgTAP 001–007 regression; any COPPA assertion weakening; the goals/
group_notes catch-up DDL failing to satisfy the swapped services' SELECTs;
PB course backfill finding >0 ambiguous multi-course matches (report and
stop rather than guess); anything erroring twice.

## 7. Deliberately welded to later phases (NOT Phase D)

- `onTimesWritten` + `dashboardAggregations` + `prsByEvent`/activity
  recompute → **J** (extends ratified D-C1(b); J's PG recompute replaces
  the mechanism).
- `meets/{id}/entries` finalTime sync + meets metadata + `import_jobs` →
  **H** / their own phases.
- TEXT CHECK → enum conversions, `select_own` family-arm drops,
  `created_by` semantics flip → **OD-1 convergence** (checklist).
- Parent-facing column-narrowing views (P2-1/P2-2 incl. created_by) →
  the parent-views work.
- Running the times backfill → cutover staging (HARD STOP rules).

## 8. RED-TEAM — findings register (all folded in above)

| # | Attack | Disposition |
|---|---|---|
| RD-1 | **Ghost tables:** pre-A swapped `goals.ts`/`groupNotes.ts` + Phase B `goals(event_name)` embeds + parentPortal detail all query tables NO migration creates (verified absent on the running DB). Jest mocks → green forever; first real run → 404s | Catch-up DDL + RLS + pgTAP land in Phase D (§3.7, D-D6); the swapped services' SELECT strings are the compatibility contract |
| RD-2 | **Unit-flip exposure window:** after 00005 renames/divides, the BSPC app still reads `time_ms` ms — `select("*")` returns no such column; jest (mocked) stays green while every time renders broken | Schema commit + app flip are an atomic same-session pair (§6 steps 2–3); fixtures prove value÷10 ⇒ display unchanged |
| RD-3 | **Silent precision loss:** a stray `time_ms` not divisible by 10 truncates sub-hundredth data in the ÷10 | Hard audit gate INSIDE the migration: DO block raises and aborts on any `% 10 <> 0` row (the 04-ratified audit, made unskippable) |
| RD-4 | **Analytics inflates attendance:** the merged table contains BSPC `'absent'` rows; `getAttendanceCorrelation` counts rows per swimmer — absences would count as practices (client-side twin of the banked J recompute bug) | 5c applies the D-C5 filter (`status.is.null,status.neq.absent`) to the analytics attendance read; jest payload pin |
| RD-5 | **Double conversion at backfill:** Coach `time` is ALREADY hundredths; a runner that "knows" about ÷10 could divide Coach values too | `migration/times/README.md` states the rule (BSPC live rows were converted by 00005; Coach docs insert verbatim); no ÷10 code exists outside 00005 |
| RD-6 | **Nullable date breaks ordering/grouping:** P0-5 makes `date` nullable; BSPC orders by `date` and groups by month — NULLs float to top / `new Date(null)` poisons | Explicit NULLS-LAST + created_at tiebreak in 5a; transforms guard null date (group undated under created_at month — they're Coach-manual rows that predate meets) |
| RD-7 | **Concurrent PR races:** two simultaneous inserts same (swimmer,event,course) could both flag PR (each snapshot blind to the other) | D-D5 trigger takes a per-key advisory xact lock before recomputing — writers serialize; recompute-from-rows is idempotent |
| RD-8 | **PB table staleness** (the model gap): with no designed owner, canonical's personal_bests diverges from reality the first Coach write | D-D5: ONE owner (the trigger), impossible to bypass — covers app writes, imports, AND the cutover backfill |
| RD-9 | **Import PR-count lies:** with the un-PR loop deleted, `result.prs` computed client-side from stale `existingTimes` could miscount vs the trigger's truth | 5d recounts from post-insert `is_personal_best` reads; jest pins the recount query |
| RD-10 | **Guardianship-parent blackout** (RC-1's sibling): live `select_own` is family-arm only; invite-redeemed guardians would see no times until convergence | §3.6 widens both `select_own` policies to the dual-arm transitional pattern; pgTAP proves both arms + pending=0 |
| RD-11 | **PB course backfill guesses wrong** on multi-course seed data | D-D4: derive from uniquely-matching swim_results; default 'SCY' only when underivable, every defaulted row RAISE NOTICEd; >0 ambiguous matches = STOP |
| RD-12 | **timeDisplay drift:** deriving on read in two places (client + functions) can diverge from stored history | Both use the same algorithm (`formatTimeDisplay` client; a pure functions-side copy with identical fixtures); pgTAP-irrelevant (no stored column to drift) |
| RD-13 | **deleteTime semantics change:** Firestore version silently no-ops on missing doc | PG DELETE of a missing id affects 0 rows — same observable no-op; jest pins "no throw on missing" |

## 9. For ratification (decisions D-D1..D-D6 — full statements above)

1. **D-D1** — `onTimesWritten` defers whole to J (extends D-C1(b) to the
   third aggregation trigger). **Recommend yes.**
2. **D-D2** — unit conversion is strict ÷10 behind the in-migration audit
   abort (no rounding path). **Recommend yes.**
3. **D-D3** — the unit cut converts ALL FOUR `time_ms` tables (+ seed) in
   one migration: swim_results, personal_bests, team_records,
   time_standards. Alternative: only D's two, leaving legacy/standards in
   ms indefinitely. **Recommend all four.**
4. **D-D4** — PB course backfill: derive from uniquely-matching results,
   else 'SCY' default with per-row report; ambiguity stops. **Recommend.**
5. **D-D5** — PR maintenance owner: **(b) the `maintain_personal_bests()`
   trigger** (advisory-locked, recompute-from-rows) vs (a) RPC pair vs
   (c) client logic. **Recommend (b).** (Canonical amendment: the trigger
   joins 01 the way A3's RPC did.)
6. **D-D6** — the goals + group_notes catch-up DDL (+pgTAP) lands inside
   Phase D. Alternative: its own micro-phase first. **Recommend in D.**
7. Bundled FYIs to accept: `timeDisplay` becomes derived-on-read
   everywhere (no stored denorm); `swim_results.date` ordering goes
   NULLS-LAST with created_at tiebreak; `created_by` parent-visibility
   stays in the accepted P2-1/P2-2 bucket; analytics adopts the D-C5
   absent-exclusion as a correctness rule (RD-4).
> ⚠️ HISTORICAL — superseded by the fresh-launch model in Director Rulings 56/57; retain the time-data contracts, but do not execute migration/backfill steps.
