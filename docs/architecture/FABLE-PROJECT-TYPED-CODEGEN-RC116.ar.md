# RC116 — Project-pinned Typed Read Feature Generation (Fable Backend)

## Objective
Fable must generate the **target architecture** instead of perpetuating existing UI/JSON/feature-core coupling. RC116 is an executable, fail-closed first production-path generator for **custom, explicitly selected authenticated read features**. It is not a generic Swagger-to-production-code claim.

## Verified source requirements
Before any preview or apply:
- Independently supplied `--expected-project-id` and `--expected-contract-hash` (64-hex SHA-256). Neither value is inferred from a fixture or a local label.
- `.fable/frontend-setup.json`: Fable Backend source, `mode=import`, `backendAuthority=true`, `projectBound=true`, matching project ID and contract SHA.
- `assets/config/backend.json` must select ready imported **Fable** only.
- `tools/verify-fable-contract.mjs` project-mode verifies the entire Fable contract, OpenAPI, handoff and mobile-core integrity. `test-project` / `fable-test` fixtures are rejected.
- Custom feature explicitly selected in `.fable/project-features.json`; exact operations listed in `.fable/feature-integration-requirements.json` with `needsBackend=true`.
- Each selected operation must be an authenticated GET with exact `operationId/method/path/feature/permissions/contractHash` in Fable's contract and matching OpenAPI 3.1 method, path, bearer security and hash. One exact success envelope and a **fully declared flat data object** are required.
- Supported fields: typed `String`, `int`, `double`, `bool`, optional variants; safe Dart identifiers, 1–32 fields per response. A GET may use typed string path parameters; unsupported query/body shapes are rejected.
- **Explicitly unsupported:** a `runtime-contract` placeholder, `{}` data, arrays, lists/pagination, nested JSON, `oneOf/allOf`, unmapped nullability, unknown field types, unauthenticated endpoints, generated mutations or a non-Fable Backend. These require source schema and separate implementation, not guessed `dynamic`.

## Generated architecture (each selected read op)
```text
packages/features/fable_<project_feature>/
  .fable-architecture.json
  pubspec.yaml
  lib/
    fable_<project_feature>.dart
    src/
      domain/<operation>_entity.dart
      domain/<operation>_repository.dart
      domain/typed_read_result.dart
      application/<operation>_use_case.dart
      data/<operation>_dto.dart
      data/fable_<operation>_repository.dart
      presentation/<operation>_controller.dart
  test/<operation>_dto_test.dart
  FABLE_GENERATED_README.md
```
Domain and Application are Dart-only; Presentation has Flutter state only; Data owns Fable contract checks, `FableAuthGateway`, map-to-typed mapping, sanitized error classification, and success-envelope validation. No credential or endpoint guess, no `e.toString()` in presentation and no hidden catch-to-empty list.

The project generator creates a package with typed dependencies and exported ports, but intentionally does **not** auto-wire app routes, perform DI registration, grant permissions, install a feature in the application registry, or claim live Backend success. Those require a separate app composition review. Existing legacy feature packages are not overwritten or falsely upgraded.

## User workflow
1. Import and review a real Backend handoff with the Flutter Wizard.
2. Explicitly select the project's custom feature and operation requirements (including DTO evidence).
3. Preview, without any writes:
```bash
pnpm wizard:feature:generate --feature orders \
  --expected-project-id <your-real-id> \
  --expected-contract-hash <actual-export-sha256>
```
4. Review result and apply:
```bash
pnpm wizard:feature:generate --feature orders --apply \
  --expected-project-id <your-real-id> \
  --expected-contract-hash <actual-export-sha256>
```
5. Review integration, generate project DI/routes explicitly, compile and run module tests, then perform **real** Backend/DB/device E2E before release.

Apply writes to a staging directory under the same `packages/features` tree and atomically renames to the absent package name. Existing package directories or changed source are NEVER overwritten. The RC115 layer gate is checked for every generated source before any files are staged.

## CI validation
- Node negative tests: multiple operation DTOs, required/optional fields, injection/unsafe identifier, missing response, missing permissions, unauthorized/public operation, stale method/path/hash and explicit selection.
- A deliberately **synthetic** source-mapped feature is generated in the GitHub Actions runner only; Flutter analyzer and independent package tests compile/run its actual output (DTO/domain/application/data/presentation).
- Android and unsigned iOS simulator builds remain CI build checks, not real device E2E.
- `projectBound` is required in real generator; CI fixture bypasses it **only** in a separate `--ci-mock-only` compiler-test program with a `GITHUB_ACTIONS=true` guard. It is never made available as an accepted production source.

## Broader unresolved gaps
- All legacy built-in features and Media's old upload Widget/Map API require migration.
- No typed OpenAPI codegen for nested/list/paginated DTOs or writes; these are deliberately blocked.
- No automatic generated integration into app DI or navigation, no native player / DRM, no general AST rule yet.
- Backend RC66 contains existing media, notifications, cache, etc.; these should be audited rather than duplicated.
- P6 live Backend/MySQL/R2, login, payment, device E2E remains unverified. No `liveE2EVerified` promotions.

**Important:** passing RC116 is evidence for code generation of a strict, source-known subset—not proof that all generated projects are complete or error-free.
