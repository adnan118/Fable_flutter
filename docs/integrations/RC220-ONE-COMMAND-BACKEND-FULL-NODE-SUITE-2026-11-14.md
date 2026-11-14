# RC220 — Include the entire historic private Backend Node test suite in the ONE `pnpm fable:all` run

**2026-11-14.** Built directly on merged Flutter RC219 main `4b59e4e44bbd8b651f0945ef40253516a756ff7a`; Backend main RC209 `54ada55570e6d1f5921b0197946da31d5db14610` remains unmodified.

## Concrete missing coverage corrected

An inspection of `Fable-Backend-RC66/lib/w1-w2-gate-plan.mjs` proves that its fast/full modes run **focused W1/W2 source and generated-project acceptance**, not the complete historical Backend test library.

The private Backend GitHub `Fable-Backend-RC66/test/` currently lists **288 `.test.mjs` files**. The single-command source orchestrator previously ran both W1/W2 fast/full but omitted the independent comprehensive Backend Node suite. This RC adds an explicit `BACKEND_ALL_TRACKED_NODE_TESTS` stage inside the **same** existing command. It scans the actual authenticated Backend checkout using NUL-delimited `git ls-files --cached -z -- test tools`, checks tracked sources with the shared secure nofollow reader, and runs them once through Node's test runner using bounded `--test-concurrency=4`.

A backed-off/absent private checkout stays `BLOCKED`. A failed private test is `FAILED`. A partial or unverified Git test inventory is `PARTIAL` even if the available tests exit zero. The report now includes `backendTestsDiscovered`, `completeBackendGitTestInventoryVerified`, and `backendUnsafeTests`, independently from Flutter's existing source inventory. No tests are silently counted as PASS because their filenames exist.

Backend W1/W2 `--fast --json`, `--full --json`, generated artifacts, Flutter W0–W8 source checks, Dart tests, `flutter analyze` and `flutter test` all remain present. The historical Node/Flutter development source and security gates are unchanged.

## One command — unchanged

From inside the cloned latest Flutter repository:

```sh
pnpm fable:all
```

This is the one normal command users need. It requires access to the private Backend checkout to execute its private suite, and uses its exact Git repository path. Report output remains automatic in `.fable/reports`, never overwriting previous reports.

## Honest status

- **18/18 isolated V8 plan/evaluation checks executed** on exact candidate GitHub source: compile, private path isolation, all twelve planned stages, fast/full both retained, missing Backend source, unverified or unsafe test inventory, real nonzero failures, historical 82 blockers, permanent production NO_GO.
- **10 new Node regression tests authored**, plus earlier 15 RC217 and 15 RC218 cases preserved; the full actual `node --test` run over all 288 private Backend tests and the Flutter source suite was **not executed in the model environment**.
- Neither these checks nor synthetic test fixtures prove real Backend generator, database migrations, OTP/push/payment providers, Android/iOS, native DPoP, W6 family E2E, production signoff or any of the 82 original W0 source/acceptance items.
- Backend remains at RC209. W6–W8 acceptance remains open, production **NO_GO**, no GitHub Actions used.
