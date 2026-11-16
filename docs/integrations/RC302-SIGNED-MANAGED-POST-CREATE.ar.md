# RC302 — Managed-entity CREATE (POST), bounded source implementation

## W3–W6 scope

The typed feature planner now admits only an explicitly selected, project-signed `POST /<feature>` when its operation ID is `<feature>.create`, permission is exactly `<feature>.create`, and both client contract and OpenAPI agree on `recordAccess=managed-entity:<relation>`. No query/path parameters, guessed tenant headers, `Idempotency-Key` requirements or unreviewed privileged/sensitive fields are accepted. Request body must satisfy existing `validatedCreateFields` constraints (bounded flat 1–16 text/UUID fields, matched required/optional shape, no credentials or financial fields).

The verified managed gateway now permits approved POST with a nonempty JSON object only for an active, server-verified **OWNER/MANAGER** selection. VIEWER cannot create. Backend retains authoritative tenant membership and field authorization. The source-pinned factory, existing generated navigation and identity/scope invalidation are reused.

Created DTOs are validated **before** the network call and map invalid input to `invalidInput`. A malformed Backend response remains `invalidResponse`. No silent mutation retries are intentionally introduced. This source change does not relax the stricter RC301 `If-Match` protection for managed PATCH/DELETE, and does not enable any arbitrary operation.

## Open gates

- The policy deliberately refuses POST operations that require idempotency headers; such operations need a dedicated signed idempotency flow, not an invented key.
- This is a **source implementation**, not verified Flutter/Dart compilation, real CREATE on an isolated tenant, device E2E or production approval. Existing generated project packages are not modified by this generator change.
- W0/W1/W2 remain source-established; W3–W6 improved but not closed; W7 testing belongs to the user; W8 final release remains open.
- **No test suites, production deploys or real database writes were executed** per user's instruction. Production NO_GO.
