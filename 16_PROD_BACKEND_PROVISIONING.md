# 16 — PRODUCTION BACKEND PROVISIONING CHECKLIST

**Status:** DRAFT checklist — prepared by the EXECUTOR seat, 2026-06-22. Pending DIRECTOR scheduling.
**This document runs nothing.** It is the ordered plan for standing up the production backend. Every step is **Kevin-live**; the cutover itself (Sitting 2) is a **separate, director-gated** operation (`06` PART B).

> **KEY-SAFETY:** before any command that targets a hosted project, print the target **Supabase URL** (and, for any Firebase touch, the **project_id** only — never secrets) and have Kevin confirm. Never read/print/commit `.env`, service-account, or key files. Never `git add .`.

---

## 0. Why this comes first

Development has run against **local** Supabase only — **there is no production project yet.** The Sitting-2 cutover writes real data *into* the production Postgres, and all three app surfaces point at it. So this Phase 1 must complete **before** the director schedules Sitting 2. (The handoff's §6 spine assumes the target Postgres already exists; this doc fills that gap.)

## 1. Production Supabase project

- [ ] Create the prod Supabase project (org owned by Kevin; **US region**; Postgres 17 to match local `config.toml`). Capture the project ref + URL.
- [ ] `supabase link` the CLI to the prod project.
- [ ] `supabase db push` — apply the **13 BSPC migrations** `00001_initial_schema` → `00013_cutover_parent_read_gaps`.
- [ ] Verify RLS is present (the 343 pgTAP tests cover it locally; spot-check the prod policies exist).
- [ ] **Auth** — enable email/password. Stage the **password-reset email template + redirect URL** (required: OD-6 imports no passwords, so every user does a forced reset/invite at go-live). **[Director Ruling 04 §7 / Ruling 05 §2] Staging the template ≠ proven delivery.** Custom SMTP, confirmed send-rate capacity, a working redirect/deep-link, and **one synthetic end-to-end mobile recovery test** are prerequisites for **triggering real recovery-email delivery to families and for disabling Firebase Email/Password sign-in** — **not** for the pre-cutover announcement, which may go out through the existing **verified team channel** (`13` Gate 6 / `19`). **Net-new onboarding** (invite redemption) is a separate **public-launch** gate (`13` Gate 7 / `19`), not a Sitting-2 blocker.
  - Staged repo artifacts: `auth-email-templates/reset-password.md`, `auth-email-templates/invite-user.md`, and the throwaway-only recovery checklist `scripts/synthetic-recovery-checklist.sh`.
- [ ] Seed the **2 demo accounts** (`demo-family` / `demo-admin`). Creds are in BSPC `CLAUDE.md` — **rotate them for prod** and have Kevin own the new ones; do not copy creds into any doc.

## 2. BSPC edge functions (4)

- [ ] Deploy `send-notification`, `calendar-feed`, `approve-family`, `cleanup-tokens` (`supabase functions deploy`).
- [ ] Set their server secrets in the Supabase functions env (`SUPABASE_SERVICE_ROLE_KEY`, any push/iCal config). Service-role key **never** ships to a client.

## 3. Storage buckets (4) — per `01_CANONICAL_SCHEMA.sql` Appendix A

| Bucket | Max object | Visibility |
|---|---|---|
| `media-audio` | 100 MB | private |
| `media-video` | 500 MB | private |
| `profile-photos` | 5 MB | private |
| `practice-plans` | 25 MB | private |

- [ ] Create all four, private.
- [ ] **Stay on the free tier for now** (`13 §8` decision 4 — no paid Supabase yet). The read-only **§B0 probe sizes the real media footprint first**; only revisit a paid tier if the actual bytes exceed free-tier headroom before the §B1 copy.
- [ ] **Enforce media consent at the storage policy layer** (not just client code) — this is part of the Gate-1 fix (`14 §4`); lock `profile-photos` reads to authorized guardians/staff, not "any authenticated user."

## 4. Coach Functions → Supabase wiring (CI gap)

The Coach Cloud Functions now read/write **Supabase**, but `functions-deploy.yml` currently provides only `FIREBASE_TOKEN`. **[Director Ruling 03 — the v1 export surface, config design, and media/attendance posture are now ruled; full detail in `17 §8`.]**

- [ ] **Initial v1 launch export set = exactly TWO scheduled functions** — `sweepAttendanceEvaluations` + `dailyDigest`. Proven by the Ruling-03 callable-auth audit (NOTES §6): the coach mobile app and the Supabase-native BSPC parent app call **none** of the callables; `redeemInvite` + `getParentPortalDashboard` + `getParentSwimmerPortalData` are **parent-portal-only (fast-follow)**; `evaluateAttendanceRules` is **deferred (Option C)** and its client kick removed (Proposal D); the AI trio is omitted (media-no-AI). **[Director Ruling 04 + 05 — RATIFIED.]** **Proposal A makes `functions/src/index.ts` export exactly those two** (a test asserts the exact two-name set) — the eight non-v1 exports (AI trio, `evaluateAttendanceRules`, **all three portal callables**, **and `syncCalendar`**) are **removed from the export surface, not merely left undeployed** — so a broad CI deploy cannot resurrect an excluded function. **`syncCalendar` is a conditionally approved follow-on** (Ruling 05 §1): **not** in the initial export set, **never** a self-skipping placeholder; added only by a later, separate change once a real production calendar feed is proven (public vs private/tokenized, config bound safely, URL never logged, tests green, target-gated deploy reviewed).
- [ ] **Config design — parameterized (Director Ruling 03 §3):** `SUPABASE_URL` = required **non-secret parameter** (no default/placeholder); `SUPABASE_SERVICE_ROLE_KEY` = **Secret Manager** parameter bound **only** to functions that use the service-role client; `CALENDAR_ICS_URL` = **follow-on only** — not provisioned, bound, or deployed during the initial two-function launch; *when* the `syncCalendar` follow-on is approved it binds as **sensitive** to `syncCalendar` only, **never logged**. **Remove all `YOUR_PROJECT`/`YOUR_SERVICE_ROLE_KEY` fallbacks**; do **not** read params during global module init (runtime-safe init); **missing config must stop deployment/initialization cleanly.**
- [ ] **CI secret boundary (Director Ruling 06 §4).** `SUPABASE_SERVICE_ROLE_KEY` **remains in Firebase Secret Manager**, and the source binds it through `defineSecret` to the permitted functions; its **value does not enter GitHub Actions secrets, workflow env, YAML, command arguments, logs, or files.** **CI carries deployment authentication only.** `SUPABASE_URL` uses the **approved non-secret parameter mechanism** (`defineString`). If a non-interactive CI ever needs parameter material, document that mechanism **separately** — never conflate it with the service-role secret.
- [ ] **`PROCESS_SHARED_SECRET` is NOT a v1 requirement** (Ruling 03 §2): its only consumers are the deferred `evaluateAttendanceRules` and the omitted AI `processSession` — the v1 export surface has no consumer, so it is **future-only**. `GCLOUD_PROJECT` / Vertex config are AI-only → not v1. (Both corrected from the earlier "required for v1" note.)
- [ ] **v1 media posture (`13 §8` decision 4):** *V1 supports private audio and video capture, upload, storage, retrieval, and playback. V1 performs no audio or video AI analysis and sends no minors' media to an AI provider.* Delivered by **Proposal C** (client hard-disable, **no re-enable switch**, **audio + video parity**) + **Proposal A** (exact-two export surface — drops the AI exports) — see the four release-hardening proposals (`17` / Ruling-03 packet). **Compliance:** minors' media *is* collected at launch → media-consent + disclosure (`14`/`15`) stays fully in scope; storage sizing (§B0 probe, `§3`) is load-bearing.
- [ ] **Four separate release-hardening changes + the identity-remediation script — a BINDING ORDER (Ruling 04): A → B → C → D → identity, one at a time, each ratified + committed before the next is begun.** Each is its own change, test run, Director review, and commit; do **not** bundle: **A** export surface = **exact two** (`index.ts` exports only `sweepAttendanceEvaluations` + `dailyDigest`; `syncCalendar` a conditional follow-on) · **B** Functions config hardening · **C** client media-no-AI (hard-disabled, **covers BOTH audio and video**) · **D** client attendance-kick removal (removes the dead `PROCESS_*` client config **only after a repo-wide zero-consumer proof**). **C and D must not be combined.**
- [ ] (Hardening) `functions-deploy.yml` deploys via an unpinned `@master` action with `--force`, and `eas-build.yml` runs no tests before a prod build — pin/guard before relying on them.

## 5. Environment-variable matrix (set values at provisioning; never commit them)

| Surface | Vars | Set where |
|---|---|---|
| BSPC mobile | `EXPO_PUBLIC_SUPABASE_URL`, `…_ANON_KEY` (a.k.a. publishable), `…_SENTRY_DSN`, `…_POSTHOG_KEY`, `…_POSTHOG_HOST`, `…_EAS_PROJECT_ID` | EAS env / build |
| Coach mobile | `EXPO_PUBLIC_SUPABASE_URL`, `…_ANON_KEY`, `…_SENTRY_DSN` | EAS env / build |
| Parent-portal | `NEXT_PUBLIC_SUPABASE_URL`, `…_ANON_KEY` | web host env |
| BSPC edge fns | `SUPABASE_SERVICE_ROLE_KEY` | Supabase fns env |
| Coach fns *(initial v1 = 2 schedulers)* | `SUPABASE_URL` (non-secret param), `SUPABASE_SERVICE_ROLE_KEY` (Firebase Secret Manager, source-bound) | Firebase parameterized config + Secret Manager; CI carries deployment authentication only |

> **`CALENDAR_ICS_URL` — follow-on only (Director Ruling 06 / 07).** Removed from the initial v1 matrix above. It applies **only** to a later `syncCalendar` change: **not provisioned, bound, or deployed initially**; treated as **sensitive**; bound **only** to `syncCalendar`; **never logged**.

⚠️ **[Director Ruling 03]** `EXPO_PUBLIC_PROCESS_SHARED_SECRET` and `EXPO_PUBLIC_PROCESS_FUNCTIONS_BASE_URL` are **removed from the v1 matrix** — the repo-wide caller audit (NOTES §6) proves their only client consumers are the removed attendance kick (Proposal D, `attendancePipeline.ts:13,17`) and the hard-disabled AI media POST (Proposal C, `mediaPipeline.ts:14,18`). Historically the shared secret shipped in the client bundle and was effectively public; that exposure is now **moot for v1** (`evaluateAttendanceRules` deferred under Option C, no exported v1 function reads `PROCESS_SHARED_SECRET`). The secret is **future-only**, reinstated only if/when an authenticated HTTP endpoint ships post-v1.

## 6. First admin / super_admin — NO bootstrap script needed

**Verified 2026-06-22** (`backfill-identity-graph-plan.ts:249-264`): Kevin's `super_admin` is **not** created from scratch — the **cutover promotes his existing Firebase coach identity**. `--super-admin-uid` must match a coach that already exists in the live Firebase data (NM-1: "Kevin is the sole super_admin"); that identity gets `role: 'super_admin'`, every other coach gets `coach_admin`. A standalone "create admin" script would **collide** with this and bypass the deliberate NM-1 confirm-the-roster safeguard — so we do **not** write one.

- [ ] **Pre-cutover smoke testing** → use the seeded **demo-admin** account (§1). No new admin needed before the cutover.
- [ ] **Kevin's real super_admin uid** → captured by the read-only **§B0 probe** (his coach doc), confirmed by Kevin, passed to `backfill-identity-graph --super-admin-uid=` at Sitting 2.
- [ ] **Kevin's identity (Director Ruling 06 — precise state):** Kevin reports **no Firebase coach document exists for him**; whether his **Firebase Auth identity** exists is **not yet proven**. This is settled by the **dedicated identity-remediation sitting (`20`), which runs BEFORE §B0** — **not** by `create-coach.ts`, the Coach app's add-coach/self-onboarding flow, or any hand-minted Supabase admin / alternative Supabase minting path (all removed). No standalone `super_admin` (the cutover mints it by UID match). **[Director Ruling 03 §4]** The remediation design (`20`) is **blessed in concept, not for execution**: Branch A (one existing Firebase Auth identity + zero matching coach docs) may proceed **only after the Director reviews the implementation evidence** — the remediation-script diff + its tests; Branch B (no Firebase Auth identity at all) = **immediate STOP + a separate bootstrap proposal.** **[Director Ruling 04 §6]** The write is further constrained: a **create-only operation (or transaction precondition)** that cannot overwrite a concurrently-created document (no unconditional `.set()`); Kevin's email + UID **never** in argv, shell history, output, NOTES, tests, or logs (collected interactively, never persisted); an **ambiguous write/network outcome = STOP, no blind delete**; reversal **only after** known-successful creation + deterministic verification. Execution stays **HELD** pending the script diff + tests.

## 7. Observability + accounts

- [ ] Create **Sentry** + **PostHog** projects; capture DSN/keys into the env matrix.
- [ ] Confirm **Apple Developer ($99)** + **Google Play ($25)** memberships (per BSPC `CLAUDE.md`, already covered).
- [ ] Initialize **EAS for BSPC** under `owner: kevinbigham` (to match Coach) so both apps share one org/account — this fills BSPC's empty `projectId`/`updates.url`.

## 8. Ownership split

- **Kevin-owned:** create accounts, billing/storage tier, all secrets/keys, store-account confirmation, running each command after KEY-SAFETY confirmation.
- **Executor-preppable now (no prod access):** the `db push` / `functions deploy` / bucket command sequences, the Supabase bootstrap script (§6), the env matrix, the CI secret wiring patch (§4).

## 9. Exit criteria (Phase 1 done → director may schedule Sitting 2)

- [ ] Prod Supabase live: schema + RLS + 4 edge fns + 4 buckets + auth (reset template) + rotated demo accounts.
- [ ] Coach functions deploy with Supabase secrets present.
- [ ] First `super_admin` minted; Kevin's real uid captured.
- [ ] Env matrix populated across all surfaces; Sentry/PostHog live; BSPC wired into EAS.
- [ ] Green bars re-confirmed read-only (BSPC `TZ=UTC`; Coach `--legacy-peer-deps`).
