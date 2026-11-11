# RC174 — Stage 6 Flutter / Backend source-only preflight

**2026-11-11 | Original Stage 6 begins | Source guard, NOT native or production approval**

## Context / decisions preserved

- Fable Backend Stage5 8/8 **development simulations** accepted after RC173 Render 12/12 actual Node restore/rollback tests; this does **not** prove production backup/DR.
- Two repositories: private `adnan118/Fable` Backend `main`, and `adnan118/Fable_flutter` Flutter `main`.
- Flutter has 17 selectable feature families; the reusable `ci_fable` app intentionally has `.fable/mobile-features.json.backendContractHash=null` and a `test-project` fixture. This must **never** become a real Fable project approval through guesswork.
- RC166 DPoP uses hardware-only P-256 AndroidKeyStore/Secure Enclave sources with exact Fable origin/contract pins. Source tests are not a device-backed ES256 signing proof.
- Other Backend requires its own catalog/operations/auth and must not inherit Fable's hash or DPoP claims. No GitHub Actions, paid services, invented APIs, test credentials, or production edits.

## Added read-only code

Run on a checkout with Node (does not require Flutter SDK):

```bash
node --test test/rc174-stage6-source-preflight.test.mjs
node tools/rc174-stage6-source-preflight.mjs --mode source
```

The CLI runs the pre-existing RC153 Stage4 contract verifier, the RC166 Dart-transport source audit and the RC166 Android/iOS bridge source audit **as separate subprocesses**. It then checks that the 17-family ledger, selected-capability manifest and source-verifier count agree, that no unverified family is declared complete, and that no Other Backend borrows a Fable hash. Return code **2** on a source blocker. It never obtains private keys or sends requests.

For a **real Fable project**, use ONLY independent trusted export values:

```bash
node tools/rc174-stage6-source-preflight.mjs --mode project \
  --expected-project-id REAL_PROJECT_ID \
  --expected-contract-hash TRUSTED_EXPORT_SHA256
```

Do NOT use `test-project` or fabricate those values. The existing verifier rejects missing, forged, stale or fixture binding. Even a passing pinned project **does not** certify Flutter/Android/iOS or stage 7. Other Backend project mode remains blocked until an independent verification contract exists.

## Execution evidence / exact acceptance limits

- **7/7 self-contained pure Node logic simulations PASS** on the current working container with Node 22.16.0 on 2026-11-11 (not the actual Flutter repo checkout). Cases: fixture source-only; strict project binding; fabricated live acceptance; feature mismatches/duplicates; missing DPoP audits; Other isolation; source verifier failure.
- **Not run:** Full RC174 CLI on Flutter `main` checkout, RC166 audits on that checkout in this session, `flutter analyze`, `flutter test`, Android/iOS compilation, real ES256 hardware signer or authenticated HTTPS to pinned real project. No GitHub Actions were used.
- The new source logic **never sets** `stage6Complete` or `productionReady` true, even if a future exact project pin passes. These require independent native/live evidence.

## Next gate

1. Execute RC174 full Node source audit in a trusted checkout or existing disposable builder; fix any failing checks.
2. Verify a separately exported non-fixture Fable project contract (real `projectId` + trusted SHA256); never alter starter fixture to feign acceptance.
3. Use a Flutter SDK environment to run all actual Dart tests/builds, with Android/iOS hardware requirements distinctly deferred if unavailable.
4. Run authenticated mobile E2E and selected provider acceptance, and maintain original deferred Stage4 #74/#82 findings. Stage7 remains NO-GO.

Links: [Backend Stage5 tracker](https://github.com/adnan118/Fable/blob/main/Fable-Backend-RC66/docs/STAGE5-8-GATES-PROGRESS-2026-11-11.md) · [Flutter #74](https://github.com/adnan118/Fable_flutter/issues/74) · [Flutter #82](https://github.com/adnan118/Fable_flutter/issues/82).
