# 16 — PRODUCTION BACKEND PROVISIONING CHECKLIST

**Status:** DRAFT checklist — prepared by the EXECUTOR seat, 2026-06-22; refreshed for the fresh-launch path on 2026-06-28. `Mission.md` remains the current source of truth.
**This document runs nothing.** It is the ordered plan for standing up the Supabase backend. Every hosted step is **Kevin-live**. Older Firebase migration / Sitting-2 language in this folder is historical under the fresh-launch decision.

> **KEY-SAFETY:** before any command that targets a hosted project, print the target **Supabase URL** (and, for any Firebase touch, the **project_id** only — never secrets) and have Kevin confirm. Never read/print/commit `.env`, service-account, or key files. Never `git add .`.

---

## 0. Why this comes first

Development has run against **local** Supabase. The fresh-launch decision means there is **no Firebase data migration** and no Sitting-2 cutover to schedule. Phase 1 stands up a clean Supabase backend, proves the migrations and RLS on an empty hosted target, deploys the BSPC Edge Functions, and proves the auth recovery path with one throwaway account before any real family data is entered.

## 1. Production Supabase project

- [x] Throwaway hosted target created by Kevin for Phase-1 proof: `https://fqjfunuqbojouyuopnuv.supabase.co`.
- [x] `npm exec -- supabase --agent no link --project-ref fqjfunuqbojouyuopnuv` completed after Kevin's per-command `go`.
- [x] `npm exec -- supabase --agent no db push` completed after Kevin's per-command `go`; hosted DB reported up to date.
- [x] `npm run audit:prod-schema -- --linked` passed on the linked throwaway target: 13 migrations, four private buckets, four storage policies.
- [ ] If this throwaway project is **not** the final production project, Kevin creates the final Supabase project (org owned by Kevin; **US region**; Postgres 17 to match local `config.toml`) and the link/push/audit sequence repeats under the same one-command target gate.
- [ ] **Auth** — enable email/password. Stage the **password-reset email template + redirect URL**. Staging the template is not the same as proven delivery: custom SMTP, confirmed send-rate capacity, a working redirect/deep-link, and **one synthetic end-to-end mobile recovery test** are prerequisites before any real recovery/invite email goes to families. The team announcement may still go through the existing verified team channel when Kevin approves the wording and timing.
  - Staged repo artifacts: `auth-email-templates/reset-password.md`, `auth-email-templates/invite-user.md`, the Kevin-owned dashboard checklist `21_SUPABASE_AUTH_DASHBOARD_CHECKLIST.md`, and the throwaway-only recovery checklist `scripts/synthetic-recovery-checklist.sh`.
- [ ] Seed the **2 demo accounts** (`demo-family` / `demo-admin`). Creds are in BSPC `CLAUDE.md` — **rotate them for prod** and have Kevin own the new ones; do not copy creds into any doc.

## 2. BSPC edge functions (4)

- [x] Run the local readiness audit first: `npm run audit:edge-functions` from `BSPC/ACTIVE` (no hosted target, no secrets).
- [x] Deploy `approve-family`, `calendar-feed`, `cleanup-tokens`, `send-notification` to the throwaway target after four separate Kevin `go` confirmations (`calendar-feed` uses `--no-verify-jwt` because it serves the public iCal subscription URL).
- [ ] If the final production project is a different Supabase project, redeploy the same four functions to that project under separate per-command target gates.
- [ ] Do **not** set manual Supabase function secrets for these four. They read only Supabase's auto-injected `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`; service-role key **never** ships to a client.

## 3. Storage buckets (4) — per `01_CANONICAL_SCHEMA.sql` Appendix A

| Bucket | Max object | Visibility |
|---|---|---|
| `media-audio` | 100 MB | private |
| `media-video` | 500 MB | private |
| `profile-photos` | 5 MB | private |
| `practice-plans` | 25 MB | private |

- [x] Create all four, private, via the migration set on the throwaway target.
- [ ] Repeat/confirm on the final production target if it is not the throwaway project already linked above.
- [ ] **Stay on the free tier for now** (`13 §8` decision 4 — no paid Supabase yet). Revisit a paid tier only if the real media footprint or launch load exceeds free-tier headroom.
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

## 6. First admin / super_admin

Under the fresh-launch path, there is no Firebase identity remediation and no cutover promotion. Milestone 2 owns a **Supabase-native** first-admin bootstrap: public signup closed, exactly one auth user/profile, zero existing staff, exactly one pending family profile promoted to approved `super_admin`, and sanitized output with no email or UUID literal.

- [ ] Draft and test the guarded Supabase-native bootstrap procedure in Milestone 2.
- [ ] Kevin creates his own auth account and gives a separate target-gated `go` before any live promotion.
- [ ] No hand-minted fallback admin, no Firebase UID path, and no account identifiers in command output, notes, tests, or logs.

## 7. Observability + accounts

- [ ] Create **Sentry** + **PostHog** projects; capture DSN/keys into the env matrix.
- [ ] Confirm **Apple Developer ($99)** + **Google Play ($25)** memberships (per BSPC `CLAUDE.md`, already covered).
- [ ] Initialize **EAS for BSPC** under `owner: kevinbigham` (to match Coach) so both apps share one org/account — this fills BSPC's empty `projectId`/`updates.url`.

## 8. Ownership split

- **Kevin-owned:** create accounts, billing/storage tier, all secrets/keys, SMTP sender, auth dashboard settings, store-account confirmation, his own super-admin login, and each hosted command approval after KEY-SAFETY confirmation.
- **Executor-preppable now (no prod access):** the `db push` / `functions deploy` / bucket command sequences, the Supabase bootstrap script (§6), the env matrix, the CI secret wiring patch (§4), and sanitized status notes.

## 9. Exit criteria (Phase 1 done → Milestone 2 may begin)

- [ ] Final Supabase target live: schema + RLS + 4 edge fns + 4 buckets + auth (reset template) + rotated demo accounts.
- [ ] Coach functions deploy with Supabase secrets present.
- [ ] First `super_admin` minted by the Supabase-native bootstrap.
- [ ] Env matrix populated across all surfaces; Sentry/PostHog live; BSPC wired into EAS.
- [ ] Green bars re-confirmed read-only (BSPC `TZ=UTC`; Coach `--legacy-peer-deps`).
