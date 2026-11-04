# Fable RC115 — Generator-wide Flutter Feature Architecture Gate

**Baseline:** Flutter/main `5799dd7a5781f311f7b9ec4f3ed7f4fafd6c4e9a` (RC114; post-merge CI succeeded 3/3).
**Principle:** compare projects to the ideal target independently of existing folder naming; enforce new source boundaries rather than adding decorative layers.

## What is enforced

The new `tools/enforce-feature-architecture-rc115.mjs` scans every `packages/features/fable_*` package and classifies it as:
1. **Adopted / enforced:** existing package with `lib/src/domain`, `application`, `data`, `presentation` plus validated package-level `.fable-architecture.json`.
2. **Legacy not certified:** one of the 17 explicitly reviewed, pre-RC115 built-in packages that has **not** adopted the new layout.
3. **Invalid newly added feature:** any new feature package outside that fixed legacy baseline that lacks all four layers or a valid architecture marker. Merely omitting the marker or all four directories cannot bypass CI.

Each adopted layer must contain Dart source. Dependency flow:
- **Domain:** Dart-only types and local Domain, optional `meta/collection`; no Flutter/Dio, cross-feature packages, transport APIs, storage, filesystem, `dynamic`.
- **Application:** only local Application/Domain; no Data, Presentation, HTTP, Fable Auth, `dynamic`.
- **Data:** local Domain/Application/Data and currently necessary migration-era legacy adapter, plus explicitly approved transport packages. No cross-feature dependency.
- **Presentation:** local Presentation/Application/Domain and narrowly allowed Flutter state/Design System/localization libraries. **Cannot import Data**, Fable Core, Dio or external feature packages; no `dynamic`.

**Important:** Dart analyzer, tests and this static import audit are complementary. RC115 uses an import-directive scanner and a small type-token check, *not a full Dart AST/symbol graph*. It does not prove that all business logic is gone from Widgets, that all DTOs are typed, or that no cycles exist through other packages. Future rules should use analyzer AST for symbol-level and transitive dependencies.

## Generator integration (actual, not just documentation)

`tools/sync-project-features.mjs` now runs the architecture audit during preview and before every `--apply` operation. The preview includes:
- `architecture.enforced` — adopted packages that are checked;
- `architecture.legacyNotCertified` — existing legacy packages, **not** treated as compliant;
- `architecture.findings` — concrete source/structure deficiencies.

An apply with any finding **throws before backup, manifest writes or package deletion**. The existing independently pinned Backend project check, feature selection, and Other Backend isolation remain unchanged. The audit never invents operations, roles, DTOs, or generated API endpoints.

CI runs both the generic gate and **negative tests** that deliberately inject:
- Domain importing Flutter/platform I/O;
- Application importing Data or another feature;
- Presentation importing Dio/Fable Core;
- `dynamic` in Domain/Application/Presentation;
- a missing layer, tampered manifest, removed manifest, or symlink;
- a brand-new package with no layered structure at all;
- feature-sync attempt with bad architecture that must not mutate existing source.

Only the reviewed baseline packages can remain legacy without blocking unrelated existing projects. Any legacy package that starts creating layers immediately becomes strictly subject to all four-layer rules; this prevents partial migration being called complete.

## Existing code explicitly NOT migrated in this RC

- `resumable_upload_card.dart` still coordinates upload/retry/cancel/storage and imports Dio.
- `media_read_repository.dart` still exposes `Map<String,dynamic>` and hand-held operation IDs.
- `fable_api.dart` still includes Fable-media-specific token/header behavior.
- Older built-in packages still need individual architectural migration; RC115 **does not** claim they are clean.
- Generated typed OpenAPI DTO clients, dependency composition, localization and design-token codegen are still pending.
- Native Android/iOS player, DRM and live Backend/DB/R2/device P6 E2E remain pending.

## Next adoption order
1. RC116+: introduce **project-bound, contract-aware typed feature scaffold/codegen** that generates this four-layer structure by default and refuses to assume unexported operations. Keep Other Backend's contract and session namespace independent.
2. Migrate the upload workflow out of Widget into typed Application/controller and appropriate Data ports; retain RC110-113 identity and R2 guards throughout.
3. Extract media-specific transport details out of generic `fable_core` using a narrowly scoped verified operation extension, without opening arbitrary credential headers.
4. Expand analyzer-level lints and enforcement across all migrated feature packages and selected projects. Add source/real device E2E separately.

## Acceptance
This slice proves an enforceable architecture **entry gate for new feature packages** and prevents a known class of regression. It does not certify the entire Flutter app. CI is source/test/build evidence only, **not live E2E**; no P6 flag is changed.
