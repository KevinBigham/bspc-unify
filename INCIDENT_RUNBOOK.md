# Incident Runbook

| Severity | Definition | Initial response |
|---|---|---|
| SEV-0 | Minor safety/privacy exposure, auth bypass, cross-family access, destructive data loss | Stop launch/traffic, revoke affected capability, preserve logs, contact Kevin immediately, legal escalation |
| SEV-1 | Widespread sign-in failure, corrupt writes, unusable practice workflow | Freeze deploys, identify last known good, communicate within 30 minutes |
| SEV-2 | Material degraded feature with workaround | Assign owner, publish workaround, repair in normal incident branch |
| SEV-3 | Cosmetic/local issue | Triage into backlog; no emergency deploy |

## First 15 minutes

1. Name incident commander and scribe; use counts/IDs only.
2. Record UTC start, build/update ID, affected surface, first symptom, and current scope.
3. Check Supabase, Expo/EAS, Firebase scheduler host, Sentry, and PostHog status independently.
4. Disable the narrowest affected feature or EAS update. Never weaken RLS, consent, or approval to restore service.
5. For suspected token/secret exposure, rotate/revoke before debugging convenience.

## Rollback

- JavaScript-only regression: republish the last known-good EAS Update to the affected runtime version; verify adoption and smoke auth/attendance.
- Native regression: halt rollout and direct testers to the previous internal/store build.
- Schema regression: do not down-migrate destructively. Apply a forward repair tested on shadow and preserve migration history.
- Scheduler regression: disable only the named exported job; the two-job allowlist must remain explicit.

## Communication

Use: “We are investigating an issue affecting [surface]. We have contained [scope]. Next update by [time].” Do not name minors or speculate about cause. Privacy/safety incidents use counsel-approved notification timing.

## Close

Require restored metrics, smoke checks, Sentry inspection, root cause, corrective owner/date, and a blameless review. Rehearse this runbook on staging once before beta and append a sanitized record to NOTES.
