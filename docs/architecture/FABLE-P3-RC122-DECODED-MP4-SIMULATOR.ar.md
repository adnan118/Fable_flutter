# RC122 — H.264 Protected Byte Source native-decoder simulator test

**Fixture:** `assets/videos/rc122_blue_h264.mp4`, SHA256 `c6b831...notused` is NOT authoritative; validate via `ffprobe` and `git hash-object` below. This is an original synthesized 32×32 single-color, 1s, 5fps H.264 baseline MP4, **video-only** (no AAC/audio claim). 1569 bytes, faststart, deterministic, no user data or credentials. Git blob `e477b0298e79f42fc73c3270c36a5b032579b713`.

The integration test `integration_test/rc122_protected_video_test.dart` mounts the real `FableNativeProtectedPlayerSurface` and supplies the exact MP4 bytes using a `DescribedMediaByteSource` implemented in memory. Native must issue range read requests over the **same lease-bound MethodChannel as production**. The test observes a real decoder `ready` notification, requires more than the initial probe byte read, calls `play()`, and requires native `ended` after actual decoding. A returned `prepare()` method result alone is **not acceptance**. A `failed` decoder event fails the test.

**Isolated scope:** no live Backend/MySQL/R2, physical device, authentication or encryption, DRM/HLS/DASH, audio codec fixture, camera, or UI feature-family E2E. Such checks remain P6. No media source file URL, bearer or token is sent to Android/iOS.

**CI:** separate Xcode 27 iOS 27 simulator `flutter test` integration job; the existing iPhone+iPad `UIScene` startup smoke remains mandatory, independent of RC122. The RC122 workflow must report success before merging.

To regenerate fixture locally:
```bash
ffmpeg -f lavfi -i "color=c=blue:s=32x32:d=1:r=5" -c:v libx264 -profile:v baseline -level 3.0 -pix_fmt yuv420p -preset veryslow -crf 35 -movflags +faststart -an -y assets/videos/rc122_blue_h264.mp4
ffprobe -v error -show_entries stream=codec_name,width,height -show_entries format=duration,size -of json assets/videos/rc122_blue_h264.mp4
git hash-object assets/videos/rc122_blue_h264.mp4
```

References: https://docs.flutter.dev/testing/integration-tests and https://developer.apple.com/documentation/avfoundation/avassetresourceloader.
