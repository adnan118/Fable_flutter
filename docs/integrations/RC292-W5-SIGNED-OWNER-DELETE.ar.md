# RC292 — W5 owner-scoped signed DELETE (source only)

## What changed
The typed Flutter feature generator now accepts a narrowly reviewed signed Fable `DELETE /{feature}/:id` operation when:
- The operation is independently present in the selected integration requirements, project-pinned contract and matching OpenAPI hash, method and bearer security.
- `operationId={feature}.delete`, one signed UUID id parameter, exactly `{feature}.delete` permission and `recordAccess=owner:<relation>` are present.
- Backend documents a `200` Fable success envelope with **null** data, no body, query or custom headers and no idempotency header requirement.
- High-risk features such as auth, payments, access control, media and system settings remain blocked; managed-entity/tenant operations remain blocked.

The generator produces a 4-layer Dart consumer (Domain entity/port, Application use case, Data gateway adapter and Presentation controller/page), verified by runtime contract hash and session identity epoch. The page requires typing a UUID, then explicitly typing **DELETE** inside a separate confirmation dialog. It performs one request only, never automatically repeats a delete, never treats HTTP 404/409 as successful, and rejects a mismatched or non-null Backend acknowledgement. Changing identity invalidates stale results. The existing GET/POST source remains unchanged.

## Important limitations
This is **not** a generic PATCH/DELETE rollout, not a source proof of optimistic concurrency, and not a claim that Backend enforces If-Match on generated mutations. Enabling idempotency-required DELETE would require an independently reviewed gateway/contract header flow, so it remains denied. For network ambiguity the user must verify server state before starting a new, independently confirmed action.

**Per user request, no Node/Dart/Flutter/Render tests were run in RC292.** The planner and renderer received a source syntax review, but generated packages must be compiled and exercised by the user in their project. Existing 17 feature-family `complete` and `liveE2EVerified` flags stay false. Backend trial results from RC291 do not constitute proof of this Flutter source.

## W0–W8
W0 foundation; W1/W2 source implemented; W3/W4 partial; W5 owner DELETE source added, PATCH and managed scope still open; W6 feature security acceptance open; W7 real feature integration open; W8 full ZIP delivery open. Production remains NO_GO.
