# RC214 — W6 Auth family: account-switch race hardening (2026-11-14)

**Scope:** One real Auth family code correction and targeted Dart/Widget regressions. **Not an approval of all 17 feature families, native platforms, providers, W6 overall, or production.**

## Production-impacting conditions corrected
1. **Late old-account Logout with `revoked:true`.** The existing `FableAuthGateway.logout()` could return `true` after the old server replied successfully, even when the device's session changed during the request and `clearSessionIfIdentity(identityAtStart)` correctly **refused** to clear the newly signed-in account. This could cause a Flutter UI to wrongly tell the user that the *current* account was signed out.
2. **Stale saved-session check leaves sign-in UI busy.** The prior `_verifySavedSession()` ignored obsolete async replies (correct), but the `finally` guard also prevented resetting `_busy` after an identity revision change (incorrect), leaving the screen's verification control disabled.
3. **Old Login result overwriting current identity UX.** The Login page previously showed a delayed old request's error even after another authenticated account switched in; error messages now require the original session identity revision.
4. **Logout UI response mismatch.** After an obsolete Logout completes, the UI re-reads the current session token. A new active token is **never cleared** or reported as 'signed out'; the screen marks it unverified and offers explicit server verification. The sensitive no-auto-retry, Fable DPoP and identity-guarded credential handling remain unchanged.

## Actual source modifications
- `packages/fable_core/lib/src/fable_auth_gateway.dart`: `logout()` now records `clearedThisIdentity=await session.clearSessionIfIdentity(identityAtStart)` and returns `clearedThisIdentity && revokedOnServer` instead of trusting only the stale Backend response.
- `packages/features/fable_auth/lib/src/login_page.dart`: releases busy state after obsolete saved-session verification; detects nonempty current session token after old Logout; protects delayed Login error display by the originating session revision.
- `packages/fable_core/test/auth_gateway_identity_regression_test.dart`: new delayed `revoked:true` test with account switch and preservation of the new access/refresh credentials.
- `packages/features/fable_auth/test/mandatory_password_change_page_test.dart`: three new Widget tests using asynchronous Dio interceptors and a deterministic in-memory identity-aware secure session. They cover obsolete saved-session verification, obsolete success reply to Logout, and obsolete Login failure.
- `test/rc214-w6-auth-race-source.test.mjs`: six source integrity tests that ensure this race fix and the targeted Flutter tests remain wired to the repository.

## Tests to execute in the real Flutter toolchain
```sh
cd Fable_flutter
npm run test:w6:auth:source
npm run test:w6:auth
flutter analyze
```

`test:w6:auth` runs:
```sh
flutter test packages/fable_core/test/auth_gateway_identity_regression_test.dart packages/features/fable_auth/test/mandatory_password_change_page_test.dart
```

**Evidence actually executed here:** 12/12 isolated V8 source/wiring assertions on exact GitHub code blobs (one Login/Logout/Build method, preservation of identity-bound cleanup and DPoP, mock test presence and target scripts). The **six Node source tests and four new Dart/Widget tests were committed, not executed in the model environment**, which has Node but no Dart/Flutter SDK or private checkout. Do not infer authenticated provider E2E, native hardware DPoP, or device testing.

## W6 stage acceptance
**Auth is still OPEN overall.** RC214 closes source-level races, but it does not replace the whole Auth (and other 16 families) acceptance set: verified Backend user/session/OTP operations, mismatched responses, 2 devices, refresh rotation, owner-required features, Other Backend adapter, native platforms, accessibility and security provider E2E remain separate prerequisites.

Latest Backend RC209 main remains `54ada55570e6d1f5921b0197946da31d5db14610`; this source update builds on Flutter RC213 main `d9e1a2f58ad13c05a6ba51221a2ee6690cc3dc6d`. No historical source, DPoP policy, prior test or 82 W0 evidence items are discarded.
