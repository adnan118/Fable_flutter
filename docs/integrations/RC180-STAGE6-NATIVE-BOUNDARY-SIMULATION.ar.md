# RC180 (Flutter) — Stage 6.7 Android/iOS platform failure-mode simulations

**2026-11-11 — 16/16 Node simulator tests PASS; 108/108 cumulative Stage6 Node-model tests PASS. This is not native execution.**

## Actual tests and exact provenance

- `test/rc180-stage6-native-boundaries-simulator.test.mjs` is **byte-for-byte identical** to executed local Node 22.16.0 test source, Git blob SHA `53ba44ea88577353f39ddab8f5b10aba98f22574`.
- The new test contains a **fake MethodChannel and OS scheduler**, not Flutter/Kotlin/Swift runtime.
- Tests 01–16 verify simulated supported platform and exact Fable pin, missing hardware, missing native channel, native exception, malformed proof shape, method/HTTPS/origin scope, identity change/logout mid-sign, no software key fallback, fake best-effort scheduling, missing worker credentials and OS opportunity.
- Combined 108/108 PASS in local temporary assembled Node test directory, with RC174–RC179 suites.
- Actual source previously reviewed: `packages/fable_core/lib/src/fable_native_dpop_proof_signer.dart`, `android/app/src/main/kotlin/com/example/helloworld/FableDpopNativeBridge.kt`, `ios/Runner/FableDpopNativeBridge.swift`, `tools/rc166-dpop-source-audit.mjs`, `tools/rc166-native-dpop-source-audit.mjs`, `packages/features/fable_offline/lib/src/offline_platform_scheduler.dart`.
- Existing RC166 source audit checks platform-bound AndroidKeyStore hardware P-256, iOS Secure Enclave, JWT P1363 and per-origin key aliases; **this RC180 change did not execute Kotlin/Swift or validate a real ES256 native signature**.

## Strict boundaries

The synthetic proof returned by the test double is **only a shape-valid string**, not a verified cryptographic signature; the actual RC175 Node cryptographic simulation separately exercises real P-256. The synthetic `hasHardware=true` flag is not proof of Android TEE/StrongBox or Apple Secure Enclave. No device/emulator, Dart/Flutter SDK, Xcode, WorkManager, BGTaskScheduler, Firebase, production credentials or paid services were used. OS opportunity is explicitly best-effort, with no timing guarantee. Source checks are not equivalent to native builds.

**Gate 6.7 DEVELOPMENT SIMULATED ACCEPTANCE ONLY.** All 17 feature families remain `complete:false` and `liveE2EVerified:false`. Stage7 production remains NO-GO. Gate 6.8 (integrated Wizard, generator, contracts) is next.

[Stage6 gates](./STAGE6-8-SIMULATION-GATES-2026-11-11.ar.md).
