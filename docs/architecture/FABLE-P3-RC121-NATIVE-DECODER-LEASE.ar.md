# RC121 — Protected Native Decoder Status and Non-secret Lease

## Bug eliminated: stale native read after a view ID is reused
RC120 already invalidated old async reads by generation and range epoch, but on rebinding the same AndroidView/UiKitView ID to another account/content source, `rangeEpoch` could begin again at zero. A delayed native read from the previous decoder could then be routed to the new Dart port by `viewId` alone.

RC121 introduces a strictly increasing **non-secret leaseId**, minted by the Dart port for each binding (never a Backend credential). Dart commands and Native reads include it, and Dart rejects mismatched leases **before calling the source**. Android Media3's DataSource is bound to its original lease, and iOS AVAssetResourceLoaderDelegate also captures the lease. All native play/pause/seek/stop/dispose commands are lease-checked: queued old-session stop cannot affect a newly rebound renderer. This is an in-process fence, not an authorization token.

## Decoder status is not a successful platform call
Android `Player.Listener.onPlayerError` and `onPlaybackStateChanged` reports categorical `failed`, `ready`, `ended`. iOS `AVPlayerItem.status` KVO and `didPlayToEndTimeNotification` report the same categories. No exception text, sensitive headers, credentials, or URL escapes across MethodChannel. Dart only accepts events matching view ID, lease ID, and current seek epoch; on `failed`, `ProtectedPlayerSession.reportRendererFailure()` enters the failed state and stops the native renderer. On `ended`, only **local playback** is stopped; backend authoritative playback end is a separate operation.

## Verification boundaries
Dart fake-channel regression tests cover old leases after reuse, pending responses after stop, event lease/epoch fencing, and failure transition to terminal state. Xcode 27/iPadOS 27 UIScene compile and simulator startup remains a mandatory CI gate. Android Kotlin and iOS Swift compilation is CI-gated. The native decoder callbacks are real, but **there is not yet an end-to-end test with a playable protected MP4 and a physical iPhone/Android device**. No live Backend/MySQL/R2 or DRM acceptance claim. Keep roadmap #58 (Track A vs B) and #15 (17 feature families) unchanged.

Official API reference: https://developer.android.com/reference/androidx/media3/common/Player.Listener
Official AVFoundation status: https://developer.apple.com/documentation/avfoundation/avplayeritem/status-swift.property
