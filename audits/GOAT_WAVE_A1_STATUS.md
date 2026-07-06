# GOAT Wave A1 Status - Time-Standard Intelligence
Date: 2026-07-06

## Result

Wave 1 implementation is committed in both app repos, but the Wave 1 boundary is not fully green
because `BSPC-Coach-App` root `npm run typecheck` remains red on pre-existing project-wide
TypeScript errors. Per the mission stop rules, Wave 2 was not started.

## Premise Check

Times data model found before design:

- Family app:
  - `BSPC/ACTIVE/types/database.ts`
  - `BSPC/ACTIVE/features/progress/api.ts`
  - `BSPC/ACTIVE/features/progress/components/ProgressScreen.tsx`
  - `BSPC/ACTIVE/features/standards/api.ts`
  - `BSPC/ACTIVE/features/standards/transforms.ts`
  - `BSPC/ACTIVE/supabase/migrations/00005_phase_d_times.sql`
- Coach app:
  - `BSPC-Coach-App/src/types/firestore.types.ts`
  - `BSPC-Coach-App/src/services/times.ts`
  - `BSPC-Coach-App/app/swimmer/[id].tsx`
  - `BSPC-Coach-App/app/swimmer/standards.tsx`
  - `BSPC-Coach-App/src/data/timeStandards.ts`

Existing standards logic found:

- Family already had `time_standards` table read/display code, but no per-swimmer motivational
  summary or closest-cut computation.
- Coach had `src/data/timeStandards.ts` plus a standards screen and badges, but the dataset was a
  representative local subset and did not provide the requested shared `swimmerStandardsSummary`
  style API or percentage-gap closest-cut sorting.
- Therefore no complete implementation existed; Wave 1 proceeded.

Event/course handling confirmed:

- Family uses event names such as `50 Free`, `100 Free`, courses `SCY | SCM | LCM`, and
  hundredths fields such as `time_hundredths`.
- Coach uses `SwimTime.event`, `SwimTime.course`, and `SwimTime.time` in hundredths.
- Wave 1 uses those exact event strings and course literals. No cross-course time conversion is
  performed in v1.

## Implementation

Dataset:

- Version: `USA Swimming 2024-2028 Age Group Motivational Standards`
- Source: `https://www.usaswimming.org/docs/default-source/timesdocuments/time-standards/2025/2028-motivational-standards-age-group.pdf`
- Parsed 482 individual event/course/gender/age-group standard sets from the official PDF.
- Relays are intentionally omitted because both apps store individual best-time rows.
- Kevin-gated accuracy flag: dataset values require Kevin spot-check against the official PDF
  before any family-facing release.

Family files changed:

- `BSPC/ACTIVE/lib/standards/usa-swimming-2028.ts`
- `BSPC/ACTIVE/lib/standards/evaluate.ts`
- `BSPC/ACTIVE/features/progress/components/StandardsSummaryCard.tsx`
- `BSPC/ACTIVE/features/progress/components/ProgressScreen.tsx`
- `BSPC/ACTIVE/types/database.ts`
- `BSPC/ACTIVE/__tests__/lib/standards/evaluate.test.ts`
- `BSPC/ACTIVE/__tests__/features/progress/ProgressScreen.test.tsx`

Coach files changed:

- `BSPC-Coach-App/src/standards/usa-swimming-2028.ts`
- `BSPC-Coach-App/src/standards/evaluate.ts`
- `BSPC-Coach-App/src/standards/__tests__/evaluate.test.ts`
- `BSPC-Coach-App/src/data/timeStandards.ts`
- `BSPC-Coach-App/src/components/StandardsSummarySection.tsx`
- `BSPC-Coach-App/src/components/__tests__/StandardsSummarySection.test.tsx`
- `BSPC-Coach-App/app/swimmer/[id].tsx`

Scope confirmations:

- No schema changes.
- No migrations created.
- No new dependencies.
- No raw Supabase calls added to components.
- No live dashboard, deploy, push, EAS, Firebase, DNS, App Store, or Google Play actions.

## Commits

- `BSPC` on `demo/expo-go-compat`: `d88f3f3 Implement password recovery flow` was fast-forwarded
  into the launch line per Director Ruling 58 before Wave 1 preconditions were rerun.
- `BSPC` on `demo/expo-go-compat`: `02651e3 Add time standards intelligence`.
- `BSPC-Coach-App` on `demo/device-build`: `fe869c0 Add swimmer standards summary`.
- Root project docs are not in a git repo; `RULING_58_recovery_merge.md` and this audit file are
  workspace artifacts.

## Test Bars

Precondition Jest bars before first Wave 1 edit:

- Family: `TZ=UTC npm test -- --runInBand` passed, 119 suites, 854 tests.
- Coach: `npm test -- --runInBand` passed, 115 suites, 1161 tests.

Wave 1 targeted bars after implementation:

- Family: `TZ=UTC npx jest __tests__/features/progress/ProgressScreen.test.tsx __tests__/lib/standards/evaluate.test.ts --runInBand`
  passed, 2 suites, 20 tests.
- Coach: `npx jest src/standards/__tests__/evaluate.test.ts src/data/__tests__/timeStandards.test.ts src/components/__tests__/StandardsSummarySection.test.tsx --runInBand`
  passed, 3 suites, 44 tests.

Wave 1 full bars after implementation:

- Family: `npm run typecheck` passed.
- Family: `npm run lint` passed.
- Family: `TZ=UTC npm test -- --runInBand` passed, 120 suites, 864 tests, 10 snapshots.
- Coach: `npm run lint:errors` passed.
- Coach: `npm test -- --runInBand` passed, 117 suites, 1172 tests, 1 snapshot.
- Coach: `npm run typecheck` failed. Representative errors include:
  - `app/_layout.tsx`: missing `subscribeToGroupTopics` export and `User.uid` property errors.
  - `app/season/index.tsx` and `app/season/plan.tsx`: `User.uid` / `User.displayName` errors.
  - `scripts/create-coach.ts` and `scripts/seed-calendar.ts`: missing Firebase module types.
  - Many existing Supabase test mock typing errors around `then` not satisfying `jest.Mock`.
  - `src/services/calendar.ts`: deep Postgrest type instantiation errors.
  - `src/services/notes.ts`: `string` assigned to `Date`.

No new standards files appeared in the Coach typecheck failure output after the Wave 1 fix.

## Stop Decision

STOP after Wave 1. Wave 2 is not allowed to start until Coach root `npm run typecheck` is green
or Kevin issues an explicit ruling changing the gate.

## Kevin-Gated Items

- Spot-check the parsed standards dataset against the official USA Swimming PDF.
- Resolve or formally rule on the existing Coach root `npm run typecheck` red bar before Wave 2.
- Push the local `demo/expo-go-compat` launch-line backup only after Kevin review; no push was
  performed in this mission.
