# RC308 — Flutter 3.50.0 stable / Dart 3.14.0, toolchain verified against Flutter's official defaults

## Decision (16 November 2026)
Use Flutter's **tested template toolchain**, not its minimum tolerated versions, and do not silently trigger a new Flutter or Dart SDK installation when running Fable.

| Component | Pinned version |
|---|---|
| Flutter (operator installs once) | **3.50.0 stable** |
| Dart (bundled with Flutter; do not install separately) | **3.14.0** |
| Gradle Wrapper | **9.5.0** |
| Android Gradle Plugin | **9.3.1** |
| Kotlin Gradle Plugin (declared, not applied by app) | **2.4.20** |
| Kotlin configuration | **Built-in Kotlin = true**, compatibility `android.newDsl=false` |
| Java / Kotlin bytecode | **17** |
| compileSdk / targetSdk / minSdk | **36 / 36 / 24** |
| Android NDK | **28.2.13676358** |
| Android Build Tools | **36.0.0** |

Flutter 3.50.0 official release notes state the default template has AGP 9.3.1, Gradle 9.5.0, Kotlin Gradle Plugin 2.4.20 and Java 17. We retained the pre-existing Fable built-in Kotlin design while keeping the legacy DSL compatibility shim until third-party Android plugins are confirmed compatible. Android SDK/NDK values match Flutter 3.50 defaults and the operator's currently installed SDK components.

Sources:
- Flutter 3.50 release: https://flutter.dev/blog/whats-new-in-flutter-3-50
- Built-in Kotlin migration: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin
- Official AGP/Gradle compatibility: https://developer.android.com/build/releases/about-agp

## What changed in the source repository
- Root `pubspec.yaml` requires Flutter `>=3.50.0 <3.51.0`, Dart `>=3.14.0 <3.15.0`. The **exact preferred patch pair** is in `toolchain/fable-flutter-3.50.json` and verified by the read-only preflight. Reusable subpackages retain broad `environment` constraints as library compatibility declarations; the root app controls its resolved SDK.
- `android/settings.gradle.kts` pins AGP 9.3.1 and KGP 2.4.20. It does NOT apply KGP to the app, which uses AGP built-in Kotlin.
- Gradle Wrapper references `gradle-9.5.0-all.zip`. On the **first** build with an empty Gradle cache it necessarily downloads that distribution, but never chooses a higher Gradle release automatically.
- `android/app/build.gradle.kts` pins compile/target/min SDK 36/36/24, NDK 28.2.13676358, Build Tools 36.0.0 and retains Java/Kotlin 17.
- iOS UIScene, DPoP/Passkeys bridges and all Fable W0–W8 business code are unchanged. The historical `.metadata` is not edited by hand: it is Flutter migration history, not the project's required SDK version.
- No pub package lockfile is committed in this source snapshot; `flutter pub get` may resolve or download pub.dev packages, but it does **not** run `flutter upgrade`.

## Windows, cache on E:
Create the three directories once (`E:\FlutterBuildCache\gradle`, `E:\FlutterBuildCache\pub`, `E:\FlutterBuildCache\temp`). Then in **the same PowerShell terminal**:

```powershell
$env:GRADLE_USER_HOME = 'E:\FlutterBuildCache\gradle'
$env:PUB_CACHE = 'E:\FlutterBuildCache\pub'
$env:TEMP = 'E:\FlutterBuildCache\temp'
$env:TMP = $env:TEMP
flutter --version
pnpm run fable:toolchain:check -- --installed
flutter pub get
```

The check stops if Flutter is NOT exactly 3.50.0 or Dart is NOT 3.14.0 (or the source Android version tuple is wrong). Update the **local Flutter SDK intentionally once** before running it; Dart comes with Flutter. Do not run `flutter upgrade` automatically as part of the Fable build. The original Flutter 3.47.9 environment is intentionally rejected by the new root pubspec and preflight. You can also run `pnpm run fable:toolchain:check` for source-only validation with **no SDK invocation**.

## Unverified boundaries
Version selection is backed by Flutter's release notes, but **this project's dependency graph and Android/iOS native plugins have not yet been built on Flutter 3.50**. Built-in Kotlin could fail on un-migrated third-party plugins; do not switch to an unreviewed mixed toolchain without inspecting the exact plugin conflict. Existing debug signing and `com.example.helloworld` Android application ID are NOT production-ready and must be configured for the user's final app.

No Flutter SDK, Gradle, Android or iOS build and no device E2E were executed. W0–W2 source established, W3–W6 integration source in progress, W7 user-owned acceptance, W8 final delivery open; production NO_GO.
