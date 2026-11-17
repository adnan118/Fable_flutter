# RC315 — W6 Analytics privacy consent panel (source-only)

## Motivation
The optional analytics package already contains a narrow in-memory event queue, attribute allowlist, explicit consent flag and host-supplied `FableAnalyticsSink`. It did not expose a standard user-facing opt-in panel. Without a deliberate consent workflow, a host app can accidentally make analytics feel automatic.

## Source implementation
- New exported `FableAnalyticsConsentPanel` uses `FableAnalyticsTracker` supplied by the host. It does not invent a collection URL, provider, token, endpoint, SDK or durable consent state.
- Host must provide a verified `identityRevision`, `identityInvalidations` stream and `mayCollect` predicate. There is **no default allow**.
- On initial mount, all consent starts **off**, even when a tracker instance was reused.
- When identity changes, becomes ineligible, or the panel is disposed/rebound to another tracker, it immediately calls `setConsent(false)` to clear unsent events.
- The switch rechecks the current identity and eligibility before any grant. If the host identity changes before asynchronous invalidation arrives, the next build also revokes consent.
- Arabic and English informational texts explain opt-in behavior. The panel never sends events automatically; the host still owns explicit `record`, `flush`, sink review, endpoint permissions and compliance.
- The canonical 17-family parity ledger records the new evidence path but continues to mark Analytics `repository_only`, `complete:false` and `liveE2EVerified:false` because the starter app does not launch a verified analytics consumer workflow.

## Host integration
```dart
FableAnalyticsConsentPanel(
  tracker: reviewedAnalyticsTracker,
  identityRevision: () => secureSession.identityRevision,
  identityInvalidations: secureSession.identityEvents.map((_) {}),
  mayCollect: () => consentPolicyAllowsTracking(),
)
```

This example deliberately depends on a host-reviewed `reviewedAnalyticsTracker` and `consentPolicyAllowsTracking`; Fable does not create either automatically. The host should additionally construct its tracker with the same identity invalidation stream. Do not bind this to a non-verified Backend operation or persist consent across accounts without an independent privacy review.

## Important boundary
This is a **real source UI addition**, not verified Flutter runtime behavior or 17/17 family acceptance. Tests are included as deferred source, not executed. No SDKs, device builds, network endpoints, Backend, databases or Render were touched. Production remains **NO_GO**.
