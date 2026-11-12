# W0.2 — Project-generation decisions manifest v1 (Backend ↔ Flutter)

**2026-11-12 | Developer/Agent input contract only; not the completed Wizard or feature-generation implementation.**

Both repositories now embed **byte-identical** `project-generation-manifest.mjs` (SHA must be checked before merge). This is a pure fail-closed validation/normalization layer; it does not silently generate routes/screens, certify external contracts, or deploy.

## Required JSON

```json
{
  "schemaVersion": 1,
  "kind": "fable.project-generation-manifest",
  "project": {"id": "demo-project", "displayName": "Demo Project"},
  "backend": {
    "kind": "fable",
    "adapter": "fable-contract",
    "origin": "https://YOUR-ACTUAL-HTTPS-FABLE-ORIGIN",
    "contractSha256": "YOUR_REAL_64_HEX_CONTRACT_SHA",
    "contractProjectId": "demo-project",
    "capabilities": ["auth"],
    "operationIds": ["auth.login"],
    "dpop": "required"
  },
  "frontend": {
    "client": "flutter",
    "features": ["auth", "profile"],
    "locales": ["ar", "en"],
    "platforms": ["android", "ios"]
  },
  "source": {
    "backendCommit": "REAL_BACKEND_MAIN_COMMIT_SHA",
    "flutterCommit": "REAL_FLUTTER_MAIN_COMMIT_SHA"
  },
  "execution": {"initiator": "developer", "mode": "guided"}
}
```

This example deliberately contains placeholders and **must not be accepted as a verified real project**. For an Agent, use `{"initiator":"agent","mode":"headless"}`; it should produce the **same decisionHash** when everything else matches. For `backend.kind="other"`, use a separately verified `adapter="openapi"` or `custom`, `contractProjectId=null`, `capabilities=[]`, and `dpop="forbidden"`. Never import Fable native DPoP.

## Commands

Backend in `Fable-Backend-RC66`:

```sh
node bin/verify-project-manifest.mjs --manifest path/to/project-manifest.json
node bin/verify-project-manifest.mjs --manifest path/to/developer.json --compare path/to/agent.json
npm run test:w0:manifest
```

Flutter at repository root:

```sh
node tools/verify-project-manifest.mjs --manifest path/to/project-manifest.json
node tools/verify-project-manifest.mjs --manifest path/to/developer.json --compare path/to/agent.json
npm run test:w0:manifest
```

Exit 0: manifest decisions valid or matching; exit 1: malformed input/unsafe mode; exit 2: valid decisions differ. **Exit 0 does not imply the independently verified contract or generated project passed.** The tool returns `contractSignatureVerified=false`, `actualGeneratedProjectVerified=false`, `liveE2EVerified=false`, and `productionReady=false` on every path.

## Acceptance and next work

- Reject credential fields, unknown options, invalid project IDs/commits/contract hash, non-HTTPS origins, Fable DPoP off, Other Backend Fable DPoP on, and external auth without declared operations.
- Preserve sorted unique selected capabilities/feature IDs for deterministic review and developer-Agent parity.
- `27/27` independent W0.2 Node cases were executed on local Node 22 against the equivalent source/CLI before GitHub upload; verify Git blob and re-run exact committed tests on a trusted checkout. Not full Node24/pnpm12 or Flutter integration.
- **W0.3 / W1 next:** bind this canonical selection manifest to actual Backend Wizard and Flutter Wizard generation, detect mismatches against verified trusted contracts and emitted files, and test 12 generated-project fixtures.
- **Combined full-source ZIP policy:** snapshots MUST be built from verified Backend and Flutter **merged main SHAs**. Never use October RC57 library bundles as a substitute or relabel them as latest. If artifact tool/network cannot fetch GitHub source archives, provide commit-pinned GitHub source ZIP links and a local bundler rather than distributing an outdated combined archive.
