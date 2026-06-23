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
- [ ] **Auth** — enable email/password. Stage the **password-reset email template + redirect URL** (required: OD-6 imports no passwords, so every user does a forced reset/invite at go-live).
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

The Coach Cloud Functions now read/write **Supabase**, but `functions-deploy.yml` currently provides only `FIREBASE_TOKEN`.

- [ ] Provide `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` to the functions runtime (Firebase Functions secrets) **and** in CI.
- [ ] Also set `PROCESS_SHARED_SECRET`, `CALENDAR_ICS_URL`, `GCLOUD_PROJECT` / Vertex config.
- [ ] **v1 scope cut (`13 §8` decision 4):** the **video AI pipeline (`processVideoSession`, Vertex/Gemini) is deferred** — do not enable/deploy it for v1. This drops the Vertex video cost and removes minors'-video-to-third-party-AI from launch (a Gate-1 win, `14 §7.5`). *(Recommend deferring `processAudioSession` likewise — pending Kevin's confirm.)*
- [ ] (Hardening) `functions-deploy.yml` deploys via an unpinned `@master` action with `--force`, and `eas-build.yml` runs no tests before a prod build — pin/guard before relying on them.

## 5. Environment-variable matrix (set values at provisioning; never commit them)

| Surface | Vars | Set where |
|---|---|---|
| BSPC mobile | `EXPO_PUBLIC_SUPABASE_URL`, `…_ANON_KEY` (a.k.a. publishable), `…_SENTRY_DSN`, `…_POSTHOG_KEY`, `…_POSTHOG_HOST`, `…_EAS_PROJECT_ID` | EAS env / build |
| Coach mobile | `EXPO_PUBLIC_SUPABASE_URL`, `…_ANON_KEY`, `…_SENTRY_DSN`, `…_PROCESS_FUNCTIONS_BASE_URL`, `…_PROCESS_SHARED_SECRET` | EAS env / build |
| Parent-portal | `NEXT_PUBLIC_SUPABASE_URL`, `…_ANON_KEY` | web host env |
| BSPC edge fns | `SUPABASE_SERVICE_ROLE_KEY` | Supabase fns env |
| Coach fns | `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `PROCESS_SHARED_SECRET`, `CALENDAR_ICS_URL` | Firebase fns secrets + CI |

⚠️ `EXPO_PUBLIC_PROCESS_SHARED_SECRET` ships in the client bundle — it is **effectively public** and provides no real auth on the functions bridge. Flag for a signed-token redesign (security item, not a provisioning blocker).

## 6. First admin / super_admin — NO bootstrap script needed

**Verified 2026-06-22** (`backfill-identity-graph-plan.ts:249-264`): Kevin's `super_admin` is **not** created from scratch — the **cutover promotes his existing Firebase coach identity**. `--super-admin-uid` must match a coach that already exists in the live Firebase data (NM-1: "Kevin is the sole super_admin"); that identity gets `role: 'super_admin'`, every other coach gets `coach_admin`. A standalone "create admin" script would **collide** with this and bypass the deliberate NM-1 confirm-the-roster safeguard — so we do **not** write one.

- [ ] **Pre-cutover smoke testing** → use the seeded **demo-admin** account (§1). No new admin needed before the cutover.
- [ ] **Kevin's real super_admin uid** → captured by the read-only **§B0 probe** (his coach doc), confirmed by Kevin, passed to `backfill-identity-graph --super-admin-uid=` at Sitting 2.
- [ ] `scripts/create-coach.ts` (stale Firebase bootstrap) → **does not need porting** for the cutover path; it retires with the rest of the tooling at `06 §B6`. *(Open question for the director: does NM-1 assume Kevin already exists as a coach doc in the real Firebase data? If not, that's the one identity gap to close — surface it, don't improvise.)*

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
