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

## 6. THE AUTH-CUTOVER MINI-PLAN (the single riskiest sub-step, expanded in place)

> **AMENDED IN PLACE 2026-06-11 per D-CUT1 (CUT-1 round, e71050a/D-J2
> annotation precedent).** The original §6 was a placeholder that prescribed
> "treat the auth cutover as its own mini-plan with its own red-team pass."
> This IS that mini-plan. The original four failure modes are preserved as
> the risk register (§6.7) with their now-settled answers. Every banked
> pointer reading "05 §6" resolves here.

> **HARD STOP (governs all of §6).** Nothing in this section runs without
> Kevin live and his explicit approval, in a dedicated cutover round. The
> operational sequences (§6.1 provisioning, §6.5 cutover/rollback) are
> INSTRUCTIONS-ONLY. The CODE changes (§6.2) land in their own pre-declared
> swap rounds (CUT-4+), authorized only after the director reviews this
> document's bound signatures, test events, and gap verdict.

### 6.0 Preconditions (proven, quoted from the record)

- **The app-side bank, from the K landed log at `e8fb7f7`:** "after Phase K,
  the Coach app's ENTIRE live firebase surface is EXACTLY the five-artifact
  auth bank — src/contexts/AuthContext.tsx, app/admin.tsx,
  app/(tabs)/settings.tsx, app/forgot-password.tsx, src/config/firebase.ts —
  re-proven by a fresh import grep on the final tree." All five die together
  here.
- **The portal-half precondition (FYI-B naming of record, scope entry at
  `cdfc8d6`):** four parent-portal files carry the portal's Firebase
  residue — `src/lib/firebase.ts` (client), `src/lib/auth.ts` (session half
  only; profile read is Supabase since Phase A), `src/app/dashboard/page.tsx`
  (firebase `User` type), `src/lib/parentPortal.ts` (httpsCallable
  transport). The session pieces swap here WITH the bank; the transport's
  fate is §6.6/D-CUT6.
- Phase K accepted at `e8fb7f7`; bars at the start of any swap round: BSPC
  835 (TZ=UTC) + pgTAP 335 / Coach 1080 / Functions 115.

### 6.1 Provisioning — the BINDING GATE (instructions-only, HARD STOP)

- **OD-6, settled 2026-06-09:** NO password-hash import. Both apps are
  pre-launch with zero real users; accounts are provisioned with fresh
  Supabase credentials (forced reset / invite flow); the migration never
  touches password material. The §6.7 risk-register item 1 is CLOSED by
  this ruling.
- **The staged run order is `BSPC/ACTIVE/migration/identity/README.md`
  steps 1–8** (apply map DDL; disable `on_auth_user_created`; provision per
  Firebase user with fresh credentials — the step-3 runner is "not yet
  written" and lands as scaffolding in the staging round; build profiles;
  coach_groups; guardianships with dangling-link COPPA repair; audits
  in==out; re-enable trigger; smoke), with its standing dry-run-against-a-
  throwaway-project requirement.
- **THE PROBE, verbatim from the bank — a BINDING gate, not advice:** "after
  provisioning, every Firestore parents-doc uid must resolve a NON-empty
  profile via the map; zero-resolves = STOP. The mask is removed by
  verification, not by code (data-layer freeze)."
- **The NM-1 step, verbatim:** "the live list must be pulled from the
  `coaches` collection at backfill time for Kevin to confirm; not derivable
  from code." Kevin = the sole `super_admin`; every remaining Coach "admin"
  → `coach_admin`. Roles are written only AFTER Kevin confirms the list
  (risk-register item 3 closes here).
- **The banked post-backfill invite/guardianship agreement audit** runs
  before the swap is declared live: every redeemed invite's guardianship
  exists; counts in == out; no dangling, no duplicates.

### 6.2 The swap design (all five bank artifacts die together; one logical change per commit)

**Identity pin (derived, not open):** post-swap `Coach.uid` :=
`auth.users.id` — forced by the D-C7 transitional `attendance.marked_by →
auth.users` FK. Legacy Firebase uids embedded in rows remap at convergence
(checklist item 5) via `migration_identity_map`.

**(i) `src/config/supabase.ts` — the RN session-persistence pin.** Today's
client is data-only (`createClient(url, anonKey)`). The swap configures:
AsyncStorage as the session `storage` adapter, `autoRefreshToken: true`,
`persistSession: true`, `detectSessionInUrl: false`. Cold-start session
restore is the §6.4 named risk; a session-restore pin is mandatory.

**(ii) `src/contexts/AuthContext.tsx` — the core swap.** Exported shape
FROZEN: `{user, coach, loading, error, signIn, signOut, isAdmin}`.
- Session: `supabase.auth.getSession()` + `onAuthStateChange` replace
  `onAuthStateChanged`; `signInWithPassword` replaces
  `signInWithEmailAndPassword`, behind the EXISTING error-message map
  (auth/invalid-credential et al. re-keyed to supabase error codes; the
  user-facing strings are part of the frozen surface and do not change).
- Coach resolution: `profiles` (by `user_id = session.user.id`) +
  `coach_groups` + `notification_preferences`, mapped into the frozen
  `Coach` type: `uid := user_id`; `email`; `displayName := full_name`;
  `role`: `super_admin→'admin'`, `coach_admin→'coach'`; `groups :=
  coach_groups.practice_group[]`; `notificationPrefs.dailyDigest :=
  digest_enabled`, remaining keys type-compat `true` (reader-less; §6.2a);
  `fcmTokens := active own push_tokens.expo_push_token[]`;
  `createdAt/updatedAt := profiles timestamps`.
- A profile that is NOT staff (`role` ∉ {super_admin, coach_admin}) or not
  `approved` resolves `coach = null` + the existing not-a-coach error path.
  **The NM-5 auto-create-admin branch (today AuthContext.tsx:57–85) is
  DELETED, not ported** — ratified; gated provisioning (OD-3) governs all
  new accounts.
- signOut: read OWN active `push_tokens` rows via the notifications
  service, `unregisterPushToken` each, then `supabase.auth.signOut()` —
  the suite's one pinned assertion ("cleans up push subscriptions before
  sign out") is PRESERVED.
- `isAdmin` stays `coach?.role === 'admin'` — which post-map means
  **super_admin ONLY (Kevin)**: D-CUT8 A-STRICT semantics. The admin screen
  and the settings import buttons become Kevin-only at the swap; any future
  widening is a named product decision in the D-H9 class, never a migration
  side-effect.

**(iii) `app/forgot-password.tsx`** — `sendPasswordResetEmail(auth, email)`
(:31) → `supabase.auth.resetPasswordForEmail(email)`. The D-K1 decline
("building a Supabase reset now is DECLINED as a mixed-auth surface
mid-migration") expires HERE, by design — the swap is the moment it stops
being mixed-auth. Reset-email template + redirect URL are cloud-console
staging lines in 06 PART B.

**(iv) `app/(tabs)/settings.tsx`** — re-points onto the D-CUT7 surface
(§6.2a). The dead-end Firestore prefs write (:46) dies with the bank.

**(v) `app/admin.tsx`** — re-points onto the D-CUT8 `staff.ts` surface
(§6.2b). The whole-collection `onSnapshot` (:39) and the two `updateDoc`
toggles (:59, :73) die with the bank.

**(vi) `src/config/firebase.ts`** — deleted (with the firebase deps from
package.json at the same commit). Per FYI-G its `storage` + `functions`
exports already have zero live importers — verified again at deletion.
Test-side, the FYI-A sweep (12 dead `jest.mock('../../config/firebase')`
lines, per-file verify-at-deletion evidence, zero count impact) lands
FIRST; then `src/__mocks__/firebase.ts` deletes with the bank.

**(vii) The portal session half.** `parent-portal/src/lib/auth.ts` sign-in/
out/listener → `supabase.auth` (same idiom the portal already uses for its
profile read since Phase A); `dashboard/page.tsx` firebase `User` type →
the Supabase session user type. `lib/firebase.ts` and the `parentPortal.ts`
httpsCallable transport die when the §6.6 direct reads land (small-gap
verdict); if the director re-banks the gap instead, the transport survives
functions-scoped until the D-CUT5 callable-retirement step — and the
Firebase client config with it, named.

### 6.2a D-CUT7 — the notification-preferences successor (signatures AS BOUND)

Derived fresh (CUT-1 round): PG `notification_preferences` has exactly TWO
real, read columns — `push_enabled` (00001; honored per-user by the BSPC
`send-notification` sender at delivery, with a `profiles.push_enabled`
fallback) and `digest_enabled` (00008/D-G3; honored by `dailyDigest` at
digest build, missing-row-means-included). NOTHING reads any other
preference key in either workspace (fresh greps, functions/ + BSPC Deno).

```ts
// src/services/notifications.ts — additions (D-CUT7, D-K4 addition class)
export interface NotificationPreferences {
  pushEnabled: boolean;   // notification_preferences.push_enabled
  digestEnabled: boolean; // notification_preferences.digest_enabled
}
export async function getNotificationPreferences(): Promise<NotificationPreferences>;
export async function upsertNotificationPreferences(
  patch: Partial<NotificationPreferences>,
): Promise<void>;
```

Semantics: own-row only (`notification_prefs_own` RLS, `user_id =
auth.uid()`); upsert is `ON CONFLICT (user_id)`; a missing row reads as
`{pushEnabled: true, digestEnabled: true}` (schema defaults + the
dailyDigest missing-row semantic). **House-mock pins, ≥2 per export, bound:**
get → (1) row→shape mapping, (2) missing-row defaults; upsert → (3)
payload + conflict-key correctness, (4) error propagation. **Minimum +4.**

**The four settings toggles, dispositions bound (returns to the director in
the round report):** the screen's toggle keys are `dailyDigest | newNotes |
attendanceAlerts | aiDraftsReady` (settings.tsx:13), all writing the dead
Firestore doc today.
- **Daily Digest → `digestEnabled`. REAL, restored end-to-end** (the
  D-CUT7 ruling's "restores a shipped toggle surface" lands here).
- **newNotes / attendanceAlerts / aiDraftsReady — NO reader exists
  anywhere post-G** (fresh greps above). RECOMMENDED: these three toggle
  rows RETIRE at the swap as a NAMED UI change (the D-K3
  named-single-UI-change class): `newNotes` — producer retired pre-G, no
  server reader; `attendanceAlerts` — superseded by the per-coach
  `notification_rules` in-app surface (real since G); `aiDraftsReady` —
  returns WITH the D-G4 product item when its producer ships. Persisting
  reader-less keys to new PG columns is DISRECOMMENDED as the FYI-C
  dead-end class reborn (a toggle that lies). The read-only "Push
  Notifications" OS-status row stays; adding a `pushEnabled` toggle is a
  future product decision (no-widening).
- The frozen `Coach.notificationPrefs` type keeps all four keys
  (type-compat `true` defaults for the reader-less three) so no consumer
  changes shape.

### 6.2b D-CUT8 — the staff administration successor (signatures AS BOUND)

```ts
// src/services/staff.ts — NEW service (D-CUT8 surface (a), D-K4 addition class)
export interface StaffProfile {
  profileId: string;   // profiles.id
  userId: string;      // profiles.user_id (= post-swap Coach.uid)
  email: string;       // profiles.email
  displayName: string; // profiles.full_name
  role: 'super_admin' | 'coach_admin'; // PG truth; the screen renders its own labels
  groups: Group[];     // coach_groups.practice_group rows
}
export function subscribeStaffProfiles(
  onChange: (staff: StaffProfile[]) => void,
): () => void;
export async function setStaffRole(
  profileId: string,
  role: 'super_admin' | 'coach_admin',
): Promise<void>;
export async function setStaffGroups(
  profileId: string,
  groups: Group[],
): Promise<void>;
```

- Transport: postgres_changes on `profiles` + `coach_groups`. **Neither
  table is in the realtime publication today (exactly 23 tables, pgTAP
  011-pinned)** — one BSPC migration grows the publication 23 → 25 with
  pgTAP 011's exact-membership VALUES list updated in the same commit (the
  RH-12 idiom; ~~that proof is ONE `results_eq` test~~, so this is a
  CONTENT-ONLY update — **pgTAP stays 335 EXACT, pre-declared**). Event
  delivery rides the existing walls (`profiles_select_admin`,
  `coach_groups_staff`).
  > **[Corrected 2026-06-11 — CUT-4+ landed log, named correction 1; the
  > e71050a amend-in-place idiom extended to this plan]** The publication
  > exact-membership proof is **TWO `results_eq` tests — pgTAP 011 AND
  > pgTAP 014 test 19** (Phase J's "publication untouched" pin carries a
  > full second copy of the membership VALUES list) — and **BOTH update
  > together with any future publication change.** Caught live by the
  > first SWAP-1 pgTAP run (014:19 failed 23-vs-25); both lists updated
  > in the same commit; the content-only pre-declaration held (pgTAP 335
  > exact at SWAP-1, growing only at the §6.6 gap-build per its own
  > pre-declaration).
- `subscribeStaffProfiles` filters `role IN ('super_admin','coach_admin')`
  and joins groups; `setStaffGroups` reconciles by delete+insert on
  `coach_groups` for that profile.
- The service does NOT pre-check authority: `enforce_profile_self_update`
  (00002:120) is the wall — role changes are DB-enforced super_admin-only;
  a guard rejection surfaces through the normal error path (A-STRICT
  semantics; the screen is Kevin-only via `isAdmin` anyway).
- **House-mock pins, ≥2 per export, bound:** subscribe → (1) rows+groups
  join mapping, (2) unsubscribe/channel cleanup; setStaffRole → (3) update
  payload + target, (4) error propagation (guard rejection); setStaffGroups
  → (5) delete+insert reconciliation, (6) error propagation. **Minimum +6.**

### 6.3 What the cutover MUST NOT change (D-I1 interplay)

- Invite redemption stays staff-authorized LINK creation; approval stays
  ACCOUNT activation. **The Phase I precisification stands verbatim:
  "'dark until approval' means ZERO rows from every swimmer-keyed table,
  proven in pgTAP"** — including the explicitly-accepted pending-redeemer
  guardianships-row read. The cutover changes WHO the redeem caller is (a
  native Supabase uid instead of a mapped Firebase one) and NOTHING else
  about invites: `parent_invites` + the redeem RPC are already PG (Phase I).
- OD-3 gated provisioning governs every new account (no auto-approve
  anywhere; the NM-5 deletion composes with it).
- The data-layer freeze holds: no service interface changes ride along with
  the auth swap beyond the two bound successor surfaces above.

### 6.4 Swap test plan (pre-declared; exact bands)

**The named risk this section exists for:** cold-start session restore
(provider-swap correctness — risk-register item 4). Coverage grows at
AuthContext specifically.

| Event (Coach jest 1080 baseline) | Count |
|---|---|
| AuthContext suite TRANSFORMS in place (mocks re-pointed to the supabase idiom; the "cleans up push subscriptions before sign out" assertion preserved) | 1 → 1, zero deletions |
| D-CUT7 pins (§6.2a, bound) | **+4 minimum** |
| D-CUT8 pins (§6.2b, bound) | **+6 minimum** |
| New AuthContext pins: role map (super_admin→admin / coach_admin→coach / non-staff→null), session restore on cold start, signOut push_tokens cleanup re-point | +3 to +5 |
| settings re-point (digest toggle wiring) + forgot-password successor | +1 to +2 |
| portal session-swap pins (land in root `test/`, the Phase A +5 precedent — parent-portal/ itself is outside the bar) | +0 to +1 |
| FYI-A dead-mock sweep (12 files) + `src/__mocks__/firebase.ts` deletion | **0, verify-at-deletion per file (K6 precedent)** |

**Band: Coach 1080 → +10..+18, ZERO deletions** (exact counts fix
per-commit in the CUT-4+ round pre-declarations). **BSPC 835 EXACT and
Functions 115 EXACT through every 05 commit. pgTAP 335 EXACT through every
05 commit** — including the publication content-only update (§6.2b) —
**except the §6.6 gap-build commit if its small-gap verdict is ratified:
that commit ADDS pgTAP pins for the two new parent-read surfaces (band +4
to +8, fixed in its own round pre-declaration).** No other bar moves.

### 6.5 Cutover execution + rollback (instructions-only, HARD STOP)

Order at the cutover round (each step gated on the one before):
1. §6.1 provisioning + THE PROBE (zero-resolves = STOP) + NM-1 confirm +
   agreement audit — on the throwaway project FIRST (mandatory dry-run),
   then live.
2. The swap code (already landed in CUT-4+, dark behind the env) goes live:
   Coach app + portal builds pointed at the Supabase project.
3. Smoke checklist, named: coach login; role renders (Kevin sees ADMIN,
   a coach_admin does not); admin list live-updates; digest toggle
   round-trips to PG; password-reset email round-trips; portal parent
   login + dashboard render; cold-start relaunch restores the session.
4. Firebase Email/Password sign-in is disabled ONLY after step 3 passes
   (the 06 §7 standing sentence) — that step lives in 06 PART B §B6.
**Rollback (pre-launch):** env flip back to Firebase + revert commit; no
data has moved that the §6.1 audits did not verify; the map table holds
the correspondence either way.

### 6.6 D-CUT6 — the portal's post-cutover data path: THE GAP INVENTORY (in full)

End-state (ratified): DIRECT Supabase reads under the parent RLS walls.
The transport breaks at the swap regardless — the Firebase callable sees
no `request.auth` from a Supabase session — so this inventory decides
WHEN the direct reads build. Field-by-field against the frozen DTOs
(`parentPortal.ts`), each mapped to its parent-readable source:

| Portal payload field | Parent-readable source today | Verdict |
|---|---|---|
| `profile` (uid, email, displayName, linkedSwimmerIds) | `profiles` self-read + `guardianships_select_own` — **the portal already does this read directly** (lib/auth.ts profile half, Phase A/I) | ✅ no gap |
| `swimmers[]` summary (id, names, group, gender, active, photo) | `swimmers_select_own` is **family_id-arm ONLY** (00001:453) — a guardianship-linked (Coach-world) parent has NO arm until OD-1 convergence item 2 | ❌ **GAP-1** |
| `swimmer.strengths` | `swimmer_coach_profile` is **staff-only** (`scp_staff_all`, 00003:84); the callable exposed a sanitized slice via service-role | ❌ **GAP-2** |
| `swimmer.goals[]` (event names) | `goals_select_own` carries the family-OR-`is_my_swimmer()` two-arm shape (00005:289, RD-10) | ✅ no gap |
| `times[]` (event, course, hundredths, isPR, meet, date) | `swim_results_select_own` two-arm (00005:220); `timeDisplay` derives client-side (the formatter is already a pure RD-12 copy — it moves into the portal) | ✅ no gap |
| `attendance[]` (id, practiceDate, collapsed status) | `attendance_parent_view` (00004:160) — same D-C4 collapse, `is_my_swimmer()` OR family arm, filter `swimmer_id` client-side | ✅ no gap |
| `schedule[]` | **already served EMPTY since Phase H** (`parentPortal.ts:267` returns `[]`; D-H5(b) calendar went staff-only). Direct-read parity = the same empty list; "D-H5(b) parent arms ship only with a parent calendar feature" stands banked | ✅ parity-is-empty |
| `profilePhotoUrl` rendering | signed-URL capability for parents on `profile-photos` exists (Phase F walls) | ✅ no gap |

**VERDICT: SMALL — exactly two narrow parent-read surfaces, both in
established idioms:**
- **GAP-1 closes** by adding the `is_my_swimmer()` OR-arm to
  `swimmers_select_own` — the SAME transitional two-arm shape
  attendance/goals/times already have (RC-1/RD-10 pattern); it narrows to
  guardianships-only at convergence exactly like checklist items 3/9.
- **GAP-2 closes** with a narrow parent view (proposed
  `swimmer_strengths_parent_view(swimmer_id, strengths)` WHERE
  `is_my_swimmer(swimmer_id)`) — the D-C4 one-wall-one-rule class; the
  staff table stays staff-only.
- Both land in ONE BSPC migration + pgTAP pins (the §6.4 pre-declared +4..+8
  band) in the swap rounds; the portal's `parentPortal.ts` re-points from
  `httpsCallable` to direct reads with the DTO interfaces FROZEN.

**Recommendation: BUILD AT THE SWAP ROUNDS (small gap). The
build-now-vs-re-bank fork returns to the director with this verdict in the
round report.** If re-banked instead, the portal transport survives
functions-scoped until the D-CUT5 callable-retirement step, named.

### 6.7 Risk register (the original §6 failure modes, with their settled answers)

1. **"Passwords don't transfer."** CLOSED by OD-6 (2026-06-09): NO
   hash import; fresh credentials; pre-launch zero real users.
2. **"One-to-one identity integrity is COPPA-critical."** Answered by the
   §6.1 BINDING probe (zero-resolves = STOP), the deterministic
   `migration_identity_map` chokepoint, the in==out/no-dangling/no-duplicate
   audits, and the mandatory throwaway-project dry-run.
3. **"The escalation guard meets a many-super_admin world."** CLOSED by
   NM-1: Kevin is the sole super_admin; the live coaches list is pulled at
   backfill for his confirmation before any role writes.
4. **"Provider-swap correctness in the Coach App."** Answered by §6.2(i)'s
   persistence pin, §6.4's mandatory session-restore + role-map pins, and
   the §6.5 smoke checklist (cold-start relaunch is a named smoke step).

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
