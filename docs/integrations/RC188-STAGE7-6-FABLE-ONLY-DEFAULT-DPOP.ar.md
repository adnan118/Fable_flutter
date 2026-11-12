# RC188 — Fable-only DPoP by default, Other Backend excluded — Stage 7.6

**2026-11-12 | Source-level development gate only; NO Android/iOS compiled, no live device/production sign-in.**

## User decisions enforced
- **Fable Backend + Flutter Fable mobile**: DPoP requires native hardware-backed P-256/ES256. No extra external API credential or paid API. Flutter's `FABLE_DPOP_NATIVE_ENABLED` build flag now **defaults to `true`**.
- **Other Backend**: **DPoP from Fable is OFF**. For an `OperationCatalog` not of type `FableContract`, the central resolver returns `null` without injection and throws `ArgumentError` when a Fable signer is supplied. The `ExternalTransportAdapter` rejects any `DPoP` header smuggling. This does NOT forbid an independently designed authentication protocol for Other Backend.
- **Fable Web**: native DPoP is not added; its separate HttpOnly cookie/CSRF design remains unchanged.
- **Release mobile safety**: `FABLE_DPOP_NATIVE_ENABLED=false` is rejected (no silent Bearer fallback). Release requires **exact 64-hex Fable Backend contract hash and exact HTTPS origin** (both supplied through trusted `--dart-define` build configuration), `selectionMode='explicit'`, auth capability and non-fixture project. Missing/altered pin blocks release. A fake injected signer is forbidden in release; signer requires AndroidKeyStore secure hardware or iOS Secure Enclave. No software key fallback.
- **Non-release test/dev**: explicit `FABLE_DPOP_NATIVE_ENABLED=false` may be used for mocked/fixture tests; missing verified pins may leave signer disabled outside release to preserve isolated fixtures. This is a compatibility boundary, **not** a production downgrade. For real Fable integration, configure verified pins before login.

## Required build configuration (from trusted project contract; never invent)

```sh
flutter build apk --release \
  --dart-define=FABLE_DPOP_NATIVE_ENABLED=true \
  --dart-define=FABLE_DPOP_BACKEND_CONTRACT_HASH=<ACTUAL_64_HEX> \
  --dart-define=FABLE_DPOP_BACKEND_ORIGIN=https://<ACTUAL_VERIFIED_FABLE_HOST>
```

Use the actual verified per-project hash and origin for iOS builds as well. These example placeholders cannot be used to build an accepted release. Native hardware not available on emulator/simulator must fail closed, and migrating old bearer-only user sessions requires coordinated re-login.

## Evidence and limits

- **15/15 direct GitHub source assertions** checked on the branch (default, Fable-only, Other Backend rejection even with explicit signer, shared Fable API/Auth ports, 17 family flags, AndroidKeyStore & Secure Enclave declarations).
- **9 Node-source and 12 Stage7.6 Node-source regression tests authored**, plus **4 Dart Flutter regressions authored** for Other Backend isolation. Their full CLI runs, `flutter test`, `flutter analyze`, Android/Kotlin and iOS/Swift compilers **were NOT executed** in this environment. Source predicates are not a compiled test pass.
- Previous Flutter Stage6 gates **8/8 development-simulation accepted**; 17/17 features still `complete=false`, `liveE2EVerified=false`.
- Backend pairing: RC188 source and generated Auth blueprint change `AUTH_DPOP_FLUTTER_MODE` default to `required`, and RC187 retains production fail-closed even on explicit `off`. Flutter's `GET /auth/session-policy` readiness probe must confirm `required` before native login/refresh, not assume source setting matches deployed Render.
- Nothing in this change deploys either repository to Render or publishes a mobile release. Current `pnpm-lock.yaml` root importer mismatch and all Stage7 real hardware/DRM/payment/approval blockers remain.

**Stage7 Gate 7.6 DEVELOPMENT SOURCE/MODEL ACCEPTED ONLY. Stage7 production decision NO-GO.** Remaining 7.7/7.8 internal gates are pending.

[Flutter Stage6 development report](./RC181-STAGE6-8-GATES-SIMULATION-ACCEPTANCE.ar.md) · [Backend Stage7 tracker](https://github.com/adnan118/Fable/blob/main/Fable-Backend-RC66/docs/STAGE7-8-GATES-PROGRESS-2026-11-11.md).
