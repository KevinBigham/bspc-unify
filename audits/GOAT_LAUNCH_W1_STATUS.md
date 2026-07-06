# GOAT Launch Wave 1 Status

Date: 2026-07-06
Wave: 1 - Coach hardening batch
Status: GREEN

## Scope

- Repository: `BSPC-Coach-App`
- Branch: `demo/device-build`
- Pushed range: `b8394ee..9405fec`

## Commits

- `bc544f0` - functions: restrict v1 launch exports to the two ratified schedulers (Proposal A)
- `e599d24` - functions: harden Supabase runtime config with params and lazy fail-closed init (Proposal B)
- `1c8153e` - Merge proposal-b config hardening
- `9405fec` - Close Coach dead-code gate

## Actions

- Merged `proposal-b-config-hardening` into `demo/device-build`.
- Resolved the single merge conflict in `functions/src/index.ts` by preserving the launch-pinned export surface: only `dailyDigest` and `sweepAttendanceEvaluations` are exported for launch.
- Added `extractMeetSchedule` to the explicit deferred export list/test so the newer meet-schedule code remains source-present but not launch-provisioned.
- Closed the dead-code gate by deleting the unused `AttendanceHeatmap` component, removing one unused standards helper/metadata export, and making internal-only types/constants non-exported.

## Verification

- `npm run quality:dead-code`: PASS
- `npm run typecheck`: PASS
- `npm run lint:errors`: PASS
- `npm test -- --runInBand`: PASS - 123 suites, 1199 tests, 1 snapshot
- `npm --prefix functions test -- --runInBand`: PASS - 16 suites, 190 tests
- `npm run madge:circular`: PASS - 316 files processed, no circular dependencies

## Dependency Changes

- None.

## Push

- Pushed `demo/device-build` to `origin` at `9405fec`.
