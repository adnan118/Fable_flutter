# RC94 — checkpoint (in progress, not production release)

## Verified baselines
- Flutter RC93 main SHA `921b9e9e54665f1befd04683e8c14dc141d4414e`.
- Backend private RC66 main SHA `226cbcdc542ebe9c005d7445d84cc0ec10631932`.
- RC93 ledger: Auth 22/40 source-reviewed, 18 still pending, 0/17 live E2E accepted.
- The user's working copies have not been synchronized recently; this branch is **not proof** that it contains any newer local changes.

## RC94 scope / source delivered in this branch
- `fable_auth_username.dart`: contract-gated username availability and update, exact Backend paths/methods, reserved-name checks, identity revision guard, strict response confirmation, optional UUIDv4 step-up proof.
- `fable_api.dart`: safe substitution for both `{param}` and NestJS `:param` path syntax.
- `fable_social/social_auth_repository.dart`: exact verified Fable social route/policy matching, strict UUIDv4 sensitive challenge validation; external catalog remains independent.
- `auth_rc94_username_mock_test.dart`: deterministic mock tests for username checks, update, contract mismatch, invalid input.
- Existing social mocks updated to match the confirmed backend manifest.

## Known outstanding tasks
- Social Link/Unlink end-to-end security proof propagation, route-specific SDK and native callback handling.
- User-facing Username and social management UI.
- Complete RC94 operation ledger reconciliation and wizard audit updates.
- Android/iOS Flutter analyze/build/tests in CI are **not yet verified**. The environment used to draft these files does not have Dart/Flutter.
- Live providers, OAuth credentials, DB, devices and OTP must eventually be tested on an actual environment; mocked scenarios do not establish real E2E compliance.
- No backend runtime code was modified. Backend PR #14 and private CI ZIP blocker remain independent.
- Comprehensive source ZIP (Flutter plus private Backend) has not been produced or validated. Do not describe a patch/checkpoint archive as a complete project backup.

## Recoverability
The RC93 baseline + this isolated branch preserve reviewed source increments separately from any un-synced local work. Do not merge automatically. The canonical Fable roadmap covers 17 families and priorities P0–P7.


## Follow-up implementation (2026-11-02)
- Social source corruption found by GitHub CI was restored from the known-good RC93 blob, then security changes reapplied safely.
- Fable Social Link checks the Backend RC66 uppercase provider acknowledgement, while login challenge remains lowercase.
- Fable-only social unlink uses DELETE `/auth/social/:provider`, authenticated Bearer request, and `X-Security-Challenge-Id` header constrained to UUIDv4 and that route. The server's last-login-method protection remains authoritative.
- Added simulated backend tests for social linking and unlink; no provider OAuth credentials or real devices used.
- Added `FableUsernameSettingsPage` reachable from authenticated session management only if the signed Fable contract exports username operations.
- Username sensitive action flow consumes a proof bound to the same gateway and identity, without exposing it as an arbitrary user-entered identifier.
- CI diagnosis: first run failed due corrupted social source (repaired); next analyzer run found missing test subclass constructor (repaired). Until latest CI completes, Auth remains at the last accepted RC93 count 22/40 and RC94 is not fully verified.
- Keep Web/Admin contract IDs separate; no Web Cookie transport implementation is bundled with Flutter.
- Backend main and locally unsynchronized source remain untouched; packaging comprehensive ZIP from the latest local frontend and backend remains an independent P0 task.
