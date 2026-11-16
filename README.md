# Fable Mobile RC49 — Flutter validation

This repository holds the **Flutter test application** generated from Fable Mobile RC49 with the native Android/iOS/web platform shells supplied in Hello-World.zip. It is **not a production-ready app**.

## SDK baseline

- Flutter **3.47.8 Stable**
- Bundled Dart **3.13.7**
- Production credentials and signing keys are intentionally not included.

## CI verification

GitHub Actions executes dependency resolution, Dart/Flutter analysis, root tests, available feature-package tests, Android debug APK build, and unsigned iOS simulator build. **Only actual green workflow results count as validation.** Neither successful upload nor a syntactically valid workflow proves Flutter compatibility.

FlutLab currently reports Dart 3.11.5 and therefore cannot resolve the SDK constraint of this test application. Use the CI runners here for the current required Flutter SDK.

Do not deploy this starter: its Android applicationId remains com.example.helloworld. Configure production identifiers, credentials, signing, integrations and live E2E tests before release.

## RC308 — Flutter 3.50 official toolchain

Fable's preferred local SDK is **Flutter 3.50.0 stable / Dart 3.14.0**, with Flutter's release-verified Android build versions **Gradle 9.5.0 / AGP 9.3.1 / Kotlin plugin 2.4.20 / Java 17**. Android SDK 36/36/24, NDK 28.2.13676358 and Build Tools 36.0.0 are pinned. Built-in Kotlin remains enabled; the legacy DSL compatibility flag remains `android.newDsl=false` while native plugins undergo real validation.

The project does **not** download or upgrade Flutter/Dart SDKs on its own. Install Flutter 3.50.0 intentionally on your machine once (Dart ships with it), then run `pnpm run fable:toolchain:check -- --installed` for the read-only installed-version check. `pnpm run fable:toolchain:check` checks source-only settings without invoking Flutter or Java. First Android build may download pinned Gradle 9.5.0 if not cached. See [RC308 compatibility and Windows E-drive cache guide](docs/integrations/RC308-FLUTTER-350-VERIFIED-TOOLCHAIN.ar.md). Build success is unverified; production remains NO_GO.
