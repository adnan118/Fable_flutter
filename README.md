# Fable Mobile RC49 — Flutter validation

This repository holds the **Flutter test application** generated from Fable Mobile RC49 with the native Android/iOS/web platform shells supplied in Hello-World.zip. It is **not a production-ready app**.

## SDK baseline

- Source-pinned Flutter **3.50.0 stable**
- Bundled Dart **3.14.0**
- Production credentials and signing keys are intentionally not included.

## CI verification

GitHub Actions executes dependency resolution, Dart/Flutter analysis, root tests, available feature-package tests, Android debug APK build, and unsigned iOS simulator build. **Only actual green workflow results count as validation.** Neither successful upload nor a syntactically valid workflow proves Flutter compatibility.

Native compatibility must be checked on the operator's real Flutter 3.50 environment. Source version pins alone are not evidence of successful builds.

Do not deploy this starter: its Android applicationId remains com.example.helloworld. Configure production identifiers, credentials, signing, integrations and live E2E tests before release.

## RC308 — Flutter 3.50 official toolchain

Fable's preferred local SDK is **Flutter 3.50.0 stable / Dart 3.14.0**, with Flutter's release-verified Android build versions **Gradle 9.5.0 / AGP 9.3.1 / Kotlin plugin 2.4.20 / Java 17**. Android SDK 36/36/24, NDK 28.2.13676358 and Build Tools 36.0.0 are pinned. Built-in Kotlin remains enabled; the legacy DSL compatibility flag remains `android.newDsl=false` while native plugins undergo real validation.

The project does **not** download or upgrade Flutter/Dart SDKs on its own. Install Flutter 3.50.0 intentionally on your machine once (Dart ships with it), then run `pnpm run fable:toolchain:check -- --installed` for the read-only installed-version check. `pnpm run fable:toolchain:check` checks source-only settings without invoking Flutter or Java. First Android build may download pinned Gradle 9.5.0 if not cached. See [RC308 compatibility and Windows E-drive cache guide](docs/integrations/RC308-FLUTTER-350-VERIFIED-TOOLCHAIN.ar.md). Build success is unverified; production remains NO_GO.

## RC309 — Generate all selected Fable features in one batch

From the **Fable Flutter source repository**, pass `--root PATH_TO_GENERATED_PROJECT` pointing to a generated project with an imported project-bound Backend contract and a `.fable/project-features.json` listing the selected custom features, preview everything in one call:

```bash
pnpm run wizard:feature:batch -- --root PATH_TO_GENERATED_PROJECT --expected-project-id PROJECT_ID --expected-contract-hash SHA256 --wire-app
```

After reviewing all source-gated operations, generate and bind all selected features in one source batch:

```bash
pnpm run wizard:feature:batch -- --root PATH_TO_GENERATED_PROJECT --expected-project-id PROJECT_ID --expected-contract-hash SHA256 --apply --wire-app
```

Every selected feature is checked before writing; packages are staged together, app registry/pubspec edits are composed in memory, and original app files are durably backed up with best-effort guarded rollback. Unsupported contracts block the batch; nothing silently bypasses security policies. The operation **does not download Flutter/Dart**, build, or run tests. It prepares source for subsequent Flutter 3.50 verification by the operator. Read [RC309 guide](docs/integrations/RC309-W4-W5-BULK-PROJECT-FEATURE-INTEGRATION.ar.md). W7/W8 live acceptance remains open.

## RC311 — Independent selected feature source attestation

The existing one-command `wizard:feature:batch -- --apply --wire-app` now re-renders and verifies every selected generated package after committing the source, rejecting missing, changed or injected files and missing/duplicate canonical app bindings. Failure enters the existing guarded rollback path.

Re-check a previously generated project without writing to it:

```bash
pnpm run wizard:feature:verify -- --root PATH_TO_GENERATED_PROJECT --expected-project-id PROJECT_ID --expected-contract-hash SHA256
```

For packages deliberately generated without host app wiring, pass `--no-app-wiring`. The verification is source-only; it does not run tests, Flutter, Gradle, SDK downloads, Prisma, networks or live E2E. Production is still NO_GO. See [RC311 details](docs/integrations/RC311-SELECTED-FEATURE-SOURCE-ATTESTATION.ar.md).
