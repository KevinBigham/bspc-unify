# BSPC state of the union

Last measured: 2026-07-12. This is the living mission-close dashboard; update it whenever a mission changes a bar, branch head, blocker, or next mission.

## Launch truth

| Line | Public remote head restored into this export | Fresh local bar |
|---|---|---|
| Family `demo/expo-go-compat` | PR 19 merged green as `5abf21b`; Ruling-60 local mission `88915f2` | Node 22 typecheck + lint; Jest 924/132; pgTAP 437/19 after clean reset |
| Coach `demo/device-build` | PR 13 merged green as `28f2303`; Ruling-64 PR 14 hosted green and ordered to merge | **Pinned post-retirement bar:** Node 22 full quality; client Jest 1,205/127; Functions 171/15; scheduler-only export pin + knip green |
| UNIFY `main` | PR 12 merged as `1373bc2`; cross-repo run 29215889421 green | docs/schema and cross-repo contract checks |

Real-clone evidence is published in Family PR 19, Coach PR 12, and UNIFY PR 12. All three missions are merged to their intended lines; app promotion to `main`, protection, tag, and final-launch claims remain open until their prerequisite evidence exists.

## Blocker board

| Blocker | Owner | Exact unblock |
|---|---|---|
| Production probe has no GREEN/YELLOW/RED classification | Kevin + agent | Correct the protected prod DB credential source; then explicitly authorize one read-only probe command |
| Production/staging/shadow writes are not authorized | Kevin | Provide target and per-command `go`; never infer authorization |
| Physical recovery/device matrix/field test incomplete | Kevin + agent | Install internal builds on iPhone and Android and execute the sanitized device checklists |
| Legal/DNS/store/mailbox/account work lacks external evidence | Kevin | Complete the phase gate pack and return non-secret confirmations/URLs |
| Ruling 66 extension-availability rider is pending | Kevin + agent | After staging authorization, verify `pg_cron` + `pg_net` read-only and record versions before creating any schedule object |
| Closed beta requires 3–5 families and two elapsed weeks | Kevin | Start only after entry gates pass; record exit metrics after the full window |

## Current mission

Phase 3 repository proofs are locally green: migrations now run through `00021`; meet import replay, onboarding audit/collision handling, Supabase roster seeding, calendar merge preservation, Sentry scrubbing, quiet-hours consent, and Coach roster scaling have named proofs. The 100-item state is maintained in `GOAT_EXECUTION_STATUS.md`.

## Next mission per lane

- Family: Phase-4 route-state/a11y/device-prep polish, then publish the green mission PR.
- Coach: Ruling 64 portal retirement merge, then await selection of the next proposed PARTIAL mission.
- UNIFY: keep the evidence ledger and gate dashboard current; prepare one owner gate pack.
- Kevin: production/shadow/staging, rulings, legal/account/device gates only; no scattered asks.
