# RC211 / W4 — preserve existing Fable contracts when selecting Other Backend

**Source implementation on latest Flutter main; production and native E2E remain unverified.**

## Confirmed W4 gap
`saveFrontendSetup` previously switched `assets/config/backend.json` to `kind:other` and `contractImported:false` but did **not** remove or retire the previously imported active `assets/contracts/contract.json` and Flutter handoff. Other tooling and future build steps could read stale Fable metadata despite the new Other Backend selection. RC188 native Dart transport correctly guards Fable DPoP by contract type, but keeping active Fable assets was unnecessary cross-backend configuration confusion.

## Implemented
- On **explicit approved** switch to Other Backend, `tools/retire-fable-contracts-for-other-backend.mjs` archives the entire prior Fable contract directory under `.fable/retired-fable-contracts/<content-hash>-<random-uuid>/contracts`, removing the former active `assets/contracts` directory via an atomic same-project rename. Nothing is deleted. Existing Backend/Flutter setup config snapshots are saved under `prior-setup/` for recovery.
- Strict preflight refuses symlinked project/target/config paths, symlink or hardlink entries within the contract bundle, special files, malformed/unidentifiable Fable catalogs and already present unknown Other Backend contracts. No previous user files are silently overwritten.
- The Guided Wizard **announces** retirement before asking for `اعتمد`/`APPROVE`; a refusal makes **zero** changes. Headless `--apply` is an explicit apply and gets identical source protections; an exception during configuration writes attempts to restore the old contract tree and previous setup byte-for-byte. If a concurrent actor recreated the active contract directory, the archive is retained for manual recovery, never deleted during rollback.
- The applied Other Backend remains `status:pending`, `contractImported:false`. No Fable DPoP, API operation, permission, authentication, provider or E2E approval is inferred. Previously imported Fable code and feature work in the repository are untouched.

## Tests authored and accepted as pending full-run evidence
- `test/rc211-w4-contract-retirement.test.mjs`: 8 real-filesystem Node tests covering successful archive with prior setup, fresh Other Backend case, failure rollback, external symlink rejection, non-Fable contract rejection, symlinked setup state, pre-approval read-only behavior and repeat switching without overwriting prior archives.
- `test/flutter-setup-wizard.test.mjs`: 2 additional end-to-end Guided Wizard *source* cases verifying an approved Fable→Other conversion archives active contract files and restores metadata, and rejected approval leaves original Fable files byte-identical.
- `npm run test:w4:retirement` runs both suites.

Full `node --test` in an authorized Flutter repository and real Flutter/Other Backend integrations were **not run in the model runtime**. Do not claim these 10 newly authored regression tests have passed without execution. RC188 existing Other Backend DPoP native source tests and full hardware/Dart E2E stay separately gated.

## Reproduce
```bash
cd Fable_flutter
npm run test:w4:retirement
npm run test:w3:current-handoff
# After actual contract imports:
npm run test:wizard
flutter analyze
flutter test
```

## W4 next gate
The authoritative W0 inventory requires **12 separate generated-project paths**: Backend kind Fable/Other × developer/agent × minimal/standard/complex. This RC211 code closes a security correctness gap in the Other Backend transition; it does not mark the matrix or any of the 82 remaining master evidence items as complete. W1–W3 project-bound tests, 17 feature families and production remain pending independent proof.
