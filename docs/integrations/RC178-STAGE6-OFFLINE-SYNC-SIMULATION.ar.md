# RC178 — Stage 6 Gate 6.5: Offline/Sync policy development simulations

**2026-11-11 — 23/23 actual isolated local Node tests PASS, zero failures. Stage6 Gate 6.5 SIMULATION ACCEPTED only.**

## Implementation and execution

- `tools/rc178-stage6-offline-sync-simulator.mjs`: **independent in-memory Node model**, NOT a change to production Flutter/Drift/WorkManager/iOS BGTaskScheduler or NestJS.
- `test/rc178-stage6-offline-sync-simulator.test.mjs`: 23 deterministic tests under Node 22.16.0, with synthetic HTTPS project scopes, demo account IDs, independently specified fake contract SHA and fake server acknowledgments.
- Combined RC174+175+176+177+178 **70/70 tests PASS** in a local temporary directory using Node; the complete Flutter repository test runner was not executed in this turn.
- Existing Flutter `FableOfflineSyncEngine`, `FableOfflineDriftStore`, `FableBestEffortWorkScheduler` reviewed as source; this model tests its intended safety policy, not those Dart implementations.

## Verified simulated safety boundaries

1. Exact HTTPS/project/user/managed-entity/contract-hash scope required. Account A's data cannot be read, queued or acknowledged under B.
2. Per-operation offline mutation grants require correct contract hash, idempotency and version/conflict protocol. No invented Fable/Other Backend routes.
3. Financial payments, bookings, balances, auth/session and other sensitive writes explicitly blocked; nested secrets are not cached.
4. Source version / ETag mandatory for queued writes; queue count capped. HTTP ACK without authoritative nonempty server version is not success and is placed in review.
5. Timeout/unknown response preserves stable idempotency key and pending state, exponentially backs off, stops after seven failed attempts for manual review.
6. 409/412 conflict does not silently overwrite server state. 401/403 suspends processing; revocation quarantines affected queue items.
7. GET cache supports TTL/staleness and returns defensive copies, never a fake server-confirmed state.
8. Concurrent foreground flushes execute single-flight. Old-account asynchronous responses cannot ACK a new account.
9. Scheduling background work is **best effort** only, no guaranteed execution: a simulated OS grant is required before a scheduled job can run.
10. Confirmed logout supports scoped purge.

## Strict non-claims

No SQLite/Drift database actually opened, no Flutter/Dart source code compiled or executed, no OS background jobs dispatched, and no actual Fable/Other Backend authenticated server call took place. Simulated `content.note.update` is a **synthetic operation name**, not evidence that any real generated project exports it. Android/iOS platform constraints and background reliability remain separate from this acceptance. No production credentials, keys, private customer data, paid services or GitHub Actions.

The 17 feature families still have `complete:false`, `liveE2EVerified:false`; Stage7 PROD remains **NO-GO**.

References: [RC88 architecture decision](./FABLE-OFFLINE-BACKGROUND-SYNC-ADR-RC88.ar.md), [RC89 Flutter implementation scope](./FABLE-OFFLINE-RUNTIME-RC89.ar.md), [Stage6 eight-gate progress](./STAGE6-8-SIMULATION-GATES-2026-11-11.ar.md).
