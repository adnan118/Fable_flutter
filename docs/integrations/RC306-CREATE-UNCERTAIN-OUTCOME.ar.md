# RC306 — Distinguish uncertain signed CREATE outcomes without replay

Paired with Backend RC305 `0604d91ba22277f84fe1f4715b981683e0139754`, whose idempotency runtime now uses an actor+managed-tenant scoped SHA256 claim key and refuses legacy-scope collisions. This file records **source changes**, not Flutter or Backend E2E acceptance.

## Generated Flutter changes (W3/W4/W5/W6)
- Generated typed response/error enum gains `outcomeUncertain`, distinct from a permission conflict or invalid user field.
- Signed-idempotency POST adapters map these known server idempotency states to `outcomeUncertain`: `IDEMPOTENCY_RECOVERY_REQUIRED`, `IDEMPOTENCY_IN_PROGRESS`, `IDEMPOTENCY_LEGACY_SCOPE_REVIEW_REQUIRED`. Other unexpected errors remain the conservative existing failure types.
- The generated create screen already disables another submit after a failed attempt until the user explicitly verifies server state and chooses to start a NEW create. RC306 reinforces that wording and points users toward operator reconciliation when applicable. The app does not fabricate a server confirmation.
- Safe POST form UUID fields require canonical UUID v4 to match the NestJS/Prisma Backend path; generic UUIDs that would fail `@IsUUID('4')` are now rejected before any network request.
- The 256-bit random `Idempotency-Key` remains unique per explicit user-intended create, never logged, stored or automatically replayed. Once an outcome is ambiguous, new creates are blocked in the existing UI until the user confirms a fresh action.

## Still blocked
No user-facing read-only per-key recovery endpoint is published in the signed Fable Client Contract. Administrative UNCERTAIN reconciliation continues through the permission-protected Backend `/admin/idempotency` controller. This RC **does not implement or claim automatic recovery**. Real concurrency, retry/replay, native Flutter compilation, request outcome and 17-family acceptance remain user-owned in W7. Production NO_GO.

No tests were executed by the assistant per user request; JavaScript source syntax was reviewed only.
