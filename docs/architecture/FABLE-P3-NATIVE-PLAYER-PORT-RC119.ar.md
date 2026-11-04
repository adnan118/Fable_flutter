# RC119 · Protected native-player port and bounded byte broker

Baseline: RC118 Flutter/main `632135589110218255f5d7778d3866aab4f234d2`; PR checks green 3/3 and post-merge main checks separately verified 3/3.

## Delivered in this source slice

- Pure Dart Domain `ProtectedPlayerPlatformPort`, `ProtectedPlayerMetadata`, `ProtectedPlayerReadRequest` and typed bytes/EOF/rejected replies. No Fable, Dio, Flutter, native imports, URL or credentials in the port.
- Application `ProtectedPlayerSession` state machine: idle → preparing → ready → playing / paused, plus seek, stop, fail, revoke, dispose.
- Native port receives **only** a validated MIME, total length and callback to request bounded bytes; it must implement its own real decoder, buffering and renderer lifecycle. No invented Android/iOS plugin APIs.
- Exact request IDs and explicit nonsecret seek-generation tags: prepare supplies initial generation, seek advances it, and delayed **not-yet-dispatched** old-generation requests are rejected before HTTP. Duplicate, out-of-range, oversized, expired and excess concurrent requests are denied without dispatch. Max chunk 512 KiB. EOF at the exact verified total avoids an HTTP call.
- Identity/rotation/end/resource-change invalidation synchronously stops new reads, calls native stop, and rejects late responses. Seek drops previous read epoch; stale native prepare/play cannot revive the controller.
- New deadline capability on `DescribedMediaByteSource`, implemented by Fable as the *earliest* of playback/idle/media-token expiry; timer stops renderer even when no further GET happens. Other Backend must supply its own independently validated source/deadline.
- Closing source/stop/dispose does **not** call server DELETE; server owner calls `FableProtectedMediaPlaybackRepository.end` explicitly.
- Fake platform/source Dart tests for pause/resume/seek, bounded concurrency/EOF, late switch/refresh/finish, 403 failures, expiry, disposal, plus Node architecture audit in CI.

## Native implementation remains open

Actual Android Media3 implementation requires `DataSource.Factory` with synchronous `open/read/close` on a player/IO thread and a bounded bridge into asynchronous Dart requests, proper EOF and native stop/flushing. Verify the installed Media3 version; never issue MethodChannel calls from Android player IO directly against Flutter UI-thread requirements without an approved marshaling mechanism.

Actual iOS implementation requires `AVAssetResourceLoaderDelegate`, correctly mapped MIME → accepted uniform type identifier, request cancellation, finite content length, seek policy, a separate delegate queue, and native AVPlayer teardown. Non-HTTP custom URI schemes must not accidentally open arbitrary local/remote resources.

Neither native adapter has been implemented in this RC. HLS/DASH, DRM/FairPlay/Widevine, codec support and matching-size mutable-object detection require separately verified contracts.

Official interfaces:
- https://developer.android.com/media/media3/exoplayer/customization
- https://developer.android.com/reference/androidx/media3/datasource/DataSource
- https://developer.apple.com/documentation/avfoundation/avassetresourceloaderdelegate
- https://developer.apple.com/documentation/avfoundation/avassetresourceloadingcontentinformationrequest
- https://docs.flutter.dev/platform-integration/platform-channels

## Correctness/acceptance

Compile/test simulation and Android/iOS **app builds are not actual player runtime verification**. P3 native implementation and P6 real physical Android/iOS with Backend/MySQL/R2 remain open. Do not modify original 17-feature liveE2E status or treat generic Other Backend as Fable-compatible. Do not mix Track B architecture debt into this PR.
