# Director Ruling 60 — urgent pushes bypass quiet hours

- Date: 2026-07-12
- Status: in force
- Decision owner: Director / Kevin
- Supersedes: the prior all-tier 21:00–07:00 suppression policy
- Evidence reviewed: `BSPC/ACTIVE/supabase/functions/send-notification/index.ts`; `BSPC/ACTIVE/supabase/functions/_shared/quiet-hours.ts`

## Decision

URGENT-tier pushes bypass the 21:00–07:00 America/Chicago time window. Normal and FYI pushes remain suppressed during that window. Urgency never overrides an individual family's push opt-out.

## Scope

This authorizes the Family send-notification implementation and regression tests. It does not authorize an Edge Function deployment or change any family's consent preference.

## Consequences

The eligibility decision must combine tier, time, and opt-in state in one tested policy. A 05:30 cancellation reaches opted-in families; an opted-out family receives no push at any tier.

## Human gates

Kevin reviews and merges the protected-branch PR and separately authorizes any deployment.
