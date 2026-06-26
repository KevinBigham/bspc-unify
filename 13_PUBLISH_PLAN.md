# 🔄🔴 FRESH-LAUNCH FORK — DIRECTOR RULING 56 + 57 (2026-06-25)

**READ FIRST. This supersedes the migration framing in the rest of this document.** Everything below that describes a Firebase→Supabase migration, Sitting 2, identity remediation, the R54 probe, or Gate R / Gate W is **HISTORICAL and SUPERSEDED — NON-EXECUTABLE.** No Executor may run any cutover, remediation tool, Firebase probe, or Firebase deployment.

**Launch model**
```text
Fresh Supabase launch
No Firebase migration
No Sitting 2
No Firebase identity remediation
No R54 Firebase probe
No Gate R or Gate W
```
The two Firebase projects were attested empty by Kevin — an **operator attestation, NOT a repository proof.** Ruling 57 does **not** authorize deletion of either Firebase project.

**Repository topology**
```text
5070f877 = historical audit artifact; never merge
launch base = Coach main 0c0f82b
future replay order = C then D
A and B = historical Firebase transition work
```
No branch creation or cherry-pick occurs under Ruling 57.

**New binding order**
```text
core governance reconciliation
→ Coach launch branch replay C
→ Coach launch branch replay D
→ production Supabase Phase 1
→ first-super-admin bootstrap
→ scheduler rehome
→ staff-assisted beta onboarding
→ device QA / closed beta
→ invite-redemption mobile UI
→ public-launch gates
→ dead-code and Firebase cleanup
```

**First-super-admin bootstrap** — concept approved; **exact SQL and hosted execution are HELD.** The eventual transaction must require:
```text
public signup closed
exactly 1 auth user
exactly 1 profile
profile maps to that user
profile initially family/pending
zero coach_admin
zero super_admin
privileged non-user execution context
exactly 1 row updated
final exactly 1 approved super_admin
full counts rechecked before commit
no email or UUID literal in SQL/output
```

**Scheduler rehome** — design-stage; neither implementation selected nor built:
```text
dailyDigest: SQL-Cron candidate
sweepAttendanceEvaluations: SQL-Cron versus scheduled Edge Function — undecided pending parity audit
```

**Onboarding** — Closed beta: the **existing admin approval path** is the staff-assisted candidate (creates the family, links the profile, inserts swimmers, records an approval log); acceptable **only after** synthetic end-to-end proof, an operator checklist, duplicate handling, and rollback verification. **Staff never redeem a parent invite.** Public launch: the **mobile invite-redemption UI is mandatory** (the RPC is tested but has no mobile caller).

**Gate 6** — Retire migrated-family and Firebase-shutdown messaging. Retain:
```text
Supabase email provider
SMTP/delivery proof
invite template
password-reset template
redirect and deep-link allow-list
synthetic invite/reset end-to-end proof
```

**Cleanup accounting**
```text
−105 retired
−102 provisional
1103 provisional
```
Exact cleanup paths and test bars require a later deletion diff and an actual test run.

**— End fresh-launch banner (Rulings 56 + 57). Historical content follows unchanged. —**

---

# 13 — PLAN FOR PUBLISH

**Status:** DRAFT — prepared by the EXECUTOR seat, 2026-06-22, at the close of Sitting 1.
Pending DIRECTOR review + ratification of the `[DECIDE]` items in §8. Not ratified policy.
**Companion docs:** `14_GATE1_LAWYER_BRIEF.md`, `15_PRIVACY_REWRITE_OUTLINE.md`, `16_PROD_BACKEND_PROVISIONING.md`.

> **One-line truth:** the build is done and proven; what remains is **operation + compliance + a bounded slice of release-hardening engineering** — Director Ruling 03's four changes (Functions export surface, Functions config hardening, client media-no-AI, client attendance-kick removal).
> Distance to *real phones in closed testing* ≈ **2–3 weeks** (the four hardening changes + their reviews now sit on the path). Distance to a *responsible public launch* ≈ **4–8 weeks**,
> paced by the children's-privacy / consent workstream (Gate 1) — still the long pole.

---

## 1. Topology — three surfaces, one backend

| Surface | Repo | Identity | Backend |
|---|---|---|---|
| Parent mobile | BSPC `880aed8` (frozen) | `com.bspowercats.swim`, v1.0.0 | Supabase/Postgres |
| Coach mobile | BSPC-Coach-App `0c0f82b` | `com.bspowercats.coach`, v1.3.0 | Firebase → Supabase (code migrated) |
| Parent-portal web | BSPC-Coach-App `/parent-portal` | Next.js 15 | Supabase/Postgres |

Canonical schema = `UNIFY/01_CANONICAL_SCHEMA.sql` (law). Cloud Functions stay Firebase-hosted as *compute* that reads Postgres, then retire at decommission (`06 §B6`).

## 2. State of each surface

- **Coach mobile** — most mature. 51 screens; service layer fully on Supabase; **1,199** client + **115** functions tests green.
- **BSPC parent** — complete, cleanly scoped (5 tabs + admin; deliberately *not* a media app per BSPC `CLAUDE.md`); **835** jest + **343** pgTAP green.
- **Parent-portal** — thinnest. 3 pages; schedule tab hardcoded empty; no host; no consent gate on signup; no password reset.

Repo docs lag reality (stale test counts, pre-migration guides) — the numbers above are the authoritative bars.

## 3. Migration status (the cutover is a separate, director-gated op)

All 11 phases (A–K) DONE + proven. **Sitting 1 (dry-run) PASSED** on synthetic data, caught + fixed the `mediaConsent` Timestamp bug (Coach `a5925aa→0c0f82b`, +8 pins, 1191→1199). Only the read-only §B0 probe has never had a live run. Full detail in `HANDOFF.md` + `06_FIREBASE_RUNBOOK.md` PART B.

## 4. How far, really — two distances + five gates

**Distance A** (backend unified, apps running on it): close — provision backend → cutover → point apps at it. Days of careful, Kevin-live, director-scheduled operation.

**Distance B** (live in both stores, with real families, legally + safely): gated by —

- **🔴 Gate 1 — children's-privacy / consent (the long pole).** Apps collect minors' DOB/medical/photos/video/audio. (1) the in-app label claims *"verifiable consent per COPPA and SafeSport MAAPP"* but the mechanism is a coach toggling Granted + typing a parent name (`edit.tsx:351-396`, `mediaConsent.ts:120-128`); (2) privacy policies are stale/inconsistent/placeholder; (3) consent is enforced client-side only, not at RLS/storage. **Needs a youth-sports/ed-tech privacy lawyer.** See `14`/`15`.
- **🔴 Gate 2 — production backend not yet stood up** (dev was local-only). See `16`.
- **🔴 Gate 3 — the cutover (Sitting 2)** — director-gated; runbook `06` PART B.
- **🟠 Gate 4 — store plumbing** — BSPC not wired to EAS (empty projectId/owner); both apps' submit creds are placeholders; no screenshots; portal has no host.
- **🟡 Gate 5 — device reality** — no app on a physical phone yet.
- **🔴 Gate 6 — recovery-email delivery + sign-in shutdown (explicit gate; Ruling 04 §7 / Ruling 05 §2).** Custom SMTP, confirmed send-rate capacity, a working redirect/deep-link, and **one synthetic end-to-end mobile recovery test** are prerequisites for **(i) triggering real recovery-email delivery to families** and **(ii) disabling Firebase Email/Password sign-in** — **not** for the pre-cutover announcement, which may go out through the existing **verified team channel**. Required order: **A** draft+approve announcement → **B** send it via the existing channel *before* sign-in is disabled → **C** prove the recovery path → **D** only then trigger real recovery messages and (separately) disable Firebase sign-in. Until the recovery path is proven there is **no real recovery-email delivery and no Firebase sign-in shutdown**; `19` describes operator-triggered recovery (pending the proven mechanism) *or* family-triggered *Forgot Password*, with no automatic-blast promise.
- **🟠 Gate 7 — net-new family onboarding (public-launch gate; Ruling 04 §8).** NOT a Sitting-2 blocker — existing families migrate regardless. Before *public* launch, provide either **(A)** tested mobile invite redemption or **(B)** tested + documented staff-assisted onboarding. The BSPC parent app has the `redeem_parent_invite` RPC + pgTAP but **no invite-redemption UI wired yet**, so `19`'s invite template stays **inactive** until one exists. Do not claim the net-new invite flow is operational until it is.

The engineering substrate is otherwise strong on *authorization* (pgTAP parent-read "walls," staff-only RLS, hardened invite redemption) — the gap is the *consent model + disclosures*, which can't be tested away.

> **[Director Ruling 03] Release-hardening now on the path (bounded engineering, not just ops).** Four separate, Director-gated frozen-repo changes: **A** Functions launch-export surface, **B** Functions config hardening, **C** client media-no-AI (hard-disabled), **D** client attendance-kick removal. The **v1 Functions allow-list was blocked on callable-auth survivability** — a Firebase callable's `request.auth` does not verify a Supabase token after cutover. That audit is now **delivered** (Ruling-03 response: the coach app + the Supabase-native BSPC parent app call **none** of the three callables; all three are **parent-portal-only / fast-follow**; mobile invite-redemption is the `auth.uid()`-gated Supabase RPC `redeem_parent_invite`, pgTAP-tested).
>
> **[Director Ruling 04 + 05 — RATIFIED]** The **initial v1 export set is exactly TWO scheduled functions** — `sweepAttendanceEvaluations` + `dailyDigest`. **Proposal A makes `index.ts` export exactly those two** (the test asserts the exact two-name set); the three portal callables, the AI trio, and `evaluateAttendanceRules` are *removed from the export surface*, not merely undeployed. **`syncCalendar` is a conditionally approved follow-on** (Ruling 05 §1) — **not** an initial export, **not** a self-skipping placeholder; it may be added only by a later separate change once a real production calendar feed is proven (public vs private/tokenized, config bound safely, URL never logged, tests green, target-gated deploy reviewed). The four changes land in a **binding order, one at a time, each ratified + committed before the next: A → B → C → D → identity-remediation script.** Proposal C covers **both audio and video**. All remain unimplemented (documentation-only).

## 5. The Plan for Publish

### 🏁 Milestone 1 — "on real phones / closed testing" (~2–3 wks)

| Phase | Work | Owner | Gate |
|---|---|---|---|
| 0. Greenlight | Director blessed baseline `0c0f82b`/1199 ✅ (Ruling 02); **−105 retirement delta RATIFIED** ✅ (Ruling 03 §1; floor = *canonical client bar − 105*; current 1199−105=**1094**; deletion = one named change after cutover+data verification); **Option C selected** ✅ (Ruling 03 §2); **callable-auth audit closed** → initial v1 Functions = **exactly 2 scheduled functions — RATIFIED** (Ruling 05 §1: `sweepAttendanceEvaluations` + `dailyDigest`; `syncCalendar` a conditionally-approved follow-on); schedule Sitting 2 | Director | — |
| 1. Prod backend | Prod Supabase · 13 migrations · 4 edge fns · Coach-fns **parameterized config** (Ruling 03 §3) · ≥500MB storage · demo accounts (`16`) | Executor + Kevin | needs prod project |
| 1b. Release-hardening *(4 changes + identity script; **binding order A→B→C→D→identity**, one at a time, each ratified+committed before the next; Ruling 04/05)* | **A** export surface = **exact two** (`index.ts` exports only `sweepAttendanceEvaluations` + `dailyDigest`; callables, AI trio, `evaluateAttendanceRules` removed; `syncCalendar` a follow-on) · **B** Functions config hardening · **C** client media-no-AI (hard-disabled, **audio+video**) · **D** client attendance-kick removal | Executor, Director-gated | frozen-repo exceptions |
| 2. Cutover | Sitting 2 spine (`06` PART B) | Executor, Kevin-live | **director-scheduled** |
| 3. EAS + build | `eas init` BSPC (projectId/owner/updates.url) · set env · dev/internal builds both apps | Executor + Kevin | needs backend |
| 4. Device QA | One full practice logged without crashes · Maestro smoke on-device | Kevin + Executor | needs build |

### 🚀 Milestone 2 — "public launch" (~4–8 wks, paced by compliance)

| Phase | Work | Owner | Gate |
|---|---|---|---|
| 5. Compliance *(start NOW, parallel)* | Lawyer · rewrite both policies + BSPC ToS · host at public URLs · real consent capture *or* soften the claim · push consent into RLS/storage · lock minors' photo reads (`14`/`15`) | Lawyer + Executor + Kevin | **the long pole** |
| 6. Store assets | Screenshots (Maestro flow exists) · metadata · fill submit creds · age-rating / Data Safety / Designed-for-Families forms | Executor + Kevin | needs M1 builds + Gate-1 verdicts |
| 7. Beta | TestFlight + Play closed testing with real coaches/families | Kevin + Executor | — |
| 8. Ship | Family announcement via the existing team channel **before** disabling Firebase sign-in; **real recovery-email delivery + the sign-in shutdown are separately gated** on the proven recovery path (custom SMTP + send-rate capacity + redirect/deep-link + one synthetic e2e mobile recovery test, `Gate 6`/`19`) · decommission: **client** bar − 105 (RATIFIED; **one named change after cutover+data verification**; currently 1199→1094, `06 §B6` step 5) + **Functions** 115→0 (step 3, separate workspace) · `eas submit` · store review | Kevin + Executor | announcement precondition |
| 9. Fast-follow | Host + harden portal (consent gate, schedule tab, reset) · OD-1 convergence sweep | Executor | post-launch |

## 6. Critical path

`greenlight → prod backend → cutover → EAS build → device QA`  ‖ (parallel)  `lawyer + policy rewrite + consent re-engineering`  →  `store assets → beta → announce → submit → LIVE`

The compliance branch runs alongside the ops branch — starting the lawyer conversation now is the highest-leverage move even though no code is blocked on it.

## 7. Recommended launch scope

**Launch the two mobile apps first; treat the parent-portal web as a fast-follow.** It is the thinnest surface and overlaps the richer BSPC parent app; cutting it from the critical path removes the least-ready surface from launch risk without losing parent-facing capability.

## 8. `[DECIDE]` — resolutions (Kevin, 2026-06-22)

1. **Launch scope** — ✅ **RESOLVED: two mobile apps now, parent-portal as fast-follow.**
2. **Consent strategy** — ✅ **RESOLVED: proceed, lean + honest v1.** Direction: the coach attests that a **signed off-app media-consent form is on file**; re-word the in-app "verifiable consent per COPPA/SafeSport" copy (`edit.tsx:351-353`) to describe *exactly that*, rather than claiming digital verifiable parental consent. A real in-app parental-consent capture flow is a **fast-follow only if counsel requires it** (`14`). Combined with decision 4 below, **v1 sends no minors' media to third-party AI**, which removes that exposure from launch entirely.
3. **Bless baseline + schedule Sitting 2** — ⏳ **DIRECTOR action** (Kevin: "hell yeah"). Prerequisites before it can be scheduled: (a) director blessed Coach `0c0f82b`/1199 ✅ (Ruling 02); decommission delta **−105 RATIFIED** ✅ (Ruling 03 §1; floor = *canonical bar − 105*; current 1094; deletion is one named change after cutover+data verification); (b) Phase 1 production backend complete (`16`), now including the four Ruling-03 release-hardening changes; (c) Kevin's identity settled — Kevin reports **no Firebase coach document exists for him** and his Firebase Auth identity is **not yet proven**; this is settled by the **dedicated identity-remediation sitting (`20`), which runs BEFORE §B0** (not `create-coach.ts`, the add-coach/self-onboarding flow, or a hand-minted Supabase admin): Branch A (existing Auth identity + zero coach docs) = create-only remediation after Director review of the script diff+tests; Branch B (no Auth identity) = STOP + separate identity-bootstrap proposal; (d) family announcement drafted + reset-email template staged. → Take this doc (esp. §8) to the director chat.
4. **Storage / AI** — ✅ **RESOLVED: no paid Supabase yet; ship media, cut AI.** Stay on the free tier; the read-only **§B0 probe sizes the real media footprint first**, and we revisit a paid tier only if it exceeds free. **Canonical (Evidence Packet 01):** *V1 supports private audio and video capture, upload, storage, retrieval, and playback. V1 performs no audio or video AI analysis and sends no minors' media to an AI provider.* The audit showed this takes more than omitting two functions — the AI surface is **three** (`processAudioSession`, `processVideoSession`, scheduled `sweepStuckSessions`) plus a required **client app-guard** (frozen-repo, director-gated); full posture in `17 §8b`. Because minors' media *is* collected at launch, the media-consent + disclosure work (`14`/`15`) stays fully in scope — only the AI-processing sub-question is removed. *(Footprint caveat: keeping media + free tier could collide if existing media exceeds free-tier storage; the §B0 probe sizes it before we decide.)*

## 9. Bottom line

Past done on the build, at the doorway of operations. Get counsel on Gate 1 now, stand up the backend and prep the cutover for the director to schedule, and both apps can be on real phones within a couple of weeks — a responsible public launch a few weeks behind.
