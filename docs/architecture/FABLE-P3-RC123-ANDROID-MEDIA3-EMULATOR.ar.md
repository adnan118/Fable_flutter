# RC123 — Real Android Media3 H264 progressive simulator proof

## Baseline and user requirements

RC122 merged Flutter/main `2debffb8bdc419c8a94af880261a20bc6331c977` after 4 exact-head CI checks, including authentic protected-bridge H264 playback on an iOS 27 simulator, with iPhone+iPad UIScene 27 compatibility. Do not alter that baseline.

RC123 adds a *separate* Android emulator GitHub Actions acceptance gate, rather than using an APK build as proof of decoding. It uses the **same original, verified 1,569-byte H264 Baseline MP4 fixture** (Git blob `e477b0298e79f42fc73c3270c36a5b032579b713`) and `integration_test/rc122_protected_video_test.dart`.

The test mounts `FableNativeProtectedPlayerSurface` on a real Android platform view and requires Android Media3 ExoPlayer to fetch bytes through the guarded Dart `DescribedMediaByteSource` and Native lease-bound `DataSource`. It verifies an actual Player.STATE_READY event, more than one read (source probe and native), play, Player.STATE_ENDED, and no native failure. A method-channel ACK, Android build, or iOS UIKit Scene launch **alone does not pass**.

**CI implementation:** `.github/workflows/rc123-media3-emulator.yml`, Linux Ubuntu 24.04, JDK17, Flutter 3.47.8, hardware KVM, Android Google APIs x86_64 API35, Pixel 6 emulator, bounded 70 minute job; `reactivecircus/android-emulator-runner@v2` owns emulator lifecycle. Any failure of the emulator start, compilation, native decoder or events fails closed. No `continue-on-error`. Existing Xcode 27 iPhone+iPad UIScene baseline gate remains mandatory.

**Strict limits:** emulator codec verification is not proof on real Android hardware; no production Backend/MySQL/R2 or protected JWT/403/rotation/expiry, no AAC/audio or DRM/HLS/DASH, and original 17 feature families remain without live E2E acceptance. Follow-up P6: seek/pause/resume/switch, real R2 protected 206 bytes and auth invalidation, device telemetry and physical iOS/Android coverage.

## RC123 first-run toolchain correction (2026-11-05)
Workflow [#42031665860](https://github.com/adnan118/Fable_flutter/actions/runs/42031665860) failed **before emulator boot**, in `android-actions/setup-android@v3` because it executed `sdkmanager tools`, which returned `Warning: Failed to find package 'tools'`. This is a hosted SDK setup incompatibility, **not a Media3 decoder failure**. On Ubuntu 24.04 use existing `ANDROID_HOME`/sdkmanager and allow `reactivecircus/android-emulator-runner@v2` to install actual API35 emulator image. Keep fixture/hardware KVM/native decoder assertion and fail-closed status mandatory.
