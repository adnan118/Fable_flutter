# RC212 W4 — 12 isolated **real Wizard application** paths, with explicit source/E2E limits

**2026-11-14.** This source change follows merged RC211 and does not weaken Fable-only DPoP, financial settlement or provider rules.

## The matrix implemented (not merely a checklist)
`tools/w4-wizard-matrix.mjs` defines exactly the 12 authoritative W0 cases:

`Fable/Other Backend × developer guided/agent headless × minimal/standard/complex`.

Every generated case calls the **actual** Flutter Wizard application code:
- Developer/Fable: `runGuidedFlutterSetup` with explicit yes/import/APPROVE choices, real Backend-export package, separately supplied expected project ID and SHA-256.
- Agent/Fable: `importBackendDecisions` with the exact same pins, followed by the same real `applyReviewedSnapshot` logic used by guided approval. The existing source revalidation and feature-sync preflight remain mandatory.
- Developer/Other: `runGuidedFlutterSetup` with actual manual prompts and approval, safe RC211 retirement of stale Fable sample contracts if a starter is copied.
- Agent/Other: `manualFrontendDecisions` + real `saveFrontendSetup(...apply:true)`, with the same explicit manifest and adapter. External Auth/permissions remain unverified and `contractImported=false`.

For each case the tool audits the emitted `backend.json`, `frontend-setup.json`, project `.fable` setup, Flutter-owned decisions and the active Fable contract bundle (or its absence for Other Backend). It hashes the generated file tree (excluding retired immutable archives with unique paths) and compares each developer/agent source pair.

Without real independently pinned Fable exports, all 6 Fable paths are **BLOCKED**, not counted as PASS. Full W4 gate PASS additionally requires `--materialize` to copy actual Flutter starter source, successful generation in all 12 scenarios and identical paired files. Even a source PASS does not prove `flutter analyze`, `flutter test`, native DPoP, external provider integration or production.

## Practical commands

From `Fable_flutter`:

```bash
npm run wizard:w4:matrix -- --plan
npm run test:w4:matrix
npm run wizard:w4:matrix -- --json
```

The final `--json` command above can successfully exercise **six Other Backend paths** with no Backend access, but will correctly return a nonzero status while the six Fable exports are unprovided.

To run the entire materialized source matrix, supply three independently verified exports from real generated Backend projects (one for each profile), e.g.:

```bash
node tools/run-w4-wizard-matrix.mjs --json --materialize --keep \
  --workspace /path/to/w4-matrix \
  --fable-minimal-export /path/to/minimal/dist/client-contract \
  --fable-minimal-project-id <real-minimal-project-id> \
  --fable-minimal-contract-hash <independent-64-char-sha256> \
  --fable-standard-export /path/to/standard/dist/client-contract \
  --fable-standard-project-id <real-standard-project-id> \
  --fable-standard-contract-hash <independent-64-char-sha256> \
  --fable-complex-export /path/to/complex/dist/client-contract \
  --fable-complex-project-id <real-complex-project-id> \
  --fable-complex-contract-hash <independent-64-char-sha256>
```

The requested source fingerprints **must not be obtained by blindly trusting Flutter's own copied artifacts**. The three Backend export digests must be distinct, and all six developer/agent results must agree in their source trees. Cases are isolated and refuse a destination that already contains files; they never overwrite a previous run. Keep the resulting workspace only if explicitly requested. If running on Windows, use paths appropriate for the shell and proper Node + Flutter toolchains.

## Tests and evidence
New `test/rc212-w4-wizard-matrix.test.mjs` (7 tests authored) covers:
1. Exact 12 W0 scenario identities.
2. Other Backend Auth and permissions always pending, not invented.
3. Six Fable paths correctly BLOCKED without real exports; Other six source applications still exercised.
4. All 12 source applications with three **synthetic independently constructed source fixtures**, and six paired fingerprints. This exercises actual JS Wizard source and asserts **NO full Flutter project/production acceptance** for lightweight mode; it does not substitute for real Backend export.
5. Reused Fable export hash rejected for three profiles.
6. User workspace overlap with Flutter source rejected.
7. Invalid/partial CLI pin sets rejected.

**Execution status:** Test suite authored and connected to `npm run test:w4:matrix`, but full `node --test` and source materialization have **not been executed in the model's full Flutter checkout**. Therefore do not mark 12/12 generated, 6/6 parity, W4, the 17 feature families or production complete without independent test output.

## Next closure
W1 real Backend Guided/Agent fresh generation; W2 full compiled/transactional generated Backend; W3 matching real-source contract origin; W4 full materialized Flutter source plus Dart analyzer/native tests; W5 17 feature binding; W6 functional flows; W7 provider+device, W8 release sign-off. 82 original W0 evidence items remain tracked and are not deleted by this source implementation.
