# RC120 — UIScene and native protected player (Track A)

## Mandatory iOS 27 / iPadOS 27 UIScene lifecycle

Flutter baseline already used `UIApplicationSceneManifest` with:
- `UIApplicationSupportsMultipleScenes=false`, one `UIWindowSceneSessionRoleApplication`.
- `UISceneClassName=UIWindowScene`, `UISceneDelegateClassName=FlutterSceneDelegate`, `UISceneConfigurationName=flutter`, storyboard Main.
- `AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate`; `GeneratedPluginRegistrant` registered inside `didInitializeImplicitFlutterEngine` rather than process launch. Workmanager background task handlers remain in application launch.

**RC120 hardens and independently verifies this configuration:** Python plistlib source/built-info gate and CI iOS simulator build on pinned Flutter 3.47.8. **CI RC120 uses the official GitHub `xcode-27` arm64 macOS 27 image (not the old `macos-26` Xcode 26.6 runner), requires iOS Simulator SDK 27, checks the compiled app plist, then installs/launches/terminates the Runner app on both iPhone 27 and iPad 27 simulators.** This proves scene-capable simulator startup only, not actual native media playback, credentials or physical hardware.

**Do not set `enable-uiscene-migration: false`, do not prefix the scene manifest with an underscore**, and never access `window?.rootViewController` in `didFinishLaunchingWithOptions`.

Apple's Xcode 27 SDK requires UIScene or startup fails. Full iOS 27 runtime launch is accepted only when the separate Xcode 27 simulator smoke test passes on iPhone AND iPad; `flutter build ios` alone is insufficient. Physical device startup still requires independent verification.

Sources:
- https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle
- https://docs.flutter.dev/release/breaking-changes/uiscenedelegate
- https://docs.flutter.dev/platform-integration/ios/platform-views

## Native bridge scope

Protected progresssive **audio/video byte streams**, no streaming manifest/DRM. Flutter Session already validates Backend range 206, MIME and response boundaries. Native platform code may consume only bounded byte buffers with nonsecret view ID, range generation and length. No source URLs, account IDs, HTTP headers, authentication or media tokens are passed into native. Android and iOS native implementations require device and Backend/R2 E2E. P6 stays open; this PR cannot be labelled production-ready based on CI builds alone.
