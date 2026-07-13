# Director Ruling 64 — retire the parent portal

- Date: 2026-07-12
- Status: in force
- Decision owner: Director / Kevin
- Supersedes: the unresolved portal-fate state
- Evidence reviewed: `decisions/PORTAL_FATE.md`; Coach `parent-portal/`; Coach `functions/src/callable/parentPortal.ts`

## Decision

Retire the Next.js parent portal and its two portal callables. The Family mobile app is the sole family-facing product.

## Scope

This authorizes source, test, CI, dependency, knip, and documentation removal in one baseline-changing Coach mission. It does not authorize deleting hosted resources.

## Consequences

The Coach launch export remains scheduler-only. The export-surface test and measured bars must be intentionally updated, with dead-code and import proofs green.

## Human gates

Kevin reviews and merges the protected-branch PR; hosted-resource inventory and teardown require separate authorization.
