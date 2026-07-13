# Pre-release Device Checklist

Run against staging builds on one physical iPhone (iOS 15+) and one Android device (Android 9+). Record build IDs, OS versions, time, tester, and sanitized result; never record emails, tokens, swimmer names, or invite codes.

## Automated smoke before touching devices

- Family: run its Maestro login/navigation/recovery/invite flows.
- Coach: run `e2e/maestro/01-login-dashboard.yaml` then `02-attendance-checkin.yaml`; optional notes/practice/media-consent flows follow.
- Confirm Sentry environment is `staging` and test accounts contain synthetic data only.

## Per-device matrix

- Cold launch and authenticated session restore.
- Sign out/in; force refresh failure; verify recovery path remains reachable.
- Airplane mode: queue one Family mutation, restore network, verify one replay and no duplicate.
- Coach voice note: interrupt upload, restore network, verify retry completes once.
- Push: token registration, digest receipt, quiet-hours suppression, cold and warm tap-through.
- Accessibility: VoiceOver/TalkBack labels on auth, tabs, attendance; maximum dynamic type; 44px targets and 60px Deck Mode targets.
- Performance: cold start under 3 seconds on mid-tier Android; 200-swimmer roster scroll/search; large meet results.

## Deep-link 12-cell matrix

Execute each link class for cold and warm app state on both OSes: password recovery, `/invite/:token`, and one content link (announcement or meet). Expected behavior: correct screen, one redemption/transition, sanitized analytics route, graceful expired/invalid state, no capability material in logs.

## Full-practice proof

At one real practice: check-in → attendance → note → time → correction. Verify crash-free session and inspect Sentry afterward. Also execute AM+PM same-date attendance and Deck Mode in sunlight/wet-hand conditions. Every observation becomes a dated finding before any polish change is credited.
