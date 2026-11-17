# RC316 — W6 verified-session payment status card

## Functional gap closed in source
Previously `FablePaymentStatusCard` called `repository.read(paymentId)` on mount without requiring an explicit current authenticated account/session identity. A request started for account A could complete after A → B → A or sign-out, and a stale payment status might be presented. The repository already validates a signed authenticated individual GET and matching returned payment ID (RC223), but the widget also needs a **display-time identity fence**.

## RC316 implementation
- Add optional host-injected `identityRevision`, `isAuthenticated`, and `identityInvalidations` parameters. All **three are mandatory to unlock data**. Legacy two-argument widgets retain source compatibility but show `A verified payment session is required` and perform zero HTTP calls.
- A verified session must have an authenticated, nonnegative revision; providers that throw fail closed. The host must increment the revision monotonically on login/logout, account replacement or return to an old account.
- Each read is pinned to a generation plus session revision. The widget checks before dispatch, after asynchronous completion, and immediately before rendering a payment state.
- Logout/revocation identity notifications wipe the in-memory future, bump the generation and require the caller to reopen the card; they deliberately **do not auto-fetch the old payment ID** under another account.
- Explicit payment ID/repository changes can start a new guarded GET. A previous payment result never becomes a new selection's status.
- The original server response ID match in the repository remains enforced, and the widget independently checks it again.
- No checkout, capture, refund, provider routing, implicit retry, or new payment API was added.

## Host usage
A host can pass the already-verified Fable session's monotonic identity revision and invalidation stream, together with its authenticated session policy:

```dart
FablePaymentStatusCard(
  repository: verifiedPaymentRepository,
  paymentId: selectedPaymentId,
  identityRevision: () => secureSession.identityRevision,
  isAuthenticated: () => hostVerifiedAuthenticatedSession(),
  identityInvalidations: secureSession.identityEvents.map((_) {}),
)
```

The example requires the host's real `verifiedPaymentRepository` and `hostVerifiedAuthenticatedSession` implementations. Never substitute a hard-coded always-true function or a non-monotonic account label. Ensure the Backend still enforces caller ownership/permissions for the operation; Flutter alone cannot prove authorization.

## Deferred regressions
`packages/features/fable_payments/test/rc316_payment_status_identity_test.dart` covers old unbound callers, A→B→A session epochs, payment ID switches and logout ahead of a delayed response. Tests were added to source, but not executed by request. No Flutter/Dart/Gradle build, live payment, device, database or Render deployment was run.

This is a real **W6 source fix**, not provider acceptance or production readiness. The 17-family ledger still marks Payments `liveE2EVerified:false`, `complete:false`, and `productionReady:false` for the overall release.
