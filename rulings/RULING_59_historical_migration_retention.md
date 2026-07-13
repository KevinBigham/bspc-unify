# Ruling 59 — Retain cancelled migration artifacts as historical-only

**Date:** 2026-07-12
**Status:** In force

`BSPC/ACTIVE/migration/` is retained in place with a root historical banner for provenance. Rulings 56/57 cancelled the data migration, so the directory is excluded from runtime, package scripts, CI execution, and release procedures. The active path is the ordered Supabase migration ledger plus fresh-launch onboarding/import tooling.

Measured bar delta: zero. No test file or executable launch artifact was removed. Any future deletion must preserve history, report the bar delta, and receive a superseding ruling.
