# RC105 — P2 project feature bindings for Fable Managed Entity scope

## Baseline
- Flutter/main RC104: `cad8f50b099754595b6f928f7bbf90748feaf744`.
- Auth owner ledger and Backend RC67 source unchanged; Web and Admin continue to use their own contracts.
- The Managed Entity header belongs only to explicitly-scoped, authenticated Fable project operations, not to all HTTP calls and never to Other Backend.

## Contract-pinned project feature API
`FableManagedScopedOperation` requires four independent, source-authored fields from the **imported, verified** Fable contract: operationId, uppercase method, exact path and contractHash. The runtime checks the exact current `FableOperation` and rejects mismatched/stale hashes, unknown IDs, anonymous operations, custom-credential operations, Auth, public managed-entity, global permissions and Admin paths. The SDK does not invent a service path, permission, role, or Backend scope declaration.

Example **only after** a selected project imports a matching Backend operation:

```dart
// Replace these placeholders with the matching values from the imported
// verified Fable project contract. This example is NOT an API route claim.
final scope=FableManagedScopedOperation(
  operationId: selectedBackendOperationId,
  method: selectedBackendMethod,
  path: selectedBackendPath,
  contractHash: currentVerifiedContractHash,
);
final result=await FableManagedAccountsRepository(gateway,contract)
    .executeBoundInStore(store,scope,path:declaredPathVariables);
```

The repository verifies the live `FableManagedEntityStore`, shared Auth namespace, exact Backend origin/contract and selection revision. It sends the header only on this opt-in call. If A→B→A happens before a response is delivered, the stale response is discarded. If Backend rejects this scope with a 403, selection is cleared. The Backend itself must authorize every operation and membership.

## Wizard audit extension
In `.fable/feature-integration-requirements.json`, a **project-selected operation** may explicitly declare `managedEntityScope:true`:

```json
{
  "operationId": "ID_FROM_IMPORTED_FABLE_CONTRACT",
  "method": "METHOD_FROM_IMPORTED_CONTRACT",
  "path": "/exact/imported/contract/path",
  "managedEntityScope": true,
  "requestDto": "documented schema",
  "responseDto": "documented schema",
  "errors": "401,403,409,429",
  "permissions": "Backend-documented permission",
  "frontendFile": "lib/src/features/example/repository.dart",
  "testFile": "test/example_repository_test.dart"
}
```

The existing Wizard selected-feature audit checks method/path/operationId, DTO evidence and contract import. RC105 additionally checks the opted-in scope is Fable-only; rejects Auth/Admin/global-permission routes; and requires the declared source to bind the exact operation with `FableManagedScopedOperation` and invoke `executeBoundInStore`, plus a relevant test file. An audit pass still says **SOURCE_MAPPED_E2E_PENDING**, not live E2E.

## Simulated verification
- `packages/features/fable_profile/test/managed_scoped_binding_rc105_test.dart`: matching scope header, no network on wrong contract/session, protection against A→B→A stale response, rejection of Auth/Admin/public/unprotected/global operations.
- `test/rc105-scoped-feature-audit.test.mjs`: checked source, no source, malformed scope, forbidden operations and Other Backend isolation.
- Existing RC99–RC104 context and OTP regression tests remain part of CI.

## Outstanding
- This is a binding **contract and audit**, not automatic code generation for all arbitrary project feature repositories. Each project feature must explicitly opt in with its real Backend operation and source/test evidence. The existing project-feature Wizard remains a selection/import tool, not a guarantee that all business DTOs are generated.
- Real multi-user Backend + database + physical-device E2E is still P6, including race mutations and revocation.
- No blanket managed header insertion, implicit permission grant, or fabricated operation/path is permitted.
