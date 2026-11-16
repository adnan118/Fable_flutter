# RC296 — Coordinated W0–W8 source batch (Flutter + paired Backend RC295)

## Purpose
W0–W8 run as a **coordinated dependency graph**, not eight independent finish lines. We can implement W3/W4/W5/W6 in the same source batch while W7 live tests are reserved for the user, and W8 export only packages pinned/merged source.

## Actual source changes
- **W2/W5/W6 Backend:** paired Backend RC295, main commit `d65af79195862050e1a5ed3d82590ebb43df9af6`, refuses empty PATCH before Prisma for owner/self, managed and global write scopes.
- **W3/W5/W6 Flutter:** generated owner PATCH/DELETE UUID input now verifies canonical **UUID v4** (matching NestJS `ParseUUIDPipe({version:'4'})`). A generated PATCH request validates client input separately from the HTTP call. Client input `FormatException` maps to `invalidInput`, whereas an incompatible Backend DTO response maps to `invalidResponse`. No unauthorized payload fallback.
- **W3/W4:** every generated feature package includes `.fable-operation-evidence.json` with selected project ID, pinned project contract hash, signed operation IDs/methods/hashes, required request fields and explicit `liveE2EVerified:false`.
- **W4/W5:** `wizard:feature:generate` returns the **actual method set** (GET/POST/PATCH/DELETE), per-operation hash receipt, and distinguishes preview (writes nothing) from source-apply with/without registry binding; old misleading `typed GET` completion label removed.
- **W0–W8 status:** `pnpm run fable:source-map` prints a read-only map from the canonical JSON parity ledger; `pnpm run fable:source-map -- --json` prints machine-readable gate status. Neither runs tests, updates production or fabricates feature completion.
- **W8:** combined Backend+Flutter committed-source ZIP via Backend `pnpm run export:full` remains available. This is an archive tool, not a certified release. Flutter package source receipt is preserved in the archive if the generated package has actually been committed.

## Explicit open gates
- W0 existing inventory, W1/W2 source implemented, W3/W4 partially integrated.
- W5 tenant-bound writes, verified optimistic concurrency (If-Match/revision), and full app integration are not closed.
- W6 none of the 17 feature families is accepted without independent evidence.
- W7 the user will perform real tests; no device, generated app or MySQL 8.4 E2E is claimed in this batch.
- W8 physical final source ZIP + release acceptance are still open; production remains `NO_GO`.

**No tests were executed in this batch per user request.** Changes were reviewed as source and merged through GitHub, but Dart SDK and generated project compilation have been explicitly deferred.
