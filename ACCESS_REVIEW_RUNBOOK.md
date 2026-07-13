# Quarterly Access Review

Run read-only against the intended environment. Output counts only; do not export names, emails, UUIDs, or roster rows.

```sql
select json_build_object(
  'super_admin', count(*) filter (where role = 'super_admin' and account_status = 'approved'),
  'coach_admin', count(*) filter (where role = 'coach_admin' and account_status = 'approved'),
  'approved_family', count(*) filter (where role = 'family' and account_status = 'approved'),
  'pending_family', count(*) filter (where role = 'family' and account_status = 'pending'),
  'deactivated', count(*) filter (where account_status = 'deactivated')
) from profiles;
```

Verify separately that Kevin is the sole approved `super_admin`, every coach admin is current staff, every approved family has at least one guardianship unless an explicit zero-swimmer approval is documented, and no deactivated profile passes `is_active_account()`.

For discrepancies: do not delete or demote from an audit session. Open a private review record, confirm with Kevin, use the approved admin path, then rerun counts. Append date, environment, query version, sanitized counts, reviewer, and disposition to NOTES. Schedule quarterly and after any staff departure.
