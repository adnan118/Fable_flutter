# RC221 — Useful safe test totals from the ONE pnpm Fable acceptance command

Date: 2026-11-14. Direct base Flutter RC220 merged main `1259f40f3fbd53b7bf191f0c43b4ff15dc702401`; Backend RC209 main unchanged.

## Single invocation remains unchanged

```sh
pnpm fable:all
```

RC220 added a complete independently tracked private Backend Node suite (288 historical `.test.mjs` test files in `Fable-Backend-RC66/test/`) alongside Flutter tests and W1/W2 fast/full, but its status report gave only the *process exit code* and no actual case counts. When hundreds of tests run, this made closeout and debugging unnecessarily opaque.

RC221 safely extracts only numeric totals from the final `node --test` TAP footer, including:
- `total`, `passed`, `failed`, `skipped`, labeled `source: NODE_TAP_FINAL_SUMMARY`.
- Handles both LF and CRLF line endings (Windows).
- Rejects malformed, oversized or numerically inconsistent TAP footers.
- The per-check report includes its numeric totals when available. The overall report now includes `observedNodeTestCounts` with totals aggregated from separate Node test groups.
- Does **not** persist raw stdout/stderr, test names, stack traces, request headers, access tokens or provider secrets. No new shell command, auth permission or deployment authority.
- If a Node child reports a nonzero count of failed tests but returns status 0, classification still becomes **FAILED**, not false PASS. Independent Git source-inventory checks and real E2E blockers stay unchanged.

## Test evidence

- Authored 11 Node regression cases in `test/rc221-safe-tap-summary.test.mjs` covering ordinary TAP, CRLF, failure and skip counts, malformed/missing footer, synthetic false-zero exit, no raw secrets, combined private Backend+Flutter counts, and production NO_GO.
- **13/13 isolated V8 functional/source assertions executed PASS** on exact RC221 branch source, including parser code and report classification.
- **Actual Node v22 test runner was invoked in the available model container** for a tiny independent 2-case TAP sample (one PASS and one SKIP). The exact parsing logic, copied from this PR, correctly produced `{total:2,passed:1,failed:0,skipped:1}` from the real runner's LF output, and then from its CRLF-transformed output. **This does not mean the complete RC221 test file, all 288 private Backend tests, or the 68 Flutter Node source files were run.** They still require the actual repository checkout/toolchains.
- No Flutter SDK, private Backend source checkout or native phone/device available for model-run tests; provider E2E and production acceptance remain open. The master W0 acceptance register still lists 82 originally outstanding evidence items, production **NO_GO**.

RC221 is developer closeout/report correctness work, not completion of the 17 feature families or W6–W8 release signoff. No previous GitHub source or test is discarded.
