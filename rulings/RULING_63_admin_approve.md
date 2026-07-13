# Director Ruling 63 — parent accounts require admin approval

- Date: 2026-07-12
- Status: in force
- Decision owner: Director / Kevin
- Supersedes: any auto-approval interpretation of OD-3
- Evidence reviewed: `decisions/OD3_APPROVAL_POLICY.md`; migrations `00018`, `00019`, and `00021`

## Decision

OD-3 is ADMIN-APPROVE. Parent invite redemption may establish a guardianship, but no parent account auto-approves while minors' data is live. Only an authorized staff approval path changes the account to approved.

## Scope

This binds Family pending-state UX, invite redemption, approval RPCs, RLS, and Coach approval workflows.

## Consequences

Pending accounts retain only the narrow pending scope. Approval stays atomic and audited; invite redemption never writes approved status.

## Human gates

Kevin retains production bootstrap and account-review authority.
