# bspc-unify

This repository is the canonical unification plan for two **separate** application repositories — `BSPC` (the parent app) and `BSPC-Coach-App` (the coach app) — which intentionally remain their own independent repos. Nothing here changes that: this repo holds only the planning and design documents for migrating both apps onto a single shared, canonical Postgres/Supabase backend.

## Documents

- **00_TERRAIN.md** — design map of the existing two-app landscape.
- **01_CANONICAL_SCHEMA.sql** — the proposed unified canonical schema.
- **02_SCHEMA_REDTEAM.md** — red-team critique of the canonical schema.
- **03_MIGRATION_PLAYBOOK.md** — step-by-step migration playbook.
- **04_CROSS_TIER_SEQUENCING.md** — cross-tier sequencing plan for the migration.
- **NOTES.md** — working notes.
