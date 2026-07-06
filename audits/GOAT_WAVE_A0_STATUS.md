# GOAT Wave A0 Status - Coach Typecheck Remediation
Date: 2026-07-06

## Result

Wave 0 is complete. Coach root `npm run typecheck` is green, `npm run lint:errors` is green, and
full Coach Jest remains green. Wave 2 may begin.

## Commit

- `BSPC-Coach-App` on `demo/device-build`: `2b6e252 Fix coach root typecheck`.

## Scope

Fixed type errors only, except for one stale-import runtime bug called out below. No feature work,
no test deletions, no dependency additions, no pushes, no deploys, and no production operations.

## Fix Groups

- Replaced stale Supabase `User.uid` / `User.displayName` reads with `user.id`, `coach.displayName`,
  or `user.email` as appropriate.
- Restored the missing `subscribeToGroupTopics` export as a no-op compatibility shim. This was a
  real runtime bug: app startup imported a symbol that no longer existed after the Supabase/Expo
  push migration.
- Converted two legacy Firebase client scripts to the repo's existing `firebase-admin` pattern, so
  typecheck no longer depends on the uninstalled `firebase` client package.
- Fixed the recursive Supabase calendar query type by introducing a narrow local `EventWindowQuery`
  interface. One `as unknown as EventWindowQuery` assertion remains to cap Supabase's deeply
  recursive generic type; it is intentionally local to the query builder boundary.
- Corrected `SwimmerNote.practiceDate` to a calendar string, matching stored rows and existing
  note/audio/video service usage.
- Updated repeated Supabase test mock annotations so awaitable `then` properties are not forced to
  be `jest.Mock`.
- Added narrow `channel` mock annotations and explicit handler parameter types where strict mode
  previously inferred recursive `any`.

## Verification

- `npm run typecheck`: PASS.
- `npm run lint:errors`: PASS.
- `npm test -- --runInBand`: PASS, 117 suites, 1172 tests, 1 snapshot.

## Notes

- No `ts-ignore` was added.
- No new `any` escape was added.
- Existing test-only `as any` usage outside Wave 0 remains untouched.
