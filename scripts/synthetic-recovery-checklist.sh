#!/usr/bin/env bash
set -euo pipefail

cat <<'CHECKLIST'
# BSPC Phase 1 Synthetic Recovery Checklist

Purpose: prove the password-reset path end-to-end with one throwaway account before any real recovery email is sent.

Human-only prerequisites:
- Kevin has created the throwaway Supabase project or approved the target.
- Kevin has configured SMTP sender, redirect/deep-link allow-list, and dashboard email templates.
- A real test device is available.

Target gate before any hosted command:
- Print only the Supabase URL.
- Wait for Kevin's explicit "go."
- Never print keys, tokens, email addresses, account UUIDs, or DB passwords.

Procedure:
1. Create one throwaway test account in the approved throwaway Supabase project.
2. Trigger a password reset for that throwaway account only.
3. Open the reset email on a real device.
4. Tap the reset link and confirm it opens the app or approved reset surface.
5. Set a new password.
6. Sign in with the new password.
7. Confirm the session survives app cold start.
8. Confirm the app lands on the expected post-login route.
9. Inspect logs/output for secrets, PII, account identifiers, roster data, and media metadata.
10. Record only a sanitized result in UNIFY/NOTES.md.

Sanitized NOTES.md template:

YYYY-MM-DD Phase 1 synthetic recovery dry run:
- Target: [Supabase URL only]
- Account: one throwaway test account, no real family data
- SMTP: configured / not configured
- Redirect/deep-link: pass / fail
- Device reset flow: pass / fail
- Cold-start session restore: pass / fail
- Result: PASS / FAIL
- Failure category, if any: [sanitized category/count only]
- Secrets/PII in output: none observed / STOPPED and redacted category recorded

Stop conditions:
- Any real family/minor/roster data appears.
- A secret, token, password, service-role key, or private account identifier appears.
- The reset link opens an unapproved URL.
- The account cannot sign in after password set.
- The session does not restore after cold start.
CHECKLIST
