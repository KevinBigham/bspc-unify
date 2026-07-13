# Launch Gate Dashboard

This dashboard separates deterministic agent checks from owner/external launch gates. A missing owner value is `WAITING`, not a failed engineering build.

## Automated gates

| Gate | Command / evidence | Current local state |
|---|---|---|
| Family static + Jest | `npm run typecheck && npm run lint && npm test -- --runInBand` | GREEN — 933 / 134; 10 snapshots |
| Family coverage | `npm run test:coverage -- --runInBand` | GREEN — 86.27 / 82.31 / 83.42 / 87.34 |
| Family schema + Edge | pgTAP floor/drift/clean reset plus Deno check/tests | GREEN — pgTAP 480 / 21; Deno 5 / 5 |
| Coach quality | `npm run quality && npm run quality:dead-code` | GREEN — client 1,205 / 127; Functions 171 / 15; portal retired; knip |
| Coach coverage | `npm run test:coverage -- --runInBand` | GREEN — 82.82 / 70.69 / 84.16 / 87.17 |
| Critical dependencies | four package-root critical audit gates | GREEN — zero critical/high |
| Secrets | gitleaks CI + local hooks | GREEN — Family 76-commit and Coach 210-commit history scans plus both worktrees |
| Hosted CI | launch-line PR checks + UNIFY drift | GREEN — Family PR 22 → `42050b4`; Coach PR 14 → `5643ae2`; UNIFY PR 16 → `40eecbc` |

## Active draft checks

| Draft | Candidate evidence | State |
|---|---|---|
| Family PR 23 | Jest 933/134; pgTAP 537/22; Deno 22/22; clean-reset RLS | GREEN / DRAFT at `d92f509` |
| Coach PR 15 | Client 1,205/127; Functions 158/13; zero runtime exports | GREEN / DRAFT at `ab26ca0` |
| UNIFY PR 17 | Cross-repository domain contract | GREEN / DRAFT at current PR head |

Draft evidence is review evidence only. It does not alter the merged launch-line
row above or authorize readiness, merge, deployment, schedule activation, or a
production command.

## Owner and external gates

| Gate | Required evidence | State |
|---|---|---|
| Production truth | sanitized `audit-prod-schema` GREEN | WAITING |
| Shadow + staging | project refs plus green proof logs | WAITING |
| Legal | engaged lawyer, redlined policy URLs | WAITING |
| DNS/mail | SPF/DMARC and three-provider delivery | WAITING |
| EAS/store | project IDs, four internal builds, account readiness | WAITING |
| Devices | recovery, invite, offline, push, a11y, performance matrices | WAITING |
| Operations | mailboxes, alerts, dashboard, cost alerts | WAITING |
| Beta | two-week exit report with zero P0 and >99.5% crash-free | WAITING |

The release check is GREEN only when every automated row is green and every owner row has a dated evidence link. Never replace `WAITING` with a fake environment value.

No owner/external row above is complete as of this reconciliation.
