# 13 — PLAN FOR PUBLISH

**Status:** DRAFT — prepared by the EXECUTOR seat, 2026-06-22, at the close of Sitting 1.
Pending DIRECTOR review + ratification of the `[DECIDE]` items in §8. Not ratified policy.
**Companion docs:** `14_GATE1_LAWYER_BRIEF.md`, `15_PRIVACY_REWRITE_OUTLINE.md`, `16_PROD_BACKEND_PROVISIONING.md`.

> **One-line truth:** the build is done and proven; what remains is **operation + compliance**, not engineering.
> Distance to *real phones in closed testing* ≈ **1–2 weeks**. Distance to a *responsible public launch* ≈ **4–8 weeks**,
> paced by the children's-privacy / consent workstream (Gate 1) — not the code.

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
- **🟠 Gate 4 — store plumbing** — BSPC not wired to EAS (empty projectId/owner); both apps' submit creds are placeholders; no screenshots; portal has no host; `create-coach.ts` still on the Firebase SDK.
- **🟡 Gate 5 — device reality** — no app on a physical phone yet.

The engineering substrate is otherwise strong on *authorization* (pgTAP parent-read "walls," staff-only RLS, hardened invite redemption) — the gap is the *consent model + disclosures*, which can't be tested away.

## 5. The Plan for Publish

### 🏁 Milestone 1 — "on real phones / closed testing" (~1–2 wks)

| Phase | Work | Owner | Gate |
|---|---|---|---|
| 0. Greenlight | Director blesses baseline `0c0f82b`/1199, ratifies −106→**1093**, schedules Sitting 2 | Director | — |
| 1. Prod backend | Prod Supabase · 13 migrations · 4 edge fns · Coach-fns service-role secret · ≥500MB storage · demo accounts (`16`) | Executor + Kevin | needs prod project |
| 2. Cutover | Sitting 2 spine (`06` PART B) | Executor, Kevin-live | **director-scheduled** |
| 3. EAS + build | `eas init` BSPC (projectId/owner/updates.url) · set env · dev/internal builds both apps | Executor + Kevin | needs backend |
| 4. Device QA | One full practice logged without crashes · Maestro smoke on-device | Kevin + Executor | needs build |

### 🚀 Milestone 2 — "public launch" (~4–8 wks, paced by compliance)

| Phase | Work | Owner | Gate |
|---|---|---|---|
| 5. Compliance *(start NOW, parallel)* | Lawyer · rewrite both policies + BSPC ToS · host at public URLs · real consent capture *or* soften the claim · push consent into RLS/storage · lock minors' photo reads (`14`/`15`) | Lawyer + Executor + Kevin | **the long pole** |
| 6. Store assets | Screenshots (Maestro flow exists) · metadata · fill submit creds · age-rating / Data Safety / Designed-for-Families forms | Executor + Kevin | needs M1 builds + Gate-1 verdicts |
| 7. Beta | TestFlight + Play closed testing with real coaches/families | Kevin + Executor | — |
| 8. Ship | Family announcement **before** disabling Firebase sign-in · decommission (Functions 1199→1093) · `eas submit` · store review | Kevin + Executor | announcement precondition |
| 9. Fast-follow | Host + harden portal (consent gate, schedule tab, reset) · OD-1 convergence sweep | Executor | post-launch |

## 6. Critical path

`greenlight → prod backend → cutover → EAS build → device QA`  ‖ (parallel)  `lawyer + policy rewrite + consent re-engineering`  →  `store assets → beta → announce → submit → LIVE`

The compliance branch runs alongside the ops branch — starting the lawyer conversation now is the highest-leverage move even though no code is blocked on it.

## 7. Recommended launch scope

**Launch the two mobile apps first; treat the parent-portal web as a fast-follow.** It is the thinnest surface and overlaps the richer BSPC parent app; cutting it from the critical path removes the least-ready surface from launch risk without losing parent-facing capability.

## 8. `[DECIDE]` — resolutions (Kevin, 2026-06-22)

1. **Launch scope** — ✅ **RESOLVED: two mobile apps now, parent-portal as fast-follow.**
2. **Consent strategy** — ✅ **RESOLVED: proceed, lean + honest v1.** Direction: the coach attests that a **signed off-app media-consent form is on file**; re-word the in-app "verifiable consent per COPPA/SafeSport" copy (`edit.tsx:351-353`) to describe *exactly that*, rather than claiming digital verifiable parental consent. A real in-app parental-consent capture flow is a **fast-follow only if counsel requires it** (`14`). Combined with decision 4 below, **v1 sends no minors' media to third-party AI**, which removes that exposure from launch entirely.
3. **Bless baseline + schedule Sitting 2** — ⏳ **DIRECTOR action** (Kevin: "hell yeah"). Prerequisites before it can be scheduled: (a) director formally blesses Coach `0c0f82b`/1199 and ratifies −106→**1093**; (b) Phase 1 production backend complete (`16`); (c) Kevin's real super_admin uid confirmed via the §B0 probe; (d) family announcement drafted + reset-email template staged. → Take this doc (esp. §8) to the director chat.
4. **Storage / AI** — ✅ **RESOLVED: no paid Supabase yet.** Stay on the free tier; the read-only **§B0 probe sizes the real media footprint first**, and we revisit a paid tier only if it exceeds free. **Defer AI analysis of videos for v1** (hold the Vertex/Gemini video pipeline). *(Open: defer the audio-AI pipeline too for consistency? — executor recommends yes; Kevin to confirm.)*

## 9. Bottom line

Past done on the build, at the doorway of operations. Get counsel on Gate 1 now, stand up the backend and prep the cutover for the director to schedule, and both apps can be on real phones within a couple of weeks — a responsible public launch a few weeks behind.
