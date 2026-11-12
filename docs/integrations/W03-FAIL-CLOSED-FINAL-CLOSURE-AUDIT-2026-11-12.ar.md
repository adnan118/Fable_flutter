# W0.3 — Fail-closed, complete Fable feature/Wizard closure audit

**2026-11-12 — Developer backlog tracker, not a production release gate**

Latest Flutter main includes a 17-family W0 inventory containing 60 previously recorded gap descriptions, 10 shared Backend/Flutter/toolchain/provider/human-approval requirements, and 12 generated-project cases. W0.3 validates this inventory on every check; no item may be dropped merely to turn a count green.

## How to run

From the `Fable_flutter` repository root:

```sh
node tools/closure-gap-audit-cli.mjs --json
node tools/closure-gap-audit-cli.mjs --strict
npm run test:closure:w03
npm run closure:check
```

The strict report currently exits **2**, intentionally, because 82 open work items remain. It never writes code or mutates approval files. A malformed input, missing row or incorrect field returns a fail-closed error (exit 1). The non-strict report emits JSON for the developer/Agent.

## Mandatory validation

- **Frozen baseline hash `f04b695d`:** historical 60 gap IDs and descriptions are checked even if someone removes or edits an item in **both** ledger and register. To revise that baseline in the future, make an explicit reviewed source change with evidence, not a silent deletion.
- 17 unique stable Flutter family rows; 60 exact gaps; status never silently promoted to `ACCEPTED`.
- A gap, family, cross-cutting item or Wizard case that claims acceptance requires a source commit, actual test command, artifact reference and named reviewer; these are **self-reported trace records, not verified signatures**.
- All ten mandatory shared work items remain present; all 12 Fable/Other × developer/agent × minimal/standard/complex cases remain tracked.
- True `complete` and `liveE2EVerified` remain unchanged; production `NO_GO` stays in every result.

## Test evidence and limitation

- **13/13** exact GitHub authored W0.3 JS test case bodies (tests 1–13) executed and passed in V8 against exact current GitHub ledger/register+audit source. Positive report: 17 families, 60 source gaps, 10 shared requirements, 12 cases, **82 outstanding**. Negative tests included loss of both ledger+register gap, altered description, duplicated family, unsupported status, false feature/project acceptance and missing required work items.
- 2 CLI-focused Node test cases (strict exit and unknown flags) are committed, but the full `node --test` checkout run is not claimed.
- Real project generation, Flutter analyze/compile, native Android/iOS tests, Node24/pnpm frozen install and full device/provider E2E are **NOT** validated by W0.3.
- **Do not set any `complete=true` or `liveE2EVerified=true`** from this source audit alone.

**Next:** W1 — actual Backend Guided Wizard versus Agent headless generation parity and generated project checks. Historical Backend PRs #2,#3,#5,#6,#7,#13,#14 are closed/reconciled in [master issue #56](https://github.com/adnan118/Fable/issues/56). Full-source ZIP must use latest paired merged main snapshots, not old RC57 archives.
