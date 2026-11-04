# Fable RC114 — Architecture Target & Gap Review (not a cosmetic refactor)

**Reviewed Flutter main:** `74c83d2256f0819e6503b6e7881fab03d6490e9f` (RC113, post-merge CI green).
**Scope:** observed Flutter source + generated feature package layout + supplied Shifaa/Nukhba quality checklist; this is NOT an audit of their private source repositories. No actual Shifaa/Nukhba repository files were inspected.

## Decision: target quality independently of existing code
Fable is a **multi-project generator**, not just one Flutter application. Therefore the target is a verifiable contract and dependency policy for *generated* code, not simply the shortest migration path from current `lib/src` files.

**Target logical dependency flow (optional layers cannot be decorative):**

```text
Presentation (Flutter/Riverpod or Bloc)
   -> typed Application Command / UseCase
   -> pure Dart Domain port + typed Entities/Failures
   <- Data adapter (Fable OR separately verified Other Backend)
   -> generated typed Client / DTO mapper
   -> verified Backend operation catalog & authenticated transport
```

The inverted arrow indicates that the application depends only on the Domain port. The Data adapter implements that port. DI composition binds adapters once per selected project/backend/account. Presentation never imports the Data adapter or Dio. There is no requirement for 10 files per simple CRUD call: the complexity of the domain determines which Use Cases are valuable.

## Evidence-backed findings in current Flutter/main

| Priority | Evidence | Gap against target | Resolution |
| --- | --- | --- | --- |
| HIGH | `packages/features/fable_media/lib/src/media_read_repository.dart` returns `Future<Map<String,dynamic>>`, parses response maps, assumes `media.clientContract` and `media.metadata` operation IDs | untyped public boundary and project operation ID assumptions | RC114 introduces parallel typed port; existing endpoints need schema verification and migration |
| HIGH | `packages/features/fable_media/lib/src/resumable_upload_card.dart` imports Dio, File, Repository, CheckpointStore; coordinates upload/resume/cancel and persistence from StatefulWidget | presentation owns async workflow and data details | future migration via application UseCases + typed state; do not rename existing code and call it Clean |
| HIGH | `packages/fable_core/lib/src/fable_api.dart` explicitly recognizes the protected `/media/:id/content` path and `X-Fable-Media-Token` | feature-specific HTTP semantics enter generic core | follow-up: generic capability-scoped binary transport + explicit verified media header policy outside core, preserving security |
| HIGH | `analysis_options.yaml` only enables a few lint rules and basic analyzer settings | no automated dependency direction / typed boundary enforcement | RC114 import-graph gate for new Media layers; expand across new generated features with Dart analyzer AST/lint later |
| MED | `packages/features/fable_media/lib/src/protected_media_playback_repository.dart` has `Map<String,dynamic>` internal decoding while public view is typed | DTO parsing and workflow concentrated in Data service | typed model mapping and generated schemas should replace hand-maintained maps |
| MED | `packages/features/fable_content/lib/fable_content.dart` still creates a concrete Fable gateway and repository inside the feature screen factory | composition/DI not wholly separate from UI ownership | move composition to backend-aware app shell |
| POSITIVE | RC110–RC113 tests, Fable auth identity fencing, explicit contract checks and fail-closed behavior | security foundation is stronger than an ad hoc app, but not live-E2E proof | preserve controls during refactor |

This table is a source review, **not proof of the absence of other issues**. In particular, the global packages, runtime devices, live DB/R2/DRM and performance are not fully audited.

## RC114 executable vertical slice — new typed contracts
- Pure Dart `domain/MediaByteRange`, `MediaByteSource`, `MediaReadResult` with safe, typed failures; no Flutter, Dio, JSON or Fable-specific types.
- `application/ReadMediaRangeUseCase` uses a port, validates maximum segment size and maps errors to typed results. No raw error is surfaced to UI.
- `data/FableMediaByteSource` adapts verified RC113 session-bound reading and maps 401/403/409/429/timeout/transport/invalid-response to typed failures. Other Backend would supply a separate adapter.
- `presentation/MediaRangeController` exposes typed Idle/Loading/Ready/Failure states; no dependency on concrete adapter, HTTP or JSON. It prevents double-load and ignores completions after reset/dispose. UI will translate failure kinds using the app's Localization strategy.
- Negative import graph tests reject domain->Flutter, application->data, presentation->Dio/Fable core and `dynamic` in the new Domain/Application files.

**Compatibility:** The RC114 slice is additive. Old upload card and playback repositories remain for existing generated clients. The new typed path is the intended direction; do NOT claim entire Media already migrated.

## Architecture acceptance gates from now on
1. Imported verified per-project contract (method/path/auth/project hash) before generating endpoints.
2. DTO / Entity typed result at the public Repository boundary; no raw response maps at the Presentation/Application API.
3. DataSource/DTO implementation may know HTTP. Domain/Application may not.
4. Failure taxonomy stable and localized by presentation; malformed payload is not silently turned into empty data.
5. Feature-level state supports simultaneous operations appropriately; cancellation/identity revisions invalidate stale results.
6. Backend-specific adapters separated, with no Fable-only credentials assumed for Other Backend.
7. DI composition outside Widgets; no eager HTTP in feature page `build` or `initState`.
8. Unit, repository adapter, UI state and negative/simulated race tests, plus Live E2E for real Backend/DB/R2/device before release assertions.
9. CI checks import graph + Dart analyze. The RC114 Node graph gate is useful but **not a Dart AST analyzer**; adopt a custom_analyzer rule/AST-based lint later to detect indirect usage/cycles/symbol-level leaks.
10. Design tokens, localization, accessibility and performance gates for generated presentation code.

## Prioritized remediation roadmap
- **P0 now (RC114):** stop creating new layer violations; introduce typed ports, failure states, negative CI tests.
- **P1:** migrate old Media read/upload UI orchestration; split UI, workflow and backend adapters; remove Fable media special-casing from generic core with security-preserving transport capabilities.
- **P2:** generator-wide typed OpenAPI DTOs/operation clients and per-feature CI guardrails (not only Media).
- **P3:** launch actual native Android/iOS player integration ONLY after player/byte-source/DRM API feasibility verification, followed by honest live E2E and playback-performance tests.
- **P4:** expand coverage for all selected features, pagination/empty/401/403/timeout/mutation idempotency, localization/tokens and external backend isolation.

## Checklist-based comparison to Shifaa / Nukhba
The pasted checklist suggests that Shifaa's reported risk is over-abstraction/manual parsing/fallback-to-empty, and Nukhba's reported risk is raw network contracts/large Core/stream ownership. These are **claims from the pasted checklist**, not independently verified code findings. A rigorous three-way ranking requires actual source for both apps and common metric tests. Fable's current source demonstrably overlaps several of the same anti-patterns; therefore calling it “best” or “error-free” is **not justified**.

## Live acceptance
Passing CI means compilation, static checks and supported simulations passed on a known commit. It does **not** demonstrate physical iOS/Android device playback, Backend/MySQL/R2 response or signed actual app project contract. P6 remains open and no `liveE2EVerified` flag changes in RC114.
