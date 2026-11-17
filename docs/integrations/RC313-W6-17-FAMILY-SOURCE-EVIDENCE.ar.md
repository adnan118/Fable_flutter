# RC313 — W6 source evidence inventory for all 17 Flutter families

## Source-only milestone

The canonical 17-family parity ledger already distinguishes declared Flutter code from independently verified mobile/server behavior. RC313 adds an **exact read-only source inventory** so a checked-out Flutter tree with missing, altered, symlinked or incorrectly registered evidence cannot masquerade as the current source baseline.

The command audits **all 17 built-in feature families in one run**, independent of which optional features a generated client selects:

```bash
pnpm run fable:families:source
```

The tool checks:
- Exactly the 17 family IDs and ownership classes declared by the Flutter ownership registry; duplicate, missing or invented IDs fail.
- Each family's source status and known gaps, while refusing to upgrade `liveE2EVerified`, `complete` or per-operation acceptance.
- The canonical app's path dependency, import and `installedFeatures` Dart entry for each built-in family, each appearing exactly once.
- Its own package's `pubspec.yaml` identity (`fable_<family>`).
- Every ledger-declared Flutter evidence file is a real, nonempty, in-repository Dart file, with no symlinked source or ancestors.
- SHA-256 content fingerprint and byte counts for each source file, aggregate family evidence hash, and app, registry and ledger hashes.

The resulting JSON is a verifiable **source manifest**, not a test report. It includes `sourceOnly:true`, `testsExecuted:false`, `nativeBuildExecuted:false`, `acceptedLiveFamilies:0`, `productionReady:false`.

## Limits

The ledger's current `frontendEvidence` paths exist in GitHub at the checked revision; this inspection confirms existence, not integration of every optional runtime provider. It does not test actual calls, permissions, DPoP, accounts, native platforms, Apple/Google provider credentials, real DB migration, complete UX flows, the user-specific generated project, or third-party SDK compatibility. A source-only receipt must **never** be treated as 17/17 accepted functionality.

The 17 built-in families differ from the RC309 selected **custom project packages**; RC311 independently re-renders those generated custom packages. RC313 instead holds the built-in family inventory, declared paths, and canonical source wiring to a stricter traceable baseline. Neither replaces W7.

No tests or Flutter/Dart/Gradle/Render commands were executed. Deferred regression source is bundled for the operator's later acceptance.
