# RC301 — Conditional managed-entity PATCH/DELETE, verified source-only

Pairing: Backend RC297 `c591b9335878f2d427b3f19ea1ba04df9991b124` (atomic revision, GET ETag, If-Match CAS) and RC300 `1f7984c63cefd50f399188d3c48aa3611a7697c2` (signed record-access OpenAPI).

## Coordinated W3/W4/W5/W6 source changes

- **Signed contracts (W3):** The Flutter importer validates a source-signed optimistic write precondition against the independent OpenAPI `x-fable-precondition`. Only `PATCH`/`DELETE` with signed `If-Match` and `sha256-id-revision-v1` are recorded as `requiresIfMatch`.
- **Managed writes (W5):** The typed feature planner now accepts a *narrow subset* of explicitly selected managed-entity `PATCH /feature/:id` and `DELETE /feature/:id`, with signed `recordAccess=managed-entity:<relation>`, exact matching permissions, allowed flat optional non-sensitive PATCH text fields, no idempotency-required writes and no guessed headers. Source-pinned same-scope GET and ETag are mandatory.
- **Authenticated gateway (W6):** The managed-only gateway allows approved operation hashes and the separately signed GET dependency. It requires an active server-verified selected entity, the matching Backend/session identity namespace and stable selection revision. Mutations require OWNER/MANAGER access (VIEWER remains read-only), an exact UUIDv4 path, 64-hex `If-Match`, no query or unexpected body. Backend remains the security authority for membership and record/field permissions. Refresh/races do not automatically repeat a mutation.
- **Generated Data & Presentation (W4/W5):** Managed PATCH/DELETE adapters use `FableManagedEntityPinnedGateway`, verify operation recordAccess, perform a fresh scoped GET, validate record ID and ETag, then dispatch one preconditioned write. The generated managed factory approves any required signed GET dependency and records it in the manifest. Generated navigation obtains the inherited `FableManagedEntityScope` from the application's existing store, uses context-specific gateways/pages and `scopeEvents`, and disables managed navigation without a selected entity. General-owner operations continue to use the unscoped gateway.
- **W8 packaging traceability:** Wizard generation report includes `managedBinding`, `managedConditionalWrites`, source hashes and missing acceptance flags. The combined Backend+Flutter ZIP *command* remains `pnpm run export:full` in the Backend repo; this RC does not create a distributable ZIP in the conversation.

## Deliberately unsupported and unresolved

Managed POST/CREATE, complex/sensitive/nested PATCH, idempotency-required mutations, uncontrolled permission-wide writes, and speculative tenant headers are still excluded. Pre-RC297 generated applications require an explicit schema migration for `fableRevision`; source generation is not a safe in-place upgrade. No production rollout to the existing RC291 Render trial has occurred.

**No tests executed at the user's request.** JavaScript source syntax review is not Flutter/Dart compilation, Prisma migration validation or authorization E2E. W3/W4/W5/W6 are more source-complete but remain open; W7 user acceptance and W8 final release remain outstanding. No 17-feature family has been falsely marked complete; production **NO_GO**.
