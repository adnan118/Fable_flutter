# RC117 — Track B: Protected Player Session Boundary (P3 prerequisite)

**Source baseline:** `Fable_flutter/main@90a60ebb680aabf79710bb4b43ed530f565138c1` (RC116, post-merge CI 3/3 verified).
**Roadmap:** [Issue #58](https://github.com/adnan118/Fable_flutter/issues/58), Track A remains the protected Android/iOS native-player bridge; Track B closes *only* the needed source/session lifecycle prerequisite.

## Confirmed architectural gap
RC113's protected byte-range repository correctly rejects stale responses, but the RC114 `MediaByteSource` contract only provided `Future<Uint8List> read(...)`, with **no revocation/event capability**. A native player or presentation owner could retain already-fetched buffered bytes after account replacement, `refresh`, `end`, or repository disposal until its next attempted read. `MediaRangeController.reset()` also depended on callers doing the right thing manually.

This is a real architectural precondition, **not** evidence that actual Android/iOS video playback is supported.

## Fixes included
- A **pure Dart Domain port** `SessionBoundMediaByteSource` extends `MediaByteSource`, exposing typed, non-sensitive `MediaSessionInvalidation` events, `isActive`, `cancelPendingReads()`, and `close()`. It does not expose HTTP, Flutter, Fable Auth, raw tokens, session IDs, DRM keys or native player interfaces.
- `FableProtectedMediaPlaybackRepository` emits synchronous, nonsecret `accountChanged / credentialsRotated / playbackEnded / disposed` signals on actual session lifecycle events. A verified `isCurrentView(view)` uses account identity revision, current view identity and playback/token TTL; `cancelReadsForView(view)` cancels only active-view requests without issuing `DELETE` to the Backend.
- `FableMediaByteSource` maps those signals to the Domain port, marks its own view invalid, rejects stale or late reads, and cancels subscriptions on `close()`. Closing the local byte source **never** means server-authoritative playback termination. The caller separately invokes the Backend `end` operation.
- `ReadMediaRangeUseCase` exposes optional typed session invalidations and cancellation without coupling the Domain or Presentation to Fable. Both pre- and post-read guards reject session changes.
- `MediaRangeController` subscribes to invalidation and **purges ready bytes synchronously**, invalidates in-flight operation generation, and cancels pending reads upon identity change, refresh, end, reset or dispose. It cancels its subscription in `dispose`. Non-session fake/legacy source support remains via an empty stream.

## Test matrix
`test/media_session_boundary_rc117_test.dart`: stale before read = no dispatch, ready buffers synchronously purged, pending responses cannot rehydrate UI, rotation/end events, reset/dispose cancel reads, source close.
`test/protected_media_range_rc113_test.dart`: mocked verified Fable transport and Auth events, account switch signal before GET, token rotation invalidates old byte source while new session is usable, end publishes before network completion, local close does not DELETE, repository disposal signals loss.
CI: Flutter analysis and all feature tests + Android Debug APK and unsigned iOS Simulator. **All these are mock/source/build evidence**, not physical device E2E.

## Scope boundary & honest closure
Track B's **player-session boundary prerequisite** can be marked closed only when the exact PR head is CI-green 3/3 and merge SHA verified on `main`. This does not close the entire architecture debt backlog (17 legacy feature families, typed upload migration, media-specific logic still in generic Core).

Track A still must implement/verify actual native player adapters, pausing/seek/resume, renderer flush/stop on invalidations, buffered-byte policy, backpressure, authorized remote content, and device-specific playback. A player that ignores this stream remains unsafe even if its byte requests individually return 206.

P6 actual Fable Backend/MySQL/R2 + physical Android/iOS devices, native DRM/FairPlay/Widevine remain **unverified**. No `liveE2EVerified` promotion.
