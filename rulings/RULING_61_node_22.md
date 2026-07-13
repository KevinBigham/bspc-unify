# Director Ruling 61 — Node 22 ratified

- Date: 2026-07-12
- Status: in force
- Decision owner: Director / Kevin
- Supersedes: none
- Evidence reviewed: `decisions/NODE_RUNTIME.md`; both app `.nvmrc` and CI workflows

## Decision

Node 22 is the ratified runtime for both apps, Coach Functions, CI, and supported repository tooling.

## Scope

This confirms the already-implemented runtime pin. It does not authorize a future Node-major upgrade.

## Consequences

Engines, local version files, Functions runtime, and CI stay aligned on Node 22 until a superseding ruling.

## Human gates

None beyond ordinary protected-branch review.
