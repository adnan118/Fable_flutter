# RC123 — Real Android Media3 H264 progressive simulator proof

## Baseline and user requirements

RC122 merged Flutter/main `2debffb8bdc419c8a94af880261a20bc6331c977` after 4 exact-head CI checks, including authentic protected-bridge H264 playback on an iOS 27 simulator, with iPhone+iPad UIScene 27 compatibility. Do not alter that baseline.

RC123 adds a *separate* Android emulator GitHub Actions acceptance gate, rather than using an APK build as proof of decoding. It uses the **same original, verified 1,569-byte H264 Baseline MP4 fixture** (Git blob `e477b0298e79f42fc73c3270c36a5b032579b713`) and `integration_test/rc122_protected_video_test.dart`.

The test mounts `FableNativeProtectedPlayerSurface` on a real Android platform view and requires Android Media3 ExoPlayer to fetch bytes through the guarded Dart `DescribedMediaByteSource` and Native lease-bound `DataSource`. It verifies an actual Player.STATE_READY event, more than one read (source probe and native), play, Player.STATE_ENDED, and no native failure. A method-channel ACK, Android build, or iOS UIKit Scene launch **alone does not pass**.

**CI implementation:** `.github/workflows/rc123-media3-emulator.yml`, Linux Ubuntu 24.04, JDK17, Flutter 3.47.8, hardware KVM, Android Google APIs x86_64 API35, Pixel 6 emulator, bounded 70 minute job; `reactivecircus/android-emulator-runner@v2` owns emulator lifecycle. Any failure of the emulator start, compilation, native decoder or events fails closed. No `continue-on-error`. Existing Xcode 27 iPhone+iPad UIScene baseline gate remains mandatory.

**Strict limits:** emulator codec verification is not proof on real Android hardware; no production Backend/MySQL/R2 or protected JWT/403/rotation/expiry, no AAC/audio or DRM/HLS/DASH, and original 17 feature families remain without live E2E acceptance. Follow-up P6: seek/pause/resume/switch, real R2 protected 206 bytes and auth invalidation, device telemetry and physical iOS/Android coverage.

## RC123 first-run toolchain correction (2026-11-05)
Workflow [#42031665860](https://github.com/adnan118/Fable_flutter/actions/runs/42031665860) failed **before emulator boot**, in `android-actions/setup-android@v3` because it executed `sdkmanager tools`, which returned `Warning: Failed to find package 'tools'`. This is a hosted SDK setup incompatibility, **not a Media3 decoder failure**. On Ubuntu 24.04 use existing `ANDROID_HOME`/sdkmanager and allow `reactivecircus/android-emulator-runner@v2` to install actual API35 emulator image. Keep fixture/hardware KVM/native decoder assertion and fail-closed status mandatory.

## Second toolchain correction
CI [#42032030335](https://github.com/adnan118/Fable_flutter/actions/runs/42032030335) proved that the new Ubuntu 24.04 hosted image lacks a pre-exported `ANDROID_HOME`, so relying on a preinstalled SDK fails before emulator setup. Confirmed from current upstream `android-actions/setup-android` documentation: **v4** no longer requests obsolete SDK `tools` package, initializes modern cmdline-tools and supports `packages: 'platform-tools emulator'`. Switch from v3/preinstalled assumption to v4. Retain emulator and actual decoder assertions; no skip.

## Third CI correction — actual emulator script shell
Run [#42032360352](https://github.com/adnan118/Fable_flutter/actions/runs/42032360352) confirmed SDK v4 installation and Android API35 emulator boot SUCCESS. It then failed before Flutter test started because `reactivecircus/android-emulator-runner@v2` uses `/usr/bin/sh` for its script, and POSIX dash rejects `set -euo pipefail`. Fixed by moving test command to `tools/rc123_media3_emulator_test.sh` with a Bash shebang and invoking explicitly as `bash tools/rc123_media3_emulator_test.sh`. This fixes the command interpreter only; real H264 decoder remains mandatory and unverified until subsequent run.

## RC123 teardown race diagnosis and correction (2026-11-05)

Exact Android API35 run [#42032956417](https://github.com/adnan118/Fable_flutter/actions/runs/42032956417) booted the emulator, installed the app, and the integration test reported `+1` after its native ready/range-read/play/ended assertions. It then emitted `PlatformException(protected_player_rejected)` from `FableNativeProtectedPlayerPort.dispose()` after the test body completed. The test's widget unmount races Flutter's asynchronous PlatformView destruction: native `PlatformView.dispose()` calls `bridge.unregister(viewId)` before the Dart State.dispose MethodChannel cleanup is processed. This is a **native cleanup lifecycle defect**, not a decoder assertion failure.

**Fix:** Android MethodChannel `stop`/`dispose` are now idempotent cleanup operations. If the PlatformView is already unregistered, or its ID has been reused under a different lease, cleanup returns success as a no-op. It never stops a newer lease. All playback-changing commands (`play`, `pause`, `seek`) remain strict on view + lease; prepare remains explicitly bound to new lease. The shared integration test now waits for source close and terminal `disposed` state after unmount so teardown errors cannot arrive after a reported pass. No errors are ignored or hidden.

The same view-destruction race is handled symmetrically in iOS AVFoundation bridge: `stop`/`dispose` on an already detached UIKit PlatformView or stale lease are successful no-ops; active `play`/`pause`/`seek` remain lease strict. This keeps cross-platform teardown semantics aligned without weakening player identity fencing.
