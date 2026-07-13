# BSPC state of the union

Last measured: 2026-07-12. This is the living mission-close dashboard; update it whenever a mission changes a bar, branch head, blocker, or next mission.

## Launch truth

| Line | Public remote head restored into this export | Fresh local bar |
|---|---|---|
| Family `demo/expo-go-compat` | PR 22 merged green as `42050b4`; final tree equals hosted-green head `df4d951` | Node 22 typecheck + lint; Jest 933/134; pgTAP 480/21; Deno 5/5 |
| Coach `demo/device-build` | PR 14 merged green as `5643ae2` | **Pinned post-retirement bar:** Node 22 full quality; client Jest 1,205/127; Functions 171/15; scheduler-only export pin + knip green |
| UNIFY `main` | PR 16 merged green as `40eecbc`; cross-repository drift remains green | docs/schema and cross-repository contract checks |

Real-clone and hosted evidence is carried by the listed merge commits and their
PR checks. App promotion to `main`, tagging, and every final-launch claim remain
open until their recorded prerequisite evidence exists.

## Current pinned bars

| Line | Suite | Pinned bar | Evidence state |
|---|---|---:|---|
| Family | Jest | 933 tests / 134 suites / 10 snapshots | Hosted green at PR 22 head; merge tree identical |
| Family | pgTAP | 480 assertions / 21 files | Hosted clean-reset RLS job green |
| Family | Deno Edge | 5 tests / 5 passed | Hosted Deno check and test job green |
| Coach | Client Jest | 1,205 tests / 127 suites | Hosted green at PR 14 head; merge tree identical |
| Coach | Functions Jest | 171 tests / 15 suites | Hosted green at PR 14 head; merge tree identical |
| UNIFY | Contract/drift workflows | all configured checks passed | PR 16 and default-branch evidence green |

## Active draft evidence (not launch-pinned)

| Train | Draft head | Candidate bar | Hosted state |
|---|---|---|---|
| Family PR 23 | `d92f509` | Jest 933/134; pgTAP 537/22; Deno 22/22 | DRAFT / CLEAN — all nine checks green, including clean-reset RLS |
| Coach PR 15 | `ab26ca0` | Client Jest 1,205/127; Functions 158/13; runtime export surface exactly zero | DRAFT / CLEAN — quality, secret-history, and advisory checks green |
| UNIFY PR 17 | current PR head | Contract/drift check | DRAFT / CLEAN — hosted domain-contract green |

These candidate bars do not replace the launch pins above until the Director
orders each PR ready and merged and the resulting launch-line tree is verified.

## Blocker board

| Blocker | Owner | Exact unblock |
|---|---|---|
| Production probe has no GREEN/YELLOW/RED classification | Kevin + agent | Correct the protected prod DB credential source; then explicitly authorize one read-only probe command |
| Production/staging/shadow writes are not authorized | Kevin | Provide target and per-command `go`; never infer authorization |
| Physical recovery/device matrix/field test incomplete | Kevin + agent | Install internal builds on iPhone and Android and execute the sanitized device checklists |
| Legal/DNS/store/mailbox/account work lacks external evidence | Kevin | Complete the phase gate pack and return non-secret confirmations/URLs |
| GOAT 31 is incomplete across all repos | Agent | After the current train missions close, add UNIFY scanner CI + pre-commit coverage and record a sanitized full-history scan |
| GOAT 34 DB-output coverage is incomplete | Agent | Inventory the bootstrap as a DB-output script and route every output/error path through fail-closed redaction tests for URLs, JWTs, capability parameters, email, and UUIDs |
| GOAT 40 does not enforce its full contract | Agent | Land one canonical-SQL↔migrations↔app-domain↔metadata verifier in every repo CI without warning-pass behavior |
| GOAT 41 lacks its required ruling | Director | Issue a durable ruling declaring the Coach launch line shippable after reviewing the green quality evidence |
| GOAT 60 date renders have not converged | Agent | Replace remaining app/PDF/export-local date renders with one tested cross-app date-format contract, including timezone boundary cases |
| GOAT 64 hundredths formatting has not converged | Agent | Replace independent Family and Coach formatters with the shared parser/formatter and extend property-based round-trip coverage to Progress/PB-adjacent surfaces |
| GOAT 73 consent is not prominent on every media surface | Director + agent | Rule whether audio and swimmer voice notes require the same media-consent contract as video, then implement and test every applicable surface without weakening the service gate |
| Ruling 66 extension-availability rider is pending | Kevin + agent | After staging authorization, verify `pg_cron` + `pg_net` read-only and record versions before creating any schedule object |
| Closed beta requires 3–5 families and two elapsed weeks | Kevin | Start only after entry gates pass; record exit metrics after the full window |

## Current mission

Family migrations now run through `00022`; Ruling 65 Phase 1 is merged but dark,
with zero schedules, deployments, or remote writes. All three Ruling-67 mission
drafts are hosted-green at the heads recorded above: UNIFY GOAT 43 truth
reconciliation, Coach GOAT 95 scheduler-host retirement, and Family push
retry/DLQ. None is ready or merged. Truth reconciliation corrected GOAT 31,
34, 40, 41, 60, 64, and 73 from DONE to PARTIAL because their literal
acceptance clauses remain incomplete. The 100-item state remains in
`GOAT_EXECUTION_STATUS.md`.

## Three outstanding resume gates

| Resume gate | Current state | Exact resume authority |
|---|---|---|
| Production truth | WAITING — probe remains unclassified after credential rejection | Kevin says exactly: `credential corrected — go for the read-only production probe` |
| Supabase scheduler activation | WAITING — `pg_cron`/`pg_net` availability record is pending; zero schedule objects exist | Kevin authorizes a named throwaway/staging read-only check, then separately authorizes any secret/deploy/schedule command |
| Launch-owner evidence | WAITING — device, legal, DNS/mail, store/account, operations, beta, and launch gates are incomplete | Kevin supplies the specific external evidence or per-action authorization recorded in the dashboard |

## Next mission per lane

- Family: PR 23 push retry/DLQ follow-on is dark, hosted-green, and awaiting a Director ready/merge order.
- Coach: PR 15 GOAT 95 scheduler-host retirement is hosted-green with all four schedulers dispositioned and awaits a Director ready/merge order.
- UNIFY: PR 17 GOAT 43 truth reconciliation is hosted-green; no owner gate is promoted from WAITING.
- Kevin: production/shadow/staging, rulings, legal/account/device gates only; no scattered asks.
