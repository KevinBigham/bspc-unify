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
- **06_FIREBASE_RUNBOOK.md** — ⛔ historical cutover runbook (PART B / Sitting 2 / §B0 probe / §B6 decommission are **superseded & non-executable** under Rulings 56 + 57 — fresh launch, no migration).

**Publish era**
- **13_PUBLISH_PLAN.md** — master Plan for Publish (§8 = the `[DECIDE]` resolutions).
- **14_GATE1_LAWYER_BRIEF.md** — children's-privacy fact pack + questions for counsel.
- **15_PRIVACY_REWRITE_OUTLINE.md** — privacy-policy + ToS gap analysis and target outline.
- **16_PROD_BACKEND_PROVISIONING.md** — Phase-1 backend checklist (what must be true).
- **17_PROD_BACKEND_RUNBOOK.md** — Phase-1 command sequence (how it's done).
- **18_DIRECTOR_ONBOARDING.md** — bootstrap brief to hand a new DIRECTOR seat the role.
- **19_FAMILY_COMMS_DRAFTS.md** — ⚠ **amended (Rulings 56 + 57):** migrated-family + Firebase sign-in-shutdown messaging **retired**; retained are the fresh-launch Gate-6 controls (Supabase email provider, SMTP/delivery proof, invite template, password-reset template, redirect/deep-link allow-list, synthetic invite/reset e2e proof). Original (now historical): pre-cutover family announcement + recovery/invite email templates, revised per Director Ruling 05 (no automatic-blast promise; recovery-email **delivery** + Firebase sign-in shutdown gated on a proven recovery path — SMTP + send-rate + redirect/deep-link + synthetic e2e mobile reset — while the announcement may use the existing team channel; invite template held inactive until a net-new onboarding path exists).
- **20_IDENTITY_REMEDIATION_SITTING.md** — ⛔ **superseded & non-executable** (Rulings 56 + 57): the Firebase identity-remediation sitting is retired; Kevin becomes first super_admin via the Supabase first-admin bootstrap. Kept as historical material, not deleted.

**Program records**
- **HANDOFF.md** — program handoff.
- **NOTES.md** — append-only, sanitized tool-output log (inspect output for secrets, PII, account identifiers, roster data, and media metadata before recording; record sanitized output only — sensitive findings as path/category or count/status only; never a secret, UID, email, minor, or roster value).
