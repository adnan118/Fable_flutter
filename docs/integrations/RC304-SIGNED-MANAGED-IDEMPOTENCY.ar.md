# RC304 — Project-signed Idempotency-Key for managed CREATE (W3–W6)

## Implementation
Backend's existing idempotency capability can require `Idempotency-Key` for POST. RC302 had to exclude these operations because the Flutter typed gateway could not carry the header. RC304 closes that source gap:

- `FableContract.fromMaps` imports `requiresIdempotency` only when the signed operation idempotency policy, signed request header and independently exported OpenAPI required `Idempotency-Key` agree. Contradictory or invented header requirements fail closed.
- `UnifiedApiClient.request` and Fable/Auth/Managed gateways accept an optional **256-bit lowercase hex key**, but can send it only to an authenticated operation whose verified contract explicitly requires it. Required keys cannot be omitted; unsigned and ambient injected keys are rejected.
- Managed POST planning permits the exact two signed forms: no header when the Backend does not require idempotency, or exactly one required `Idempotency-Key` when it does. Non-managed POST and managed PATCH/DELETE retain their existing conservative restrictions.
- The generated managed create repository calls `FableIdempotencyKey.generate()` after input validation, before dispatching one user-intended request. It uses `Random.secure()` and 32 cryptographic bytes, does not log or persist the key, and does not silently repeat writes. The gateway preserves the same key if a transport refresh path retries an authenticated request.
- The generated feature receipt and Wizard operation report record `requiresIdempotency:true` for traceability; schema fields and permissions remain independently signed.

## Out of scope
This is **not** proof of crash-safe replay/recovery or of a successfully completed POST. Ambiguous network outcomes still require independent server-state verification; pressing Submit again represents a new user action with a new key. Generic managed writes with arbitrary headers, PUT, or unsigned/sensitive POST remain excluded.

**No tests or real requests were executed per user request.** W3–W6 source wiring improved, W7 acceptance is user-owned, W8 final physical bundle and production readiness remain open. `NO_GO`.
