# 14 — GATE 1: BRIEF FOR PRIVACY COUNSEL

**Status:** DRAFT — prepared by the EXECUTOR seat, 2026-06-22, for review by Kevin + the DIRECTOR before it goes to an attorney. **Nothing here is legal advice; it is a fact pack + a question list.**
**Looking for:** an attorney experienced in **youth-sports / ed-tech privacy** (COPPA, SafeSport/MAAPP, US state privacy law).
**No real personal data appears in this document** — all data is described at the category level only.

---

## 1. Who we are

A pre-launch software suite for **one youth swim team** (Blue Springs Power Cats), operated by an individual founder. **No production users yet** — a clean slate to get consent right *before* any real family's data is collected. Target infra is near-zero-cost (Supabase, Sentry, PostHog, Expo). US-based; team is in Missouri.

## 2. The surfaces and their users

| Surface | Used by | Purpose |
|---|---|---|
| Coach mobile app | Coaches/admins (adults, 18+) | Roster, attendance, times, practice plans, AI audio/video coaching tools |
| Parent mobile app (BSPC) | Parents/guardians (adults) | Schedule, announcements, meets, their swimmer's progress |
| Parent-portal web | Parents/guardians (adults) | Read-only view of their swimmer's times/attendance |

**Children do not have accounts and do not log in or enter data.** All data is entered by adults (coaches and parents).

## 3. Data collected *about minors* (category level)

| Category | Collected by | Notes |
|---|---|---|
| Identity | Coach app | Name, **date of birth**, gender, practice group |
| Performance | Coach + parent apps | Swim times, splits, personal records, **attendance** |
| **Medical info** | Coach app | Free-text medical notes (admin-restricted within the app) |
| **Media of minors** | Coach app | **Photos, video, and audio recordings** of swimmers; AI analysis of that media (Google Vertex/Gemini) |
| Free-text notes | Coach app | Coach observations about a swimmer |

Stored in **Supabase (PostgreSQL + Storage), United States.** The parent app (BSPC) itself collects *no* media — only the Coach app does. AI features send media to **Google Vertex AI (Gemini)** for transcription/analysis.

## 4. The current consent model (verbatim mechanics — this is what counsel must assess)

- **Media consent is coach-asserted, not parent-verified.** In the Coach app, a coach opens a swimmer, toggles "Granted / Not Granted," **types the parent/guardian's name into a free-text box**, and optionally adds a free-text note (e.g. "Signed form on file"). No parent participates in the system; nothing is verified; no document is uploaded. (`app/swimmer/edit.tsx:348-396`, `src/utils/mediaConsent.ts:120-128`.)
- **Parent↔child linkage is via an invite code.** A coach issues an 8-character code (7-day expiry); whoever redeems it becomes a "guardian" of that swimmer. **The system does not verify the redeemer is actually the child's parent/guardian.**
- **No age gate.** Date of birth is stored but never used to branch any under-13 logic.
- **Enforcement is client-side only.** The media-consent / "Do Not Photograph" gate is enforced in app code (TypeScript), not at the database or storage layer. A determined/programmatic path, or a staff/service-role actor, can bypass it. (Profile photos of minors are, under the current transitional Firebase storage rule, readable by any authenticated user.)

## 5. The claims the product currently makes

- The Coach app's media-consent screen states consent is **"verifiable consent per COPPA and SafeSport MAAPP requirements"** (`edit.tsx:351-353`) — a claim the §4 mechanism does **not** substantiate.
- The privacy policies assert COPPA compliance. The Coach policy leans on "not directly collected from children" to address COPPA in a single thin paragraph and **does not disclose** that the app collects minors' media/medical data. The BSPC policy says "we do not collect photos or videos" — true for BSPC alone, but the same operator's Coach app does, on the same children. (Full gap analysis: `15_PRIVACY_REWRITE_OUTLINE.md`.)

## 6. What is already strong (so counsel can scope effort)

Authorization and data-minimization are well-built: parents get only a sanitized, minimized view of their own child's data (no raw attendance/notes), cross-family isolation is proven by database tests, medical notes are admin-restricted in-app, and invite redemption is hardened against spoofing/races. **The gap is consent + disclosure + the layer at which the media gate is enforced — not access control.**

## 7. Questions for counsel

1. **COPPA applicability** — given that minors' data is entered by adults (not collected *from* the child), and children have no accounts: does COPPA's verifiable-parental-consent obligation attach? Is the service "directed to children"? What is the safest defensible posture?
2. **Verifiable parental consent** — if required (or advisable regardless), what mechanism satisfies it here (e.g., parent-side in-app affirmation, signed-form upload, the invite-redemption flow upgraded to capture consent)? We can build whatever is needed.
3. **The "verifiable consent" claim** — what is the exposure (deceptive-practices / misrepresentation) of the app asserting COPPA/SafeSport "verifiable consent" while the mechanism is a coach toggle? Should we build the mechanism up to the claim, or soften the claim?
4. **SafeSport / MAAPP** — what obligations apply to collecting, storing, and using **photos/video/audio of minor athletes**, and to coach↔athlete data? Does our media-consent concept need to meet a specific standard?
5. **AI processing of minors' media** — any added requirements from sending minors' photos/video/audio to a third-party AI (Google Vertex/Gemini) for analysis?
6. **Parental rights** — what review/correction/deletion rights must we give parents over their child's specific data, and what response SLAs?
7. **Privacy policy + ToS** — required disclosures for this data profile; whether one operator-level policy covering both apps + the portal is preferable to two app-specific policies; the BSPC app currently has **no** Terms of Service.
8. **State law** — Missouri governing law plus any cross-state considerations; biometric/student-data statutes implicated by storing minors' video/audio.
9. **App-store gates** — what age-rating, Apple "kids" review, Google Play "Designed for Families," and Data Safety attestations will we be asked to make, and can we make them truthfully under the recommended consent model?
10. **Retention** — required/advisable retention + deletion defaults for minors' data, including media.

## 8. What we're asking counsel to deliver

1. A **consent-architecture recommendation** we can implement before launch.
2. A **redline** of the privacy policies + a BSPC ToS (we'll supply drafts — `15`).
3. A **go / no-go** on the current in-app COPPA/SafeSport claim.
4. A **store-form attestation guide** (what we can truthfully check on the Apple/Google kids/families/data-safety forms).

## 9. Constraints / advantages

Pre-launch (no users to remediate — we can design it right the first time). We control all three surfaces and can build any consent flow, add any DB/storage enforcement, and change any in-app copy. Timeline goal: counsel turnaround is the pacing item for public launch (`13 §5`, Milestone 2).
