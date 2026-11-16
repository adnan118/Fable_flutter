# RC309 — W4/W5 all-selected typed Flutter feature batch (one command)

## Why
The previous `wizard:feature:generate` required one invocation per feature. For a project with several selected custom features, operators repeatedly ran generator, app pubspec edits and feature-registry edits, creating partial integration and avoidable handoff steps.

**RC309 composes all the already-signed, reviewed feature operations across up to 24 explicitly selected custom project features into ONE source batch.** It reuses the existing `planPinnedTypedFeature` contract/architecture verifier and `planW5AppFeatureBinding` import/registry transformer. It does not guess endpoints or invent Backend contracts.

## One-command source preview

Run from the intended **generated Flutter project root** that contains `.fable/project-features.json`, `assets/contracts/{contract,openapi}.json`, the independently imported setup and the selected feature requirements:

```bash
pnpm run wizard:feature:batch -- --expected-project-id PROJECT_ID --expected-contract-hash CONTRACT_SHA256 --wire-app
```

Preview validates every selection, pinned contract and the proposed pubspec/registry mutations **without writing any file**. It returns one JSON report with source file counts, methods, signed operation IDs, managed-entity requirements and `liveE2EVerified:false`.

## One-command stage and app binding

```bash
pnpm run wizard:feature:batch -- --expected-project-id PROJECT_ID --expected-contract-hash CONTRACT_SHA256 --apply --wire-app
```

- Validates and renders **ALL** selected custom feature packages before mutating source. A failing/unsupported feature blocks the whole batch. No partial support is treated as success.
- Refuses symlinked project source folders, unsafe names/paths, duplicates, existing feature packages and more than 24 selected features or 2,400 generated files.
- Performs all pubspec/feature registry changes in memory, using the existing canonical W5 integration transformer.
- Creates a filesystem writer lock and temporary stage inside `packages/features`, and durable original app source backups under `.fable/feature-backups/rc309-...`.
- Rechecks the signed Backend import, project feature requirements and initial app source bytes before commit. Moves already prepared packages into place, then writes only canonical app wiring.
- Compares each committed generated package file to its original preflight bytes and confirms the new app registry/pubspec. If an error occurs, **attempts a guarded rollback** of only unchanged files created in the batch and preserves concurrent edits rather than deleting third-party changes. On power failure, interrupted process or concurrent external editor changes, inspect the durable backups: this is a best-effort source transaction, not a full filesystem ACID database transaction.
- Does **NOT** call `flutter pub get`, Gradle, Dart analyzer, live Backend, Render, GitHub Actions or Android/iOS tools. No new downloads or SDK changes are triggered.

## Dependencies / limits
- The CLI expects the generator tools and `package.json` script from the Fable Flutter source checkout to be present in the **generated project** invoking it. Source-only preview may be used until all selected features have independent, signed operation contracts.
- Only explicitly supported CRUD operations are emitted; sensitive/unsupported/ambiguous write signatures fail closed.
- After a committed source batch, the user intentionally runs `flutter pub get` and Flutter/Dart build checks under pinned Flutter 3.50.0 / Dart 3.14.0 to test the generated project.
- The existing single-feature command remains available and unchanged.
- This improves **W3/W4/W5/W8** source generation workflow. It does not mark W5, 17 feature families, W7 live E2E or W8 production acceptance complete.
- Per user request, **no test suites or native Flutter builds have been executed**; JavaScript source syntax review and static inspection only.

See also [RC308 pinned toolchain](./RC308-FLUTTER-350-VERIFIED-TOOLCHAIN.ar.md) and the canonical W0–W8 parity ledger.
