# OD-3 account approval policy

- Date originally ratified: 2026-05-30 (recorded in `NOTES.md`)
- Formalized: 2026-07-12
- Status: in force

All new accounts require staff approval. Parent invite redemption creates a guardianship link but never changes `profiles.account_status`; a pending parent retains only the deliberately narrow pending-account scope until a coach admin approves the profile. Coach accounts are provisioned by an authorized admin and never auto-promote. No first-login auto-admin path exists.

Implementation evidence: migration `00019_family_approval_rpc.sql` makes family approval atomic; `redeem_parent_invite` is pinned not to write profiles; the family app has pending-state UX and invite redemption tests; approved-only content gates are in migration `00018` and pgTAP files 017/018.
