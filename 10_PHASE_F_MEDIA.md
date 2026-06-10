# UNIFY/10 — PHASE F (MEDIA): MINI-PLAN + RED-TEAM

**Status: the scoping tripwire FIRED — the inverted default held. No code has
been written.** This document is the mini-plan + red-team, ending with the
[DECIDE] block. Same drill as C (07) and D (08).

Baseline at investigation: BSPC jest 835 (TZ=UTC) + pgTAP 125 · Coach 998 ·
Functions 119. All repos clean on main, synced.

---

## §0 Why the tripwire fired

Kevin's gate: execute straight through ONLY if the end-state storage home
(and transitional story), the URL/access strategy, the bucket layout, and
file-layer consent gating are ALL already pinned. **None of the four is
pinned anywhere.** 04's entire storage guidance for Phase F is the single
word "storage." 01_CANONICAL_SCHEMA pins the TABLE side completely (six
tables, enums, junctions, the deferred FK block) but is structure-only and
deliberately host-agnostic (`storage_path TEXT`). No UNIFY document mentions
Supabase Storage at all. And the investigation surfaced two hard
architectural couplings no prior phase had:

1. **The auth-cutover coupling.** After the Phase A cutover the apps hold
   SUPABASE auth tokens, not Firebase tokens. Firebase Storage rules
   authenticate `request.auth` — a Firebase token. Post-cutover, client
   uploads/reads against auth-gated Firebase Storage rules CANNOT
   authenticate. "Files stay on Firebase forever" is not a free default; it
   breaks at cutover unless something is engineered around it.
2. **The Vertex AI coupling.** `onVideoUploaded` analyzes >20MB videos by
   passing a `gs://` GCS URI to Vertex (`fileData.fileUri`) — a GCS-only
   API. Files leaving Google-hosted storage breaks the large-video analysis
   path unless the pipeline gains a staging step.

Either coupling alone is [DECIDE] territory. Both at once is the
architecture decision of the whole migration's file tier.

---

## §1 Terrain — what was read end to end

### 1a. Coach client (the six file-touching services)

| Service | Rows/docs side | File side (Firebase Storage path) |
|---|---|---|
| `audio.ts` | `audio_sessions` docs; per-coach subscribe (status machine `uploading→uploaded→transcribing→extracting→review→posted/failed`) | `audio/{coachId}/{date}/audio_{ts}.m4a`, 100MB/audio-mime rule |
| `video.ts` | `video_sessions` docs; `taggedSwimmerIds`+`selectedSwimmerIds` arrays; **consent asserted at create** (`assertCanTagSwimmers`); drafts in SUBCOLLECTION | `video/{coachId}/{date}/video_{ts}.mp4`, 500MB/video-mime rule |
| `aiDrafts.ts` (draft-half) | `audio_sessions/{id}/drafts` subcollection; `subscribePendingDrafts` = N+1 (sessions `status=='review'` then per-session drafts fetch, `approved` unset); approve = draft update + (since E) canonical note insert | — |
| `videoDrafts.ts` (draft-half) | `video_sessions/{id}/drafts`; same approve shape | — |
| `swimmerVoiceNotes.ts` (file-half) | rows already canonical (E) | `audio/swimmers/{swimmerId}/{practiceDate}/{noteId}.m4a` — **nested under the `audio/` prefix**, same wall as session audio; AsyncStorage offline retry queue |
| `profilePhoto.ts` (file-half) | row-write already canonical (B) | `profiles/{swimmerId}/photo.jpg`; the persisted `profile_photo_url` is a host-agnostic capability URL by B's design |

Also in the storage blast radius but NOT Phase F data: `practicePlans.ts`
dashboard PDFs (`practice_plans/{coachId}/{date}/{file}` — plans data is
Phase H) and `imports/` (import_jobs — H/later per B/D deferrals).

**Upload mechanics:** screens (`app/audio.tsx`, `app/video.tsx`) and the
offline-queue flusher (`app/_layout.tsx`) call `uploadAudio`/`uploadVideo`
then flip the session doc to `status: 'uploaded'` — that status flip IS the
pipeline trigger. `downloadUrl` is returned by every upload helper but
**never persisted** for sessions/voice notes; playback derives it fresh from
`storage_path` (`voice-note-recorder.tsx` calls `getDownloadURL` at play
time). The one persisted URL anywhere is `swimmers.profile_photo_url`.
`onProgress` percent callbacks ride `uploadBytesResumable` — part of the
frozen service signatures.

### 1b. Functions (the pipeline)

- **`onAudioUploaded`** — Firestore `onDocumentUpdated(audio_sessions)`,
  fires on status→'uploaded': downloads the file via ADMIN SDK (bypasses
  rules), Vertex Gemini transcription, `extractObservations` writes drafts
  (swimmer reads already canonical since B), status walks to `review`.
- **`onVideoUploaded`** — same trigger shape on `video_sessions`: <20MB
  inline base64, **≥20MB via `gs://` URI**; writes drafts subcollection.
  **Still reads `swimmers/{id}` from FIRESTORE** (deliberately not re-pointed
  in B; the banked F fix — RF-10).
- **`onDraftReviewed`** — audio drafts trigger; when all drafts reviewed,
  flips session→'posted'. **Duplicates the client's
  `checkAndCompleteSession`** — both exist today.
- **`onVideoSessionWritten`** — recomputes dashboard aggregations on any
  video_sessions write: the FIFTH aggregation trigger, same family the
  D-C1(b)/D-D1 ratifications sent to J.

**All four are Firestore document triggers. When sessions/drafts move to
Postgres, the trigger MECHANISM dies regardless of where the FILES live** —
Cloud Functions cannot fire on Postgres writes. Nothing in 04 addresses the
replacement. (D-F2.)

### 1c. The file wall today (`storage.rules`)

- `audio/**`, `video/**`: read+write **coaches only** — `isCoach()` is a
  Firestore `coaches/{uid}` DOC-EXISTENCE check. Mime+size caps (100MB/500MB).
- `profiles/**`: read **any authenticated user**; write **any authenticated
  user** (5MB/image mime) — no coach check, no ownership check.
- `practice_plans/{coachId}/**`: read+write **the owning coach only** —
  PER-COACH PRIVATE, strictly tighter than the staff-wide table walls.
- `imports/**`: coaches only.

Two facts matter: (1) `isCoach()` reads the OLD Firestore identity model —
at identity cutover the `coaches` docs stop being written and the wall
fails closed (coaches locked out of their own files). This sat on no
checklist until now. (2) Consent (`media_consent`, `do_not_photograph`)
gates exist ONLY at the app layer (session create + draft approval) — the
file layer has never had per-swimmer consent logic; files are keyed by
coach, not swimmer (voice notes excepted).

### 1d. BSPC + the parent-visible media surface

BSPC parent app has **ZERO media surface** — no storage import, no
photo/video/audio reads anywhere in features/lib/types. The ONLY
parent-visible media field in the system is the portal's `profilePhotoUrl`
(frozen 8-field… sanitizer landed in B), which serves whatever capability
URL sits in `swimmers.profile_photo_url`. So Kevin's "not one field wider"
rule has a precise meaning in F: **parents end the phase with exactly one
media affordance — a swimmer photo URL — same as today.**

### 1e. Canonical (the pinned table side)

`audio_sessions`, `audio_session_swimmers` (P1-4 junction),
`audio_session_drafts`, `video_sessions`, `video_session_swimmers` (P1-4,
`kind media_select_kind` 'tagged'|'selected' — tagged = the consent-gated
set), `video_session_drafts`; status enums match the app machines verbatim;
the deferred-FK block (schema lines 777–787) is byte-for-byte the banked-E
obligation: `fk_notes_source_audio_draft` + both `posted_note_id` FKs.
RLS: staff-only FOR ALL on all six. Gaps found: canonical drafts have NO
`reviewed_at` (Firestore drafts carry `reviewedAt`, `approveDraft` writes
it) — amendment candidate (D-F5). `thumbnail_path`/`frame_count` have no
writers anywhere (dormant; keep). Denorm names (`coachName`/`swimmerName`)
drop per the house derive-on-read pattern.

### 1f. Banked-from-E obligations (inventoried per the phase rule)

From NOTES (E landed log): ① `ADD CONSTRAINT fk_notes_source_audio_draft`;
② both `posted_note_id` FKs; ③ backfill pass 2 (pointer closure); ④
aiDrafts/videoDrafts draft-halves; ⑤ voice-note + profile-photo file moves
("storage stays Firebase until F" comments in both services). Every one is
closed by this plan (§5) or explicitly re-banked with a named home (§4
D-F4: practice-plan PDF + import FILES → H with their data). Nothing
dropped.

---

## §2 Findings register

| # | Finding |
|---|---|
| RF-1 | **No document pins the file tier.** 04 says "storage" (one word); canonical is host-agnostic; "Supabase Storage" appears nowhere in UNIFY. The end-state home, transitional story, URL strategy, and bucket layout are all open. |
| RF-2 | **The pipeline trigger mechanism dies in F unconditionally.** All four media functions are Firestore document triggers; their subject docs move to PG in F regardless of the file decision. No replacement is specified anywhere. |
| RF-3 | **Vertex couples large-video analysis to GCS.** `fileData.fileUri` accepts `gs://` only; inline base64 is capped (~20MB request). Moving files off Google storage requires a pipeline staging step. |
| RF-4 | **The storage wall breaks at identity cutover.** `isCoach()` = Firestore `coaches/{uid}` existence; post-cutover those docs aren't maintained → fails closed. Worse: post-AUTH-cutover clients hold no Firebase token at all, so NO auth-gated Firebase rule can pass. |
| RF-5 | Today's `profiles/**` rule lets ANY authenticated user read AND WRITE any swimmer's photo. Read parity must be preserved (parents see photos via capability URL); the open WRITE is a pre-launch artifact — tightening it narrows, never widens. |
| RF-6 | `practice_plans/**` files are per-coach PRIVATE — tighter than staff. Their DATA is Phase H. Moving these files under a staff-wide wall in F would WIDEN access coach→staff. (→ D-F4: files move with their data in H, inheriting D-F3's pattern, preserving per-coach scope.) |
| RF-7 | Voice-note files live UNDER `audio/` (`audio/swimmers/...`) — they share the session-audio wall today and must not end up looser than it. |
| RF-8 | `downloadUrl` is never persisted for sessions/voice notes — playback derives from `storage_path` at one code point per consumer. The swap surface is small and contained. `profile_photo_url` is the single persisted URL (host-agnostic by B's design — it absorbs a host change at backfill). |
| RF-9 | Canonical drafts lack `reviewed_at` (stored data has it). Same class as the `media_consent_granted_by_name` over-canonical amendment in B. |
| RF-10 | `onVideoUploaded` still reads swimmers from Firestore — the one un-re-pointed roster read left in F-scope (extractObservations precedent says: PG select). |
| RF-11 | `onDraftReviewed` duplicates client `checkAndCompleteSession`. The trigger dies with the subcollection; completion-ownership needs one owner. Retiring it is a SUBJECT-CODE deletion → its tests are deletable under the standing norm, named, with replacement proofs. |
| RF-12 | `onVideoSessionWritten` is the fifth aggregation trigger → J, extending D-C1(b)/D-D1/onNotesWritten verbatim. |
| RF-13 | **Local testability split.** Supabase Storage walls are RLS on `storage.objects` — pgTAP-provable exactly like table RLS (the local stack runs the storage container). Firebase Storage rules have NO local proof harness in this repo (jest mocks only). Webhook DELIVERY (if chosen in D-F2) and Vertex calls are not locally provable — flagged risks, never trusted mocks. |
| RF-14 | P1-4 junction mapping: `selectedSwimmerIds` → audio junction rows; video `taggedSwimmerIds`→`kind='tagged'`, `selectedSwimmerIds`→`kind='selected'` (created identical at create today — both sets written). FK to swimmers kills the stale-id class; consent stays asserted at create/approve (BUG #4 verbatim) with junction integrity now DB-enforced. |

---

## §3 Already pinned — needs no decision

The TABLE-side execution is fully determined by canonical + house style +
prior ratifications, whatever D-F1 decides: six tables in 00007 (house TEXT
CHECK for the enums per OD-1 deferral; `practice_group` 8-value CHECK), the
two junctions, coach_id RESTRICT, staff-only RLS with pgTAP wall proofs
(parents/guardians/pending/anon read ZERO), the deferred-FK closure
(banked ①②) in the SAME migration that creates the tables (RC-3: no
exposed intermediate), drafts' `posted_note_id` written at approve from F
on, realtime-parity subscribes, derive-on-read for the name denorms,
junction mapping per RF-14, `subscribePendingDrafts`' N+1 collapsing to one
join-shaped read (the searchNotes simplification precedent), and the
sessions' practice_date/calendar-string discipline. None of that is asked
below.

---

## §4 The decisions

### D-F1 — End-state home for media FILES (the centerpiece)

- **(a) Supabase Storage — RECOMMENDED.** Buckets + `storage.objects` RLS
  become the wall: same `is_staff()` helpers, same pgTAP proof style —
  "one wall, one rule" extends to files LITERALLY. Post-auth-cutover
  clients authenticate natively (RF-4 dissolves rather than needing
  repair). Per-bucket `file_size_limit` + `allowed_mime_types` reproduce
  today's rule caps declaratively. Costs: the upload helpers re-implement
  progress via TUS resumable uploads (supabase supports it; `onProgress`
  signature preserved); the >20MB Vertex path needs a transient GCS
  staging copy INSIDE the video function (server-side only, RF-3); files
  copy GCS→Supabase at cutover staging (scaffolding in F, run behind the
  HARD STOP).
- **(b) Stay on Firebase Storage/GCS permanently.** Pipeline untouched,
  zero file migration. But RF-4 must be engineered around: post-cutover
  clients can't pass auth-gated rules, so uploads need server-issued
  signed PUT URLs (a new callable + GCS signing path) and reads need
  capability URLs everywhere; the wall stays in a technology with no local
  proof harness (RF-13); Firebase stays in the stack forever (against the
  unification thesis); the `isCoach()` rule still needs a rewrite NOW.
- **(c) Hybrid (AI media on GCS, the rest on Supabase).** Two walls, two
  rule technologies, forever — rejected on the one-wall-one-rule principle
  unless Kevin overrides.

### D-F2 — Pipeline orchestration replacement (needed under EVERY D-F1 option)

- **(i) Client-invoke + scheduled sweeper — RECOMMENDED.** After flipping
  the PG row to 'uploaded', the client calls the (HTTPS-converted)
  process function directly; a scheduled function (syncCalendar precedent)
  sweeps rows stuck in 'uploaded' >N minutes and re-invokes. Every link is
  jest/pgTAP-testable; no new infrastructure; at-least-once via the sweep.
- **(ii) Supabase database webhook (pg_net) on status→'uploaded' → HTTPS
  function + the same sweeper.** Server-truth firing, but webhook delivery
  is exactly the kind of behavior the local stack can't faithfully prove
  (colima networking, RF-13) — a standing flagged risk in every session.
- **(iii) Sweep-only.** Simplest; minutes of latency on every recording —
  bad deck UX. Not recommended.
- Either way: the two AI functions convert to authenticated HTTPS handlers
  (logic unchanged and unit-tested as today), `onVideoUploaded` re-points
  its roster read to PG (RF-10), `onDraftReviewed` RETIRES with completion
  owned per D-F6 (subject-code deletion, tests named per the standing
  norm), `onVideoSessionWritten` banks to J (RF-12).

### D-F3 — Bucket layout, URL strategy, and the file wall (under (a))

- Buckets: `media-audio` (sessions + voice notes, RF-7 kept under one
  wall), `media-video`, `profile-photos`. Mime/size caps per bucket
  matching today's rules (100MB audio / 500MB video / 5MB image).
- Walls (storage.objects policies, pgTAP-proven): media buckets staff-only
  read+write — the same set as today's coaches-only `isCoach()` wall, not
  one bit wider. `profile-photos`: write STAFF-ONLY (tightens RF-5's
  pre-launch artifact — narrower, allowed), read via **long-lived signed
  URLs persisted in `profile_photo_url`** — capability semantics
  shape-identical to today's Firebase token URLs (unguessable link, no
  login required to render), so the parent surface keeps its exact shape:
  one photo URL. The bucket itself stays private (a public bucket would
  make photos path-guessable — WIDER than today's token URLs; rejected).
- Consent at the file layer: NONE TODAY, NONE ADDED — consent remains
  enforced at session-create/draft-approve (BUG #4 assertions verbatim)
  plus P1-4 junction integrity. Stated explicitly so the new layer
  (storage policies) gets its proofs without smuggling in a consent-model
  change nobody ratified.

### D-F4 — Scope boundary for the other file classes

Profile photos + voice-note audio move in F (the B/E comments promised
exactly that). Practice-plan PDFs and import files move WITH THEIR DATA in
H/later, inheriting D-F3's bucket+policy pattern but keeping their
PER-COACH-PRIVATE scope (`owner = auth.uid()` policy — RF-6; moving them
under a staff wall would widen). Re-banked, named home: Phase H.

### D-F5 — Canonical amendment (over-canonical, granted_by_name precedent)

`audio_session_drafts.reviewed_at TIMESTAMPTZ` +
`video_session_drafts.reviewed_at TIMESTAMPTZ` — the stored data has it,
approve flows write it, dropping it loses review provenance. PROPOSED for
ratification with this plan.

### D-F6 — Approve-draft atomicity (heals the E seam)

With drafts in PG, approve becomes note-insert + draft-update IN ONE
DATABASE. RECOMMENDED: a small SECURITY DEFINER RPC `approve_draft(...)`
(the D-C2 attendance_check_in precedent) doing both transactionally and
returning the note id — restores the atomicity the E seam consciously
broke, kills the partial-approve window for good. `approveAllDrafts`
chunks through it; `checkAndCompleteSession` stays client-side as the one
completion owner (or folds into the RPC's tail — implementer's choice at
execution). Alternative: two plain statements, accepting the tiny window.

---

## §5 Execution sequence (after ratification, one green commit each)

1. **BSPC `00007_phase_f_media.sql` + pgTAP 010**: six tables (house
   style) + junctions + `reviewed_at` (D-F5) + deferred-FK closure
   (banked ①②) + staff RLS + `approve_draft` RPC (D-F6) + buckets/policies
   (D-F1a/D-F3) — one migration, RC-3. Proofs: shapes/SELECT contracts,
   FK cycle + SET NULL orphan behavior, junction integrity, staff walls
   (table AND storage.objects), RPC payload, parents/guardians/pending/
   anon = ZERO everywhere.
2. **Coach `audio.ts`** swap: sessions + junction rows to PG, realtime
   parity, upload helper per D-F1 (TUS progress), pipeline kick per D-F2.
3. **Coach `video.ts`** swap: same + consent assertions verbatim at create
   + both junction kinds.
4. **Coach `aiDrafts.ts` draft-half**: PG drafts, `approve_draft` RPC,
   `posted_note_id` written from now on; approveAllDrafts single-store
   again (E-seam heal).
5. **Coach `videoDrafts.ts` draft-half**: same.
6. **Coach `swimmerVoiceNotes.ts` + `profilePhoto.ts` file-halves** (+
   `voice-note-recorder` playback URL derivation — a data-plumbing line in
   a component, the BSPC view-swap precedent): uploads → Supabase Storage,
   queue format unchanged; `profile_photo_url` now stores supabase signed
   URLs (still host-agnostic).
7. **Functions**: the two AI functions → HTTPS handlers (+ sweeper per
   D-F2); RF-10 re-point; retire `onDraftReviewed` (tests deleted AND
   NAMED, replaced by RPC/pgTAP + sweeper proofs); `onVideoSessionWritten`
   → J bank in NOTES.
8. **`migration/media/README.md` + scaffolding**: row backfill order
   (sessions → junctions from the arrays → drafts), **pass-2 pointer
   closure** (banked ③: `source_audio_draft_id` from the E transient map +
   `posted_note_id` back-pointers), FILE copy manifest GCS→Supabase
   (paths preserved verbatim under the new buckets; `profile_photo_url`
   rewrite pass) — runs at cutover staging behind the HARD STOP, like
   every backfill.
9. **NOTES**: ratifications + landed log; push all repos.

**No production/live file moves anywhere in F** — code paths, policies,
proofs, and scaffolding only, per the phase rule.

---

## §6 Red-team of this plan

| Risk | Mitigation |
|---|---|
| TUS/progress parity is new client ground — supabase-js standard upload has no progress callback | Resumable (TUS) uploads carry progress; the service signature (`onProgress` percent) is the frozen contract and is jest-pinned before swap. If TUS misbehaves in Expo, fall back to chunk-progress emulation — still behind the same signature. |
| pgTAP storage proofs depend on the local storage schema accepting direct fixture inserts | Verified the storage container runs locally; proofs write `storage.buckets`/`storage.objects` fixtures directly. If a storage-API behavior can't be exercised from SQL, it gets FLAGGED in the report, not mocked (Kevin's rule). |
| Vertex staging copy (>20MB videos) adds a GCS write inside the function | Server-side only, transient object, deleted after analysis; never client-visible; unit tests pin the branch logic exactly as today's 20MB branch is pinned. |
| Hosted-project storage quotas (500MB videos) at the real cutover | Cutover-checklist line, not code: confirm project tier/global `file_size_limit` before the file copy. Banked to the runbook. |
| Client-invoke pipeline misses (app killed between flip and call) | The sweeper IS the at-least-once guarantee; cadence is a tunable; sweep logic fully unit-tested. |
| Signed-URL expiry on profile photos (capability URLs must not rot) | Issue max-expiry URLs and re-issue on every upload; the backfill rewrite pass covers existing rows; document expiry in the runbook. Today's Firebase token URLs are the same capability model. |
| The two AI HTTPS handlers become publicly addressable | Shared-secret header checked first line (service-role style), tests pin the 401 path; they were never client-called before and still aren't. |
| Junction double-write (`tagged` + `selected` identical at create) reads as redundant | It IS today's stored shape (both arrays written identically at create); canonical's `kind` is the future-proof split. Migrating faithfully beats editorializing. |

Errors-twice, material divergence, and HARD STOP rules apply unchanged.

---

## §7 [DECIDE] — for Kevin

- **D-F1 — Where do media files live end-state?** (a) Supabase Storage
  (RECOMMENDED — native post-cutover auth, pgTAP-provable wall, one rule
  technology; costs: TUS upload rework + transient GCS staging for >20MB
  Vertex calls + a file-copy step at cutover staging) / (b) Firebase
  Storage forever (no file copy; costs: signed-upload-URL machinery once
  Firebase Auth is gone, an unprovable wall, permanent Firebase
  dependency) / (c) hybrid (two walls — not recommended).
- **D-F2 — What replaces the Firestore pipeline triggers?** (i)
  client-invoke + scheduled sweeper (RECOMMENDED — every link locally
  testable) / (ii) supabase database webhook + sweeper (server-truth
  firing; webhook delivery locally unprovable) / (iii) sweep-only (deck
  latency — not recommended).
- **D-F3 — Ratify the bucket/wall/URL design:** three buckets with
  per-bucket mime/size caps; staff-only media walls (today's coaches-only
  set, not one bit wider); profile photos private-bucket + long-lived
  signed capability URLs (today's exact parent-visible shape); write
  access to photos tightened to staff; consent stays at create/approve
  (BUG #4 verbatim) — no file-layer consent logic added or removed.
- **D-F4 — Scope:** photos + voice audio move in F; practice-plan PDFs +
  import files re-banked to H WITH their data, keeping per-coach-private
  scope. Confirm.
- **D-F5 — Canonical amendment:** ADD `reviewed_at` to both draft tables.
  Ratify.
- **D-F6 — `approve_draft` SECURITY DEFINER RPC** healing the E-seam
  atomicity split (attendance-RPC precedent); `onDraftReviewed` retires
  with named test deletions. Ratify.
- **FYI bundle (no decision, flagged):** RF-8 (URLs derived, swap
  contained); RF-10 re-point; RF-12 fifth aggregation trigger → J;
  dormant `thumbnail_path`/`frame_count` kept; statuses as house TEXT
  CHECK until OD-1; Vertex calls remain mock-tested only (jest-blindness
  acknowledged — flagged every phase the pipeline is touched).
