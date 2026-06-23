# 20 — KEVIN IDENTITY-REMEDIATION SITTING (proposed; for Director review)

**Status:** PROPOSED sitting — drafted by the EXECUTOR seat, 2026-06-22. **Nothing here has run.** **[Director Ruling 03 §4 — BLESSED IN CONCEPT, NOT FOR EXECUTION.]** Branch A may proceed **only after the Director reviews the remediation-script diff + its tests**; Branch B = immediate STOP + a separate bootstrap proposal. **Execution remains HELD pending that diff + tests.** **[Director Ruling 04 §6 — amended for safety: create-only write (no overwrite of a concurrently-created doc), zero PII in argv/history/output/NOTES/tests/logs, STOP-don't-delete on an ambiguous outcome, verified-reversal-only.]** A separate, dedicated, director-scheduled sitting that must complete **before** Sitting 2.
**Why it exists:** Director ruling #3 — *"Kevin is not currently represented by a coach record in the real Firebase source."* NM-1 promotes an **existing Firebase coach identity** to `super_admin`; if Kevin isn't in the source, the cutover has no identity to promote. This sitting makes him a proper Firebase coach **so the existing, tested promotion path runs unchanged** — it does **not** hand-mint an admin.

> **KEY-SAFETY (applies to every phase):** the only hosted target here is **Firebase**. Before **every Phase-0 hosted read** (**Gate R**) and again immediately before the **single Phase-2 write** (**Gate W**), print the **Firebase `project_id` only** (never a secret) and wait for Kevin's explicit "go." The sitting log **redacts** UID, email, and every identifying value — record them as `<KEVIN_AUTH_UID>` / `<KEVIN_EMAIL>` placeholders. The approved remediation tool **may load the service-account credential from its approved local location**; **no human or tool output may inspect, display, paste, serialize, log, copy, or persist its contents**, and **no credential path or content appears in `NOTES.md` or chat.** This sitting must **never** use `seed-*.ts` (they bind the real service-account key). **[Director Ruling 04 §6]** Kevin's email and UID must **never** appear in `argv`, shell history, command output, `NOTES.md`, tests, or logs. Any sensitive input is collected **interactively at run time (hidden prompt) and never persisted** — not to a file, an on-disk env var, or history. The redacted placeholders above are the *only* form these values take in any written record.

---

## What this sitting does and does NOT do

| Does | Does NOT |
|---|---|
| Read-only probe Firebase Auth + Firestore for Kevin's state | Create a second Auth user |
| Write **exactly one** Firestore doc: `coaches/<KEVIN_AUTH_UID>` | Create or promote any `super_admin` (that's the cutover's job, later) |
| Bind that doc to Kevin's **existing** Auth UID | Touch Supabase / Auth / Storage |
| Prove exactly one matching coach record after | Run any `seed-*` script or `create-coach.ts` as-is (see §why-not) |
| Be reversible **only after** verified-successful creation (deterministic delete of the one doc) | Begin Sitting 2 · overwrite a concurrently-created doc · blind-delete on an ambiguous outcome |

**Promotion happens later, not here.** Kevin becomes `super_admin` only when the actual cutover runs `backfill-identity-graph --super-admin-uid=<KEVIN_AUTH_UID>` — promotion is decided by **uid match**, not the coach `role` field (`backfill-identity-graph-plan.ts:249-250,287`). This sitting just puts the matchable identity into the source.

---

## Branch ruling (Director Ruling 02 §5 — binding)

Phase 0 discovery (below) decides the branch; the Phase-2 write happens **only on Branch A**.

- **Branch A — an existing Firebase Auth identity for Kevin IS found:** remediation **may proceed, but only after explicit Director blessing** of this sitting. One scoped Firestore write, bound to that existing Auth UID.
- **Branch B — NO Firebase Auth identity is found:** **immediate STOP.** Do **not** create an Auth user inside this sitting. Return a **separate identity-bootstrap proposal** for Director review (creating Kevin's *first* Firebase identity is a distinct action this sitting is not authorized to take).
- **Always, both branches:** no automatic Auth-user creation; no standalone `super_admin`; **no write until the Firebase `project_id` is printed and Kevin gives an explicit go**; no UID / email / identifying value in the sitting log (redacted placeholders only).

---

## Proposed coach-document payload (Director Ruling 03 — exact table)

From the current `Coach` type (`src/types/firestore.types.ts:13-30`) and what the migration mapper actually consumes (`mapping.ts`, `backfill-identity-graph-plan.ts:281-305`). **No real UID / email / name appears here — only value *categories*.**

| field | source type | required/optional | proposed value (category) | migration consumer | reason required |
|---|---|---|---|---|---|
| `uid` (doc id) | string | **REQUIRED** | Kevin's **existing** Firebase Auth UID *(identity key — not printed)* | `doc.id` → `migration_identity_map.firebase_uid` → `--super-admin-uid` match (`backfill-identity-graph-plan.ts:287`) | the **only** structurally indispensable field — the join key the promotion matches on |
| `email` | string | **REQUIRED** | Kevin's account email *(PII — not printed)* | → `profiles.email`; the `createUser` key at cutover step 3 | identity/profile mapping; the profile row is incomplete without it |
| `displayName` | string | **REQUIRED** | Kevin's name *(PII — not printed)* | → `profiles.full_name` | profile display name |
| `role` | string enum `'coach'`\|`'admin'` | **REQUIRED** | the literal string **`'coach'`** — **SETTLED by Director Ruling 07** (`role:'admin'` is **not authorized** for this remediation; see the **role decision** note below) | **none** — the promotion ignores this field entirely | the `Coach` type requires it; see "role" note. **Does NOT confer super_admin.** |
| `groups` | string[] | **REQUIRED** (may be empty) | **exactly `[]`** (empty array) — **SETTLED by Director Ruling 07**; do **not** infer or guess practice groups | → `coach_groups` (receives no rows; an out-of-domain value would be dropped + reported, but none is written here — `backfill-identity-graph-plan.ts:93-102`) | roster scoping; see "groups" note |
| `notificationPrefs` | object `{dailyDigest,newNotes,attendanceAlerts,aiDraftsReady}`: booleans | OPTIONAL | **exact, source-proven:** `{dailyDigest:true, newNotes:true, attendanceAlerts:true, aiDraftsReady:true}` (`create-coach.ts:60-65`; type `firestore.types.ts:21-26`) | **none** | the `Coach` type declares it; the **app** reads only `dailyDigest` at runtime (from PG `notification_preferences.digest_enabled`, `AuthContext.tsx:73-97`) — the migration never reads any of it |
| `fcmTokens` | string[] | OPTIONAL | `[]` (empty) | **none** | the `Coach` type declares it; populated by the **device** at first sign-in — not the migration |
| `createdAt` / `updatedAt` | Firestore `Timestamp` | OPTIONAL | server timestamp at write | **none** | the `Coach` type declares them; audit/order only — the migration never reads them |

**`role` decision (Director Ruling 07 — SETTLED: `role:'coach'`).** `role:'coach'` is selected. **No pre-cutover admin power is needed** for this remediation, and **`role:'admin'` is NOT authorized in this sitting.** NM-1 promotion keys **only on the existing Auth UID** (`backfill-identity-graph-plan.ts:287`) — never on this `role` field — so the remediation's sole purpose (a matchable identity) is fully served by `role:'coach'`, and `super_admin` is conferred later by UID match regardless.

> For the record (why least-privilege is correct): `role:'admin'` *would* have granted real pre-cutover powers `role:'coach'` lacks — update/delete **other** coaches' docs (`firestore.rules:25-26`), write `swimmers/{id}/medical` (`:46`), read-all + delete `import_jobs` (`:95,102`), the admin / import-roster / meet-results / import-history UI (`admin.tsx`, `import.tsx`, `import/history.tsx`, `settings.tsx`), and `setStaffRole`/`setStaffGroups` (`services/staff.ts:92-114`). **This remediation requires none of them**, which is exactly why the least-privilege role is chosen. No real identity value appears here.

**"groups" note (Director Ruling 07 — settled):** write **exactly `[]`** (empty array). Do **not** infer or guess Kevin's practice groups. `coach_groups` simply receives no rows; the mapper would drop + report any out-of-domain value, but none is written here. Groups can be assigned later through the normal staff-admin flow.

**`notificationPrefs` / `aiDraftsReady` note (Director Ruling 07):** the four booleans are written all-`true` for source compatibility. **`aiDraftsReady` is compatibility metadata only — it does NOT enable, invoke, or authorize any AI processing** (no audio or video is sent to any AI provider; the v1 media-no-AI posture is unchanged). Post-cutover the app reads only `dailyDigest` (from PG `notification_preferences.digest_enabled`); the migration reads none of these.

**Confirmation — the payload does NOT mint `super_admin`.** This sitting writes ONE Firestore `coaches/<uid>` document with `role: 'coach'` (a coach-app label; Director Ruling 07), creates **no** Auth user, and writes **no** `super_admin` anywhere. `super_admin` is conferred later **only** by the cutover's `backfill-identity-graph --super-admin-uid=<UID>`, which matches on **UID** — never on this `role` field. This single document cannot and does not grant `super_admin`.

**Confirmation — the NM-1 mapper consumes the EXISTING Auth UID.** Promotion fires when `coach.uid === superAdminUid` (`backfill-identity-graph-plan.ts:287`). The `uid` written here **is** Kevin's existing Firebase Auth UID (from P0.1's `getUserByEmail`), and that same UID is later passed as `--super-admin-uid`. The mapper keys on the **existing** Auth UID, not on any newly-minted identifier.

---

## Gate R — read-target approval (before every Phase-0 hosted read)

- [ ] Print the **Firebase `project_id` only** (never a secret, never a URL or credential) that the Phase-0 reads will target. Kevin **explicitly approves the read target.** **No approval = STOP** — run no read.

---

## Phase 0 — Read-only discovery (proves the preconditions)

All read-only (firebase-admin `getUserByEmail`, Firestore `get`). No writes. Capture results **redacted** into the sitting log.

- [ ] **P0.1 — Kevin has an existing Firebase Auth identity.** `auth().getUserByEmail(<KEVIN_EMAIL>)` → exactly one user. Record its UID as `<KEVIN_AUTH_UID>` (redacted). **If zero users → HALT (Branch B below).** Do not create one without a separate Director ruling.
- [ ] **P0.2 — No coach doc exists for that UID.** `firestore().doc('coaches/<KEVIN_AUTH_UID>').get()` → `exists === false`. If it exists, ruling #3 is wrong → **HALT and re-surface to Director** (nothing to remediate).
- [ ] **P0.3 — No duplicate by UID.** Confirm no other `coaches/*` doc carries `uid === <KEVIN_AUTH_UID>` (doc-id is canonical; this guards stray data).
- [ ] **P0.4 — No duplicate by email (manual — the tooling won't catch this).** Evidence Packet 01 §3 found **email is never normalized and never a dedupe key** (`grep` clean across `functions/` + `scripts/`; only `create-coach.ts:30` does a bare `.trim()`). So **explicitly** read all `coaches/*` emails and compare **case-insensitively** to Kevin's. **[Director Ruling 03 — KEY-SAFETY]** the check **reports COUNT/STATUS only** — `0 matches` (proceed) or `≥1 match` (HALT) — and **never prints any email value**, neither Kevin's nor any compared document's. Any match → **HALT** (a second identity for Kevin already exists; remediate that instead of adding a third).
- [ ] **P0.5 — Confirm zero create-time side-effects.** Verified (Evidence Packet 01 §3 / Agent-D #4): there are **no `onCreate`/`onWrite`/Auth triggers on the `coaches` collection** in the live function set (`functions/src/index.ts:1-23`; grep clean). So the Phase-2 write fires **nothing** in Firebase. (The Supabase `on_auth_user_created` trigger is irrelevant here — no Auth user is created — and is independently held disabled until cutover step 8.)

**Branch B (P0.1 returns zero Auth users) — RULED 02 §5: IMMEDIATE STOP.** Kevin has *no* Firebase identity at all. **Stop the sitting; create NO Auth user here; write nothing.** Return a **separate identity-bootstrap proposal** for Director review — creating Kevin's *first* Firebase Auth identity is a distinct action this sitting is not authorized to take. Do not improvise it inside this sitting.

---

## Gate W — write-target approval (immediately before Phase 2)

- [ ] Print the **same Firebase `project_id` only**. Summarize the planned write as **"one create-only `coaches` document."** Kevin **explicitly approves the write.** **No approval = STOP** — write nothing.

---

## Phase 2 — The single scoped write

- [ ] Write **exactly one** document, `coaches/<KEVIN_AUTH_UID>`, with the §payload fields above, via a **create-only operation that cannot overwrite a concurrently-created document** — firebase-admin `.create()` (fails if the doc already exists) **or** a transaction whose precondition asserts non-existence. **Not an unconditional `.set()`** (Director Ruling 04 §6: between the P0.2 read and this write another actor could create the doc; a bare `.set()` would clobber it). **One doc. No Auth user. No other collection.**
- [ ] **Tooling:** a small, purpose-built remediation script that does only *read-checks → one **create-only** write → re-read* — **not** `create-coach.ts`. Writing that script is a **frozen-repo (Coach `0c0f82b`) exception**: it needs advance Director blessing, its own tests, and its own commit (Evidence Packet 01 §7 rules). It is **not** written yet.

### Why not `create-coach.ts` (Evidence Packet 01 §3 / Agent-D #5)
It is triple-stale and would do the wrong thing: it **creates a new Firebase Auth user with a password** (client SDK `createUserWithEmailAndPassword`, `:11,49`) — violating "use the existing UID / no second user / no password (OD-6)"; it hardcodes `role:'admin'` (pre-NM-1) and only **6 of 8** groups (omits `Masters`, `Swim Lessons`). It must not be used for remediation.

---

## Phase 3 — Post-write read-only proof

- [ ] **P3.1 — complete-payload verification (redacted compare).** `coaches/<KEVIN_AUTH_UID>` now exists and **every written field** matches the intended payload: **document ID / `uid`**, **`email`**, **`displayName`**, **`role` (= `'coach'`)**, **`groups` (= `[]`)**, **`notificationPrefs` (= `{dailyDigest:true, newNotes:true, attendanceAlerts:true, aiDraftsReady:true}`)**, **`fcmTokens` (= `[]`)**, and **`createdAt` + `updatedAt` present with `Timestamp` type**. All comparisons remain **redacted** (UID / email / name never printed).
- [ ] **P3.2 — exactly-one, same-document (counts/status only, redacted).** Pre-creation, P0.3/P0.4 established **zero** matches by UID and **zero** case-insensitive matches by email. **After** creation: **exactly one** `coaches/*` document matches `<KEVIN_AUTH_UID>` by UID, **exactly one** matches Kevin's email case-insensitively, and **both are the same newly-created document** (no second or stray identity). No UID or email value is printed.
- [ ] **P3.3 — Auth unchanged:** the Auth user count for `<KEVIN_EMAIL>` is still **one** (no second user was born).
- [ ] **P3.4** — Record the redacted proof in the sitting log; report PASS to the Director.

---

## Halt + reversal plan (Director Ruling 04 §6)

- **Any** Phase-0 HALT (no Auth identity / doc already exists / email dup) → stop, write nothing, surface to Director.
- **Ambiguous write / network outcome** (timeout, unknown error, dropped connection — the write *may or may not* have landed) → **STOP. Do NOT blind-delete.** A delete on an indeterminate state could destroy a document another actor legitimately created. Re-establish read-only certainty first (re-read the doc), surface to Director, and act only on a **known** state.
- **Reversal is allowed ONLY after** (a) the create is **known to have succeeded**, *and* (b) **deterministic verification** (Phase 3) proves the new document must be removed (wrong field, unexpected dup, count drift). Only then delete `coaches/<KEVIN_AUTH_UID>` (the single doc just created). Reversal is clean because **no trigger fires on a `coaches` write** (P0.5) — there is no cascade to undo. Then re-surface to Director. Do not retry without a ruling.

---

## What the Director is asked to do

The payload is **settled by Director Ruling 07** (`role:'coach'`, `groups:[]`, source-compatible `notificationPrefs` all-`true`, `fcmTokens:[]`, server-timestamp `createdAt`/`updatedAt`) — **no payload or role choice is requested.** The remaining asks:

1. **Review / bless the remediation-script diff + its tests** — the frozen-repo (Coach `0c0f82b`) exception, with its own tests and its own commit. (It is not written yet.)
2. **Schedule the identity-remediation sitting** only **after** that implementation evidence is blessed.

Execution remains **HELD.** Branch B needs no advance ruling: if Phase 0 finds **no** Firebase Auth identity, the sitting **STOPs immediately — no Auth creation, no coach-document write — and returns a separate identity-bootstrap proposal.**
