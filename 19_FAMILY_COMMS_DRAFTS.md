# 19 — FAMILY COMMUNICATIONS (drafts for Director review)

**Status:** DRAFT — prepared by the EXECUTOR seat; **revised per Director Ruling 05**, 2026-06-23. Sanitized; **no real family/swimmer/email/account data**. All variable content is a placeholder in `[BRACKETS]` (human-filled) or a Supabase template token `{{ .Like_This }}` (system-filled).
**Not sent. Not scheduled.** Paste-ready drafts only; sending is a go-live step gated by the Director and the cutover schedule.

> **Sequencing law (every artifact depends on it):** the announcement (Artifact 1) goes out **before** Firebase sign-in is disabled. The password emails (Artifacts 2a/2b) go out **at/after** cutover, once accounts exist in the new system. **Passwords are never migrated** — every family sets a new one. No artifact may claim or imply an old password was transferred, or that data is fully preserved.

## Flow decision (Director Ruling 05 — taxonomy ratified; delivery gated, announcement not)

**The taxonomy is ratified — two mechanisms, never interchangeable, each with its own accurate template:**

- **Migrated account → RECOVERY** (Artifact 2a). The cutover **pre-creates** every migrated family's account in Supabase Auth with no usable password (OD-6 imports no passwords). The account already exists, so the correct mechanism is **password recovery** ("set a new password for your existing account").
- **Genuinely net-new account → INVITE** (Artifact 2b). A family who was **not** in the migrated data has **no** account yet → an **invite** ("create your account"). Ongoing / fast-follow onboarding, **not** the go-live event.

Mislabeling one as the other is a factual error (an "invite" to someone who already has an account; a "reset" to someone who has none).

> **[Director Ruling 04 §7 / Ruling 05 §2] No automatic recovery blast is proven yet — do not imply one.** Until the send mechanism is proven, the go-live recovery is described as **one of two honest options**, not a guaranteed mass email:
> - **Option A — operator-triggered recovery**, *pending a proven batch send mechanism* (custom SMTP + confirmed send-rate capacity). Until that exists, a team-wide automatic blast is **not** claimed.
> - **Option B — family-triggered recovery** through the app's **Forgot Password** screen (each family initiates it; no batch send required).
>
> **What the recovery-path prerequisites actually gate (Ruling 05 §2):** (1) **custom SMTP** sender; (2) **send-rate capacity** confirmed for the roster volume; (3) a working **redirect/deep-link**; (4) **one synthetic end-to-end mobile recovery test** passed (a throwaway account completes set-password on a real device). These are prerequisites for **triggering real recovery-email delivery to families** and for **disabling Firebase Email/Password sign-in** — they do **NOT** block the **pre-cutover announcement**, which may be sent through the existing **verified team channel**.
>
> **Required order (Ruling 05 §2):** **A.** draft + approve the announcement → **B.** send it through the existing team channel **before** Firebase sign-in is disabled → **C.** prove the recovery path (SMTP, capacity, redirect/deep-link, synthetic mobile reset) → **D.** only then may real recovery messages be triggered and Firebase sign-in later be disabled (under its own separate gate).
>
> **Volume is recorded as a COUNT only** — never addresses or identities (e.g. "≈N migrated accounts"). Which addresses are migrated vs net-new is an operational input Kevin holds; it never appears here.
>
> **[Director Ruling 04 §8] The invite template (2b) stays INACTIVE** until a net-new-family onboarding path exists (tested mobile invite redemption *or* tested, documented staff-assisted onboarding — a **public-launch gate**, `13` Gate 7). Do not claim the net-new invite flow is operational until one exists.

---

## Artifact 1 — Family pre-cutover announcement

*Channel: whatever the team already uses to reach families (email / team-app broadcast / posted notice). Send while the current app still works.*

**Subject:** Action needed soon: set a new password for the [TEAM NAME] app

Hi [Family / Swim Family],

We're moving the [TEAM NAME] app to a new system. When the move goes live on **[LAUNCH DATE]**, you'll set a **new password** before you sign in again.

**Why a new password?** We do **not** carry passwords over during a move like this. Your current password will stop working — it is not transferred to the new system.

**What you'll do:**
1. On **[LAUNCH DATE]**, sign-in through the current app is turned off.
2. Set a new password one of two ways (we'll tell you which applies before launch): open the app and tap **"Forgot password"** to send yourself a reset link, **or** follow the **"Set your [TEAM NAME] app password"** email if we send you one. Either way it goes to the address on file for your account.
3. Tap the link to set a new password and sign in. Please do this by **[RESET DEADLINE]**.

**Before [LAUNCH DATE], please check:**
- **Is the email on your account current?** The password email goes **only** to that address. If you're not sure which email is on file — or you no longer use it — contact **[SUPPORT CONTACT]** before **[LAUNCH DATE]** so we can update it.
- **Didn't get a reset email, or not sure which method applies?** You can always start it yourself in the app with **"Forgot password,"** or contact **[SUPPORT CONTACT]** — we can help you reset or update your address.

The link in that email expires after a limited time. If yours expires, request a new one from the sign-in screen or contact **[SUPPORT CONTACT]**.

Questions or trouble? Contact **[SUPPORT CONTACT]**.

— [TEAM NAME / SENDER NAME]

---

## Artifact 2a — Supabase RECOVERY email (for migrated accounts; delivery not yet proven)

*Supabase → Authentication → Email Templates → **"Reset Password"** (recovery). This is the template body whether the reset is **family-triggered** (Forgot Password) or **operator-triggered** (pending a proven batch send mechanism — see the Flow-decision prerequisites; do **not** run a real mass send, and do **not** disable Firebase sign-in, until custom SMTP + send-rate capacity + redirect/deep-link + the synthetic end-to-end mobile recovery test are proven). Delivers `{{ .ConfirmationURL }}`.*

**Subject:** Set your [TEAM NAME] app password

**Body (HTML or text):**

> Hi,
>
> The [TEAM NAME] app has moved to a new system. To finish moving your account, set a new password.
>
> **[ Set my password ]** → {{ .ConfirmationURL }}
>
> Your previous password was **not** carried over — this link lets you choose a new one.
>
> This link expires after a limited time. If it expires, open the app and choose "Forgot password" for a new link, or contact [SUPPORT CONTACT].
>
> Don't recognize this account, or weren't expecting this? Contact [SUPPORT CONTACT].
>
> — [TEAM NAME]
>
> *If the button doesn't work, copy and paste this address into your browser:* {{ .ConfirmationURL }}

---

## Artifact 2b — Supabase INVITE email (net-new families only — INACTIVE until an onboarding path exists)

*Supabase → Authentication → Email Templates → **"Invite user"**. For a family who was **not** in the migrated data (a genuinely new account). Delivers `{{ .ConfirmationURL }}`. Do **not** send to migrated families — they get Artifact 2a. **[Director Ruling 04 §8] HELD INACTIVE** until a net-new onboarding path exists (tested mobile invite redemption *or* tested, documented staff-assisted onboarding — a public-launch gate). Do not claim the net-new invite flow is operational until one exists.*

**Subject:** You're invited to the [TEAM NAME] app

**Body (HTML or text):**

> Hi,
>
> [TEAM NAME] uses an app for schedules, times, attendance, and team announcements. You've been invited to create your account.
>
> **[ Create my account ]** → {{ .ConfirmationURL }}
>
> This link sets up your account and lets you choose a password.
>
> The link expires after a limited time. If it expires, contact [SUPPORT CONTACT] for a new invite.
>
> Not expecting this invitation? You can ignore this email, or contact [SUPPORT CONTACT].
>
> — [TEAM NAME]
>
> *If the button doesn't work, copy and paste this address into your browser:* {{ .ConfirmationURL }}

---

## Requirement checklist (Director Ruling 04 — all items)

- [x] Passwords do **not** migrate; a new password is required. *(All three artifacts.)*
- [x] Announcement occurs **before** Firebase sign-in is disabled. *(Sequencing law + Artifact 1 step 1.)*
- [x] Removed **"Nothing is lost"** *and* the **"account + swimmer's information move with it"** data-completeness phrasing *(Ruling 04 §7 — neutral wording, no data-completeness promise)*.
- [x] Removed **"more secure."** *(Neutral "a new system.")*
- [x] Removed **"your account won't change until the link is used."** *(Replaced with a "don't recognize this account?" support line.)*
- [x] Does **not** promise migration of every data category. *(No enumerated list of preserved data.)*
- [x] **Support path** for families who no longer control the email on file, or don't receive a message. *(Artifact 1 "Before [LAUNCH DATE]" + both templates point to [SUPPORT CONTACT].)*
- [x] **No link-expiration duration stated** — "a limited time," pending verification of the configured value.
- [x] **Invite vs recovery taxonomy ratified** (Ruling 04) — recovery for migrated accounts (2a), invite for net-new (2b); two distinct, accurate templates.
- [x] **No automatic recovery blast implied** (Ruling 04 §7) — go-live recovery is operator-triggered (pending a proven batch mechanism) *or* family-triggered Forgot Password; no "you will receive" promise.
- [x] **Recovery-path prerequisites stated** — custom SMTP + send-rate capacity + redirect/deep-link + one synthetic end-to-end mobile recovery test, gating **real recovery-email delivery and Firebase sign-in shutdown** (Ruling 05 §2).
- [x] **Announcement decoupled from delivery** (Ruling 05 §2) — the pre-cutover announcement may go through the existing verified team channel; only real recovery delivery + sign-in shutdown wait on the proven recovery path. Order: A announce → B send via channel before sign-in disabled → C prove recovery → D trigger real recovery + disable sign-in.
- [x] **Volume = count only** — no addresses or identities anywhere.
- [x] **Invite template held inactive** (Ruling 04 §8) until a net-new onboarding path exists (public-launch gate).
- [x] Placeholders kept: `[LAUNCH DATE]`, `[RESET DEADLINE]`, `[TEAM NAME]`, `[SUPPORT CONTACT]`.
- [x] No real family, swimmer, email, or account data.

## Open items for the Director / Kevin (not blocking the drafts)

- **Verify the configured link-expiry duration** in Supabase Auth before sending; only then may a concrete duration replace "a limited time" (Ruling 03 forbids stating it unverified).
- **Migrated vs net-new list:** Kevin confirms which addresses are pre-created (→ 2a) vs genuinely new (→ 2b). At a single-team go-live this is usually "all recovery," but confirm.
- **Delivery is a GATE, not a detail (Ruling 04 §7 / Ruling 05 §2, `13` Gate 6):** Supabase's default sender has low deliverability + rate limits. Custom SMTP (`[SMTP PROVIDER]`), confirmed send-rate capacity, a working redirect/deep-link, and **one synthetic end-to-end mobile recovery test** are **prerequisites for real recovery-email delivery and for disabling Firebase sign-in** (the announcement is not gated) — not optional polish.
- **Address hygiene:** the reset link only works if the email on each account is current — Artifact 1's "Before [LAUNCH DATE]" nudge is the mitigation; staff can update an address and re-send on request.
