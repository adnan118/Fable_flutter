# RC218 — One pnpm command, complete tracked Node tests, Windows Flutter and safe reports

Date: 2026-11-14. Built on merged Flutter RC217 main `49e3a742c03aee65573d23c0adefff8b8b7cc75e`, preserving Backend RC209 main `54ada55570e6d1f5921b0197946da31d5db14610`.

## User-facing invocation (UNCHANGED)

```sh
pnpm fable:all
```

No separate npm/node test commands or `--help` are needed. This remains the **only** normal validation command. Prior scripts and W1/W2 `--fast`/`--full` commands are retained internally as diagnostic entrypoints, not deleted.

## Actual RC217 gap fixed: omitted Git tests

RC217 aggregated only directly listed `node --test` commands in `package.json`. A source-tree audit of the current RC218 GitHub branch found **68 `.test.mjs` source files** across `test/` and `tools/`, of which only **31** were listed in `test:*` scripts. Hence **37** test source files were at risk of being omitted, despite the user's explicit instruction to include all past tests.

RC218 reads the NUL-delimited Git-tracked file inventory (`git ls-files --cached -z -- test tools`), merges it with the existing npm/pnpm script file list, deduplicates paths, and opens each with the prior nofollow/single-hardlink source evidence reader. Dangerous/untracked, missing, or linked test files are never executed. Node test execution is capped at 4 workers to limit resource contention, while the full set is still run. The report shows `testsDiscovered`, `previouslyUnregisteredNodeTests` and `completeGitTestInventoryVerified`.

If Git is absent or a declared file is unsafe, safe tests can still run, but the report must say **PARTIAL** rather than a misleading complete source test PASS. A genuine failing test is **FAILED**. This guarantees test inventory completeness is evidenced independently from test process exit code.

## Windows-compatible native Flutter

`flutter` on Windows is generally a `flutter.bat` launcher. Calling `spawnSync('flutter',...)` directly without a shell can fail, even when Flutter is installed and in PATH. RC218 now uses `cmd.exe /d /s /c` for Windows **only**, and passes exclusively hard-coded/strictly allowlisted Flutter command tokens, rejecting shell metacharacters. Linux/macOS remain direct `spawnSync('flutter',...)` without shell. Exit code, timeout, and absence of token-leaking logs are retained; missing SDK results in a blocked native check.

## Correct private Backend source checkpoint

The generated Backend project lives in `Fable-Backend-RC66`, but the checkout root is not reliably `dirname(projectRoot)` (e.g. custom checkout folder names). RC218 determines the **actual Git top-level** using `git rev-parse --show-toplevel`, and uses that for independent Backend origin and SHA checks and the W3 contract-export source gate. This fixes incorrect source pairing in nonstandard Windows workspace layouts.

## Safe persistent report storage

The command checks the destination root, `.fable`, and `.fable/reports` are actual directories and **not symlinks**, and creates reports with `wx` (never overwrites an existing report) and restricted file permissions where supported. Explicit risk of report output leaving the project through a linked directory is rejected.

## Evidence and acceptance

Added `test/rc218-complete-test-inventory-windows.test.mjs` (15 authored Node tests) to cover Git-NUL test inventory, path safety, skipped evidence, all-user command, Windows launcher safety, actual Backend checkout root, and symlink-resistant reports. Adapted the 15 RC217 synthetic regression cases to the new injectable source reader and correct PARTIAL semantics rather than weakening production checks.

**17/17 isolated V8 branch-source functional checks executed PASS**, including real parsing and pure logic paths; the complete 68-file `node --test` run and Flutter/Dart hardware tests **were not executed in this session** because the model runtime lacks the full GitHub checkout and Flutter SDK. Do not claim 68 test files passed, only that they are now selected when a tracked repository is available.

W0 register remains **82 items needing evidence** (17 families / 60 family gaps / 10 cross-cutting / 12 Wizard scenarios), W1–W8 final acceptance and production remain **NO_GO** pending real generated projects, device/provider E2E and independent owner approval. Zero historical changes are discarded.
