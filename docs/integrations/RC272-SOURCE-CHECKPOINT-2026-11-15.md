# Fable RC272 — checkpoint (15 November 2026)

**All prior work preserved in default branches.** This entry supplements, not replaces, RC242/RC264/RC269/RC271 continuity notes and the canonical W0–W8 gap register.

## Exact default-branch pins before checkpoint commit

- **Flutter:** `adnan118/Fable_flutter@84e224f7318390e16cf674e41a94f883fefa9e69` (RC272 code merged in PR #160).
- **Backend:** `adnan118/Fable@ace409305c582a5e7dfff535520c25f5d63dc073` (RC268).
- **Open pull requests:** zero in both repositories.

## Source features now implemented in W5 generic typed generator

1. Project-pinned GET single-object data screen, Repository, UseCase, Controller and navigation.
2. Narrow signed `POST .create` with bounded required/optional text/UUID request DTO, user confirmation, single-shot retry-guard and sensitive/admin/payment/tenant protections.
3. Source-verified `GET *.list.unpaginated` (signed item fields, `count/maxRows/limitExceeded`, bounded typed cards).
4. **RC272**: `GET *.list.paginated` **page mode only**, exact `page/limit/mode` Backend-signed query contract and meta variants, `page=1..100000`, `limit=20`, UI previous/next, bounded typed data, session invalidation, rejection of tenant-scoped/unbound-required-header operations.
5. **RC272** also fixed a legacy invalid Dart Widget test source line missing a closing parenthesis in `tester.tap`.

## Validation evidence and limits

- RC272 + RC271 + RC270 + RC267: **12/12 isolated JS source test groups passed**. Inspected generated Dart DTO, Repository, controller, page and generated Widget test syntax text.
- No Flutter SDK, Dart analyzer, real Backend DB, browser device, Android/iOS signing, live tenant E2E or production deployment tests were performed. Source validation is not production readiness.
- Generated-package README now correctly states page mode is present but **search/filter/sort are NOT**. Other Backend implementations are independent and not inherited.

## What must still be built

- W5: signed and role-checked **search/filter/sort** query UI; explicit tenant/entity context; conditional PATCH and DELETE with optimistic concurrency, recent-auth and proper idempotency/uncertain-result controls. End-to-end generated-project run still outstanding.
- W6: family-specific gaps in auth/profile/media/messaging/content/etc., with actual endpoint bindings and platform behavior.
- W7/W8: production-grade DB migration/recovery, operational monitoring, native Passkeys RP/Associated Domains release checks, device/provider security/performance tests, complete source ZIP/export acceptance.

Production remains **NO_GO**. Do not mark any family `complete:true` or claim production E2E from source-only evidence.
