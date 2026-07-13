# GOAT Execution Status

**As of:** 2026-07-12
**Scope:** all 100 numbered items in `BSPC_GOAT_AUDIT.md` §12, executed in the order prescribed by `BSPC_GOAT_EXECUTION_ORDER.md`.
**Status law:** `DONE` requires a durable artifact plus verification. `PARTIAL` means useful work exists but at least one acceptance clause is unproven. `OWNER` requires Kevin/Director identity, a physical device, a paid/external account, legal advice, or an explicit product ruling.

Pinned hosted bars: Family 933 tests / 134 suites plus pgTAP 480 / 21 files and Deno 5/5; Coach 1,205 / 127; Functions 171 / 15; portal source and callables retired. Both application roots typecheck on Node 22. These bars are evidence, not substitutes for production, device, or owner gates.

Active candidate bars remain unmerged: Family PR 23 is green at `d92f509` (Jest 933/134, pgTAP 537/22, Deno 22/22); Coach PR 15 is green at `ab26ca0` (client 1,205/127, Functions 158/13, zero runtime exports); UNIFY PR 17 is green at its current head. All three remain drafts and no owner gate is credited.

| # | State | Acceptance evidence or exact remaining gate |
|---:|:---:|---|
| 1 | DONE | `Mission.md` now names the restored public launch heads and measured bars. |
| 2 | DONE | Canonical SQL contains the shipped 9-group enum and storage truth through migrations 00014/00015. |
| 3 | DONE | Family `supabase/config.toml` enumerates every migration through 00022. |
| 4 | DONE | Applicable historical UNIFY docs and consumed audit prompt carry the Rulings 56/57 banner. |
| 5 | PARTIAL | Family PR 19 and Coach PR 12 merged green into their launch lines; promotion from those lines to `main` correctly waits for item 9 GREEN and item 21 live rotation. |
| 6 | DONE | `STATE_OF_THE_UNION.md` exists; update it at every subsequent mission close. |
| 7 | DONE | `rulings/INDEX.md`, template, and Rulings 56–58 are indexed. |
| 8 | DONE | Append-only `NOTES.md` template adopted and new entries appended chronologically. |
| 9 | OWNER | The authorized retry reached the endpoint but failed authentication before any query; classification remains UNCLASSIFIED/STOP pending corrected credentials and a new per-command `go`. |
| 10 | OWNER | Production `db push` needs probe GREEN and Kevin's explicit go; migration history must then be captured. |
| 11 | OWNER | A separate prod-shaped remote shadow project is not provisioned; local Supabase is green but is not credited as the remote shadow. |
| 12 | OWNER | Strict function is pinned/tested locally; production definition still requires read-only verification. |
| 13 | OWNER | Throwaway production recovery user can only be deleted after item 19. |
| 14 | PARTIAL | Orphan policy/test support exists locally; production count-only sweep and disposition are pending credentials. |
| 15 | OWNER | Bucket names/caps/RLS are tested locally; production re-verification awaits item 10. |
| 16 | PARTIAL | Scheduled read-only audit workflow and sanitized artifact exist; the protected environment/secret must be owner-provisioned and observed once. |
| 17 | OWNER | Backup/PITR plan selection and a real shadow restore rehearsal remain. |
| 18 | OWNER | Staging project, credentials, and end-to-end staging release check remain. |
| 19 | OWNER | Physical iPhone and Android recovery matrix with real email is required. |
| 20 | DONE | All recovery token/error shapes and expired UX are covered; current Family bar is 924. |
| 21 | PARTIAL | Placeholder scanner/allowlist exists; live demo accounts still need rotation/disable and tracked history proof. |
| 22 | DONE | Ruling 63 ratifies ADMIN-APPROVE; invite redemption never auto-approves, and the atomic approval RPC is tested. |
| 23 | OWNER | Bootstrap guards exist; shadow dry-run and Kevin's live sole-super-admin execution remain. |
| 24 | DONE | Cold restore, refresh failure, inactive lockout, and pending-account scope have named tests. |
| 25 | PARTIAL | Client exponential backoff and abuse posture are tested/documented; hosted rate-limit confirmation and signup-burst alert remain. |
| 26 | OWNER | DNS SPF/DMARC mutation and Gmail/Outlook/iCloud deliverability need domain-owner access. |
| 27 | OWNER | Lawyer engagement/send cannot be evidenced from this workspace. |
| 28 | OWNER | Redlined public policy URLs and monitored privacy/support mailboxes remain. |
| 29 | PARTIAL | pgTAP media walls and Coach consent affordance/service tests are green; physical-device affordance proof remains. |
| 30 | OWNER | Await lawyer-defined consent architecture; the agent must not invent compliance. |
| 31 | PARTIAL | Family and Coach have Gitleaks CI/hooks and green full-history scans with documented public-client-key fingerprints; UNIFY still lacks scanner CI, a pre-commit variant, and its own full-history report. |
| 32 | DONE | Critical audit gates and OSV reporting are in both CIs; all four package roots have zero critical advisories, with remaining major-only debt documented. |
| 33 | DONE | Family deep-link threat model, sanitized analytics route, and no-token logging tests exist. |
| 34 | DONE | Shared redaction helper/tests protect the production audit and the DB-output inventory proves other scripts print only static repository validation. |
| 35 | OWNER | Retention/deletion semantics require Director/legal ruling before implementation and shadow proof. |
| 36 | PARTIAL | `ACCESS_REVIEW_RUNBOOK.md` contains the count-only query and escalation path; the first production run remains owner-gated. |
| 37 | PARTIAL | Both apps now scrub user identity, auth/cookies, email, JWT, and capability URLs before transport; configured projects and inspected canary remain owner-gated. |
| 38 | DONE | Ruling 64 retired the parent portal and its two callables; Coach PR 14 merged green. |
| 39 | DONE | Family CI resets local Supabase and runs the 480-assertion / 21-file pgTAP suite. |
| 40 | PARTIAL | Family enforces migration inventory/domain/metadata checks, Coach enforces its shared-domain copy, and UNIFY compares all three domain contracts to canonical enum values; the required full canonical-SQL↔migration assertion and all-repo CI enforcement are not implemented. |
| 41 | PARTIAL | Coach typecheck, knip, strict-type, randomness, process, and circular-dependency gates are green; the roadmap's explicit durable ruling declaring the line shippable is still absent. |
| 42 | DONE | Ruling 61 ratifies Node 22; engines, `.nvmrc`, Functions, portal, and CI are aligned and verified. |
| 43 | PARTIAL | Ruling-67 reconciliation separates merged launch pins from the three hosted-green draft heads and preserves exactly three resume gates; public policy/store/device and every other owner row remain WAITING. |
| 44 | OWNER | Family EAS project initialization/projectId needs the Expo account owner. |
| 45 | PARTIAL | 9-group copy is corrected; screenshot regeneration and store-form drafts/final values remain. |
| 46 | DONE | Family threshold is enforced and both CIs publish coverage/test artifacts; Coach has explicit global thresholds. |
| 47 | OWNER | GitHub branch-protection mutation requires owner confirmation after required checks exist. |
| 48 | DONE | `docs/reproducible-builds.md` records exact clean-install commands and lockfile policy; clean local builds are green. |
| 49 | OWNER | Four EAS internal builds and physical install matrix require staging, EAS/store accounts, and devices. |
| 50 | DONE | Coach login/navigation/attendance Maestro flows and the cross-app pre-release device checklist are wired as the mandatory release sequence. |
| 51 | OWNER | One full real-practice run plus Sentry inspection is a physical field gate. |
| 52 | OWNER | Offline queues have unit tests; device airplane-mode/voice retry/cold-restore execution remains. |
| 53 | OWNER | Recovery/invite routing tests exist; the 12-cell cold/warm × iOS/Android device log remains. |
| 54 | OWNER | Push routing/quiet-hours have code tests; real token/delivery/tap-through needs staging devices. |
| 55 | OWNER | Requires measured 200-swimmer/device startup data before the top-three fix pass. |
| 56 | PARTIAL | Accessibility implementation exists on core surfaces; systematic device screen-reader/max-type audit remains. |
| 57 | DONE | Family invite redemption screen, token deep link, MSW tests, and pending-only semantics are implemented. |
| 58 | DONE | Family has an executable exact 24-route loading/error/empty matrix plus a readable audit; the sweep added a retryable notification-preference failure state. |
| 59 | DONE | Today reads recent `schedule_change_log` summaries and renders neutral New/Changed/Back-on badges with API/component tests. |
| 60 | DONE | Shared date/time utilities and deterministic timezone tests are in both app trees. |
| 61 | DONE | Ruling 60 is merged: urgent bypasses the 21:00–07:00 CT time window, normal/FYI remain suppressed, and opt-out blocks every tier; current Family bar is 933/134. |
| 62 | DONE | Commit prevents in-app navigation, uses `Linking.openURL`, tracks failure, and returns with a useful toast under named tests. |
| 63 | DONE | Glossary search/filter/empty states and horizontally safe standards filters/table exist; a named AR-1 test proves free-text standards render. |
| 64 | DONE | One shared hundredths parser/formatter is used by both apps with round-trip coverage. |
| 65 | OWNER | Sunlight/wet-hand Deck Mode QA is a physical-device gate. |
| 66 | PARTIAL | Kind pending-state copy, gated data, coach escalation, and configured support mailto are tested; the monitored mailbox value remains owner-gated. |
| 67 | PARTIAL | Pure 200-swimmer filter/sort is under 100ms and roster aggregation fanout fell from ~400 channels to one; physical perceived/two-tap measurement remains. |
| 68 | OWNER | AM+PM same-day attendance requires on-device proof. |
| 69 | OWNER | Taxonomy change requires Kevin's real-usage review. |
| 70 | DONE | Checked-in adversarial SDIF/HY3 golden files cover malformed rows, weird IDs, DQ, and unknown events with coach-readable line errors. |
| 71 | DONE | Migration 00020 adds import identity; conflict-safe upserts and an import-twice test prove idempotency while PR counts remain trigger-owned. |
| 72 | OWNER | Kevin's authoritative coaching corpus is not available in the workspace. |
| 73 | DONE | AST tests prove AI upload/navigation affordances unreachable; consent is prominent and service-enforced; signed uploads target Supabase Storage. |
| 74 | DONE | Coach generate/share/status/revoke parent-invite flow and tests exist. |
| 75 | DONE | `docs/aggregation-contract.md` maps every screen/service to pgTAP-014 views; tests pin mappings, source refresh, and all fresh-club empty cases. |
| 76 | DONE | Ruling 64 retirement merged in Coach PR 14 with its intentional post-retirement baseline pinned. |
| 77 | PARTIAL | Ruling 65 Phase 1 merged in Family PR 22 with leases/retries/dead state and dark Edge Sentry; staging extension proof and any activation remain gated. |
| 78 | PARTIAL | Direct-SQL daily digest parity and idempotency are pgTAP-green; authorized remote staging proof remains. |
| 79 | PARTIAL | Sweep idempotency/retry behavior is locally and shadow-green; authorized remote staging run-twice proof remains. |
| 80 | PARTIAL | UID/nullable-coach and mutated-feed tests now prove timing refresh preserves coach-authored fields; remote-shadow proof remains and runtime export stays disabled. |
| 81 | PARTIAL | `seed-roster.ts` exists; remote-shadow execution with RLS visibility assertions remains. |
| 82 | PARTIAL | Migration 00021 adds staff-only approval audit and pre-write collision rejection; duplicate approval/RLS/rollback primitives are pgTAP-green, but the remote-shadow scenario remains. |
| 83 | OWNER | Aggregation staleness semantics require Director ruling before implementation. |
| 84 | DONE | Canonical header explicitly closes P2-8 for fresh launch and re-defers P2-5/P2-9 with one-line reasons and prerequisites. |
| 85 | DONE | `M4_ONBOARDING_OPERATOR_CHECKLIST.md` specifies dry-run, RLS proof, approval, duplicate, rollback, and stop conditions. |
| 86 | PARTIAL | Fresh-launch announcement/invite/recovery copy and safe order are finalized; review and real sends remain Kevin/counsel-owned. |
| 87 | OWNER | Real monitored mailboxes and feedback closure loop remain. |
| 88 | PARTIAL | One-page severity/containment/rollback/comms runbook exists; one staging tabletop record remains. |
| 89 | OWNER | Sentry routing to Kevin and calendar ritual require owner accounts. |
| 90 | PARTIAL | Five-number privacy-safe dashboard contract is documented; project/dashboard configuration requires owner access. |
| 91 | OWNER | A complete 3–5-family, 14-day script and exit criteria exist; elapsed beta evidence cannot be simulated. |
| 92 | OWNER | Timed launch-day staging rehearsal depends on staging and store accounts. |
| 93 | DONE | Coach README/ROADMAP/CODEBASE_GUIDE and templates are Supabase-native, Node-22/launch-line accurate; both READMEs name launch lines. |
| 94 | DONE | Rulings 59 and 62 retain `ACTIVE/migration/` as historical-only with a root banner, no runtime/CI execution, and measured zero bar delta. |
| 95 | PARTIAL | Coach PR 15 dispositions all four schedulers, pins zero runtime exports, documents every remaining non-scheduler Function, and is hosted-green at `ab26ca0`; it remains a draft awaiting Director ready/merge authority. |
| 96 | DONE | Coach `shared/domain` plus drift-checked Family copy contain groups/courses/standards/time truth. |
| 97 | DONE | `M9_MONOREPO_PLAN.md` defines target tree, subtree history preservation, parity checks, rollback, and post-tag gate. |
| 98 | OWNER | Usage alerts require Supabase/Sentry/PostHog owner access; paid-trigger policy remains documentable. |
| 99 | PARTIAL | `COST_AND_OBSERVABILITY_POLICY.md` adds EAS adoption and the count-only Supabase log skim to the weekly ritual; console enablement and first review remain owner-gated. |
| 100 | OWNER | Forbidden until every prior gate is complete: green hosted CI, prod GREEN, device links, tag, baseline, announcement, and LAUNCHED ruling. |

## Current execution frontier

The repository-owned frontier includes the three active Ruling-67 draft closeouts plus the newly re-opened GOAT 31 and 40 CI gaps. Those CI gaps start only after the current train missions close or the Director explicitly selects them; one-mission-per-train still applies. Production, legal, account, device, beta-duration, and final-ship states are deliberately not represented as complete without evidence.
