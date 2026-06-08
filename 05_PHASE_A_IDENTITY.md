# 05 — Phase A: Identity (profiles · auth map · guardianships)

**PLAN ONLY.** No app code, no app commits yet. This document is for review.
Canonical schema (`01_CANONICAL_SCHEMA.sql`) stays law; where the live code wants
something it lacks, a schema migration is **proposed here**, not hacked around.

Settled going in (Kevin, this session):
- **Cluster-by-cluster** migration (not big-bang).
- **One shared accounts system** — Coach identities merge INTO the existing BSPC
  Supabase `profiles` table, not a parallel one.

---

## 0. Plan-reframing discoveries (read first — these change Phase A's shape)

Two facts from reading the actual code, not just the planning docs:

### 0.1 The live BSPC DB is **not** on the canonical schema yet
`BSPC/ACTIVE/supabase/migrations/00001_initial_schema.sql` is the *pre-D-A* model:
- ✅ `profiles` columns, `user_role` (`family`/`coach_admin`/`super_admin`), and
  `account_status` (`pending`/`approved`/`deactivated`) **already match canonical.**
- ❌ **No `guardianships` table.** Access is `profiles.family_id → families.id ←
  swimmers.family_id` (1 parent → 1 family → N swimmers). `approveFamily()`
  creates a family and stamps `swimmers.family_id`; `fetchFamilySwimmers()`
  filters by `family_id`.
- ❌ **No SECURITY DEFINER RLS helpers** (`is_staff`, `is_my_swimmer`,
  `is_active_account`, …) — BSPC RLS is inline SQL.
- ❌ **No `enforce_profile_self_update` escalation guard** (P0-1).
- ❌ **No `coach_groups` table.**

So Phase A is not merely "fold Coach into profiles." It must also **bring the
existing, green BSPC app forward to the guardianships access model** — the canonical
schema removes `swimmers.family_id`, but the BSPC app's whole family-access path
(and its pgTAP RLS tests) currently depends on it. This is the central tension of
Phase A and the source of the biggest open decision (§7, OD-1).

### 0.2 The two apps authenticate against **different** auth systems
- BSPC parent-app → **Supabase Auth** (`auth.users` UUIDs). `profiles.user_id →
  auth.users(id)`.
- Coach App → **Firebase Auth** (string UIDs). `coaches/{firebaseUid}`,
  `parents/{firebaseUid}`.

The canonical schema has **no Firebase-UID column and no auth-map table** — the
"Firebase-UID → profiles.id remap" exists only as a *backfill* artifact. So Phase A
contains a genuine **runtime auth cutover** (Coach App login: Firebase → Supabase),
which is a different animal from the pure data-layer swaps of `groupNotes`/`goals`.
It is the single riskiest sub-step (§6).

> **Why this is still tractable (code-first, cutover-last).** Per `04`, mocked
> client/function tests pass independent of which backend the *other* side talks to,
> and "split-brain" is a runtime/cutover property. Both suites mock their backend,
> so we can migrate the identity-resolution **code** (and re-point mocks) keeping
> all three suites green, and defer the real auth/data cutover to one coordinated
> step. The auth cutover is *planned* in Phase A but *executed* at cutover.

---

## 1. Scope — what migrates in Phase A vs. what's deferred

### In scope (Phase A)
| Item | What it means |
|---|---|
| **`profiles` as the single identity table** | Coach `coaches` docs + `parents` docs fold into BSPC `profiles`. Profiles table shape is unchanged (already canonical). |
| **`guardianships`** | New table added to the **live BSPC** schema (it already exists in canonical). Becomes the access primitive replacing `linkedSwimmerIds[]` (Coach) and, transitionally, `swimmers.family_id` (BSPC). |
| **`coach_groups`** | New table; replaces Coach `coaches.groups[]`. |
| **RLS helper functions + escalation guard** | `is_staff`, `is_super_admin`, `is_active_account`, `is_my_swimmer`, `auth_profile_id`, `my_family_ids`, `my_swimmer_groups`, `enforce_profile_self_update` added to live BSPC. |
| **Firebase-UID → profiles.id remap (backfill scaffolding)** | A **transient** migration-only map table + backfill scripts (NOT canonical law; lives in a `migration_*` namespace). Used to remap document ids/actor refs and to provision Supabase Auth accounts. |
| **Coach App identity-resolution CODE** | `AuthContext` (coach role/groups/name/email read), `parent-portal/src/lib/auth.ts` (parent profile read), and the **identity gate** of functions `parentPortal` + `dailyDigest` (who-is-this-caller / enumerate-coaches), re-pointed to Supabase. |
| **redeemInvite guardianship-write semantics** | The *definition* of "redemption creates a guardianship" (D-A). The SECURITY DEFINER redeem RPC is designed here; see deferral note. |

### Explicitly deferred (NOT Phase A)
| Deferred item | Phase |
|---|---|
| `coaches.notificationPrefs` → `notification_preferences` table | **G** (notifications) |
| `coaches.fcmTokens[]` → `push_tokens` (FCM→Expo, decision #7) | **G** |
| `parentPortal` **data** reads (attendance / times / swimmers payloads) | **C / D / B** (only the identity gate moves in A) |
| `parent_invites` collection CRUD (`parentInvites.ts`) + full `redeemInvite` body | **I** (parent_invites + portal cutover) |
| `swimmers` roster reconciliation (Coach↔BSPC dedupe) | **B** |
| `dailyDigest` notification *production* (it's a notifications producer) | **G** (only its coach-enumeration source is readied in A) |
| Dropping `swimmers.family_id` from BSPC | After A — **OD-1** decides timing |

---

## 2. Identity reconciliation — Coach models → canonical `profiles` + `guardianships`

### 2.1 Coaches → profiles
| Coach `coaches` field | Canonical target | Clean? |
|---|---|---|
| `uid` (Firebase) | `profiles.user_id` (Supabase `auth.users.id`) via remap | ⚠️ different auth system (§6) |
| `email` | `profiles.email` | ✅ |
| `displayName` | `profiles.full_name` (NOT NULL) | ✅ (coaches have a real displayName) |
| `role: 'admin'` | `profiles.role = 'super_admin'` (NOTES #3) | ⚠️ see NM-1 |
| `role: 'coach'` | `profiles.role = 'coach_admin'` (NOTES #3) | ⚠️ naming only (NM-2) |
| *(no field)* | `profiles.account_status = 'approved'` | ⚠️ Coach has no status (NM-3) |
| `groups[]` | `coach_groups(profile_id, practice_group)` rows | ✅ (enum 1:1 subset) |
| `notificationPrefs{}` | `notification_preferences` | ⏭ deferred to G |
| `fcmTokens[]` | `push_tokens` | ⏭ deferred to G |

### 2.2 Parents → profiles + guardianships
| Coach `parents` field | Canonical target | Clean? |
|---|---|---|
| `uid` (Firebase) | `profiles.user_id` via remap | ⚠️ §6 |
| `email` | `profiles.email` | ✅ |
| `displayName` (= `email.split('@')[0]`) | `profiles.full_name` (NOT NULL) | ⚠️ NM-4 (it's a hack value) |
| *(no field)* | `profiles.role = 'family'` | ✅ |
| *(no field)* | `profiles.account_status = 'approved'` | ⚠️ NM-3 (Coach parents have no pending state) |
| `linkedSwimmerIds[]` | one `guardianships(guardian_profile_id, swimmer_id)` row each | ✅ (N:M native; `is_primary` default false, `relationship` null) |

### 2.3 BSPC (existing) parents → guardianships
Today: `profiles.family_id → swimmers.family_id`. Backfill creates one
`guardianships(profile, swimmer)` row for each swimmer in the parent's family. The
`families` rows survive as the household grouping (`profiles.family_id`), exactly
as canonical intends.

### 2.4 Where roles/fields do **NOT** map cleanly (call-outs)
- **NM-1 — `admin → super_admin` mints many super-admins.** Every Coach-App "admin"
  (likely every head coach) becomes `super_admin`, which in canonical can write
  `swimmer_medical` and (via `enforce_profile_self_update`) change other users'
  roles. Confirm this blast radius is intended, or whether only one person should be
  `super_admin` and the rest `coach_admin`. (NOTES #3 settled the mapping; flagging
  the privilege consequence.)
- **NM-2 — naming inversion.** A plain Coach "coach" becomes `coach_admin`.
  Semantically fine (both are staff), but the label is counter-intuitive; noting so
  nobody reads it as a bug later.
- **NM-3 — no `account_status` in the Coach world.** Coaches and invite-redeemed
  parents have no status concept; we backfill them as `approved`. But BSPC's entire
  `pending → approved` admin-approval gate (and "pending parents see only
  announcements/schedule") has **no Coach-side equivalent**. Decision needed on
  which provisioning path governs *new* accounts post-merge (OD-3).
- **NM-4 — parent `full_name` is a placeholder.** Coach parents store
  `displayName = email.split('@')[0]`. `profiles.full_name` is NOT NULL; backfill
  must carry this placeholder forward (or prompt for a real name later). Not a
  blocker, but it's dirty data entering the canonical table.
- **NM-5 — auto-admin-on-first-login disappears.** Coach `AuthContext` currently
  *auto-creates a coach with `role:'admin'`* the first time an unknown user logs in.
  Canonical `handle_new_user()` creates `family`/`pending`. After merge, a brand-new
  Supabase Auth user is **never** auto-admin; new coaches must be provisioned by a
  `super_admin`. This is a **behavior change that is also a security fix** (the old
  behavior is a privilege-escalation footgun). Confirm acceptable, and confirm the
  new coach-provisioning path (admin UI or backfill-only).
- **NM-6 — linkedSwimmerIds had no integrity; guardianships do.** Firestore arrays
  can hold stale/dangling swimmer ids; `guardianships.swimmer_id` is a FK with
  `ON DELETE CASCADE`. Backfill must drop/repair dangling links (and resolve them
  against the **B**-phase roster reconciliation so a Coach swimmer id maps to the
  right canonical `swimmers.id`). A wrong resolution here is a COPPA mis-link.

---

## 3. The Firebase-UID → profiles.id remap (how code keeps working as the key changes)

**The key changes underneath; the interfaces don't.** Three layers, kept stable:

1. **Auth session layer.** `AuthContext`'s exported shape (`{user, coach, isAdmin,
   signIn, signOut}`) is frozen. Internally it stops using `firebase/auth` +
   `coaches/{uid}` and instead uses `supabase.auth` + a `profiles` read, then
   **maps the `profiles` row (+ `coach_groups`) back into the existing `Coach`
   type** (`role: 'super_admin'→'admin'`, `'coach_admin'→'coach'` on the way out so
   `isAdmin` and every consumer keep working). Same trick as the playbook's "derive
   normalized-out fields on read, keep the param for compat."

2. **The remap table (backfill scaffolding, NOT canonical law).** A transient
   table — proposed name `migration_identity_map` — populated during backfill:
   ```
   migration_identity_map(
     firebase_uid TEXT PRIMARY KEY,   -- old Coach/parent doc id
     user_id      UUID,               -- new Supabase auth.users.id (provisioned)
     profile_id   UUID,               -- resulting profiles.id
     source       TEXT                -- 'coach' | 'parent' | 'bspc'
   )
   ```
   This is the single source of truth the backfill uses to (a) provision a Supabase
   Auth user per Firebase user, (b) create the `profiles` row, and (c) **rewrite
   every `firebaseUid` reference** embedded in documents/arrays/JSONB across all
   later phases (`created_by`, `marked_by`, `coach_id`, `practice_plan` authorship,
   `ratings` keys, `meets.events`, etc.). It lives outside canonical because it's
   migration-only and gets dropped after cutover. **Proposed, flagged — not added to
   `01`.**

3. **Function identity resolution.** `parentPortal`/`dailyDigest`/`redeemInvite`
   currently key off `request.auth.uid` (Firebase). Post-cutover they key off the
   Supabase JWT `sub` (= `auth.users.id`) and resolve `auth_profile_id()`. The
   functions' *return shapes* are unchanged; only the lookup changes. During the
   code-first window their tests mock the resolver, so they're green regardless of
   which backend is live.

**Why existing code survives:** every consumer talks to a frozen interface
(`Coach`, `ParentProfile`, the callables' DTOs). We change the *resolver* and the
*storage*, not the contract. The remap table absorbs the id-type change (string
Firebase UID → UUID) so no consumer ever sees a Firebase UID after cutover.

---

## 4. Test-green strategy (Coach 968 · BSPC 774 · functions 106)

**Governing fact:** the jest suites **mock their backend**. So *schema migrations
and backfill scripts do not touch the jest suites at all* — only app-CODE changes
move those numbers. This lets us land the foundational schema first with zero risk
to the 774/968/106, then migrate code incrementally.

| Suite | What changes in A | How it stays green | New tests added |
|---|---|---|---|
| **BSPC 774** (jest, `TZ=UTC`) | Nothing in the additive-schema commit (mocked). If OD-1 = transitional, BSPC app code is largely untouched in A. | Mocks isolate it from schema; unchanged app code = unchanged tests. | none required for schema commit |
| **BSPC pgTAP RLS** (`npm run test:rls`, local Supabase) | New `guardianships` table, helpers, escalation guard exercised against real schema. | **Add** pgTAP tests for guardianships access + helper functions + P0-1 guard; existing `001-family-access`/`002-admin-controls` stay green (transitional keeps `family_id` path intact). | guardianship-access, escalation-guard, helper-fn tests |
| **Coach 968** (jest) | `AuthContext` + `parent-portal/auth.ts` re-pointed to Supabase. | Re-point the 1 AuthContext test's mocks (`firebase/auth`+firestore → `config/supabase`); preserve its signOut-cleanup assertion; map profile→Coach so `isAdmin` etc. unchanged. | **Add:** profile→Coach mapping, role-map (super_admin→admin), groups→coach_groups read, parent profile resolution via guardianships. Count goes **up**. |
| **functions 106** (jest) | Identity gate of `parentPortal` (caller→profile, linked swimmers via guardianships) and `dailyDigest` (enumerate coaches from profiles). | Add a Supabase service-role mock alongside the firebase-admin mock; preserve every behavioral assertion (unauth rejection, permission-denied for unlinked swimmer, sanitization). | **Add:** identity-resolution-via-profiles tests for each migrated function. Count goes **up**. |

Bar rule (unchanged): test count never drops; run the single changed file
`--verbose` for the proof, then the full suite for the green bar; show diff + both
runs; stop for approval before each commit.

---

## 5. Commit-by-commit sequence (smallest blast radius first)

Each is a single logical, green, reviewed step. Cutover is the last, separate step
and is **not** a code commit.

0. **(BSPC) Additive schema migration — the foundation, zero app-code change.**
   New forward migration adding `guardianships`, `coach_groups`, the SECURITY
   DEFINER helpers, and the `enforce_profile_self_update` trigger. **`swimmers.
   family_id` is kept** (transitional — pending OD-1). Add pgTAP tests for the new
   objects. jest suites untouched (968/774/106); `test:rls` proves the new SQL.
   *This is the first, smallest, green commit* — the analog of the "inert client"
   commit: it adds capability without changing any running behavior.

1. **(BSPC) Backfill scaffolding (not executed).** Add `migration_identity_map`
   DDL + backfill script skeletons (UID provisioning, profiles/coach_groups/
   guardianships builders, dangling-link repair) under a `migration/` dir, with
   **unit tests on the pure mapping logic** (role map, linkedSwimmerIds→guardianship
   rows, family_id→guardianship rows). Nothing runs against a DB. Suites green.

2. **(Coach) AuthContext identity read → Supabase.** Swap coach identity resolution
   (role/groups/name/email) from `coaches/{uid}` Firestore to `profiles` +
   `coach_groups`; map row→`Coach`; freeze the exported interface; re-point the test
   mock; add mapping/role tests. Coach suite green & up. *(fcmTokens/notificationPrefs
   stay on Firestore — deferred to G; flagged coupling below.)*

3. **(Coach) parent-portal `auth.ts` parent read → Supabase.** `getParentProfile`
   resolves `profiles` + derives `linkedSwimmerIds` from `guardianships`; frozen
   `ParentProfile` shape; tests.

4. **(functions) `parentPortal` identity gate → Supabase.** Caller→profile,
   linked-swimmer authorization via guardianships; **data payloads unchanged**
   (still Firestore until B/C/D). Preserve sanitization + permission-denied tests;
   add resolution tests.

5. **(functions) `dailyDigest` coach-enumeration source → profiles.** Read the coach
   roster from `profiles` (role ∈ staff); **notificationPrefs check stays Firestore**
   until G (or defer the whole function to G — see OD-4). Tests preserved.

6. **(design, lands code in I) redeemInvite SECURITY DEFINER redeem RPC.** Specify
   and unit-test the RPC that, on valid invite, creates a `guardianships` row
   (never a client-side insert — D-A). Full `redeemInvite` body + `parent_invites`
   CRUD migrate in **Phase I**; see OD-2 for the A↔I gap.

— **CUTOVER (separate, after schema applied + backfill staged; not a commit):**
apply BSPC migration to the real DB; disable `on_auth_user_created`; provision
Supabase Auth accounts for every Firebase user; build `migration_identity_map`;
create profiles + coach_groups + guardianships; switch the Coach App auth provider
to Supabase; re-enable the trigger; verify both apps. (See §6.)

---

## 6. SINGLE riskiest sub-step — the **auth-credential / account cutover** (review hardest)

Not a data swap — this is moving every human's *login* from Firebase Auth to
Supabase Auth, and it's where the worst failure modes live:

1. **Passwords don't transfer.** Firebase stores scrypt hashes; Supabase uses
   bcrypt. We cannot silently re-home credentials. Either (a) export Firebase scrypt
   hashes and import via a custom-hash path Supabase can verify, or (b) force a
   password reset for all users at cutover. (a) is fiddly and may not be supported;
   (b) is a coordinated user-facing event. **This needs a decision and a tested
   dry-run before any cutover.**
2. **One-to-one identity integrity is COPPA-critical.** Each Firebase user must map
   to exactly one Supabase user → exactly one `profiles` row, and each parent's
   `guardianships` must *exactly* reproduce their prior `linkedSwimmerIds`. A single
   mis-mapped row exposes the **wrong child's** attendance/times/notes to a parent.
   The remap table is the chokepoint; it must be built deterministically and
   audited (counts in = counts out, no dangling, no duplicates) against a throwaway
   DB first.
3. **The escalation guard meets a many-super_admin world (NM-1).** Once
   `enforce_profile_self_update` is live, only `super_admin` can change roles. If the
   admin→super_admin backfill mints many super_admins, that's a wide privileged
   surface from day one. Get NM-1 settled before backfill writes roles.
4. **Provider-swap correctness in the Coach App.** `AuthContext` is the one place the
   whole app's session originates; a subtle bug (e.g. session not restored on cold
   start, or `isAdmin` mis-derived from the role map) locks staff out or over-grants.
   Its existing test coverage is **one test** — coverage must grow here specifically.

**Recommendation:** when we execute, treat the auth cutover as its own mini-plan
with its own red-team pass; build the `migration_identity_map` + provisioning +
guardianship reconstruction against a **throwaway Supabase project** and assert
in/out integrity before touching anything real; decide the password story (import vs
forced reset) up front.

---

## 7. Schema migrations proposed (don't hack around canonical)

All of these bring the **live BSPC DB** up to what canonical already specifies;
none change canonical's intent. Proposed as forward migrations in
`BSPC/ACTIVE/supabase/migrations/`:

- **SM-1 `guardianships` table** (+ `idx_guardianships_swimmer/guardian`, RLS:
  `guardianships_select_own`, `guardianships_staff_write`) — verbatim from canonical.
- **SM-2 RLS helper functions** — `auth_profile_id`, `is_staff`, `is_super_admin`,
  `is_active_account`, `is_my_swimmer`, `my_family_ids`, `my_swimmer_groups` —
  verbatim from canonical §helpers.
- **SM-3 `enforce_profile_self_update` trigger** (P0-1) — verbatim; the live BSPC DB
  lacks this escalation guard today.
- **SM-4 `coach_groups` table** — verbatim from canonical.
- **SM-5 (transitional, OD-1) keep `swimmers.family_id`** for now and add
  guardianships *alongside*; converge later by switching BSPC reads/RLS to
  guardianships, then a final migration drops `family_id`. The alternative
  (drop now, rewrite `approveFamily`/`fetchFamilySwimmers`/RLS + pgTAP in Phase A)
  is larger blast radius. **OD-1 decides.**

**Transient, NOT canonical (migration scaffolding):**
- `migration_identity_map` (§3.2) — dropped post-cutover.

**No change required to:** `profiles`, `families`, `user_role`, `account_status` —
already canonical in the live BSPC DB.

---

## 8. OPEN DECISIONS — need your call before we execute (per "ask, don't guess")

- **OD-1 — `swimmers.family_id` transition strategy** *(biggest)*. (a) **Transitional**
  (recommended): add guardianships alongside, keep `family_id`, switch BSPC
  reads/RLS to guardianships incrementally, drop `family_id` in a later cleanup —
  smallest blast radius, but the live DB temporarily diverges from canonical (which
  has `family_id` removed). (b) **Converge now**: rewrite BSPC's family access to
  guardianships and drop `family_id` within Phase A — matches canonical exactly but
  is a large change to the green parent-app's tested core during the foundation
  phase. → I recommend (a). Your call.
- **OD-2 — redeemInvite A↔I gap.** redeemInvite both validates `parent_invites`
  (a Phase-I collection) and writes the parent↔swimmer link (a Phase-A guardianship).
  Options: (a) keep redeemInvite whole in **I** and accept that, between the A and I
  cutovers, new redemptions write Firestore `linkedSwimmerIds` while reads come from
  guardianships (a split-brain window) — mitigated by sequencing A→I close together;
  (b) pull `parent_invites` forward and migrate redeemInvite whole in **A**; (c) add
  a temporary dual-write bridge in redeemInvite for the window. → I lean (a) with
  A and I run back-to-back. Your call.
- **OD-3 — new-account provisioning post-merge.** Coach world auto-approves
  (no `account_status`); BSPC gates `pending → approved`. After merge, when a brand
  new parent or coach appears, which path governs? (Coaches: provisioned by a
  super_admin? Parents: still admin-approved, or auto-approved on invite redemption
  like Coach does today?) Ties to NM-3/NM-5.
- **OD-4 — `dailyDigest` in A or G?** Migrate only its coach-enumeration source in A
  (leaving the prefs check on Firestore until G — a half-migrated function), or defer
  the whole function to G and only *ready* its identity source? → I lean defer-whole
  to G; in A we just ensure profiles can answer "who are the coaches."
- **OD-5 — confirm NM-1** (admin→super_admin minting many super_admins) and **NM-5**
  (auto-admin-on-first-login removed; what replaces coach provisioning).
- **OD-6 — password cutover** (§6.1): Firebase scrypt-hash import vs. forced reset
  for all users. Needs a decision + dry-run before cutover.

---

## 9. Backfill checklist for Phase A (separate deliverable, staged before cutover)
- Provision a Supabase Auth user per Firebase user; record in `migration_identity_map`.
- Disable `on_auth_user_created` during load (else it inserts conflicting
  family/pending profiles).
- Build `profiles` (role map per NOTES #3; coaches/redeemed-parents → `approved`),
  `coach_groups` from `coaches.groups[]`.
- Build `guardianships`: Coach `parents.linkedSwimmerIds[]` → rows; BSPC
  `family_id` → rows; **drop/repair dangling swimmer ids** and resolve against the
  Phase-B roster reconciliation (COPPA — NM-6).
- Audit integrity: in-count == out-count, no dangling FK, no duplicate
  `(guardian_profile_id, swimmer_id)`.
- Re-enable trigger; smoke-test both apps' login + swimmer visibility.

---

*Next action after your review: lock OD-1…OD-6, then (if approved) implement
commit 0 (the additive BSPC schema migration + pgTAP tests) — the smallest green
step. No code until you sign off on the sequence.*
