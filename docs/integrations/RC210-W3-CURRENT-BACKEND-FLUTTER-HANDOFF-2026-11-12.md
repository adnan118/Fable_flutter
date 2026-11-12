# Fable RC210 — W3 current Backend contract → Flutter import gate (2026-11-12)

## Why
The historical `tools/verify-cross-repo-source-pair.mjs` is pinned to the old RC86 repository source. A check that refuses all later Backend changes cannot be used to certify the new RC209 Backend/Flutter handoff. **RC210 does not overwrite or weaken that historical ledger.** Instead it adds a separate, *current-project*, read-only comparison.

## What the new W3 gate does
`tools/verify-current-w3-handoff.mjs` takes the actual project export produced by the private Backend and compares its `contract.json`, `flutter-handoff.json`, `openapi.json` and `mobile-core-operations.json` to the exact JSON imported into the Flutter project. It verifies:

- Backend contract's canonical SHA-256 hash, export manifest project name+ID, exported operations/features counts, Flutter handoff's SHA-256 manifest, and mobile core operation hash;
- exact semantic equality of all four separately supplied Backend and Flutter documents (even if field serialization order differs);
- independent existing `verifyFableContract` **project mode**, with expected Project ID and contract SHA coming from the separately located Backend export. Rejects demo `test-project`/`fable-test` identities, invented/changed operations and stale Flutter imports;
- independently supplied full Backend commit SHA, actual clean Git HEAD on branch `main`, and a GitHub origin matching `adnan118/Fable`. A merely matching filename or a cloned old checkout is insufficient;
- rejects symlinked input directories/intermediate document paths, oversized documents, unknown CLI flags, and incomplete verification;
- returns `productionApproved:false` and `liveE2EVerified:false` regardless of a W3 source PASS.

**Important trust boundary:** Git source checkpoint confirms *which checked-out private repository is being reviewed*, but an earlier exported JSON artifact does not cryptographically attest which CLI commit originally created it. The result explicitly reports `backendExportProvenanceVerified:false`. Before a release-source origin is considered proven, export provenance must be explicitly and independently bound to an actual generation event. Do not claim W3 final production approval.

## Run after cloning both latest branches and exporting a real project

```bash
# Export from an actual generated Backend project, where Fable CLI is installed
fable client contract export --client all --out dist/client-contract

# From Flutter repository root; use your own actual project paths
node tools/verify-current-w3-handoff.mjs \
  --backend-export /path/to/generated-backend/dist/client-contract \
  --flutter-root /path/to/generated-flutter \
  --backend-repo /path/to/private/adnan118-Fable-checkout \
  --expected-backend-sha <full-40-char-verified-Backend-main-SHA> \
  --json
```

For a freshly imported Fable Flutter project, `assets/config/backend.json` must mark the backend as imported/ready. The user's independent `--backend-export` location is the expected source for the comparison, not Flutter's own copied contract. This check does **not** apply to Other Backend, which must never be forced to consume Fable contracts/DPoP.

## Evidence in this turn
Implemented pure `tools/w3-handoff-integrity.mjs`, read-only CLI `tools/verify-current-w3-handoff.mjs`, and 12 regression tests `test/rc210-w3-current-handoff.test.mjs`. Added `npm run test:w3:current-handoff` and `npm run w3:handoff:verify`.

Isolated V8 acceptance checks were executed against the GitHub function source using a **test-only noncryptographic digest shim**, to verify logic paths for matched documents, mismatched contract/OpenAPI/mobile operations, forged Backend manifest, handoff and mobile fingerprint drift, fixture rejection, and missing independent verification. This is **not** equivalent to Node's real SHA-256 validation or running the new Node test file in a complete Flutter checkout.

**Still open:** actual Backend export from a real generated W1/W2 project, real Flutter contract import, executed `npm run test:w3:current-handoff`, Flutter analyzer/device tests, all 12 W4 wizard paths, W5–W8 and 82 original gap/evidence work items. Final source and production GO are not declared.

Latest Backend source baseline: RC209 `54ada55570e6d1f5921b0197946da31d5db14610`. This change advances the existing Flutter `main` history without discarding RC94–W0.3 features.
