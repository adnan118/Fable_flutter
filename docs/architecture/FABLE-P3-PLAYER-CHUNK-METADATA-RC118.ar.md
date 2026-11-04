# RC118 — Track A: Verified Progressive Range Metadata for Native Player Bridge

**Baseline:** RC117 Flutter/main `ac223675d18cbcf1e2233de1451fd7e119936e9e`; post-merge CI 3/3 confirmed. **Scope:** native-player prerequisite in Track A, not a native player implementation or Track B refactor.

## Why this is necessary

RC113/RC114/RC117 provide bounded authenticated bytes, typed failures, cancellation and synchronous invalidation, but `MediaByteSource.read()` returns only a copy of the bytes. An Android Media3 `DataSource.open(DataSpec)` may need a resolved stream length; an iOS `AVAssetResourceLoaderDelegate` must respond to content-information and byte-range requests. A byte buffer without the **server-confirmed total length and MIME** cannot safely describe a seekable progressive resource.

Official platform interfaces consulted:
- Android Media3 DataSource (open/read/close): https://developer.android.com/reference/androidx/media3/datasource/DataSource
- Android custom DataSource factory: https://developer.android.com/media/media3/exoplayer/customization
- Apple AVAssetResourceLoaderDelegate: https://developer.apple.com/documentation/avfoundation/avassetresourceloaderdelegate
- Apple AVAssetResourceLoadingContentInformationRequest: https://developer.apple.com/documentation/avfoundation/avassetresourceloadingcontentinformationrequest

## Changes

- **Additive pure-Dart Domain contract:** `MediaByteChunk` copies the byte buffer and carries `start`, `totalLength`, `mimeType`; `DescribedMediaByteSource` extends the existing session-bound port with `readChunk(MediaByteRange)`. Existing `MediaByteSource.read()` and its consumers remain source-compatible.
- **Fable Data adapter:** `FableProtectedMediaPlaybackRepository.readContentRangeChunk()` derives the total strictly from a validated `206 Content-Range` and the MIME from the guarded `Content-Type`. Bounded length, exact `Content-Length`, no-store, identity encoding, same session/epoch, and no redirect or leaked URL/token remain enforced. Old `readContentRange()` delegates to the new implementation.
- **Session-bound chunk source:** `FableMediaByteSource` now implements the optional described port and **rejects differing MIME or total-length values within a single playback view**. Read still returns bytes only for current callers.
- **Conservative progressive scope:** MIME must match `audio/*` or `video/*`; malformed/HTML/JSON/manifest-style headers cannot silently become playable content. This MIME check alone is NOT proof of codec support.
- **Simulations:** verify exact metadata, immutable defensive byte copies, short final range, nonmedia MIME rejection, and metadata changes during a view.

## Native adapter design — next RC, not included here

1. **Android:** implement platform-owned `DataSource.Factory` / `DataSource` plugged into Media3 `ProgressiveMediaSource`. Map `DataSpec.position` into sequential bounded `readChunk` requests. Correctly model `open/read/close` and EOF; cancellation/identity invalidation must stop/release the decoder and discard queued bytes. Never block Flutter's UI thread waiting for a synchronous native read.
2. **iOS:** adopt `AVAssetResourceLoaderDelegate` for a custom, non-network asset scheme, supply validated `contentLength`, format metadata and bounded offsets, and honor delegate cancellation. Player item must be destroyed/stopped when the Domain invalidation signal fires; never treat an old buffer as still authorized.
3. **Bridge:** per-player session generation and pending request IDs; max 512 KiB chunk; bounded queue, backpressure, timeout and explicit `cancel`; asynchronous Dart requests carry only `start/length` and nonsecret request identity. Never pass credential headers, tokenized URLs, account IDs or raw backend response maps to platform code.
4. **Limit:** Progressive authenticated byte streams only. DRM, HLS/DASH manifest/license fetching, codec/media compatibility and hardware behavior require separate proved designs and device testing.
5. **Tests:** slow/out-of-order native requests, refresh while playing, A→B identity, pause/resume/seek/end/dispose, content-type and total-size discrepancies, EOF and native teardown. CI builds are not actual Android/iOS playback tests.

## Acceptance honesty

RC118 proves only source-level metadata and simulation. It does **not** constitute a functioning Media3 or AVPlayer bridge. Track A and P6 remain OPEN until source adapters, CI, actual devices and real Backend + DB + R2 are verified. All 17 feature-family `liveE2EVerified` flags remain false. Backend main and private source ZIP are unchanged.
