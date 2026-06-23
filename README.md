# bspc-unify

This repository is the canonical unification plan for two **separate** application repositories — `BSPC` (the parent app) and `BSPC-Coach-App` (the coach app) — which intentionally remain their own independent repos. Nothing here changes that: this repo holds only the planning and design documents for migrating both apps onto a single shared, canonical Postgres/Supabase backend.

## Documents

**Design & schema**
- **00_TERRAIN.md** — design map of the existing two-app landscape.
- **01_CANONICAL_SCHEMA.sql** — the unified canonical schema (law; storage spec at Appendix A).
- **02_SCHEMA_REDTEAM.md** — red-team critique of the canonical schema.
- **03_MIGRATION_PLAYBOOK.md** — step-by-step migration playbook.
- **04_CROSS_TIER_SEQUENCING.md** — cross-tier sequencing plan for the migration.

**Migration phases**
- **05_PHASE_A_IDENTITY.md** · **07_PHASE_C_ATTENDANCE.md** · **08_PHASE_D_TIMES.md** · **10_PHASE_F_MEDIA.md** · **11_PHASE_G_NOTIFICATIONS.md** · **12_PHASE_H_CALENDAR_MEETS_PLANS.md** — per-phase design + ratification records.
- **06_FIREBASE_RUNBOOK.md** — the cutover runbook (PART B = Sitting 2; §B0 probe; §B6 decommission).

**Publish era**
- **13_PUBLISH_PLAN.md** — master Plan for Publish (§8 = the `[DECIDE]` resolutions).
- **14_GATE1_LAWYER_BRIEF.md** — children's-privacy fact pack + questions for counsel.
- **15_PRIVACY_REWRITE_OUTLINE.md** — privacy-policy + ToS gap analysis and target outline.
- **16_PROD_BACKEND_PROVISIONING.md** — Phase-1 backend checklist (what must be true).
- **17_PROD_BACKEND_RUNBOOK.md** — Phase-1 command sequence (how it's done).
- **18_DIRECTOR_ONBOARDING.md** — bootstrap brief to hand a new DIRECTOR seat the role.
- **19_FAMILY_COMMS_DRAFTS.md** — pre-cutover family announcement + recovery/invite email templates, revised per Director Ruling 05 (no automatic-blast promise; recovery-email **delivery** + Firebase sign-in shutdown gated on a proven recovery path — SMTP + send-rate + redirect/deep-link + synthetic e2e mobile reset — while the announcement may use the existing team channel; invite template held inactive until a net-new onboarding path exists).
- **20_IDENTITY_REMEDIATION_SITTING.md** — proposed pre-cutover sitting to seed Kevin's coach identity (exact coach-document payload table; create-only write, zero-PII-in-logs, verified-reversal-only per Director Ruling 04 §6; execution held).

**Program records**
- **HANDOFF.md** — program handoff.
- **NOTES.md** — append-only, sanitized tool-output log (inspect output for secrets, PII, account identifiers, roster data, and media metadata before recording; record sanitized output only — sensitive findings as path/category or count/status only; never a secret, UID, email, minor, or roster value).
