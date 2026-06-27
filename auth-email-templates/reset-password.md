# Supabase Reset Password Template

**Dashboard location:** Supabase -> Authentication -> Email Templates -> Reset Password

**Status:** Staged draft. Do not send real recovery email until custom SMTP, send-rate capacity, redirect/deep-link, and one synthetic mobile recovery test are proven.

**Subject:** Set your [TEAM NAME] app password

**Body:**

```html
<p>Hi,</p>

<p>The [TEAM NAME] app has moved to a new system. To finish moving your account, set a new password.</p>

<p><a href="{{ .ConfirmationURL }}">Set my password</a></p>

<p>Your previous password was <strong>not</strong> carried over. This link lets you choose a new one.</p>

<p>This link expires after a limited time. If it expires, open the app and choose "Forgot password" for a new link, or contact [SUPPORT CONTACT].</p>

<p>Don't recognize this account, or weren't expecting this? Contact [SUPPORT CONTACT].</p>

<p>- [TEAM NAME]</p>

<p>If the button doesn't work, copy and paste this address into your browser: {{ .ConfirmationURL }}</p>
```

## Operator Notes

- Replace only bracketed placeholders before dashboard entry.
- Do not replace `{{ .ConfirmationURL }}`; Supabase fills it.
- Do not add a concrete expiration duration until it is verified in Supabase Auth.
- Do not include real family, swimmer, email, or account data in this file.
