# Aggregation Staleness Policy

**Status:** Awaiting owner ruling
**Recommendation:** treat the four launch aggregation views as compute-on-read, not cached truth.

The current `agg_swimmer_attendance`, `agg_swimmer_prs_notes`, `agg_dashboard_attendance`, and `agg_dashboard_activity` surfaces are views over canonical source tables. They do not need a recompute scheduler. Their `updated_at`/activity timestamps describe source freshness, while the client query timestamp describes when the view was read.

Proposed v1 policy:

- Label parent/coach aggregation cards “Updated [relative read time]”; never “Live”.
- Refetch on source-table Realtime events and pull-to-refresh.
- If a read is older than 15 minutes while online, show “May be out of date” and refetch.
- Offline cached data always shows “Last updated [time]”.
- No materialized aggregation may be introduced without an owner, recompute trigger, failure alert, and visible data-as-of marker.

Owner acceptance of this memo closes schema P2-5 without adding a scheduler. If rejected in favor of materialization, implementation and shadow failure proofs are required before launch.
