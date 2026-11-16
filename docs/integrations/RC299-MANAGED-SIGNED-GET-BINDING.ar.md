# RC299 — Signed Fable managed-entity GET binding (W3–W6)

Backend pairing: **RC300** commit `1f7984c63cefd50f399188d3c48aa3611a7697c2` (recordAccess metadata mirrored into OpenAPI).

## The actual source implementation

1. `FableContract.fromMaps` independently matches the project-signed operation ID, HTTP method, route, hash and `recordAccess` against OpenAPI. A missing or contradictory managed policy fails closed. `FableOperation.recordAccess` is read-only and validated; no client-provided role or tenant string becomes authority.
2. Typed Flutter feature planning accepts **managed GET by UUID** and **managed paginated GET/search** only when `recordAccess=managed-entity:<relation>` and OpenAPI `x-fable-record-access` exactly agree. It refuses managed POST, PATCH, DELETE, unbounded list operations and unsigned headers.
3. `FableManagedEntityPinnedGateway` extends the verified Fable Auth gateway for these read operations. It requires a user-session-bound `FableManagedEntityStore`, a Backend identity binding, an explicitly activated server-verified entity selection, and an allowlist of exact operation hashes. On every request it supplies `X-Fable-Managed-Entity-Id` through the existing authenticated transport, checks selection revision/role/user identity continuously, and discards stale A→B→A responses. Writes are intentionally blocked until reviewed.
4. For each managed feature the generator produces a `*ManagedBinding` Dart factory and `.fable-managed-source-binding.json` receipt with the operation hashes, selected feature and context requirements. Managed data adapters require the pinned gateway type and verified access string. Existing infinite-scroll and read pages can receive `gateway.scopeEvents` as their identity/context invalidation stream.

## Integration example (conceptual)

First establish the **same** FableSecureSession in both the Auth gateway and the managed store. The operator/application must explicitly bind the store with `FableAuthGateway.managedEntityBackendIdentityFor(baseUri,contract)` and activate only a Backend-verified OWNER/MANAGER/VIEWER selection. Then use the generated feature's `Fable<Feature>ManagedBinding.create(...)`, the generated data repository, and pass `gateway.scopeEvents` to the page. The factory does not select an entity, fetch membership, or grant permissions.

## W0–W8 boundaries

W0 inventory and W1/W2 source remain as before; W3 verified scoped contract matching improved, W4 typed managed binding factory added, W5 signed managed GET/list/page/search source added, W6 tenant switch fencing and read-only authorization improved. W7 live integration tests remain with the user; W8 release/ZIP approval remains open. No completed feature-family count changed, no production acceptance claimed. **RC299/RC300 have not been compiled or run on real Flutter/Backend environments by the assistant at the user's request.**

Managed entity **PATCH/DELETE remain blocked** despite the presence of If-Match in the underlying generic transport. Expanding them requires independently signed per-operation mutation scopes, audited authorization, preconditions and real acceptance. Production **NO_GO**.
