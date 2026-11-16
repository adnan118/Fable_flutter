# RC282 — Signed sorting across Backend ↔ Flutter W5

## Reference
- Backend main (merged RC282): `fbe31f30f191bb38ab334242fe2dafb0f1963dbb`.
- Flutter baseline: `35e28f84afd65a5dbd1ade4bea46b3c826a84506` (RC281).

## Source delivered
1. Generated Backend feature list query `sort` metadata includes `sortAllowedFields` directly from its normalized, safe sort-field allowlist. It is included in the signed operation hash.
2. Exported OpenAPI mirrors the exact field list on the sort query parameter as `x-fable-sort-allowlist` (no change to backend sort syntax).
3. Flutter codegen only accepts a match between independently signed operation + OpenAPI. Unsupported/unsigned/mismatched sort metadata rejects or produces no sort UI.
4. Flutter presents up to eight safe sort fields, ascending/descending. The typed Repository → UseCase → Data adapter → Controller → Infinite Scroll UI carry the chosen token across every paged request. Account changes erase the sort and stale results; changing sort resets pagination to page one.
5. Data adapter rejects any sort token not in the exact signed selected allowlist. Arbitrary multi-sort, sensitive fields and tenant-unbound query are not generated.

## Evidence & limits
- Backend test source: `test/rc282-signed-sort-allowlist.test.mjs` (authored, not run in a full Node checkout).
- Flutter 10/10 isolated JavaScript callbacks **executed** with the actual current planner and renderer source (includes RC278–RC282 cases). Not Flutter SDK, not a live project.
- No generated Nest/Prisma/MySQL, real permissions/tenants or Android/iOS E2E accepted. W5 remains partially complete, W6–W8 remain open. Production `NO_GO`.

## Next accelerated batch
- RC283+ W5: design and implement scoped conflict-safe PATCH/DELETE only with signed headers, idempotency and conditional write evidence.
- One W5/W6 source regression run and integration checklist; release archive only after main branch states are pinned.
