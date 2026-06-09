# 06 — Firebase Go-Live Runbook (beginner-friendly)

**You do NOT need any of this for the migration work or the test suites.**
Every jest suite mocks Firebase entirely, and the code-first migration never
talks to a live Firebase project. You need this runbook only when you want to
**run the apps for real** (Coach App on a phone/simulator, parent portal in a
browser against real data) or **deploy** the security rules and Cloud
Functions. Until then, this file is just sitting here waiting.

| You want to… | You need |
|---|---|
| Run tests / continue the migration | **Nothing.** Skip this runbook. |
| Run the Coach App or parent portal against real data | Sections 1–3 |
| Deploy Firestore/Storage rules + Cloud Functions | Sections 4–5 |
| Seed demo data | Section 6 |
| Understand what changes after the Supabase cutover | Section 7 |

Everything below was derived from the repo itself (`.firebaserc`,
`firebase.json`, `.env.example`, `README.md`) — file paths are exact.

---

## 1. Create the Firebase project (one time, ~5 minutes)

1. Go to **https://console.firebase.google.com** and sign in with the Google
   account that should own the project.
2. Click **"Create a project"** (or "Add project").
3. Project name: type **`bspc-coach`** — use this exact name. The repo's
   [`.firebaserc`](../BSPC-Coach-App/.firebaserc) is already pinned to project
   id `bspc-coach`, and its Storage rules target is pinned to the bucket
   `bspc-coach.firebasestorage.app` (which is the default bucket name a
   project with this id gets). If Firebase says the id is taken and offers
   something like `bspc-coach-1a2b3`, accept it BUT you must then edit
   `.firebaserc` to the new id in both places (the `"default"` entry and the
   storage target key/bucket name).
4. Google Analytics: **disable** it (toggle off) — the app doesn't use it.
5. Click **Create project**, wait for it to finish, click **Continue**.

## 2. Enable the three services (one time, ~5 minutes)

All of these are in the left sidebar under **Build**.

1. **Authentication** → click **Get started** → **Sign-in method** tab →
   click **Email/Password** → toggle **Enable** (leave "Email link" off) →
   **Save**. That is the only sign-in method either app uses.
2. **Firestore Database** → **Create database** → choose location
   **us-central1** (any region works, but you can never change it later) →
   choose **Start in production mode** → **Create**. Don't write any rules in
   the console — the repo's [`firestore.rules`](../BSPC-Coach-App/firestore.rules)
   get deployed in section 5.
3. **Storage** → **Get started** → same region → production mode. (Used for
   swimmer photos and audio/video uploads.)

## 3. Register the web app and paste the six values (~5 minutes)

1. Click the **gear icon** (top of left sidebar) → **Project settings** →
   scroll to **Your apps** → click the **`</>`** (Web) icon.
2. App nickname: anything, e.g. `bspc-coach-web`. Do NOT tick Firebase
   Hosting. Click **Register app**.
3. Firebase now shows a `firebaseConfig` code block with six values. Keep
   that page open.
4. In the repo, copy the template:
   ```bash
   cd BSPC-Coach-App
   cp .env.example .env
   ```
5. Open the new `.env` and fill BOTH blocks from the console values — same
   six values, two prefixes (the Expo coach app and the Next.js portal each
   read their own prefix):

   | firebaseConfig field | → root `.env` line (Coach App) | → also this line (portal) |
   |---|---|---|
   | `apiKey` | `EXPO_PUBLIC_FIREBASE_API_KEY` | `NEXT_PUBLIC_FIREBASE_API_KEY` |
   | `authDomain` | `EXPO_PUBLIC_FIREBASE_AUTH_DOMAIN` | `NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN` |
   | `projectId` | `EXPO_PUBLIC_FIREBASE_PROJECT_ID` | `NEXT_PUBLIC_FIREBASE_PROJECT_ID` |
   | `storageBucket` | `EXPO_PUBLIC_FIREBASE_STORAGE_BUCKET` | `NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET` |
   | `messagingSenderId` | `EXPO_PUBLIC_FIREBASE_MESSAGING_SENDER_ID` | `NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID` |
   | `appId` | `EXPO_PUBLIC_FIREBASE_APP_ID` | `NEXT_PUBLIC_FIREBASE_APP_ID` |

6. **Portal gotcha:** Next.js only reads env files from its own folder, so
   the portal needs its own copy. Create **`parent-portal/.env`** containing
   just the six `NEXT_PUBLIC_FIREBASE_*` lines (paste them from the root
   `.env`). Both files are already gitignored — they must never be committed.
   (These six values are public client config by design, not secrets — but
   the habit of never committing `.env` protects the day a real secret lands
   in one.)
7. Run things locally:
   ```bash
   npm start                              # Expo coach app (from BSPC-Coach-App/)
   npm --prefix parent-portal run dev     # parent portal at localhost:3000
   ```

## 4. Install the Firebase CLI + upgrade to Blaze (only when deploying)

1. The Firebase CLI (`firebase-tools`) is **not installed on this Mac**. No
   global install needed — run it ad hoc:
   ```bash
   npx firebase-tools login      # opens a browser; sign in with the same Google account
   ```
2. **Blaze plan:** deploying Cloud Functions (the repo uses 2nd-gen functions,
   Node 20) requires the pay-as-you-go **Blaze** plan. In the console:
   bottom-left **"Spark plan — Upgrade"** → choose **Blaze** → attach a
   billing account. Pre-launch usage will round to ~$0; you can set a budget
   alert during the upgrade flow.
3. The AI draft features (`extractObservations` etc. via Vertex AI) also need
   the **Vertex AI API** enabled: console.cloud.google.com → select project
   `bspc-coach` → "APIs & Services" → enable **Vertex AI API**. Skippable
   until you care about AI drafts.

## 5. Deploy rules, indexes, and functions

From `BSPC-Coach-App/` (project id comes from `.firebaserc` automatically):

```bash
# Security rules + composite indexes + storage rules — deploy these BEFORE
# real users touch anything (production mode blocks all access until then):
npx firebase-tools deploy --only firestore:rules,firestore:indexes,storage

# The 16 Cloud Functions (needs Blaze, section 4):
npm --prefix functions ci
npx firebase-tools deploy --only functions
```

Function environment values go in **`functions/.env`** (gitignored;
firebase-functions v6 picks up dotenv files at deploy):

- `CALENDAR_ICS_URL=` — optional; only the `syncCalendar` scheduled function
  uses it (an iCal feed URL for the team calendar). Leave unset to skip.
- Post-cutover Supabase values — see section 7.

## 6. Seeding demo data (optional, local convenience)

`npm run seed:demo` (script `scripts/seed-demo-data.ts`) writes demo docs to
the live Firebase project. It needs:

1. A **service-account JSON**: Project settings → **Service accounts** →
   **Generate new private key**. Save it as
   `BSPC-Coach-App/google-service-account.json` (the `FIREBASE_ADMIN_KEY_PATH`
   default in `.env`). **This file is a real secret** — it's gitignored;
   never commit, paste, or screenshot it.
2. `EXPO_PUBLIC_BSPC_ENV` in `.env` left as `local` is the safety belt; the
   seed script is meant for a demo project, not a real-data one.

## 7. What changes after the Supabase cutover

The migration replaces Firebase **Auth** and **Firestore** with Supabase, but
the **Cloud Functions stay hosted on Firebase** (they just read Postgres).
Re-homing them off Firebase is a separate, optional, post-Phase-J decision.

- **Functions deploys additionally need** (in `functions/.env`, or better,
  `npx firebase-tools functions:secrets:set SUPABASE_SERVICE_ROLE_KEY` since
  the service-role key is a real secret):
  - `SUPABASE_URL` — the Supabase project URL
  - `SUPABASE_SERVICE_ROLE_KEY` — **secret**; bypasses RLS, server-only
  (read by `functions/src/config/supabase.ts`)
- **The parent portal additionally needs** in `parent-portal/.env`:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY` — public-safe (RLS enforces access)
  (read by `parent-portal/src/lib/supabase.ts`)
- After the cutover is verified, Email/Password sign-in and Firestore in the
  Firebase console become dead weight and can be disabled — but not before;
  the HARD STOP rule applies to that whole sequence.

## Standing security rules (apply to every step above)

Never commit `.env`, `parent-portal/.env`, `functions/.env`, or any
service-account JSON. Never put real swimmer/family data in a demo project.
The `EXPO_PUBLIC_*` / `NEXT_PUBLIC_*` web-config values are public by design;
the service-account JSON and `SUPABASE_SERVICE_ROLE_KEY` are not.
