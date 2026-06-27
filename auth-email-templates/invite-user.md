# Supabase Invite User Template

**Dashboard location:** Supabase -> Authentication -> Email Templates -> Invite user

**Status:** Staged draft. Held inactive until a tested net-new family onboarding path exists.

**Subject:** You're invited to the [TEAM NAME] app

**Body:**

```html
<p>Hi,</p>

<p>[TEAM NAME] uses an app for schedules, times, attendance, and team announcements. You've been invited to create your account.</p>

<p><a href="{{ .ConfirmationURL }}">Create my account</a></p>

<p>This link sets up your account and lets you choose a password.</p>

<p>The link expires after a limited time. If it expires, contact [SUPPORT CONTACT] for a new invite.</p>

<p>Not expecting this invitation? You can ignore this email, or contact [SUPPORT CONTACT].</p>

<p>- [TEAM NAME]</p>

<p>If the button doesn't work, copy and paste this address into your browser: {{ .ConfirmationURL }}</p>
```

## Operator Notes

- Use only for genuinely net-new families, not migrated/pre-created accounts.
- Replace only bracketed placeholders before dashboard entry.
- Do not replace `{{ .ConfirmationURL }}`; Supabase fills it.
- Do not add a concrete expiration duration until it is verified in Supabase Auth.
- Do not include real family, swimmer, email, or account data in this file.
