# Parent portal fate decision memo

- Date: 2026-07-12
- Status: decided — retire under Director Ruling 64
- Decision: retire the Next.js parent portal before beta and make the family mobile app the only family-facing product.

The portal already uses direct Supabase reads/RPC rather than the retired Firebase callables, but it duplicates authentication, family authorization review, release hosting, accessibility, incident response, and policy-link obligations. The mobile app now includes invite redemption and the intended family surfaces.

If approved: remove `parent-portal/`, its root tests/knip entries, and the two unused portal callable source modules in one baseline-changing cleanup; document the intentional bar delta; prove no runtime/import/export caller remains; update launch docs and CI. Do not delete hosted resources until Kevin separately authorizes an inventory and teardown.

If retained: it must receive a fresh authorization review, deployment owner, full release checks, policy/support links, and beta/device-browser coverage. Merely leaving source in the repository does not authorize shipping it.
