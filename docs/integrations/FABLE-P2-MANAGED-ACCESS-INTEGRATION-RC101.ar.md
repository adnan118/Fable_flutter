# RC101 — Shared Managed Accounts / Access Control identity binding

## Baseline and scope

- Based on Flutter `main` after RC100: `08cfb910f4869ad9a43a86520bd7a827aed03858`.
- RC99 and RC100 remain merged; this work changes Flutter only. No Backend/Auth ownership or operation counts are reclassified.
- Fable `PermissionService.snapshot(userId)` returns the signed-in user's **global** role/permission keys. The managed-account context interceptor separately validates membership and records `managedAccountAccess`. These are distinct authorization dimensions; OWNER/MANAGER/VIEWER is never converted into a global permission key.
- Backend remains authoritative for every request. UI snapshots and managed selection are display/context state, not grants.

## RC101 changes

1. `FableAuthGateway.sessionNamespaceFor(base, contract)` exposes the stable namespace already used by Fable auth clients (origin + project name). Separate feature gateways therefore share the namespace-scoped identity epoch and event stream.
2. `FableManagedEntityStore` now verifies a shared identity namespace rather than Dart object identity, and pins the exact contract hash + Backend origin. The starter app creates it with the same namespace as its feature gateways instead of the unrelated default `fable` namespace.
3. `FableAccessBootstrap` receives the app's Fable-only managed store, verifies namespace and Backend identity, and binds it to `FableAccessSession`.
4. Every managed selection change invalidates the permission UI snapshot immediately and starts a fresh user-global permissions read. In-flight earlier snapshots are discarded by the existing generation epoch. Foreground and 403 revalidation remain intact.
5. The permission endpoint is deliberately called without a managed-entity header. Managed role checks remain separate and are revalidated by the Backend on entity-scoped operations.
6. `FableManagedAccountsRepository.executeUsingStore` now checks both shared identity namespace and exact Backend identity. A 403 or `MANAGED_ACCOUNT_NOT_FOUND` on an explicitly scoped operation clears the selected context.
7. `FableManagedAccountsPage` re-reads the signed-in user's memberships when the app resumes; a role downgrade or revoked membership clears the selected entity and propagates invalidation to Access Control.
8. The Wizard's selected-feature audit now detects missing app/store/bootstrap/session/repository wiring when both Profile and Access Control are selected and the imported Fable contract contains managed-entity operations.

## Regression coverage

- Core store tests verify that distinct gateway objects may share only the same identity namespace and exact Backend binding.
- Access Control lifecycle tests verify immediate snapshot invalidation, refetch on selection changes, and rejection of late prior snapshots.
- Managed repository tests verify stale A/B/A responses remain discarded a scoped 403 clears the selected entity, and resume refresh handles role downgrade.
- `test/managed-access-context-wizard.test.mjs` verifies the Wizard audit passes on the starter and fails closed when binding code is absent.

## Remaining work

- Newly scaffolded project-specific repositories must opt into `executeUsingStore` whenever their operation is explicitly managed-entity-scoped; never add a global default header.
- Continue owner/member/invitation lifecycle edge-case coverage and screen-level role-refresh behavior.
- Live Backend + database + Android/iOS device E2E remains pending. Source mocks and CI are not live authorization proof.
