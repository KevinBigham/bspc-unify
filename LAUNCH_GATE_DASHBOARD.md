# Launch Gate Dashboard

This dashboard separates deterministic agent checks from owner/external launch gates. A missing owner value is `WAITING`, not a failed engineering build.

## Automated gates

| Gate | Command / evidence | Current local state |
|---|---|---|
| Family static + Jest | `npm run typecheck && npm run lint && TZ=UTC npm test -- --runInBand` | GREEN — 908 / 128 before migration-20 additions |
| Family coverage | `npm run test:coverage -- --runInBand` | GREEN — configured 75/65/75/75 threshold enforced |
| Family schema | `npm run check:pgtap-floor && npm run check:schema-drift && npm run test:rls` | GREEN — 433 / 19 |
| Coach quality | `npm run quality && npm run quality:dead-code` | GREEN before current Phase-3 additions; remeasure at mission close |
| Coach coverage | `npm run test:coverage -- --runInBand` | GREEN — explicit 75/65/75/75 threshold |
| Critical dependencies | four package-root critical audit gates | GREEN |
| Secrets | gitleaks CI + local hooks | Configured; full-history run awaits real-clone sync |
| Hosted CI | launch-line PR checks | WAITING — publish current branches |

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
