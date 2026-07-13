# BSPC state of the union

Last measured: 2026-07-12. This is the living mission-close dashboard; update it whenever a mission changes a bar, branch head, blocker, or next mission.

## Launch truth

| Line | Public remote head restored into this export | Fresh local bar |
|---|---|---|
| Family `demo/expo-go-compat` + open PR 19 | launch `a4c8861`; PR head base `7bc9680` plus this local mission | Node 22 typecheck + lint; Jest 918/131; pgTAP 437/19 after clean reset |
| Coach `demo/device-build` | `9405fec` plus this local mission | Node 22 full quality; client Jest 1,210/128; Functions 191/16; portal build + knip green |
| UNIFY `main` | `37b20a7` before this execution pass | docs/schema checks only |

The supplied folders have no `.git` metadata. Hosted PR, merge, protection, history-scan, CI, and tag claims require evidence from real clones/GitHub and remain unproven here.

## Blocker board

| Blocker | Owner | Exact unblock |
|---|---|---|
| Production probe has no GREEN/YELLOW/RED classification | Kevin + agent | Correct the protected prod DB credential source; then explicitly authorize one read-only probe command |
| Production/staging/shadow writes are not authorized | Kevin | Provide target and per-command `go`; never infer authorization |
| Physical recovery/device matrix/field test incomplete | Kevin + agent | Install internal builds on iPhone and Android and execute the sanitized device checklists |
| Legal/DNS/store/mailbox/account work lacks external evidence | Kevin | Complete the phase gate pack and return non-secret confirmations/URLs |
| Portal, scheduler, retention, and aggregation-staleness choices need owner rulings | Director/Kevin | Approve the prepared decision memos before behavior-changing implementation |
| Closed beta requires 3–5 families and two elapsed weeks | Kevin | Start only after entry gates pass; record exit metrics after the full window |

## Current mission

Phase 3 repository proofs are locally green: migrations now run through `00021`; meet import replay, onboarding audit/collision handling, Supabase roster seeding, calendar merge preservation, Sentry scrubbing, quiet-hours consent, and Coach roster scaling have named proofs. The 100-item state is maintained in `GOAT_EXECUTION_STATUS.md`.

## Next mission per lane

- Family: Phase-4 route-state/a11y/device-prep polish, then publish the green mission PR.
- Coach: remaining device-informed polish and Firebase/portal disposition after owner rulings.
- UNIFY: keep the evidence ledger and gate dashboard current; prepare one owner gate pack.
- Kevin: production/shadow/staging, rulings, legal/account/device gates only; no scattered asks.
