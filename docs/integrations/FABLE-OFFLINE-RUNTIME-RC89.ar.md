# RC89 — Offline SQLite/Drift + Best-Effort Sync: reusable implementation status

**Runtime code:** `packages/features/fable_offline/lib/src/{offline_drift_store,offline_sync_engine,offline_platform_scheduler}.dart`.  
**Policy/Wizard:** `tools/{frontend-owned-decisions,offline-sync-wizard}.mjs`.  
**Platform:** `ios/Runner/{Info.plist,AppDelegate.swift}`; Android WorkManager plugin through Flutter federated plugins.

## What is implemented and reusable

- Local SQLite via Drift + scoped physical database per Backend origin/project/account/managed entity (hashed filename, no credential in name), cache TTL/stale handling, transactional logout scope purge, outbox persistence, retry scheduling and explicit conflict state. **SQLite is not encrypted at rest:** only allow non-secret cache/queue data after content-classification policy review.
- Sync engine accepts a **verified contract hash** and per-operation write grants with method, idempotency and conflict-version preconditions. No invented `/sync` API, no auto-replay of payments/bookings/prices/inventory/session/auth, no secret fields. Every write needs baseVersion and stable idempotency key.
- Sync requires exact active account/managed entity/Backend verification. Acknowledgment requires a source-confirmed server version; network timeouts are retries with same key; unknown/unsafe/conflicting operations remain queued for manual review. Auth invalidation stops operations.
- Foreground observer syncs on app open/resume. Android uses WorkManager; iOS uses BGTaskScheduler. Both best-effort with no SLA; background scheduling **opt-in** and requires app-specific callback dispatcher bootstrapping a verified credential/Backend adapter **inside the worker isolate**. There is no unsafe default worker that silently sends transactions.
- Wizard per-project optional choice via `pnpm wizard:offline`, config `.fable/frontend-owned-decisions.json` mirrored to `assets/config/`. Storage=SQLite/Drift, policy=foreground_plus_background_best_effort; existing projects keep their old Offline opt-in status. Neither Fable Backend nor Other Backend privileges are modified. New project requires explicit yes/no.

## How to use later when a concrete project's Backend contract is ready

1. Run main Backend Wizard (Fable signed contract OR separate verified Other Backend catalog).
2. Run `pnpm wizard:offline on foreground_plus_background_best_effort` and type `اعتمد`. This only configures local policy; it cannot authorize a backend mutation.
3. Build `FableOfflineDriftStore.onDevice(...verified origin/project/user/entity...)`. Provide `FableVerifiedSyncContext` that validates account/session/network and exact scope; pass reviewed public read operation IDs and individually proven `FableOfflineWriteGrant` objects.
4. In the host's app lifecycle, use `FableForegroundSyncObserver` and invoke `onAppOpened()` after login/session revalidation. Executor must send the same `idempotencyKey` and record server response version accurately; don't hardcode ACK.
5. For background support, supply a `@pragma('vm:entry-point')` top-level Workmanager dispatcher that recreates secure identity and the Backend executor inside the background isolate, then call `FableBestEffortWorkScheduler.initialize(dispatcher)` and `schedule()`. **Never** schedule if project/backend/session has not been verified.
6. For iOS, ensure the actual app's `PRODUCT_BUNDLE_IDENTIFIER`-prefixed task identifier exactly matches `BGTaskSchedulerPermittedIdentifiers` and `FableBestEffortWorkScheduler.taskIdentifier`. The starter contains `com.example.helloWorld.fable.sync`; project clones must replace it with the app-specific ID. iOS AppDelegate registers Workmanager in UIScene. Android WorkManager requires no always-running service.
7. After logout, cancel host background scheduling for revoked identity, invalidate worker session, and call `clearOnConfirmedLogout()` if project policy is to erase queued data. On switch of Backend/account/managed entity, open a **new** isolated scoped store. Do not replay old account data.
8. Run all package tests and real Android/iOS interrupted-work, Force Quit, battery saver, background delay, conflict, 401/403 and server ACK tests. Integration cannot be signed off without a real Backend and devices.

## Important non-claims

- This is **ready-to-bind reusable Core infrastructure**, not automatic complete offline parity for each Fable/Other Backend capability. Full E2E is **0/17** until live verification. Real pricing/booking/payment mutations remain ONLINE_ONLY and must be revalidated.
- iOS does **not** promise background execution at a specific interval or after Force Quit. Android likewise enforces Doze/app restrictions.
- The repo's old `OfflineReactionQueue` based on SharedPreferences is still present for backward compatibility and remains **only** for its explicitly allowed low-risk reactions. This new Drift outbox should become the general path after API binding; do not copy private data into the legacy storage.
- README/ADR references: [RC88](./FABLE-OFFLINE-BACKGROUND-SYNC-ADR-RC88.ar.md); [Wizard](./FRONTEND-SETUP-WIZARD.ar.md); [Parity master](./FABLE-FLUTTER-PARITY-MASTER.ar.md).

## Test evidence

- Flutter package: `cd packages/features/fable_offline && flutter test` (Drift memory DB, scoped cache, allowed writes, ACK, conflict, retry, logout).
- Wizard: `node --test test/offline-sync-wizard-rc89.test.mjs`.
- CI: Flutter analyze + project Flutter tests + all feature packages + Android debug + iOS simulator.
- **Backend live E2E:** requires signed concrete project contract, DB, API + device. Do not infer from CI.

## Official reference

- [drift_flutter](https://pub.dev/packages/drift_flutter) and its shared-isolate option.
- [Workmanager quickstart](https://docs.page/fluttercommunity/flutter_workmanager/quickstart)
- [Apple BackgroundTasks](https://developer.apple.com/documentation/backgroundtasks).
