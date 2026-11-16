# RC298 — Paired Flutter owner PATCH/DELETE optimistic preconditions

**Backend pairing:** RC297 `c591b9335878f2d427b3f19ea1ba04df9991b124`.
**Flutter source baseline:** `79e8549c592fbcd751be5ab5acbc6de899f56630`.

## Implementation W3/W5/W6
- The typed generator accepts only a project-signed `precondition={required:true,header:"If-Match",scheme:"sha256-id-revision-v1",readOperation:"<feature>.get"}` that independently matches the OpenAPI `x-fable-precondition` and required If-Match header.
- Each PATCH/DELETE also requires a separately signed GET by the same record ID, exposing an OpenAPI ETag response header with matching `x-fable-etag`. The GET operation hash and method are pinned in the generated Dart source.
- Data layers perform the fresh, authenticated GET immediately before mutation, require a successful envelope with matching record UUID, validate a quoted 64-hex SHA-256 ETag, and pass the unquoted hash to the Fable gateway's existing `ifMatch` parameter.
- Account/session-identity changes invalidate the GET result or the mutation response. 412 and missing-precondition 428 are explicit conflicts. No failed mutation is automatically retried; the user must review the new server state before another explicitly confirmed operation.
- The operation-level generated source receipt carries the signed GET precondition, making source pairing visible in W4/W8 artifacts.
- If the signed read or conditional write metadata is missing, the generator **fails closed**; old RC293-only feature contracts cannot silently bypass RC297's server concurrency enforcement.

## Scope and caveats
This completes a **source pairing**, not a live Dart acceptance. User requested deferring tests. Generated Flutter SDK compilation, real concurrent edit/delete races, migration of pre-RC297 project schemas, and managed-entity mutation adapters remain unverified. The previously deployed RC291 trial has not been re-deployed from the newer source.

**No tests were executed**. JavaScript source syntax was inspected only. W3/W4/W5/W6 remain open; production remains NO_GO.
