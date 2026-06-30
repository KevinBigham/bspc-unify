# 21 — SUPABASE AUTH DASHBOARD CHECKLIST

**Status:** Kevin-owned dashboard checklist for Milestone 1. This document stores no
secrets, passwords, email addresses, account IDs, roster data, or real
family/minor data.

Use this against the approved Supabase target only:

```text
https://fqjfunuqbojouyuopnuv.supabase.co
```

If this throwaway project is replaced by a final production project, repeat this
checklist on the final project before any real family data is entered.

## Hard Rules

- Do not paste passwords, SMTP credentials, API keys, or account identifiers into
  chat, docs, shell commands, or notes.
- Use one throwaway test account only. Do not use a real family, swimmer,
  guardian, roster, or staff account for the synthetic recovery proof.
- Do not send recovery or invite email to real families until the throwaway
  reset test passes on a real device.
- Record only sanitized pass/fail status in `NOTES.md`.

## Dashboard Steps

1. Open Supabase Dashboard for the approved target.
2. Go to **Authentication → Providers → Email**.
3. Enable email/password sign-in.
4. Go to **Authentication → Emails** (or **Email notifications**) and configure
   the custom SMTP sender.
   - Kevin owns the SMTP provider, credentials, sender identity, and any billing.
   - Confirm the provider can send enough messages for the expected roster size.
   - Do not record SMTP credential values anywhere in this repo.
5. Go to **Authentication → Email Templates → Reset Password**.
   - Copy the subject and body from `auth-email-templates/reset-password.md`.
   - Replace only bracketed placeholders like `[TEAM NAME]` and
     `[SUPPORT CONTACT]`.
   - Do not replace `{{ .ConfirmationURL }}`.
6. Go to **Authentication → Email Templates → Invite user**.
   - Copy the subject and body from `auth-email-templates/invite-user.md`.
   - Replace only bracketed placeholders.
   - Do not replace `{{ .ConfirmationURL }}`.
   - Keep this template inactive for real families until the net-new onboarding
     path is tested.
7. Go to **Authentication → URL Configuration**.
   - Set the Site URL to the approved app or reset surface.
   - For the current mobile reset proof, the approved redirect URLs are
     `bspc-swim://reset-password` and `bspc-swim:///reset-password`.
   - Add future web reset URLs only after the portal/reset host exists.
   - Do not add broad wildcard URLs unless Kevin explicitly approves that risk.
8. Create exactly one throwaway test user in **Authentication → Users**.
   - Kevin controls the inbox.
   - The email address and user ID stay out of docs, chat, shell history, and
     logs.
9. Tell Codex `done`.

## What Codex Runs Next

After Kevin reports `done`, Codex will run the local checklist script:

```bash
./scripts/synthetic-recovery-checklist.sh
```

Then, with Kevin operating the real device and inbox, the synthetic flow is:

1. Trigger reset for the throwaway account only.
2. Open the reset email on a real device.
3. Tap the reset link.
4. Confirm it opens the approved app/reset surface.
5. Set a new password in the BSPC app reset screen.
6. Sign in.
7. Cold-start the app.
8. Record only sanitized pass/fail status in `NOTES.md`.

## Stop Conditions

- Any real family/minor/roster/staff data appears.
- Any secret, token, password, private account identifier, or SMTP credential
  appears in output.
- The reset link opens an unapproved URL.
- The throwaway account cannot sign in after setting the password.
- The session does not restore after cold start.

## References

- Supabase Auth email templates:
  https://supabase.com/docs/guides/auth/auth-email-templates
- Supabase custom SMTP:
  https://supabase.com/docs/guides/auth/auth-smtp
- Supabase URL configuration:
  https://supabase.com/docs/guides/auth/redirect-urls
- Supabase mobile deep-linking:
  https://supabase.com/docs/guides/auth/native-mobile-deep-linking
