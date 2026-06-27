# 17 — PRODUCTION BACKEND RUNBOOK (executable command pack)

**Status:** DRAFT — **NOT READY-TO-RUN.** Reconciled to **Director Ruling 05** (2026-06-23): the **initial v1 export set is RATIFIED at exactly TWO scheduled functions** (`sweepAttendanceEvaluations` + `dailyDigest`); **`syncCalendar` is a conditionally approved follow-on** (not an initial export, not a self-skipping placeholder); Option C and parameterized config selected; media-no-AI is a **hard client-disable, no re-enable switch, covering BOTH audio and video**; the four changes + identity script land in a **binding order A→B→C→D→identity, one at a time.** The blockers below must clear before any hosted command runs. Do not run any hosted command until the Director clears this doc.
**Relationship to `16`:** `16_PROD_BACKEND_PROVISIONING.md` is the *checklist* (what must become true and why). **This doc is the *hands-on-keyboard command sequence*** that makes it true. Run them in order; each is **Kevin-live**.
**This file is not the cutover.** Standing up the backend (this doc) is Phase 1. The Sitting-2 cutover (`06` PART B) is a separate, **director-scheduled** operation that runs *after* every exit criterion here is green.

### ⛔ NOT READY-TO-RUN — blockers (Director Ruling 04; allow-list RATIFIED, implementations not landed)

> **Binding order (Ruling 04):** the four changes + the identity script land **one at a time, each ratified + committed before the next: A → B → C → D → identity-remediation script.** This doc is documentation; **do not begin Proposal A yet.**

1. **Functions config hardening not landed** (§8a) — design **selected** (Ruling 03 §3: `SUPABASE_URL` param, service-role Secret-Manager bound per-function, `CALENDAR_ICS_URL` sensitive, runtime-safe lazy init, **no placeholders**, **missing-config-stops-deploy**). **Proposal B** — frozen-repo, own commit. Not yet implemented/tested.
2. **`evaluateAttendanceRules` — Option C selected** (Ruling 03 §2): do not export/deploy; **remove the client kick** (**Proposal D**); rely on the 5-min `sweepAttendanceEvaluations`. Not yet landed.
3. **Media-no-AI not landed** — drop the 3 AI exports (**Proposal A**) **and** hard-disable the client with **no re-enable switch** (**Proposal C**, Ruling 03 §C — supersedes the earlier `EXPO_PUBLIC_MEDIA_AI_ENABLED` flag idea). Two separate frozen-repo commits.
4. **v1 export surface not yet pinned** — the **initial export set is RATIFIED at exactly TWO** (Ruling 05 §1: `sweepAttendanceEvaluations` + `dailyDigest`; callable-auth audit, §8b / NOTES §6). But **Proposal A** (make `index.ts` export *exactly* those two; remove the eight non-v1 exports — AI trio, `evaluateAttendanceRules`, three portal callables, **and `syncCalendar`**; add a test asserting the **exact two-name export set** so a broad CI deploy cannot resurrect an excluded function) is **not yet implemented/committed.** `syncCalendar` is a **conditionally approved follow-on** (added only by a later separate change once a real production calendar feed is proven), never an initial export or self-skipping placeholder.
5. **Kevin identity remediation not executed** (`20`) — **blessed in concept only** (Ruling 03 §4); Branch A needs Director review of the script diff+tests; Branch B = STOP + separate bootstrap proposal.
6. **Production exit criteria not completed** (§11).

---

## 🔒 KEY-SAFETY — the gate pattern (read once, applies to every step)

Before **any** command that touches a hosted project, the executor prints the **target** and waits for Kevin's explicit "go":

> **TARGET → Supabase URL:** `https://<ref>.supabase.co`  (and for any Firebase touch, the **project_id only** — never a secret)
> **Kevin, confirm this is the PROD project before I run the next command. (yes / no)**

Hard rules, no exceptions:
- **Never** read, print, paste, or commit `.env*`, service-account JSON, private keys, or any secret **value**. Set secrets by typing them into the provider prompt / dashboard — never echo them into a doc, a log, or the chat.
- **Never** `git add .` / `git add -A`. The app repos stay frozen (BSPC `880aed8`, Coach `0c0f82b`); this runbook edits **no app code**.
- **One command at a time.** Propose → confirm target → run → **inspect the output for secrets, PII, account identifiers, roster data, and media metadata, then record only sanitized output in `NOTES.md`** (sensitive findings as path/category or count/status only — never a secret value, UID, email, minor, or roster value) → next.
- **No paid Supabase tier** (`13 §8` decision 4). **Do not deploy the AI pipelines** (`§8` below).
- If anything surprises you (a migration error, an unexpected bucket, a secret already set) — **STOP and surface it.** Never improvise a fix on prod.

---

## 1. Pre-flight — local checks plus one target-gated, read-only Firebase prerequisite

- [ ] **Tooling:** `supabase --version` (CLI present), `firebase --version`, `eas --version`, `node --version`. Record the version strings in `NOTES.md` (version strings only — inspect first; no secrets).
- [ ] **Accounts ready (Kevin-owned):** Supabase org, Firebase project (existing Coach project), Apple Dev ($99) + Google Play ($25) confirmed, Sentry + PostHog orgs creatable.
- [ ] **Decisions in force:** free tier only · defer AI for **both video and audio** (Ruling 04 §4 — audio parity, no longer "recommended") · initial v1 surface = **exactly 2 schedulers RATIFIED** (`syncCalendar` a conditional follow-on) · launch the two mobile apps, portal fast-follow.
- [ ] **Firebase scheduled-function prerequisite (Director Ruling 06 §6 / 07 — the one hosted touch in pre-flight; target-gated, read-only):** **before the read, print the Firebase `project_id` only; Kevin explicitly approves the read target; no approval = STOP.** Then confirm (read-only) the existing Firebase project **supports the two scheduled Functions + Cloud Scheduler**. Record **billing-plan/status only** (no billing identifiers). A **billing-plan change requires Kevin's explicit founder approval** and the normal target gate. **No scheduled-function deployment until this prerequisite is proven.**
- [ ] **Source of truth paths** (verified 2026-06-22):
  - BSPC Supabase root → `/Users/kevin/bspc-unify/BSPC/ACTIVE/supabase`
  - Coach Functions root → `/Users/kevin/bspc-unify/BSPC-Coach-App/functions`
  - Canonical schema → `/Users/kevin/bspc-unify/UNIFY/01_CANONICAL_SCHEMA.sql` (storage spec at **Appendix A**, lines 1218–1266)

---

## 2. Create + link the production Supabase project

- [ ] **Create the project** in the Supabase dashboard (Kevin, in browser): org = Kevin's; **Region = US**; **Postgres 17** (matches `config.toml major_version = 17`). Set a strong DB password (Kevin stores it in his password manager — never in a file here).
- [ ] Capture the **project ref** + **URL**. Inspect first, then record *only the URL/ref* in `NOTES.md` (these are not secrets; record nothing else).

🔒 **TARGET confirm**, then link the local CLI to the remote project:

```bash
cd /Users/kevin/bspc-unify/BSPC/ACTIVE/supabase
supabase login            # opens browser / pastes a CLI token — token is a SECRET, never echo it
supabase link --project-ref <PROD_REF>
```

- [ ] Verify: `supabase projects list` shows the prod project as **linked** (●).

---

## 3. Push the schema — this also creates the buckets

`supabase db push` applies all **13** migrations to the linked remote. **Finding (verified):** migrations **`00007_phase_f_media.sql`** and **`00009_phase_h_calendar_meets_plans.sql`** contain `INSERT INTO storage.buckets …` and the `storage.objects` RLS policies — so **the push creates all four buckets and their access policies automatically.** There is **no** separate "create buckets" step.

🔒 **TARGET confirm (this WRITES to prod)**, then:

```bash
supabase db push        # applies 00001 … 00013 in order
```

The 13 migrations that must apply (confirm each in the output):

```
00001_initial_schema              00008_phase_g_notifications
00002_phase_a_identity            00009_phase_h_calendar_meets_plans   ← creates practice-plans bucket
00003_phase_b_swimmers            00010_phase_i_parent_invites
00004_phase_c_attendance          00011_phase_j_aggregations
00005_phase_d_times               00012_cutover_realtime_staff_admin
00006_phase_e_notes               00013_cutover_parent_read_gaps
00007_phase_f_media   ← creates media-audio / media-video / profile-photos buckets + storage RLS
```

- [ ] **Inspect the push output, then record only sanitized output in `NOTES.md`** (migration names + applied/failed status; sensitive findings as path/category or count/status only — no secret, PII, or roster value). **If any migration errors, STOP** — do not `--force`, do not hand-edit prod. Surface it.

---

## 4. Verify schema · buckets · RLS (read-only checks in the SQL editor)

Run these as read-only confirmations (Supabase Studio → SQL editor, or `supabase db` query):

- [ ] **Buckets exist, private, correct limits** (must return exactly these four):

```sql
select id, public, file_size_limit, allowed_mime_types
from storage.buckets order by id;
-- expect: media-audio 104857600 {audio/*} | media-video 524288000 {video/*}
--         practice-plans 26214400 {application/pdf} | profile-photos 5242880 {image/*}   (all public=false)
```

- [ ] **Storage RLS is on + staff-gated** (the Gate-1-relevant policies):

```sql
select policyname from pg_policies where schemaname='storage' and tablename='objects' order by policyname;
-- expect: media_audio_staff, media_video_staff, profile_photos_staff, practice_plans_files_owner
```

  > Note for Gate 1: on **Supabase**, `profile-photos` is **staff-only** (`profile_photos_staff`) — the "any authenticated user can read a minor's photo" problem was the *Firebase transitional* rule, not the target. Parents receive **signed capability URLs** only (Appendix A). The remaining Gate-1 storage work is pushing *consent* (not just staff-role) into the policy — track in `14`/`15`, **not** here.

- [ ] **RLS is enabled on the core tables** (spot-check; the 343 pgTAP tests prove the policy *logic* locally — here we just confirm policies shipped):

```sql
select tablename from pg_policies where schemaname='public' group by tablename order by tablename;
```

---

## 5. Auth configuration (dashboard)

OD-6 imports **no passwords** — every real user does a forced reset/invite at go-live — so the reset path must be staged now.

- [ ] **Enable Email provider** (Auth → Providers → Email): email+password ON.
- [ ] **Password-reset + invite email templates** (Auth → Email Templates): set sender, copy, and the **redirect URL** (the app/portal deep-link that lands the reset). Stage both *reset* and *invite* templates.
  - Staged template files: `auth-email-templates/reset-password.md` and `auth-email-templates/invite-user.md`.
  - Synthetic recovery checklist: `scripts/synthetic-recovery-checklist.sh` prints the no-secrets device checklist and sanitized `NOTES.md` result template. Run it only against a Kevin-approved throwaway target; never with real family data.
- [ ] **Site URL / redirect allow-list:** add the mobile deep-link schemes + the portal origin (once it has a host).
- [ ] Confirm in `NOTES.md`: provider on, templates saved, redirect URL set (no secrets).

---

## 6. Demo accounts (manual — and why there's no bootstrap script)

**Finding (verified):** demo accounts are **not** seeded by SQL. `seed.sql` seeds reference data only (glossary, team records); the demo creds live in its **comments** + BSPC `CLAUDE.md`. Accounts are created in the **Auth dashboard**, and the `handle_new_user()` trigger auto-creates the matching `profiles` row.

- [ ] **Auth → Users → Add user**, twice — create `demo-family` and `demo-admin`. **Rotate the passwords for prod** (do not reuse the dev creds in `CLAUDE.md`; Kevin owns the new ones, stored in his password manager).
- [ ] **Promote demo-admin to `coach_admin`** via the SQL editor (service role bypasses RLS — needed because the escalation guard only lets a *super_admin* change roles, and none exists pre-cutover):

```sql
update public.profiles set role = 'coach_admin'
where id = (select id from auth.users where email = '<the rotated demo-admin email>');
```

- [ ] **No `super_admin` bootstrap script** (verified `backfill-identity-graph-plan.ts:249-264`): Kevin's real `super_admin` is **minted by the cutover**, which *promotes an existing Firebase coach identity* (NM-1). Pre-cutover smoke testing uses **demo-admin**. Do **not** hand-mint a standalone admin in Supabase, and use **no alternative Supabase minting path** — it would collide with the NM-1 promotion. **Identity (Director Ruling 06 — precise state):** Kevin reports **no Firebase coach document exists for him**; whether his **Firebase Auth identity** exists is **not yet proven**. This is settled by the **dedicated identity-remediation sitting (`20`), which runs BEFORE §B0** — **not** by `create-coach.ts`, the Coach app's add-coach/self-onboarding flow, or any improvised seeding path (all removed). **Branch A** (existing Firebase Auth identity **and** zero coach docs) → a **purpose-built create-only remediation only, after Director review** of the script diff + tests; **Branch B** (no Firebase Auth identity) → **immediate STOP + a separate identity-bootstrap proposal.**

---

## 7. BSPC edge functions (deploy 4)

**Finding (verified):** all four functions read **only** `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` via `Deno.env.get()`. Supabase **auto-injects both** into every Edge Function as default secrets — so **no manual `supabase secrets set` is required** for these four. (Re-confirm by skimming each `index.ts` for any *other* `Deno.env.get(...)` before deploy.)

🔒 **TARGET confirm**, then:

```bash
cd /Users/kevin/bspc-unify/BSPC/ACTIVE/supabase
supabase functions deploy send-notification
supabase functions deploy approve-family
supabase functions deploy cleanup-tokens
supabase functions deploy calendar-feed     # if this serves a public iCal URL, it may need --no-verify-jwt — check its index.ts first
```

- [ ] Verify each shows **deployed** in the dashboard (Edge Functions list) and `supabase functions list` matches.
- [ ] `cleanup-tokens` is a sweeper → confirm/stage its **schedule** (cron) if it relies on one.
- [ ] **Inspect the deploy output, then record only sanitized output → `NOTES.md`** (function names + deployed/failed status; no secret value or URL; sensitive findings as path/category or count/status only).

---

## 8. Coach Cloud Functions → Supabase wiring (the CI gap) + the AI-defer scope cut

The Coach Functions are **Firebase-hosted compute that now read/write Supabase**, but `functions-deploy.yml` currently provides **only `FIREBASE_TOKEN`**. They need the Supabase secrets, and the AI pipelines must be **left off** for v1.

### 8a. Runtime configuration — parameterized (Director Ruling 03 §3 — REQUIRES Proposal B first)

> **Blocked until Proposal B lands.** Today the source reads **plain `process.env`** with **placeholder fallbacks** (`functions/src/config/supabase.ts:8-9`: `?? 'https://YOUR_PROJECT.supabase.co'` / `?? 'YOUR_SERVICE_ROLE_KEY'`) **at module load** — a misconfigured deploy boots **green and fails open.** Ruling 03 §3 requires removing that and adopting params/secrets with runtime-safe init. **Do not provision config against the unhardened source.**

Selected design (implement in Proposal B, then provision):
- `SUPABASE_URL` — required **non-secret parameter** (`defineString`), **no default/placeholder**.
- `SUPABASE_SERVICE_ROLE_KEY` — **Secret Manager** parameter (`defineSecret`), bound **only** to functions that use the service-role client.
- `CALENDAR_ICS_URL` — **follow-on only; NOT provisioned, bound, or deployed during the initial two-function launch** (see the `syncCalendar` follow-on note in §8b). *When* the `syncCalendar` follow-on is later approved it binds as **sensitive** (`defineSecret`), to `syncCalendar` only, **never logged**.
- **No global-init reads** — construct the Supabase client **lazily inside the handler**; **missing config throws and stops deployment/initialization cleanly** (fail-closed).

🔒 **Firebase project_id confirm** (print project_id only), then — for the initial v1 surface (the 2 schedulers only; `syncCalendar` follow-on / `redeemInvite` / portal callables / `evaluateAttendanceRules` / AI are NOT deployed):

```bash
cd /Users/kevin/bspc-unify/BSPC-Coach-App/functions
firebase functions:secrets:set SUPABASE_SERVICE_ROLE_KEY    # PROD service-role key — RUNTIME SECRET, server-only; bound per-function. Stays in Firebase Secret Manager; its VALUE never enters GitHub Actions secrets, workflow env, YAML, argv, logs, or files.
# SUPABASE_URL is a NON-secret param (defineString), set via param/env config, NOT secrets:set.
# CALENDAR_ICS_URL is NOT set here — syncCalendar is a follow-on, not part of the initial two-function launch (see §8b). No calendar config is provisioned, bound, or deployed now.
# PROCESS_SHARED_SECRET is NOT set for v1 — no exported v1 function consumes it (Ruling 03 §2). Future-only.
```

- [ ] **CI injects only `FIREBASE_TOKEN`** — the data-plane secret + param must exist in the runtime independent of CI. With `defineSecret`, a required-but-unbound secret makes the **deploy fail closed** (the desired behavior).
- [ ] **Verify fail-closed:** after Proposal B, a deploy with the secret unbound must **refuse to deploy** (not boot green). Prove a real Supabase call succeeds before trusting any write.

### 8b. v1 launch export surface — the TWO scheduled functions (Director Ruling 05)

**Canonical media statement (verbatim):** *V1 supports private audio and video capture, upload, storage, retrieval, and playback. V1 performs no audio or video AI analysis and sends no minors' media to an AI provider.*

The Ruling-03 callable-auth audit (NOTES §6) closes the export question. A Firebase **callable's `request.auth` does not verify a Supabase token after cutover**, and no launching surface calls the callables anyway (coach mobile + the Supabase-native BSPC parent app use Supabase Auth and call none of them).

- [ ] **Initial v1 DEPLOY set — exactly 2 scheduled functions (RATIFIED, Ruling 05 §1):** `sweepAttendanceEvaluations` + `dailyDigest`. Platform-triggered (Cloud Scheduler) → no client token → immune to the callable-auth problem. **`syncCalendar` is a conditionally approved follow-on — NOT in the initial deploy** (Ruling 05 §1): add it only by a later, separate, target-gated change once a real production calendar feed is proven (public vs private/tokenized, `CALENDAR_ICS_URL` bound safely + never logged, tests green). Never deploy it as a self-skipping placeholder.
  `--only functions:sweepAttendanceEvaluations,functions:dailyDigest`
- [ ] **v1 OMIT set + why:**
  - `processAudioSession`, `processVideoSession`, `sweepStuckSessions` — **media-no-AI** (Proposal A drops the exports; Proposal C hard-disables the client).
  - `evaluateAttendanceRules` — **Option C** (Ruling 03 §2): deferred; the 5-min `sweepAttendanceEvaluations` runs the identical core; the client kick is **removed** (Proposal D).
  - `redeemInvite`, `getParentPortalDashboard`, `getParentSwimmerPortalData` — **parent-portal-only / fast-follow.** Mobile invite-redemption is the `auth.uid()`-gated Supabase RPC `redeem_parent_invite` (BSPC `00010_phase_i_parent_invites.sql`, pgTAP-tested); `redeemInvite` is already a thin shell over that RPC (`06 §B6` C2). **[Ruling 04/05] These three callables — plus `syncCalendar` — are *removed from the v1 export surface* (Proposal A exact-two), not merely undeployed.** The portal's own data lib already uses direct Supabase reads/RPC (`parent-portal/src/lib/parentPortal.ts:149/175/267`), so even the fast-follow portal does not call the Firebase callables; any future portal server endpoint is a separate authorization.
- [ ] **Initial export set RATIFIED (Ruling 05 §1).** The initial v1 Firebase-hosted surface is exactly these **two** scheduled functions (`sweepAttendanceEvaluations` + `dailyDigest`); nothing else. `syncCalendar` is a conditionally approved follow-on.
- [ ] **Exact-two export surface (Proposal A, Ruling 05 §1).** `functions/src/index.ts` must export **exactly** the two scheduled functions (`sweepAttendanceEvaluations` + `dailyDigest`) — the eight non-v1 exports (AI trio, `evaluateAttendanceRules`, three portal callables, **and `syncCalendar`**) **removed** — with a test asserting the **exact two-name export set** (not mere presence/absence) so a broad CI deploy **cannot resurrect** an excluded function. CI today deploys bare `--only functions --force` → whatever is exported deploys; pinning the export set is what makes the surface safe. **Existing hosted copies** of excluded functions need a **read-only inventory** now and a **later `project_id` + Kevin-go removal sitting** — **no hosted removal is authorized now.**
- [ ] **`PROCESS_SHARED_SECRET` NOT required for v1** (Ruling 03 §2) — no exported v1 function consumes it (future-only). Vertex / `GCLOUD_PROJECT` not needed.
- [ ] **Client media-no-AI = HARD-DISABLED, no switch — BOTH audio and video (Proposal C, Ruling 04 §4).** The app auto-fires the AI POST on every upload (`src/services/mediaPipeline.ts:14`, via `audio.ts:209` / `video.ts:438` + offline replay in `app/(tabs)/index.tsx`). v1 must inventory and address **every** path for **both** media types — capture, upload, automatic processing request, offline processing replay, status/loading view, notification/deep-link entry, AI review/results entry, retrieval, playback. **Acceptance:** audio **and** video capture/upload/storage/retrieval/playback work; **neither** invokes processing; **no background path can restart AI**; **uploaded** is an honest terminal v1 state (no "AI analysis starting"/analyzing/permanent-loading copy); all AI review/results entry points hidden or honestly unavailable; **no `EXPO_PUBLIC` re-enable switch**; **no test deletion**; the exact client count **holds or rises.**
- [ ] **Compliance:** minors' audio/video *are* captured at launch → media-consent + disclosure (`14`/`15`) stays fully in scope.

### 8c. CI patch (`.github/workflows/functions-deploy.yml`)

- [ ] **CI carries deployment authentication only (Director Ruling 06 §4).** `SUPABASE_SERVICE_ROLE_KEY` **stays in Firebase Secret Manager** (bound per-function via `defineSecret`); its **value does not enter GitHub Actions secrets, workflow env, YAML, command arguments, logs, or files.** `SUPABASE_URL` is supplied through the **approved non-secret parameter mechanism** (`defineString` param/env config), **not** as a CI secret. `CALENDAR_ICS_URL` is **omitted** — `syncCalendar` is a follow-on, not in the initial launch. **Not** `PROCESS_SHARED_SECRET` (no v1 consumer). With `defineSecret`, the deploy **fails closed** if a bound secret is missing. If a non-interactive CI ever needs parameter material, document that mechanism **separately** — never conflate it with the service-role secret.
- [ ] **Hardening (flag, not blocker):** the workflow deploys via `w9jds/firebase-action@master` (floating) with `--force`, and `eas-build.yml` runs **no tests** before a prod build. Pin the action to a SHA/tag and add a test gate before relying on either for a real release.

> This 8c YAML edit is the one place this runbook touches a repo file. It's CI plumbing, not app logic — but the Coach repo is baseline-frozen at `0c0f82b`, so **get the director's OK** before committing it, and commit it on its own.

---

## 9. Environment-variable matrix (populate per surface)

Values are set at provisioning and **never committed**. The full matrix is `16 §5`; the commands are:

- [ ] **BSPC mobile** (EAS env): `EXPO_PUBLIC_SUPABASE_URL`, `…_ANON_KEY`, `…_SENTRY_DSN`, `…_POSTHOG_KEY`, `…_POSTHOG_HOST`, `…_EAS_PROJECT_ID`
  `eas env:create --scope project --name EXPO_PUBLIC_SUPABASE_URL --value <url> --visibility plaintext` (repeat; mark keys **sensitive**).
- [ ] **Coach mobile** (EAS env): `EXPO_PUBLIC_SUPABASE_URL`, `…_ANON_KEY`, `…_SENTRY_DSN`.
  ⚠️ **[Director Ruling 03]** `EXPO_PUBLIC_PROCESS_SHARED_SECRET` + `EXPO_PUBLIC_PROCESS_FUNCTIONS_BASE_URL` are **removed from the v1 matrix.** The repo-wide caller audit (NOTES §6) proves their only client consumers are the **removed** attendance kick (`attendancePipeline.ts:13,17`, Proposal D) and the **hard-disabled** AI media POST (`mediaPipeline.ts:14,18`, Proposal C) — so the v1 client has no consumer. Future-only.
- [ ] **Parent-portal** (web host env, fast-follow): `NEXT_PUBLIC_SUPABASE_URL`, `…_ANON_KEY`.
- [ ] The **anon/publishable** key is safe in clients; the **service-role** key is server-only (edge fns auto-have it; Coach fns via §8a) — **never** in any client surface.

---

## 10. Observability + EAS init for BSPC

- [ ] **Sentry** + **PostHog** projects → capture DSN/keys into the §9 matrix.
- [ ] **BSPC into EAS** (fills its empty `projectId`/`updates.url`; match Coach's `owner: kevinbigham`):

```bash
cd /Users/kevin/bspc-unify/BSPC/ACTIVE          # (or wherever app.json/eas.json lives — confirm first)
eas init --id   # creates/links the EAS project; writes projectId
```

  ⚠️ This **writes to app.json/eas.json in the frozen BSPC repo.** Get the director's OK first; commit on its own, clearly scoped.

---

## 11. Exit criteria — Phase 1 done → director may schedule Sitting 2

(Mirrors `16 §9`; tick all before greenlighting the cutover.)

- [ ] Prod Supabase live: 13 migrations applied · RLS present · 4 buckets verified (private, correct limits) · 4 edge fns deployed · Email auth + reset/invite templates staged · **rotated** demo accounts (demo-admin promoted).
- [ ] Coach Functions: **Proposal B config hardening landed** (parameterized, fail-closed, no placeholders); **`index.ts` exports exactly the 2 schedulers** (Proposal A; AI trio + `evaluateAttendanceRules` + 3 portal callables + `syncCalendar` removed from the export surface, two-name pin test green); `syncCalendar` added only later as the approved follow-on once its calendar source is proven; secrets **bound** & verified in logs; deploy **fails closed** when a bound secret is unset.
- [ ] **Firebase scheduled-function prerequisite proven (Director Ruling 06 §6):** read-only confirmation the existing Firebase project supports the two scheduled Functions + Cloud Scheduler; **billing-plan/status recorded (no billing identifiers)**; any plan change had Kevin's explicit founder approval + target gate. **No scheduled-function deploy occurred before this was proven.**
- [ ] Env matrix populated across BSPC + Coach (portal deferred); Sentry/PostHog live; BSPC wired into EAS.
- [ ] No secret value ever printed/committed; every command's output **inspected for secrets/PII/account-identifiers/roster/media-metadata and recorded *sanitized*** in `NOTES.md` (sensitive findings as path/category or count/status only).
- [ ] Green bars re-confirmed read-only (BSPC `TZ=UTC` → 835 jest / 343 pgTAP · Coach `--legacy-peer-deps` → the **then-current blessed Coach baseline** — 1199 / 115 today, adjusted by the Proposals A–D commits once blessed).

---

## 12. Guardrails recap (the do-NOT list)

- ❌ No paid Supabase tier. ❌ No `processVideoSession` / `processAudioSession` / `sweepStuckSessions` deploy or secrets (media-no-AI, **audio + video**). ❌ No `evaluateAttendanceRules` or portal-callable deploy in v1 (Option C / fast-follow). ❌ `index.ts` must export **exactly** the 2 schedulers (`sweepAttendanceEvaluations` + `dailyDigest`) — never re-export an excluded function (Proposal A two-name pin test). ❌ `syncCalendar` is NOT in the initial set — add it only via the later target-gated follow-on once a real calendar feed is proven; never as a self-skipping placeholder. ❌ No placeholder config fallbacks — deploy must **fail closed**. ❌ Never log `CALENDAR_ICS_URL`. ❌ No **real recovery-email delivery** and **no Firebase sign-in shutdown** until the recovery path is proven (custom SMTP + send-rate capacity + redirect/deep-link + one synthetic e2e mobile recovery test); the pre-cutover announcement may still go out through the existing verified team channel. ❌ Do not begin Proposals A/B/C/D out of order — binding order **A→B→C→D→identity**, one at a time, each ratified + committed first. ❌ No standalone `super_admin` bootstrap (the cutover mints it). ❌ No `git add .`. ❌ No secret values in files/logs/chat. ❌ No `--force` migration edits on prod. ❌ Do not start Sitting 2 — that's director-scheduled, after these exit criteria.
- ✅ Print target + confirm before every hosted command. ✅ One command at a time, **sanitized** output → `NOTES.md`. ✅ Surface every surprise; never silently fix prod.
