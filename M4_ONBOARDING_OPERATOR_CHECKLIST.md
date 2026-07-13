# Staff-assisted Family Onboarding Operator Checklist

Use staging/shadow first. Use only approved club records in production and never paste PII into terminals, tickets, or NOTES.

1. Confirm the family profile is `pending`, role `family`, and not deactivated.
2. Confirm the intended swimmers and practice groups with the guardian using the club's approved process.
3. Search existing swimmers by club identifier and then normalized name/date; stop on ambiguity rather than creating a collision.
4. For roster seeding, run `npm run seed:roster -- --dry-run` with a private ignored CSV. Expect count-only JSON.
5. On shadow, run without `--dry-run` and with `--verify-rls`. Expect inserted/skipped counts and `staffRlsVerified: true`.
6. Approve through the Family admin UI, which calls the atomic `approve_family` RPC. Never reproduce its multi-table writes in a client script.
7. Verify one family row, approved profile link, intended swimmers, guardianships, and approval-log entry. Use IDs/counts only in evidence.
8. Sign in as the synthetic guardian: linked swimmers visible; unrelated swimmers, notes, attendance, media, and results invisible.
9. Repeat the same roster input and approval attempt. Expected: roster replay inserts zero; already-approved RPC rejects without new family/link rows.

## Rollback on shadow

Delete the synthetic auth user through the admin API and confirm cascades/cleanup match the retention policy. If a real record is wrong, do not improvise SQL: deactivate access, open a privacy-safe incident, and use the approved deletion/correction procedure.

## Escalate immediately

Stop for duplicate identity ambiguity, unexpected family visibility, missing guardianship, partial approval state, PII in logs, or any need to use service-role credentials in a client environment.
