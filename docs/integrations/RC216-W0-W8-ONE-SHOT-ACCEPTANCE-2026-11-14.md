# RC216 — one-shot W0–W8 local acceptance and production NO-GO guard

**Date:** 2026-11-14. **Source line:** Flutter RC215 and private Backend RC209. No GitHub Actions.

## Why this is the accelerated closure path
Past Fable RCs added actual Backend generation replay, Flutter Wizards, real operation source audits, identity-bound Auth/Notifications code and numerous focused test files. A separate manual checklist for each small patch was slowing acceptance, while the authoritative W0 ledger still had **82 outstanding gates**. The new local command executes everything available from one authenticated checkout and emits a single machine-readable report. It does **not** silently mark missing tests PASS.

## Verified unchanged baseline
Running `auditClosureRegister` on the authoritative original W0 master and gap register in this turn returned:
- 17 feature families, 60 original feature gaps.
- 10 cross-cutting items.
- 12 distinct generated Wizard scenarios.
- **82 outstanding**; by gate: W1 1, W2 1, W3 1, W4 14, W5 1, W6 60, W7 3, W8 1.
- Authoritative release decision: **NO_GO**.

No original gap was erased or changed. Source implementation may reduce engineering work but does not replace third-party, native/hardware, real provider or independent human signoff.

## What the runner actually checks
`tools/w7-w8-local-acceptance.mjs` and CLI `tools/run-w7-w8-local-acceptance.mjs`:

1. Validate the expected 40-character Git commit for **both** cloned repositories, clean tracked source, `main` branch and the exact intended GitHub origin. Fable's nested `Fable-Backend-RC66` package runs commands inside the package, while W3 verifies Git identity from the repository root. Missing or dirty checkouts are blocked.
2. Parse the two historical W0 files with the shared nofollow feature-source reader, and audit their original fingerprint/baseline through `auditClosureRegister`.
3. If the actual Backend source is accessible and both pins match, run RC208 W1+W2 **full** real-generation acceptance command.
4. W3 compares four real private Backend-export JSON documents against the Flutter-imported project, only when an export path and Git checkpoint are supplied. A W3 source pass never asserts cryptographic provenance of the export build.
5. W4 creates the materialized **12-case** Guided/Agent Flutter Wizard matrix, but only with three separate independent Fable export profiles; otherwise BLOCKED.
6. W5 runs the actual selected feature operation source chain against a generated Flutter project, requiring separately pinned source/contract and all operation evidence.
7. W6 always tries the available JS source regressions with valid source pins. With explicit `--with-flutter`, also runs the targeted actual Auth/Notifications Dart+Widget tests.
8. W7 optionally runs `flutter analyze` and `flutter test` with the real Flutter SDK. Neither test means a real Android/iOS device, real push/OTP/payment provider or DB has been verified.
9. W8 remains NO_GO pending independently reviewed evidence and human production authorization. No local command or self-asserted JSON can set `productionReady=true`.

Each subprocess executes by explicit argv arrays, no shell, bounded time, captures only exit/status/duration, not potentially sensitive stdout/stderr. Source or native tests are labeled accordingly. Unknown prerequisites appear as BLOCKED, missing runs NOT_RUN, nonzero exits FAILED. Reports are read-only except if the user explicitly supplies `--output`, which refuses to overwrite an existing file and uses owner-only permissions where supported.

## One command on the user's authorized development machine

```bash
cd Fable_flutter
npm run fable:closeout -- --help
npm run fable:closeout -- --plan
npm run test:closeout
```

With authenticated clones of both real `main` repositories and each independent source PIN:

```bash
node tools/run-w7-w8-local-acceptance.mjs \
  --backend-root /path/to/Fable/Fable-Backend-RC66 \
  --expected-backend-sha YOUR_VERIFIED_BACKEND_MAIN_SHA \
  --expected-flutter-sha YOUR_VERIFIED_FLUTTER_MAIN_SHA \
  --backend-export-root /path/to/real-backend/dist/client-contract \
  --generated-flutter-root /path/to/real-flutter-project \
  --project-id YOUR_PROJECT_ID \
  --contract-hash YOUR_INDEPENDENT_SHA256 \
  --with-flutter \
  --output /path/to/rc216-acceptance-report.json
```

Provide `--fable-{minimal,standard,complex}-export`, `--fable-{profile}-project-id`, and `--fable-{profile}-contract-hash` for **each** of the three independent Backend scenarios to enable the W4 matrix. Their exact flag names appear in `--help`.

Do not paste keys, login credentials, refresh tokens or private provider secrets into command arguments, logs or JSON reports.

## Tests and evidence status
- Added 13 Node regression cases in `test/rc216-local-closeout.test.mjs`: W0–W8 shape, correct private repo checkout separation, no valid source without Git main pins, three-export requirement, missing evidence as blocked, explicit native opt-in, nonzero/signal failures, 82-item baseline preservation, and **NO_GO** even when a synthetic ledger claims zero open gaps.
- **15/15 isolated V8 functional assertions actually executed PASS** on the fetched candidate pure plan, evaluator and CLI argument parser. This does not substitute for a complete Node checkout test run or a real Flutter/Backend generation.
- Node source tests, full Backend build, actual 12 generated projects, native Android/iOS and real third-party providers are **not marked executed** in the model environment.
- Release builder ZIP is a Windows helper to fetch full private source after user GitHub authentication; it is **not** the complete private source itself.

**Next real blockers:** complete the 60 per-family acceptance cases against real generated apps; execute and collect 12 Wizard outputs and all W1–W3 contracts; owner-test OTP/push/payments and Android/iOS; independent review and explicit production GO. This one-shot runner eliminates repeated manual checking, not legitimate release gates.
