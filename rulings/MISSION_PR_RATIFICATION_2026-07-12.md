# Mission PR ratification — 2026-07-12

The Director retroactively ratified Family PR 19, Coach PR 12, and UNIFY PRs 12–14 on their green hosted CI, conditional on the three evidence read-backs below. Read-backs 1 and 3 are clean. Read-back 2 exposed the double-cast exemption and is remediated by local Coach commit `d534efe`; unconditional ratification awaits that protected-branch PR's green review and merge.

## 1. pgTAP 008 before/after — verbatim changed hunks

```diff
 select columns_are('public', 'swim_results',
   ARRAY['id', 'swimmer_id', 'event_name', 'time_hundredths', 'meet_id', 'date',
-        'is_personal_best', 'created_at', 'course', 'splits', 'meet_name', 'source', 'created_by'],
-  'swim_results has exactly the merged Phase D column set (time_hundredths, no time_ms)');
+        'is_personal_best', 'created_at', 'course', 'splits', 'meet_name', 'source', 'created_by',
+        'import_fingerprint'],
+  'swim_results has exactly the canonical column set including import replay identity');

-select results_eq(
+select throws_ok(
   $$select (select count(*) from public.swim_results),
            (select count(*) from public.personal_bests),
            (select count(*) from public.goals),
            (select count(*) from public.group_notes)$$,
-  $$values (0::bigint, 0::bigint, 0::bigint, 0::bigint)$$,
-  'anon sees zero rows across all four Phase D tables');
+  '42501', null,
+  'anon has no SELECT grant across the Phase D tables');
```

The migration-20 accommodation is schema-shape-only. The anonymous COPPA wall changed from relying on RLS-filtered zero rows to requiring SQLSTATE `42501`, proving SELECT privilege is absent.

## 2. strict-types detector before/after — verbatim

```diff
-# Ban implicit escape hatches. A two-step `as unknown as SpecificRow` assertion is
-# intentionally not part of this gate: Supabase's ungenerated query result type
-# occasionally needs an explicit, reviewable boundary assertion before it enters
-# a typed row mapper. Those assertions remain visible to review and `tsc`; treating
-# them as equivalent to `any` made the quality gate reject valid typed boundaries.
-pattern='(:[[:space:]]*any\b|as[[:space:]]+any\b|<any>|any\[\]|Array<any>|Record<[^>]*any)'
+# Ban implicit escape hatches, including two-step assertions that first erase a
+# value to `unknown` and then assert the desired production type.
+pattern='(:[[:space:]]*any\b|as[[:space:]]+any\b|as[[:space:]]+unknown\b|<any>|any\[\]|Array<any>|Record<[^>]*any)'
+
+# Keep the detector fail-closed: a future edit cannot silently stop recognizing
+# the double-cast form this gate exists to prevent.
+if ! printf '%s\n' 'value as unknown as SpecificRow' | rg -q "$pattern"; then
+  echo "Strict-type detector self-test failed: double-cast escape was not detected."
+  exit 1
+fi
+if printf '%s\n' 'value as SpecificRow' | rg -q "$pattern"; then
+  echo "Strict-type detector self-test failed: a specific assertion was rejected."
+  exit 1
+fi

-  echo "Weak production types found. Replace any/as any with specific types or guarded unknown."
+  echo "Weak production types found. Replace any/as any/as unknown with specific types or guarded unknown."
```

Production `as unknown` and `as any` counts are zero. Ungenerated Supabase results that TypeScript cannot prove now cross explicit runtime object guards. Local bars: client 1,212/129, Functions 191/16, typecheck/build/knip/strict-types green.

## 3. `.gitleaksignore` entries

| Exact pattern | Suppressed file | False-positive reason |
|---|---|---|
| `9405fec73621d72985cd1d35a843211e41f5250c:eas.json:generic-api-key:20` | historical `eas.json` | Exact historical fingerprint for the public Supabase anonymous client key; RLS is the authorization boundary. |
| `eas.json:generic-api-key:20` | current `eas.json` | Worktree-form fingerprint for the same public anonymous client key at the fixed public EAS environment field. |
| `86f6de83f0732befaac7a8d755d4fc47cc75e8bc:eas.json:generic-api-key:20` | historical `eas.json` | Exact historical fingerprint for the same public Supabase anonymous client key. |
| `0350becfed9b28484e7548c2c647d90879ced358:eas.json:gcp-api-key:13` | historical `eas.json` | Firebase web client API key in the public EAS client configuration; not a server credential. |
| `0350becfed9b28484e7548c2c647d90879ced358:eas.json:gcp-api-key:26` | historical `eas.json` | Same public Firebase web client API key in a second build-profile block. |
| `0350becfed9b28484e7548c2c647d90879ced358:eas.json:gcp-api-key:38` | historical `eas.json` | Same public Firebase web client API key in a third build-profile block. |
| `b1fdb3b13555f27937885510c1f5406ea236ebd0:.codex/handoff.json:gcp-api-key:21` | historical `.codex/handoff.json` | Exact historical fingerprint of public Firebase web client configuration copied into a handoff artifact. |
| `b1fdb3b13555f27937885510c1f5406ea236ebd0:.codex/FULL_APP_OVERVIEW.md:gcp-api-key:253` | historical `.codex/FULL_APP_OVERVIEW.md` | Exact historical fingerprint of public Firebase web client configuration documented in an overview artifact. |

No service-role key, private key, password, or bearer token is allowlisted.
