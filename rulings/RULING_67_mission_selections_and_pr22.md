# Director Ruling 67 — mission selections and PR 22 disposition

- Date: 2026-07-12
- Status: in force
- Decision owner: Director / Kevin
- Supersedes: none
- Evidence reviewed: Family PR 22; `STATE_OF_THE_UNION.md`; `GOAT_EXECUTION_STATUS.md`; Coach `functions/src/index.ts`

## Decision

Family PR 22 is approved to merge after a verbatim `scheduler_runs` access
read-back proves there is no family, anonymous, or public-client path. GOAT 43
truth reconciliation is selected for UNIFY. GOAT 95 scheduler-host retirement
is selected for Coach after PR 22 lands. The Family push retry/dead-letter
follow-on selected by Ruling 66 starts after PR 22 as a separate dark mission.

## Scope

The Coach mission must disposition all four scheduled Firebase functions:
`dailyDigest`, `sweepAttendanceEvaluations`, `sweepStuckSessions`, and
`syncCalendar`. It must pin the resulting runtime export surface and document
every retained non-scheduler Function. The UNIFY mission records current heads,
bars, and resume gates without claiming an owner gate complete. The Family
mission may implement and prove retry/dead-letter behavior locally, but may not
deploy or activate it.

## Consequences

PR 22 merged to `demo/expo-go-compat` as `42050b4` after every hosted check
passed. Its final tree exactly matches the hosted-green PR head. The new pinned
Family bars are Jest 933/134, pgTAP 480/21, and Deno 5/5. All successor missions
remain draft PRs until separately ordered ready and merged.

## Human gates

Production probing still requires the Director's exact credential-corrected
authorization phrase. Throwaway/staging extension verification, secret
provisioning, function deployment, every schedule object, and every production
activation remain Kevin-gated. Legal, store/account, device, DNS/mailbox,
elapsed-beta, and launch actions remain owner-only and incomplete.
