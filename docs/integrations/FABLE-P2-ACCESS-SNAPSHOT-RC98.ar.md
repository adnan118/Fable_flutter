# RC98 — P2 Access Control: authoritative snapshot envelope

## Baseline verified on 2026-11-02
- Flutter/main RC97 merge: `7d080af27fc99dadb0952c5cfa222e698a769976`.
- Backend/main RC67 merge: `706aedd0bbda15149f9141ff767a901b06ffca5d`.
- RC97 Auth ledger: **31 Mobile source-reviewed, 7 Web SDK source-reviewed, 2 Admin SDK source-reviewed; 40/40 classified**. Flutter/main CI 3/3 passed.
- Auth real Backend/provider/DB/device E2E: still not accepted (0/40), not an obstacle to source-level P2 work.
- Backend CI remains blocked on existing runner/ZIP workflow; Web/Admin source mock tests are independently verified under Flutter CI.

## Bug fixed
Backend RC66 `GET /permissions/me` returns data via NestJS `SuccessResponseInterceptor`:
`{success:true,data:{userId,keys,roles},requestId,...}`.
Flutter `FableAccessRepository.current()` previously attempted to parse the **outer wrapper** as a snapshot, discarding valid grants and roles.

### Contract-correct handling
- Under a verified Fable access-policy provider, require `success:true` and a `Map` `data` object, then parse only that object.
- Reject absent/false success, null/nonobject data, or forged top-level fields.
- Other Backend retains its independent operation and mapping and is **not** forced to adopt Fable's JSON envelope.
- Server remains ultimate authorization authority. These snapshots are for screen/action visibility, never a substitute for permission guards.

### Added regressions
- Valid Fable envelope exposes exactly returned grants.
- Plain/unconfirmed response cannot grant privileges.
- Malformed envelope fails closed.
- Independent Other Backend nested-field mapping still works.
- Missing/unrecognized provider rejected.

## P2 continuation
- Managed Accounts 18 routes: source discovered; RC96 invitation integrity already merged.
- Remaining: role changes while multiple accounts are active, immediate revocation from 403, account-scoped caches and UI, role/permission admin operations, replay and actual DB-backed tests.
- P3 services continue after P2 source gate. No refactoring Auth again solely because Web/Admin production E2E is deferred.
