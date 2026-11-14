# RC223 W6 Payments — strictly authenticated read and payment identity binding

Date: 2026-11-14. Direct Flutter RC222 main baseline `09b1b5e8c108d33353028bab4c2ab6fc338faeb4`; private Backend RC209 main unchanged.

## Two actual source defects fixed

1. The existing `FablePaymentOperations.fromContract` accepted any individually addressable GET with `requiresAuth=true`, even when `enforceAuth=false`. The core `FableOperation` default is `enforceAuth=false`. For account-sensitive financial data, merely advertising authentication is insufficient. Now `requiresAuth` **and** `enforceAuth` must both be true; weak, anonymous, admin, query-bearing, external-credential and non-GET operations remain refused. No guessed endpoint is introduced.
2. `FablePaymentReadRepository.read(id)` previously decoded a successful response and returned it **even when the actual response payment ID differed from the requested payment ID**. The card could therefore display an unrelated account's payment status. Now the decoded `payment.id` must match the validated requested payment UUID (case-insensitive UUID spelling); a mismatched response throws `FormatException` before the state is delivered to the UI. This is a data correctness guard, **not** an authorization substitute on the Backend.

## Regressions and one command

- `packages/features/fable_payments/test/payments_contract_test.dart`: six actual Dart test cases covering enforced auth, denied weak/anonymous/checkout/admin/query/credential operations, one valid read, mismatched and malformed response, UUID case normalization and invalid ID before networking. Test-only explicit `dio: ^5.9.0` dev dependency added; no runtime package dependencies added.
- `test/rc223-payment-identity-auth-source.test.mjs`: six Node source integrity regressions.
- Targeted payment Dart tests are added to the existing `pnpm fable:all` Flutter step; no second developer command. Code is still **read only**. Capture/refund/settlement/idempotency remain separate unimplemented capabilities. Never retry a payment-creating POST automatically.

**Actual evidence here:** 14/14 isolated source/structural assertions passed on exact candidate GitHub blobs. Dart/Flutter SDK, real financial Backend provider/device and all original W0 acceptance gaps remain unexecuted/unapproved. No source-only PASS is production approval. W6 Payments remains OPEN overall and production remains **NO_GO**.

All previously merged Auth, Notifications, Wizard, Backend, DPoP and source closeout work preserved, no GitHub Actions dependence.
