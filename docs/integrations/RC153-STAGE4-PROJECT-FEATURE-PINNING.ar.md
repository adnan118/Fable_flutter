# RC153 — Stage 4 / Contract Provenance Gate

**Original roadmap:** Stage 4 — 17 optional Flutter capabilities, NOT a new product stage.
**Source base:** Flutter `d4d520b7ec60c87677ed789f85dcfee23313cdc4`; Backend RC152 merged `7aa1e6876319841ccd22a87ff8b8293e095cb0ee`.
**Existing work preserved:** RC142 (verified Backend feature policy), RC143 (Other Backend isolation), RC144 (Support identity-safe ticket workflow).

## Finding

The checked-in reusable `ci_fable` starter has 17 optional capabilities in `.fable/mobile-features.json` but `backendContractHash: null`. Its imported `assets/contracts/contract.json` is `test-project`, not a real service-specific export. **This is intentional for the reusable test fixture.** Do not populate its hash from the fixture, and do not point a user-facing build to a real API as though that fixture were a pinned project contract.

The existing Wizard writes a real `backendContractHash` and `selectionSource: verified-backend-project:<id>` when it safely applies a reviewed and independently pinned project export. RC153 now checks that the generated selection manifest actually remains bound to that export and its verified frontend setup.

## Added read-only acceptance

`node tools/verify-stage4-feature-binding.mjs --mode source`

This validates the source-side feature list, no duplicated features, equality of capabilities/features if both are present, valid Fable export/handoff and any non-null feature contract hash. The reusable fixture may pass **source** mode, with `fixture=true` and `projectBound=false`. Source success **never** claims real project readiness.

For a **real Fable generated project only**, run with independently obtained values:

```bash
node tools/verify-stage4-feature-binding.mjs --mode project \
  --expected-project-id ACTUAL_PROJECT_ID \
  --expected-contract-hash TRUSTED_BACKEND_EXPORT_SHA256
```

Project mode additionally fails closed when the Flutter manifest lacks an exact export pin, has a stale `selectionSource`, or the reviewed frontend setup / feature-sync provenance is missing or conflicts with the same project ID and hash. It uses the existing `verifyFableContract` signature/integrity validation; it does **not** ask the client to invent a hash or sign a contract itself.

**Other Backend:** Fable-specific hashes are rejected, and project-mode acceptance intentionally remains blocked until the separate Other OpenAPI/custom catalog, source, auth mappings and E2E checks are proven. RC153 does not force Fable routes onto Other.

## Automated evidence

- New `test/rc153-stage4-feature-contract-binding.test.mjs`: 8 cases for the 17 feature starter, fixture refusal, stale/bad hash, duplicates, valid synthetic pinned project, missing sync/wizard metadata, wrong independent hash, Other Backend isolation, and strict CLI exit.
- `.github/workflows/flutter-rc49-validation.yml` runs RC153 Node tests and source gate **before** Flutter analyze/test and Android/iOS simulator builds.
- The Node script returns exit **2** for an untrusted/unbound project and always reports `productionReady:false` and `liveE2EVerified:false`.

## Not closed by RC153

- 17/17 user flows are **not** E2E accepted.
- No real Other Backend project export was provided; no guessed credentials, DTOs, routes or permissions.
- Render RC152 verified 18 local HTTP Auth/ACL/session checks with disposable MariaDB; it did **not** validate Support, Media upload/download or 17 Flutter capabilities against that server.
- Real project contract re-export, per-capability live E2E, MySQL 8.4, APNs/FCM/Passkeys, Android/iOS devices and licensed DRM remain open.
- The stage 7 production gate remains NO-GO.

Tracker: https://github.com/adnan118/Fable_flutter/issues/74
