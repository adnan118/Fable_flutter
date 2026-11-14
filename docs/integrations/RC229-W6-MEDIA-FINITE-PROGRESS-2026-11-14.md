# RC229 — W6 Media upload: reject nonfinite server-confirmed progress

Date: 2026-11-14. Direct descendant of merged Flutter RC228 `f877ba4999a64a7ddf14b2c9dec84d9120b66a78`; Backend main RC209 unchanged.

## Actual Dart defect
`MediaUploadRepository._progress` accepted a numeric `percentage` when `pct>=0 && pct<=100`. However `double.nan` compares false for both `<0` and `>100`, meaning malformed Backend progress could be displayed as server-confirmed upload state and permit further media transfer. RC229 now requires **a finite numeric value** in [0,100], alongside existing byte bounds and total file size agreement. Negative and infinite percentages remain rejected. Fable and Other Backend operation mapping, authenticated media identity fence, no automatic mutation retries, R2 presigned URL and checkpoint protections remain intact.

## Tests
The real `media_identity_transfer_rc110_test.dart` fixture now has 11 tests (two new). It injects NaN, ±Infinity, negative and >100 server percentages into the actual upload repository's `prepare` request, verifies rejection, then proves a valid zero progress still works. Another test verifies a malformed initial response never sends a media chunk, never completes the upload and never invokes checkpoint persistence. No physical upload or presigned R2 URL is needed for these authored unit regressions.

Six Node source guards in `test/rc229-media-upload-finite-progress-source.test.mjs` are included in all-Git-tracked tests. **Those six tests were actually executed in isolated V8 using exact candidate GitHub source blobs; 6/6 passed.** The existing one developer command `pnpm fable:all` also explicitly targets the real Flutter media identity tests.

Not yet executed in this model environment: actual full Node checkout test suite, Dart/Flutter SDK, Cloudflare R2 network uploads, Android/iOS, third-party providers, hardware or native E2E. W0 authoritative 82 acceptance evidence items and W6–W8 release signoff remain unverified. Production **NO_GO**; no prior features/PRs/merges discarded.
