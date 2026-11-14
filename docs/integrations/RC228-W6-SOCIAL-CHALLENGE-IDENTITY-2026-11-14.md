# RC228 — W6 social authentication identity and challenge-expiry hardening

Date: 2026-11-14. Flutter RC227 baseline main `517b4ab3b1ef5422a6896b47087a13ddb67ddc8f`; Backend RC209 remains unchanged.

**Real production Dart changes**

1. Imported social-operation mappings must have `enforceAuth=true` on every mapped role. The shared validator previously checked role-specific `requiresAuth` but never checked the operation's enforceAuth value. Public sign-in/challenge roles legitimately use `requiresAuth=false`, while link/unlink require a user session; both now require an explicitly enforced route policy. No external provider keys are accepted.
2. In `FableSocialRepository._run`, the OAuth challenge deadline was measured using wall-clock time **after** receiving the challenge response. Network latency could therefore make an already-expired challenge look fresh. A monotonic `Stopwatch` now starts **before** the challenge HTTP request and validates the challenge immediately on response and after the native SDK's credential callback. Real Backend remains the final authority on expiration.
3. The linked-account path reads secure accessToken asynchronously. If logout or user switch occurs while that read is in flight, the old code continued to request a challenge before rejecting later. The code now checks the original identity epoch immediately after the token read and returns without any Backend operation when superseded.

**Test evidence and single command**

`social_auth_repository_test.dart` expanded from 7 to 10 authored Dart tests, covering unenforced route policy, a deliberately slow challenge response, and an account switch during the token read. The existing nonce mismatch, two-factor, mandatory password change and provider proof tests remain. `test/rc228-social-challenge-expiry-identity-source.test.mjs` adds seven source integrity cases.

Those seven Node test cases were **actually executed in an isolated V8 JavaScript evaluation of the exact GitHub code blobs and all seven passed**. The production code and Dart tests were fetched by SHA. A complete Node project test invocation, native Dart/Flutter test suite, Google/Apple native SDK, OTP/provider and physical device E2E have **not** been run in the model environment. This is source-layer hardening, not production signoff.

The single developer command `pnpm fable:all` now additionally targets the real social Dart test file, without removing any earlier tests. Original W0 82 acceptance items and all remaining W6/W7/W8 release evidence remain OPEN; production **NO_GO**. No GitHub Actions requirement.
