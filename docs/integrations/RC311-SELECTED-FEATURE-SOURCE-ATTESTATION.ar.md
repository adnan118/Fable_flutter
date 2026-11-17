# RC311 — W3/W5/W8: source attestation after selected-feature generation

## Scope
RC309 already builds all explicitly selected Flutter feature packages from independently pinned Fable Backend operation contracts. RC311 closes a source-integrity gap: after a batch is committed, the project must be independently re-renderable from the **same pinned signed contract** with an exact source-tree match, and (when requested) canonical Flutter host app registration.

The RC309 one-command `--apply --wire-app` flow now invokes this attestor before announcing success. Any disagreement enters RC309's existing compare-before-rollback and durable-backup recovery path. The original output remains source-only.

## Checks (fail closed)
1. Explicit independent project ID and 64-character Backend contract SHA-256; the existing RC116 contract verifier checks imported Fable-only project authority, signatures and permitted operations.
2. The **17 feature families are NOT implicitly considered complete**. Only 1–24 explicitly selected custom packages in `.fable/project-features.json` are within this attestation.
3. For every selected feature, regenerate expected source using the current RC116 signed typed planner in read-only verification mode. Compare **every exact file byte** with the committed generated package, detect omissions, extra files, changed content and symbolic links (including path ancestors), and produce deterministic per-package SHA-256 source-tree fingerprints.
4. Confirm the selected host-app dependencies resolve by their canonical local package paths and that each exported feature import and typed registry entry exists exactly once. The attestor does not accept the mere presence of a feature name elsewhere in a file.
5. Snapshot six signed project inputs before verification and recheck them afterward, so a concurrent contract or selection change cannot yield a successful attestation.

Verification does not execute/interpret Dart files, fetch external contracts, download toolchains, invoke Flutter/Dart/Gradle, call Render/Prisma, or write to the project. Tests are included as **deferred code** and were not executed at user request.

## One-command integrated build-and-attest
From the Fable Flutter checkout, pass a **generated project** location:

```bash
pnpm run wizard:feature:batch -- --root PATH_TO_GENERATED_PROJECT --expected-project-id PROJECT_ID --expected-contract-hash SHA256 --apply --wire-app
```

The result now includes `sourceTreeAttestation` and `appWiringVerified`. A source-commit success is not a release acceptance.

## Independent read-only verification of existing packages
```bash
pnpm run wizard:feature:verify -- --root PATH_TO_GENERATED_PROJECT --expected-project-id PROJECT_ID --expected-contract-hash SHA256
```

The independent command defaults to **requiring app wiring**; add `--no-app-wiring` only if feature packages were intentionally left unbound. It does not generate or repair missing packages. A failed check should stop delivery; investigate source drift, signed project import or unexpected mutations rather than relaxing the contract.

## W0–W8 status and safety
- W3: project-verified contract remains independent of generated Dart source.
- W4/W5: typed feature integration gains exact source and canonical host-binding attestation.
- W6: preserved security checks, no acceptance upgrade.
- W7: user-owned real environment, permission, native and E2E validation remains pending.
- W8: source-only attestation improves reproducibility, not native build, final combined ZIP creation or production GO.

This is **not** proof that all 17 feature families are implemented, no test suite was executed, and deployment remains **NO_GO** until the user validates the real generated system.
