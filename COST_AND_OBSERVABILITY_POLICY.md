# Cost and Observability Policy

## Five-number launch view

1. Invite-to-redeemed activation rate.
2. Weekly-active approved families.
3. Crash-free session percentage by app/build.
4. Digest attempted/succeeded/failed rate.
5. Open support cases older than 48 hours.

No dashboard property may contain swimmer names, email addresses, invite/recovery tokens, media URLs, or free-text notes.

## Alerts and paid-upgrade triggers

| Service | Owner alert | Review / upgrade trigger |
|---|---|---|
| Supabase | 70% and 90% of plan DB/storage/egress; auth anomaly | two consecutive weeks above 70%, or forecasted beta growth crosses quota |
| Sentry | new issue, crash spike, 70% event quota | sampling drops required launch signals or crash-free cannot be measured |
| PostHog | 70% and 90% event quota | five-number dashboard cannot retain the beta/launch window |
| EAS | build/update quota and failed rollout | required platform build or safe rollback cannot be completed |

Kevin configures billing/usage alerts in each owner console and records a screenshot/link without exposing account identifiers.

## Weekly 15-minute ritual

- Review new Sentry issues and crash-free by build.
- Review EAS Update adoption; investigate stranded runtime versions.
- Skim Supabase Auth/Postgres/Storage logs for errors, denials, slow queries, and unusual volume; record counts only.
- Review digest failures and support cases older than 48 hours.
- Assign one owner/date per action; append the sanitized result to NOTES.
