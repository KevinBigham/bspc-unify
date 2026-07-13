# M9 Monorepo Plan

This plan begins only after both v1.0.0 tags and `LAUNCH_BASELINE.md` are frozen. It does not authorize pre-launch repository moves.

## Target tree

```text
apps/family/          Expo Family app
apps/coach/           Expo Coach app
apps/portal/          Next.js portal, only if item 76 keeps it
packages/domain/      groups, courses, standards, time/date contracts
packages/backend/     generated Supabase types and safe query helpers
supabase/              canonical migrations, seed, pgTAP
governance/            rulings, mission, launch baseline
```

## History-preserving dry run

1. Create a private throwaway integration repository and tag all source heads.
2. Use `git subtree add --prefix=apps/family FAMILY_REMOTE v1.0.0` and equivalent Coach/UNIFY commands; never copy without history.
3. Move already-shared domain code first and make both apps consume one package.
4. Preserve release tags and write a mapping table from old commit/tag to new commit.
5. Run every legacy repo command plus clean workspace installs, mobile bundles, portal build if retained, pgTAP, gitleaks, OSV, and madge.
6. Compare generated native identifiers, EAS project IDs, runtime versions, Functions deploy targets, and Supabase migration hashes.
7. Trial one PR/release/update from the new repository without changing production.

## Go/no-go

Proceed only with green parity, reviewed history mapping, rollback instructions, and a Director ruling. Keep old repositories read-only for provenance after cutover; do not delete them.
