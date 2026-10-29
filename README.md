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
