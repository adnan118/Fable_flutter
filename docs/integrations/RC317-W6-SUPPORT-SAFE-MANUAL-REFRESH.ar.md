# RC317 — W6 support ticket manual refresh with session identity fence

## Functional improvement
The existing authenticated ticket list had a read-only source widget and protected against delayed old-account ticket results (RC225). On failed reads, however, it displayed a text-only unavailable message with no way for the user to retry from the screen, and lacked an explicit on-demand refresh.

RC317 adds:
- A **Try again** button only after a failed current-session GET.
- A **Refresh** button on the loaded current-session ticket list.
- Both actions compare the current authenticated identity revision to the revision pinned when the list was loaded. If sign-in/account changed but the invalidation event is delayed, the action removes the old ticket snapshot and **does not send another GET**.
- The asynchronous builder rechecks the authenticated identity immediately before rendering loaded data or errors, preventing a delayed old-account completion from appearing.
- Refresh increments the existing generation and creates a new FutureBuilder key. Previous in-flight results cannot overwrite a newer list.
- Existing automatic list reload on legitimate identity invalidation and six RC225 widget test cases remain in place. A read-only list never calls `create()` or creates a support ticket.

## Project/backend contract boundary
A host must still supply the `FableSupportRepository` backed by a verified authenticated external or Fable project operation contract, plus monotonic session identity, auth eligibility and invalidation stream. A standalone unbound widget continues to perform **zero** requests. The Backend must independently check permissions and tenant ownership; Flutter UI guards are not authorization.

## Deferred acceptance
The new `packages/features/fable_support/test/rc317_support_manual_refresh_test.dart` adds three widget cases: recover a failed load, block refresh after a silent identity switch, and ignore an earlier refresh completion after a newer request. It is registered in the existing one-command Flutter test gate.

Per user request, these tests are authored **but not run**. No Dart/Flutter analysis, builds, network, provider E2E or Render deployment was performed. W6 source integration improves, W7 remains user-owned, and production stays **NO_GO**.
