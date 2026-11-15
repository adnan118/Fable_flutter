# RC280 — W5 Signed numeric range filters in Flutter

**Implementation scope:** Generated, project-signed Fable `GET *.list.paginated` consumers only. Base Backend main: `b61e7d6bb69f4d330a16dc045bc7428a07f8be46` (RC279).

## What was added
- The planner accepts an **atomic numeric Min/Max pair** only when the numeric base and both bounds are declared in the signed Fable operation **and** match OpenAPI; the base must appear as a nonsensitive integer/decimal in the signed response item projection.
- Preserve all existing RC278 text/boolean exact filters. At most three query controls are generated, so a two-bound range is only selected when two slots remain.
- Typed numeric fields use integer/decimal keyboards. Domain, UseCase, Repository, Controller, Widget and generated widget tests all receive the exact pair, with no arbitrary query-map or Local-only filtering.
- The Gateway adapter rejects missing or malformed numbers, non-finite decimals, integers beyond signed Int32 and reversed Min > Max; identity-epoch fencing and Infinite Scroll reset to page one remain unchanged.
- Validation deliberately sends only Min/Max (not an equality value simultaneously) to avoid RC279's ambiguous-filter rejection.
- Protected/sensitive item fields, mismatched or partial query schemas, tenant-scoped pagination, sort fields, generic PATCH/DELETE and Other Backend remain fail-closed.

## Verification
- 6/6 isolated regression test callbacks **executed against the actual current planner and renderer source** in a JavaScript isolate, comprising the prior RC278 equality/search cases and three RC280 cases. This is **not** `node --test` in the full repository, nor Dart/Flutter SDK validation.
- Tests are stored in `test/rc278-signed-equality-filters.test.mjs`; they can also run in a full Node development checkout.
- Live generated project, Nest/Prisma/MySQL E2E, Android/iOS devices, real tenant permissions: **not verified**. Production remains **NO_GO**.

## Next
1. W5: signed datetime From/To filters and sort allowlist, avoiding generated fields inferred from untrusted names.
2. W5: dedicated, conflict-safe PATCH/DELETE (auth, scope, If-Match/ETag and idempotency evidence).
3. W6–W8: real project/tenant lifecycle and full-source release ZIP.
