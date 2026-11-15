# Fable RC271 — source checkpoint, 2026-11-15

## Verified default-branch source pins before this documentation merge

- **Flutter main** `adnan118/Fable_flutter@2d89efa6a0294e9656d17b06b4825452cc6d1651` — includes all merged prior RC228–RC269 and RC270–RC271.
- **Backend main** `adnan118/Fable@ace409305c582a5e7dfff535520c25f5d63dc073` — RC268 strict JSON request schema and prior backend work.
- Both repositories currently have **zero open pull requests**.

## Added in this batch

| Version | Merged PR | Concrete source |
| --- | --- | --- |
| RC270 | Flutter #157 | Generated signed create-POST now supports optional text/UUID fields with strict signed-required parity; omitted optional input does not become an empty JSON property. Create UI is single-shot after success/failure; user must explicitly acknowledge server-state verification before creating again. Clears old fields on identity/gateway change. |
| RC271 | Flutter #158 | Supports `GET *.list.unpaginated` only when signed Backend `list-result.item`, `meta.modes=['unpaginated']`, OpenAPI item/meta schema, permissions and operation hashes match. Generates immutable typed list item/entity, strict bounded DTO, data adapter, repository/use case/controller, real list UI and widget/DTO test source. |

## Source evidence versus live tests

- Isolated JS execution of source tests for RC267, RC270 and RC271: **9/9 test groups passed**. Checked generated DTO and Flutter list-page source and the GET/POST source compatibility.
- This is NOT a `flutter test`, `dart analyze`, signed Android/iOS build, Backend DB test, load test, real Auth/provider E2E or production certification.
- Native Passkeys RC253–255 and app wiring RC265–266 remain source-implemented but await actual app signing/domains and physical device validation.

## Remaining source work (do not mark W5–W8 closed)

1. **W5:** Signed paginated/search list query binding; dedicated conditional PATCH/DELETE mutations with concurrency tokens, recent auth, idempotency and tenant context. Do not guess these routes or weaken their security for convenience. Many of the 17 family gaps and Other Backend parity also remain open.
2. **W6:** Complete missing family-specific integration and actual backend/Flutter flows, only where a verified Backend contract exposes them.
3. **W7/W8:** Run real tests, MySQL/Render production-like DB resilience and migration/recovery, Android/iOS native E2E, load, threat review, and final source ZIP/export/production acceptance evidence.

**Production verdict: NO_GO**. Do not report code-generated coverage as full product completion. All prior code is preserved in default branches; no unmerged PR drafts remain.
