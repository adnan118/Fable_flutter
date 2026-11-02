# RC96 — P2 Profile, managed accounts and role-bound UI (first increment)

## Transition
- RC95 Flutter/main merged: `664e4a5ce225cf48543311a424ea31beb3ebbfc4`. The mobile Auth core/API workflows are source-implemented and CI-verified; live identity providers and devices remain P6 E2E gates.
- Backend private RC66 SHA `226cbcdc542ebe9c005d7445d84cc0ec10631932` remains unchanged; no simulation can substitute for live database acceptance.
- Auth ledger is still the RC93 baseline `22/40` until source-evidence reconciliation. The extra mobile operations implemented in RC94/RC95 are **not** yet reflected in that counter. Do not advertise 31/40 as a validated ledger count.
- Of the original 18 unreviewed Auth IDs, nine belong to Web/Admin, not Flutter Mobile.

## P2 source parity
Backend Managed Accounts manifest declares **18 routes**. The Flutter managed-accounts repository contains matching source route usage for all 18: 16 literal paths and two dynamic invitation accept/decline suffixes. This is source discovery, **not** a claim of 18 passed E2E operations.

### RC96 concrete hardening
- `respondToInvitation` requires authenticated, contract-bound endpoint and checks identity revision after the response.
- For **accept**, require `success:true`, exact `MANAGED_ENTITY_INVITATION_ACCEPTED` code, a UUID managed entity and MANAGER/VIEWER access. Never treat OWNER as invitational.
- For **decline**, require exact `MANAGED_ENTITY_INVITATION_DECLINED` code and null payload.
- Invalid or stale response is rejected; the UI must not claim a successful membership update from HTTP 200 alone.
- Mocked regression tests cover accept, decline, a forged OWNER acknowledgment and account switch while a request is in flight.

## Subsequent P2 acceptance tasks
- Detailed DTO/permission/error review for the eighteen routes, including owner-only operations and invitation races.
- Binding managed entity selection to all scoped capabilities and clearing it on logout / role revocation.
- Fable Access Control policy snapshots and permission update on 403/foreground/role changes.
- UI for Google/Apple Link/Unlink alongside account management and native SDK adapter readiness.
- CI Flutter analyze/tests and Android/iOS builds required; actual device/Backend E2E deferred to P6, never misrepresented as passed.

## Project state
The 17-family Fable roadmap is unchanged. Continue P2 directly after CI, not another Auth redesign loop.
