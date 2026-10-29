# Fable RC49 — FlutLab validation project

This ZIP was merged from the user-supplied Hello-World Flutter project and the
Fable RC49 Fable-Backend test application. The `android/`, `ios/`, and `web/`
platform shells are from Hello-World. The `lib/`, `packages/`, `assets/`,
`test/`, `pubspec.yaml`, `l10n.yaml`, and generator metadata come from Fable.

## Import

1. In FlutLab's projects dashboard, choose **Upload as a ZIP file**.
2. Upload **this file**, not the previous Fable RC49 ZIP.
3. The previous `android/ required` error should no longer appear, since
   `android/` and `ios/` are now present and contain nonempty platform projects.
4. Confirm the SDK used by FlutLab. Fable RC49's pubspec declares Dart
   `>=3.13.5 <4.0.0` and uses `material_ui` and `cupertino_ui` packages.
   Use Flutter **3.47.7 or newer**, preferably 3.47.8 / Dart 3.13.7.
   The original Hello-World shell was configured for Flutter >=3.41,
   but that does NOT mean RC49 can build on Dart 3.11.
5. Run Pub Get, then Flutter Analyze / Tests, and Android Build.
6. Preserve and share the first error log if any of those steps fails.

## Safety / provenance

- The test Android applicationId and Kotlin namespace are kept as
  `com.example.helloworld` to preserve the working starter native structure.
  Change them before any actual release.
- No credentials or provider production configuration are added.
- Runtime Flutter native build has NOT been executed while preparing this ZIP;
  file and source references have been checked statically.
- This ZIP is for testing, not a production-signed app or release candidate.
