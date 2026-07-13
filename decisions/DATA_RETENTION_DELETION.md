# Data Retention and Deletion Policy Decision

**Status:** Awaiting lawyer and owner ruling
**Do not implement from this draft without counsel approval.**

## Proposed operational model

- Deactivate access immediately when a family leaves or staff relationship ends; preserve an audit-safe minimal record while the deletion request is verified.
- Verify a parental deletion request through the existing authenticated account plus an out-of-band staff check. Never accept a bearer invite/recovery link alone as deletion authority.
- Remove guardianships first to terminate family visibility, then execute the counsel-approved cascade for profile/family, feedback, push tokens, swimmer records, attendance, results, notes, and media.
- Shared swimmer custody requires resolving whether another verified guardian or legitimate club record basis remains; one guardian must not silently delete another household's lawful access/records.
- Delete private Storage objects before or transactionally coordinated with database pointers; record counts/object prefixes only.
- Preserve only the minimum legal/security audit evidence counsel specifies, separated from app-visible data and with a defined expiry.

## Required ruling inputs

Counsel must define retention periods, club record obligations, minor/guardian authority, SafeSport incident-record exceptions, backup/PITR expiry, processor deletion duties, and response/notification timing. Kevin must name the approver and monitored privacy channel.

After ruling: implement one SECURITY DEFINER deletion RPC or server-only workflow, add dry-run/count-only mode, prove it on shadow including shared-custody and media cases, rehearse restore/irreversibility boundaries, and update public policy text.
