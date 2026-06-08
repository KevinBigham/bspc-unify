# 03 — Service Migration Playbook (Firestore → Supabase/Postgres)

Reusable pattern for migrating one Coach App service's data layer onto the
canonical schema (`UNIFY/01_CANONICAL_SCHEMA.sql` — **law**). Derived from the
first migration, `groupNotes.ts` (done 2026-05-30). Services 2–N inherit this.

## Operating rules (in force for every migration)
- **Tests are the bar.** Never advance with red tests. The full Coach client
  suite (`npm test -- --runInBand`) must stay green; baseline counts live in
  memory `bspc-unify-green-baseline`.
- **One service at a time.** Smallest blast radius.
- **Swap the data layer UNDER the existing interface only.** Exported function
  signatures + exported types do **not** move. UI/business logic untouched.
- **Schema is law.** If app code wants something the schema lacks, propose a
  schema migration — don't hack around it.
- **Commit after each green logical step**, descriptive message.
- **COMMIT VERIFICATION.** After every approved commit, run `git log --oneline -1`
  + `git status` to confirm it actually landed and the tree is clean. Never
  assume a commit happened; verify it. (Lesson: a session once stacked a new
  commit on top of two changes that were only *believed* committed — the new
  commit then referenced an untracked file.)

## The two-commit shape
- **Commit 1 — inert client (ONE TIME ONLY, already done).** Added
  `@supabase/supabase-js` + `src/config/supabase.ts` (env-driven:
  `EXPO_PUBLIC_SUPABASE_URL` / `EXPO_PUBLIC_SUPABASE_ANON_KEY`, placeholder
  fallbacks mirroring `firebase.ts` so import never throws), imported by
  nothing. Suite stayed green because nothing imported it.
  → **Services 2–N skip this. The client already exists, so each subsequent
  migration is a SINGLE commit (the service swap).**
- **Commit N — service swap.** Rewrite the one service's body to hit Supabase;
  re-point its test's mock; add lifecycle tests; full suite stays green; commit.

## Realtime parity contract (the real risk)
Firestore `onSnapshot` → Supabase `postgres_changes`. The replacement MUST honor
all four properties, or subscribers (hooks/screens) silently break:
1. **Immediate first fire.** Run the query once on subscribe and emit the full
   result before any change event (`void emit()` synchronously in the function
   body). `onSnapshot` fires immediately; so must we.
2. **Full-list re-emit on every change.** On any `postgres_changes` event,
   **re-fetch the whole ordered/limited list and emit it** — do NOT merge
   deltas. `onSnapshot` hands the callback the entire snapshot each time;
   matching that keeps the callback contract identical.
3. **Synchronous teardown.** `subscribeX(...)` must return a `() => void`
   **synchronously** (callers use it directly as a React `useEffect` cleanup).
   Build the channel synchronously and return a closure; never return a Promise.
   The returned fn calls `supabase.removeChannel(channel)`.
4. **active-guard against post-teardown races.** Supabase has a race
   `onSnapshot` doesn't: an in-flight `emit()` can resolve *after* teardown.
   Guard with a captured `let active = true;` set to `false` in the teardown fn;
   `emit()` bails (`if (!active ...) return;`) so no callback fires post-unsub.
- Channel names must be unique per subscription (collisions drop events): use a
  module-level `let channelSeq = 0;` suffix, e.g. `group_notes:${group ?? 'all'}:${channelSeq++}`.
- The `Unsubscribe` type: drop the `firebase/firestore` import and define a
  local `type Unsubscribe = () => void`. Structurally identical to Firebase's —
  **this is not a signature change** (flag it to the reviewer anyway).

## "Derive normalized-out fields on read, keep the param for compat"
The canonical schema normalizes fields Firestore denormalized (e.g. `coachName`
was stored on each `group_notes` doc; the table has no such column — it lives on
`profiles.full_name`).
- **Read:** resolve via an embedded join in the select
  (`coach:profiles(full_name)`) and populate the field in the row→domain mapper
  (`coachName: row.coach?.full_name ?? ''`).
- **Write:** **keep the now-unused param in the signature** (interface frozen)
  but do not persist it; mark intent with `void param;` + a one-line comment.
- Confirm the backing column name against the schema before writing the select
  (it was `full_name`, not `display_name` — verify, don't assume).

## Field/type mapping notes
- snake_case columns ↔ camelCase domain fields, mapped explicitly in a
  `rowToX(row): XWithId` helper (single source of truth for the shape).
- Enums: check label parity against the schema. Coach `Group`/`NoteTag` are
  exact 1:1 subsets of `practice_group`/`note_tag` → pass strings through, no
  mapping code. Verify per service; add a map only if labels differ.
- `FirebaseTimestamp` is `= Date` in this codebase, so Postgres ISO strings map
  via `new Date(row.created_at)` — type-identical, no signature move. (Watch for
  any consumer calling Firestore `Timestamp` methods like `.toDate()`; grep
  before swapping. groupNotes had none.)
- `serverTimestamp()` on insert → omit the column; rely on the DB
  `DEFAULT NOW()`.
- **`created_at`/`updated_at` are DB-owned** via `DEFAULT NOW()` + a
  `BEFORE UPDATE … update_updated_at()` trigger on every timestamped table (16 of
  them — verified schema-wide). The client sends **NEITHER** on insert or update.
  A test asserting the client sends them is testing the OLD (Firestore
  `serverTimestamp()`) reality — **invert it** to assert the payload omits them.
  By contrast, **domain timestamps** like `achieved_at` have NO trigger and ARE
  client-set (e.g. `markGoalAchieved` writes `achieved_at: new Date().toISOString()`).
- Insert returns id via `.insert({...}).select('id').single()` → `data.id`.
- Always check `{ error }` and `throw error` on writes (no extra handling beyond
  that).

## Test rule: add lifecycle tests, never drop the bar
- Re-point the test's mock from `firebase/firestore` + `config/firebase` to
  `config/supabase`. **Preserve every original behavioral assertion** (query
  scope, row mapping, insert payload, delete target) — re-expressed against the
  Supabase mock.
- **ADD** lifecycle tests proving the realtime contract, by name:
  initial-emit, re-emit-on-change, synchronous-teardown-removes-channel,
  no-emit-after-unsubscribe. Test count should go **up**, never down.
- Mock the Supabase builder as a chainable thenable (resolves to
  `{ data, error }`) so `await query` works; capture the `postgres_changes`
  handler so tests can fire a synthetic change; expose the channel object so
  tests can assert `removeChannel(channel)`.
- Run the single file `--verbose` for the lifecycle proof, THEN the full suite
  for the green bar. Show the reviewer both, plus the diff. Stop for approval
  before committing.

## Pre-swap checklist (do this before touching a service)
1. **Who else touches the collection?** grep `functions/` and the Next.js
   `parent-portal/` for the collection name. If the Cloud Functions or
   parent-portal read/write it, migrating the client alone **split-brains** the
   data (writes to PG, reads from Firestore). Prefer collections touched ONLY by
   the Coach client for early migrations; otherwise the consumer must move in
   the same step.
2. **Intra-service dependents?** grep `src/` for imports of the service. A
   dependent that only consumes the frozen interface (and mocks the service in
   its tests) is safe; one that reads the raw collection is not.
2a. **Is the DATA LAYER actually tested?** A service's test file mocking
   `firebase/firestore` does NOT mean its CRUD is covered — the mock is often
   just import-safety so pure helpers can be tested. VERIFY the test file
   *invokes* the subscribe/CRUD functions by name. Counter-example:
   `seasonPlanning.test.ts` has 19 tests and mocks firestore, but every test is
   a pure helper (yardage/taper/phase math); `subscribeSeasonPlans`/`create`/
   `delete`/`upsert` are never called → its data layer is UNGUARDED, so it is a
   BAD migration pick despite the green count. No guardrail = don't migrate it
   until tests exist.
3. **Does it depend on un-migrated data?** Services that read other collections
   (search, analytics) should wait until those are migrated.
4. **Canonical table exists + shape matches?** Confirm the table, columns, RLS,
   and any normalized-out fields in `01_CANONICAL_SCHEMA.sql` before coding.
5. **Backfill FOLLOWUPs that touch it?** Cross-reference `UNIFY/NOTES.md`
   (identity remap Firebase-UID→profiles.id is near-universal for `*_id`/actor
   columns; note any service-specific ones).

## Done so far
- ✅ `groupNotes.ts` — `group_notes`. Commit 1 (inert client) + commit 2 (swap).
  962 → 965 tests (added 3 lifecycle tests). Pattern proven.
