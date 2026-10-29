---
name: mobile-flutter-dart
description: Senior-plus Flutter/Dart mobile engineering, including architecture, widgets, state, networking, offline data, performance, testing, Android Gradle builds, iOS/Xcode integration, plugins, signing, and release readiness for Google Play and App Store.
---

# Mobile — Flutter + Dart + Platform Build Tooling

## Scope

Flutter and Dart are the primary application technologies. Stay Dart-first. Native platform files are part of Flutter delivery and may be inspected/edited for Gradle, manifests, signing, entitlements, permissions, plugins, platform channels, or platform APIs.

Do not replace Flutter with a native application architecture.

## Architecture

Choose architecture based on product complexity, not fashion.

For medium/large products, prefer feature-oriented boundaries with clear presentation/application/domain/data responsibilities where those layers provide real value. Avoid ceremonial layers for tiny features.

Trace each feature end to end:

widget/route -> state controller/notifier/bloc -> use case/service -> repository -> remote/local data source -> NestJS API/local storage.

The backend remains authoritative for security-sensitive business rules.

## Dart quality

- sound null safety
- strict analysis/lints
- immutable state where practical
- explicit async error paths
- cancel/ignore stale asynchronous work when lifecycle requires it
- avoid uncontrolled `dynamic`
- avoid giant widgets and giant state controllers
- separate view formatting from domain behavior
- deterministic models and serialization
- no swallowed exceptions

## State management

Respect the project's established approach. Do not mix Riverpod, BLoC/Cubit, Provider, GetX, and ad-hoc singletons without a compelling reason.

For new complex projects, choose one primary state-management model after evaluating team/project needs. Keep server state, navigation state, form state, and ephemeral widget state appropriately scoped.

## Flutter ecosystem/tooling

Understand `pubspec.yaml`, dependency constraints, lockfiles, build_runner/code generation, assets/fonts, flavors, environment configuration, localization generation, lints/analyzer options, plugin registrants, and package migration notes. For new dependencies, prefer actively maintained packages with clear platform support and avoid adding packages for trivial functionality.

## Networking/API

Support robust integration with NestJS APIs:

- typed request/response models
- auth token lifecycle
- refresh serialization to prevent refresh storms
- request cancellation/timeouts
- retry only when semantically safe
- idempotency for retryable writes
- pagination
- multipart/file transfer
- WebSocket/realtime when required
- consistent backend error mapping
- offline/cache strategy when product needs it

Never log secrets/tokens in production.

## Local data and offline

Choose local persistence based on query and consistency needs. Handle schema migrations, encryption needs, cache invalidation, conflict resolution, and logout/account deletion cleanup.

Offline-first is a product architecture, not merely saving API responses locally.

## Flutter UI/UX

Handle:

- responsive/adaptive layouts across compact phones, large phones, tablets/iPads, landscape, foldable/large-screen classes when supported
- safe areas and system insets
- keyboard and focus
- text scaling
- semantics/screen readers
- RTL/localization
- theme/dark mode
- animations without blocking interaction
- empty/loading/error/skeleton/retry states
- platform conventions when they materially improve UX

For every user-facing Flutter screen/layout, load `../responsive-adaptive-ui/SKILL.md`. Load UI/UX skill as well for design-heavy or product-flow work.

## Performance

Review rebuild scope, list virtualization, image memory, shader/animation cost, isolate use, excessive JSON work, startup path, plugin overhead, memory leaks, retained controllers, and background tasks. Measure before large optimization rewrites.

## Android + Gradle mastery

Treat the Android directory as production code. Understand and troubleshoot:

- Gradle wrapper
- Android Gradle Plugin (AGP)
- Kotlin/Gradle DSL used by Flutter project templates
- `settings.gradle(.kts)` and `app/build.gradle(.kts)`
- Flutter Gradle plugin
- compileSdk / targetSdk / minSdk
- namespace/applicationId
- JDK/Gradle/AGP compatibility
- NDK requirements
- product flavors/build types
- signing configs and upload keys
- manifest merging
- permissions
- deep links/app links
- R8/minification/ProGuard rules
- multidex
- dependency resolution conflicts
- ABI packaging
- AAB/APK release builds
- Play signing

Do not blindly bump Flutter, Gradle, AGP, JDK, and Kotlin-related settings together. Consult current Flutter/Android compatibility guidance first.

Flutter's current docs note major Gradle/Kotlin build-script changes across versions and ongoing migration for AGP 9+ built-in Kotlin. Treat these as version-sensitive.

## iOS integration mastery

Understand and troubleshoot:

- Xcode project/workspace
- Bundle ID and versions/build numbers
- signing certificates/profiles
- entitlements and capabilities
- Info.plist usage descriptions
- CocoaPods/SPM/plugin integration as used by the project
- deployment target
- universal/deep links
- push notifications/background modes
- keychain/secure storage
- privacy manifests
- required-reason APIs and third-party SDK declarations
- archive/IPA/TestFlight/App Store release

## Plugins

Before adding or upgrading a plugin:

1. verify active maintenance and platform support,
2. check Flutter/Dart/AGP/iOS compatibility,
3. inspect permission/data/privacy impact,
4. inspect native minimum versions,
5. consider bundle/performance impact,
6. test release builds on both Android and iOS.

## Store compliance

For any production mobile release or feature affecting data, permissions, accounts, payments, login, tracking, SDKs, or target SDK, load:

`/mnt/skills/user/software-engineering/release-compliance/SKILL.md`

Store compatibility is a design constraint, not a final checklist added after coding.

## Verification

Use relevant:

- `dart format`
- `flutter analyze`
- unit tests
- widget tests
- integration tests
- golden tests where appropriate
- Android release build/AAB
- iOS release archive/IPA when macOS tooling exists
- physical device validation for permissions, deep links, background behavior, camera/media, notifications, biometrics, and purchases
- store-compliance preflight
- responsive/adaptive validation matrix from `../responsive-adaptive-ui/SKILL.md`

## Fable verified HTTPS links (RC38; Developer / Agent)

- Add `deeplinks` only when the project requires HTTPS app links. Never install its `app_links` dependency in Core or apps with the feature removed.
- From Wizard choose Verified HTTPS Deep Links; use `fable-mobile deeplinks plan|apply|verify|disable` for automation. The same workflows apply with Fable Backend and Other Backend.
- `domain`, Android `applicationId`, real release signing SHA-256 fingerprint, Apple App ID Prefix (may differ from Team ID), and iOS bundle ID are required. Do not invent, reuse a debug fingerprint for production, or store signing private keys.
- Host `.well-known/assetlinks.json` and `.well-known/apple-app-site-association` publicly on HTTPS, with 200 and no redirect; native entitlements + Android autoVerify must match. Validate on actual devices.
- Link routes must be registered once with `FableDeepLinkDispatcher.instance.register('/prefix', callback)` and only for declared destination screens; Auth gate may defer then resume. A verified HTTPS link never grants permission or bypasses Backend access control.
- Re-run generator and link verify after `flutter create` or Bundle ID changes. Remove generated native assets with `deeplinks disable` BEFORE removing optional feature.
- Never report native / domain-live checks as passed unless the tests actually ran.

## Fable RC39 verified link safety
Handle links through optional `fable_deeplinks`, keep the backend neutral, and re-evaluate Auth for deferred navigation. Guard against stale asynchronous authorization answers and encoded path traversal. Treat an existing Android deep-link meta-data declaration or iOS associated-domains entitlement as a manually owned configuration: fail with an actionable message, never duplicate it. Run both Node generator tests and Flutter package analyze/test on a real SDK; static Node tests are not evidence of Dart compilation.

## RC40 — Notification clicks
- عند تثبيت notifications وتهيئة Firebase استخدم `FablePushTapBootstrap` الذي يتلقى `getInitialMessage` و`onMessageOpenedApp`، مع Inbox داخلي يوجّه `ListTile.onTap` إلى `FableNotificationNavigation`.
- `data.target` أو `data.route` يجب أن يشير إلى قدرة مثبتة ومصرّح بها؛ `data.deepLink` أو `data.url` يمر عبر سياسة HTTPS المرتبطة بالدومين المعتمد قبل التنقل.
- رابط المورد التفصيلي يحتاج Route مشروع مسجلة صراحة، ولا يجوز إنشاء وجهة أعمال بالاستدلال من الاسم. لا تستخرج صلاحيات من الـModel أو الـpayload.
- جلب صلاحيات المستخدم من Backend يبقى المصدر الحقيقي، وإشعارات Firebase/Inbox لا تمنح سلطة إضافية. عند غياب الجلسة يُؤجل الانتقال ولا تُعرض بيانات محمية.


## Fable RC41 — link authorization and foreground inbox invalidation
- Use the centralized generated Auth binding for installed verified Deep Links, with explicit public home exception only. Authenticate private destinations for Fable and Other backends through their own session namespace.
- A link or FCM data payload is never a permission grant. Preserve stale-identity cancellation and fail closed when contracts, sessions, or verification are missing.
- `FirebaseMessaging.onMessage` invalidates visible Inbox data; never treat delivery as a tap. Inbox subscriptions to identity and refresh events must be canceled on dispose, and previous-account items removed promptly.
- Run the generated-project regression matrix (provider x Firebase), re-generation/idempotency, Dart analysis and Flutter tests, then native builds in supported CI.

## RC42 — Node.js October 2026 security baseline for Mobile generator (Developer + Agent)
- CLI/CI tools use patched Node >=22.23.4 on Node 22 or >=24.22.1 on Node 24. The supported runtime policy is reviewed in `tools/mobile-oct2026-security.mjs`.
- Before generator/Flutter release run `node tools/mobile-oct2026-security.mjs --policy` and `--runtime` on the actual build runner. CI source, Android and iOS all pin `22.23.4`; do not downgrade to `22` or `22.16.0`.
- Flutter remains independent of Node.js runtime: do not add Node or Nest dependencies to Flutter Core or feature packages. Backend Other remains isolated from Fable.
- Perform dependency advisory checks and Flutter native builds using connected environments. Never interpret a passing policy/source-only check as evidence that a production runtime was patched.

## Fable Stage 3 — Role layout and permission-driven UI (RC45)

For a generated Fable app, first read `.fable/agent/CONTRACT.md` and its required skills; use the selected Backend's verified contract and `operationId` names. A separate-role project owns only **presentation** role ordering via generated `assets/contracts/role-layout.json`. `FableRoleView` selects one declared screen from active backend `roles`, and `FableOperationVisibility` / `FableAuthorizedAsyncButton` / `FableAuthorizedScreen` gate protected actions using the operation policy. Neither role folder nor role name grants a permission. Backend guards always authorize requests.

For a non-Fable backend, import an independent OpenAPI/Custom contract and map the authenticated access snapshot explicitly; never inherit Fable endpoints or `roles`/`keys` names implicitly. On logout, account swap, 403, invalid contract, or a stale response, protected content fails closed. Do not add hand-written repeated `if (role)` permission checks in each screen. Run `npm run test:stage3` and the full Node source gates; run Flutter package analysis/tests and native builds before claiming device readiness.

### RC47 — Optional location contract integration
When working on `fable_location`, inspect the verified Backend RC66 location operations, use provider-neutral repository and explicit External mappings. Do not embed server API keys or silently request OS GPS. Show attribution, respect provider rendering policy and validate route/coordinate inputs. Stage4 Node acceptance plus actual `flutter analyze` and package widget tests are release gates; Node alone does not prove Dart compiles.

## Fable RC49 acceptance rule
For any selected feature, verify its actual Backend operation catalog, optional package dependencies, and generated Native footprint. For support/messaging require explicit client APIs (not incoming Webhooks). Passkeys require a real OS credential adapter and two-factor continuation. Payments are read-only until specialized, reviewed financial transport exists. Run Stage12/3/4 Node gates AND Flutter analyze/test/build on an installed toolchain; report absence of Flutter SDK instead of simulation as compilation evidence. Read `docs/STAGE-4-7-RC49-20261029.ar.md`.
