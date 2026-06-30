# BSPC Auth Email Setup — Handoff

_Sender domain: `auth.bspowercats.com` · Supabase project: `bspc-unify` (fqjfunuqbojouyuopnuv) · Team: Blue Springs Power Cats_

## ✅ Done and verified (email/domain pipeline is live)

- **Resend domain `auth.bspowercats.com` — Verified.** DNS records added in **Squarespace** (your DNS host — not Google Cloud), existing Google Workspace records left untouched:
  - `TXT  resend._domainkey.auth` → DKIM key
  - `MX   send.auth` → `feedback-smtp.us-east-1.amazonses.com` (priority 10)
  - `TXT  send.auth` → `v=spf1 include:amazonses.com ~all`
  - Skipped (optional): DMARC record and the inbound/receiving MX. Add later only if needed.
- **Resend API key** "Supabase Auth SMTP" created — Sending access, scoped to `auth.bspowercats.com`. (Shown once in Resend; you copied it. Not recorded here.)
- **Supabase Custom SMTP — saved:** host `smtp.resend.com`, port `465`, username `resend`, sender `noreply@auth.bspowercats.com`, sender name `Blue Springs Power Cats`.
- **Supabase Email provider — enabled** (email + password sign-in).
- **Supabase URL configuration:**
  - Site URL: `bspc-swim://reset-password`
  - Redirect URLs: `bspc-swim://reset-password` and `bspc-swim:///reset-password` (no wildcards)
- **Email templates:** Reset Password and Invite User subjects branded; bodies keep `{{ .ConfirmationURL }}` intact. Optional polished bodies are below.

## ✅ Blocker resolved — signup trigger made safe

**What was wrong:** the signup trigger `on_auth_user_created` on `auth.users` runs `public.handle_new_user()`, which inserts a row into `profiles`. That function is correct and matches your canonical schema — but the `profiles` table doesn't exist in this project yet, so every signup failed with `relation "profiles" does not exist`.

**What I did (reversible):** I couldn't disable the trigger (Supabase locks `auth.users` changes to its auth-admin role), so I made the **function** tolerant — it still inserts the profile, but if `profiles` is missing it skips without breaking signup. It **auto-heals**: the moment you create the canonical `profiles` table, it resumes creating profile rows with no further changes. Applied function:
```sql
create or replace function public.handle_new_user() returns trigger language plpgsql security definer as $function$
begin
  begin
    insert into profiles (user_id, email, full_name, role, account_status)
    values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name','New User'), 'family', 'pending');
  exception when undefined_table then null;  -- profiles not created yet; don't block signup
  end;
  return new;
end; $function$;
```

**To restore the original strict version later** (after `profiles` exists):
```sql
create or replace function public.handle_new_user() returns trigger language plpgsql security definer as $function$
begin
  insert into profiles (user_id, email, full_name, role, account_status)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name','New User'), 'family', 'pending');
  return new;
end; $function$;
```

**Caveat:** any users created while `profiles` is missing won't have a profile row. Fine for the throwaway test user (delete it after); apply your real schema before real users sign up.

### Still recommended (the real fix)
Apply your canonical schema / migration (`03_MIGRATION_PLAYBOOK.md`) so `profiles` (and the rest) exist. After that the trigger creates profiles automatically and you can restore the strict function above.

### Create the test user
Authentication → Users → Add user → **Create new user**. Keep **"Auto confirm user?"** checked. Use a disposable alias (e.g. `you+bspctest@gmail.com`).

## Polished template bodies (optional)
Paste into Supabase → Authentication → Emails → Templates → (template) → **Source**. `{{ .ConfirmationURL }}` must stay exactly as-is. Replace "Blue Springs Power Cats support" with a real email/phone when you have one.

### Reset password
```html
<h2>Reset your password</h2>
<p>Hi,</p>
<p>We received a request to reset the password for your Blue Springs Power Cats account.</p>
<p>Tap the button below to choose a new password. For your security, this link will expire soon.</p>
<p><a href="{{ .ConfirmationURL }}">Reset password</a></p>
<p>If you didn't request this, you can safely ignore this email — your password won't change.</p>
<p>Need help? Contact Blue Springs Power Cats support.</p>
<p>&mdash; Blue Springs Power Cats</p>
```

### Invite user
```html
<h2>You're invited to Blue Springs Power Cats</h2>
<p>Hi,</p>
<p>You've been invited to join the Blue Springs Power Cats app.</p>
<p>Tap the button below to accept your invitation and set up your account.</p>
<p><a href="{{ .ConfirmationURL }}">Accept invitation</a></p>
<p>If you weren't expecting this, you can ignore this email.</p>
<p>Questions? Contact Blue Springs Power Cats support.</p>
<p>&mdash; Blue Springs Power Cats</p>
```

## Unrelated note (not touched)
Your **root** `bspowercats.com` has two SPF `TXT` records (one is malformed with literal quotes: `'v=spf1 include:_spf.google.com ~all'`). Two SPF records on one host is invalid and can hurt Google Workspace deliverability. Worth cleaning up the malformed one separately — left alone here since it wasn't part of this task.
