# RC225 W6 — identity-safe standalone support-ticket list

Date: 2026-11-14. Direct base Flutter RC224 main `5b7fb5ee0c86f842b6678917e85f2758a5b703c3`, Backend RC209 unchanged.

## Concrete UI bug fixed
The main `FableSupportWorkflowPage` already required an authenticated identity revision and invalidation stream (RC144), but the smaller exported `FableSupportTicketList` formerly called `repository.list()` immediately at widget init **without any session binding**, then displayed whatever the Future resolved to. A previously loaded support record could remain visible after a different user signed in unless a replacement repository was provided.

RC225 retains the original constructor's `repository` parameter for source compatibility, while adding optional `identityRevision`, `isAuthenticated`, and `identityInvalidations` callbacks. In the **absence** of all three verified bindings the standalone widget now **fails closed** with a notice and does not make a network request. An unauthenticated session cannot load or display ticket information.

For an authenticated identity, the Widget captures the identity revision with each load, subscribes to invalidation events, clears its cached Future and identity on logout/switch, and assigns a new `ValueKey` generation to prevent an obsolete `FutureBuilder` snapshot from reappearing. Each build independently rechecks `isAuthenticated` and the current revision, hiding old tickets even when the host has not yet emitted a session event. Repository/identity provider replacement cancels old listener and binds the new backend.

No support API paths guessed, no automatic create POST or retry, and no raw fields displayed.

## Evidence and remaining boundaries
- Six new Dart `testWidgets` cases in `packages/features/fable_support/test/support_list_identity_rc225_test.dart`: no identity binding, verified user, delayed old response after new account switch, silent epoch change, silent revocation, no fetch after logout. Prior RC144 support workflow tests remain.
- Eight new Node source integrity tests in `test/rc225-support-ticket-identity-source.test.mjs`; all selected by **same** `pnpm fable:all` command.
- **14/14 isolated V8 source/wiring checks PASS** on exact branch blobs. Dart/Flutter SDK and native provider tests **NOT executed** in model runtime; actual widget and account-switch E2E requires the owner's Flutter checkout.
- Profile, payments, Auth, Notifications, Backend, DPoP and all earlier RCs preserved. 82 original W0 signoff/evidence items remain OPEN. Production NO_GO. No GitHub Actions.
