# RC100 — P2 managed account context race isolation

## Baseline
- This branch was created from RC99 source (which in turn started on RC98 Flutter/main).
- The 40 Auth source-owner classifications remain unchanged. Backend RC67 Web/Admin source untouched.
- FableManagedEntityStore is volatile, login-identity-scoped and must be bound to the **same** FableSecureSession as the API gateway.

## New source behavior
- The entity store has a monotonic `selectionRevision` incremented on every activation and clear, including repeated A→B→A selection.
- `FableManagedAccountsRepository.executeUsingStore(store,operationId)` binds a scoped operation to the current Fable-confirmed selection, exact secure-session object and selection revision.
- After the Backend responds, the repository revalidates both identity revision (existing) and managed selection revision (new), discarding data on same-login context switches.
- The old `executeInContext(selection,...)` is retained for source compatibility but does **not** provide the same-store switching guarantee. New generated UI should prefer `executeUsingStore`.
- Backend still checks membership and authorization for every request. Neither selection revision nor a UI context is a permission token.
- Other Backend mappings remain independent and must opt into their own verified context contract.

## Simulated tests
`packages/features/fable_profile/test/managed_context_switch_rc100_test.dart` covers:
1. A stale privileged response for entity A after choosing B;
2. A→B→A switching with same selection instance;
3. Clearing a selected entity while a scoped request is in flight;
4. A store bound to different Auth credentials cannot run the operation.

### Remaining P2 and P6 work
- RC101 closes the app/store/Access Control namespace binding. Newly scaffolded project-specific repositories still need to opt into `executeUsingStore` for explicitly scoped operations; see [RC101](./FABLE-P2-MANAGED-ACCESS-INTEGRATION-RC101.ar.md).
- React to revocation or role downgrade while a screen is open; RC99 invalidates selected context on refresh/403.
- Actual Backend+DB/device E2E remains unapproved; source mocks do not establish live E2E.
